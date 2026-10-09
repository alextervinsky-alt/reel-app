#if os(macOS)
import AppKit
import ImageIO
import SwiftUI
import ReelCore

enum ImageKind {
    case poster, thumbnail, backdrop, profile, still, logo

    var tmdbSize: String {
        switch self {
        case .poster: "w342"
        case .thumbnail: "w92"
        case .backdrop: "w1280"
        case .profile: "w185"
        case .still: "w780"
        case .logo: "w500"
        }
    }

    /// Images are decoded at the size they are shown, which keeps memory use low.
    var maxPixels: Int {
        switch self {
        case .poster: 570
        case .thumbnail: 160
        case .backdrop: 1800
        case .profile: 240
        case .still: 820
        case .logo: 700
        }
    }
}

/// A decoded image. Immutable after creation, so it is safe to hand between threads.
final class DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
    let cost: Int

    init(cgImage: CGImage) {
        self.cgImage = cgImage
        self.cost = cgImage.bytesPerRow * cgImage.height
    }
}

/// Posters and photos: memory first, then the Image Cache folder, then TMDB.
/// Each image is downloaded once and stored as a small file; the folder is trimmed to a size limit.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()
    static let cacheLimit: Int64 = 400_000_000
    static let cacheTarget: Int64 = 300_000_000

    /// Posters and small photos have their own memory, so big backdrops and stills never push
    /// the library's posters out (which made scrolling reload them from disk).
    private let small = NSCache<NSString, DecodedImage>()
    private let large = NSCache<NSString, DecodedImage>()
    private let lock = NSLock()
    /// Loads under way, and whether each is only reading ahead.
    private var running: [String: (task: Task<DecodedImage?, Never>, ahead: Bool, token: UUID)] = [:]
    private var folder: URL?
    /// Downloads wait their turn here, without a clock running, rather than in URLSession's
    /// queue, where a crowd of them at launch timed out and left posters blank.
    private let gate: DownloadGate
    /// Which images views on screen are waiting for.
    private let interest: Interest
    /// Images TMDB doesn't have (or sends broken): not asked for again this session.
    private var missing: Set<String> = []
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 30
        // A download that stalls without ending would hold one of the gate's places for good.
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private init() {
        let interest = Interest()
        self.interest = interest
        gate = DownloadGate(limit: 6, keepFree: 2) { interest.isWanted($0) }
        small.totalCostLimit = 256 * 1024 * 1024
        large.totalCostLimit = 160 * 1024 * 1024
    }

    private func memory(for kind: ImageKind) -> NSCache<NSString, DecodedImage> {
        switch kind {
        case .poster, .thumbnail, .profile, .logo: small
        case .backdrop, .still: large
        }
    }

    func configure(folder: URL) {
        lock.withLock { self.folder = folder }
    }

    static func key(_ path: String, _ kind: ImageKind) -> String {
        kind.tmdbSize + path.replacingOccurrences(of: "/", with: "_")
    }

    /// The key in memory: the grey version of an image is kept apart from the colour one.
    private static func memoryKey(_ path: String, _ kind: ImageKind, _ monochrome: Bool) -> String {
        key(path, kind) + (monochrome ? "~mono" : "")
    }

    /// TMDB has no such image (or sends one that won't decode): asking again won't help.
    func isMissing(_ path: String, _ kind: ImageKind) -> Bool {
        lock.withLock { missing.contains(Self.key(path, kind)) }
    }

    /// Instant answer from memory, so cached posters never flicker while scrolling.
    func cached(_ path: String, _ kind: ImageKind, monochrome: Bool = false) -> DecodedImage? {
        memory(for: kind).object(forKey: Self.memoryKey(path, kind, monochrome) as NSString)
    }

    /// An image from memory, the cache folder or TMDB. Asked for twice at once, it's loaded once
    /// (except that a view doesn't wait on reading ahead).
    func image(_ path: String, _ kind: ImageKind, monochrome: Bool = false,
               priority: TaskPriority = .userInitiated) async -> DecodedImage? {
        await image(path, kind, monochrome: monochrome, priority: priority, waiting: true)
    }

    /// `waiting`: a view waits for it (the grey version's own load of the colour image doesn't
    /// count again).
    private func image(_ path: String, _ kind: ImageKind, monochrome: Bool, priority: TaskPriority,
                       waiting: Bool) async -> DecodedImage? {
        let memoryKey = Self.memoryKey(path, kind, monochrome)
        if let hit = memory(for: kind).object(forKey: memoryKey as NSString) { return hit }
        let ahead = priority.rawValue <= TaskPriority.utility.rawValue
        let (task, token): (Task<DecodedImage?, Never>, UUID) = lock.withLock {
            // A view never waits behind reading ahead (it runs at low priority and may be far
            // down its queue): it loads the image itself.
            if let existing = running[memoryKey], ahead || !existing.ahead { return (existing.task, existing.token) }
            let created = Task.detached(priority: priority) {
                monochrome ? await self.makeMonochrome(path, kind, memoryKey) : await self.fetch(path, kind, Self.key(path, kind))
            }
            let token = UUID()
            running[memoryKey] = (created, ahead, token)
            return (created, token)
        }
        // While a view waits, its download keeps its place; once it's gone (scrolled away), the
        // download steps back behind images still on screen.
        let claim = ahead || !waiting ? nil : interest.claim(Self.key(path, kind))
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            if let claim { self.interest.release(claim) }
        }
        if let claim { interest.release(claim) }
        lock.withLock { if running[memoryKey]?.token == token { running[memoryKey] = nil } }
        return result
    }

    /// Reads images into memory ahead of time (posters about to scroll in), at low priority,
    /// two at a time and behind anything a view is waiting for. Returns at once.
    func warm(_ images: [(path: String, monochrome: Bool)], _ kind: ImageKind) {
        guard !images.isEmpty else { return }
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var started = 0
                for image in images where self.cached(image.path, kind, monochrome: image.monochrome) == nil {
                    if started >= 2 { _ = await group.next() }
                    started += 1
                    group.addTask {
                        _ = await self.image(image.path, kind, monochrome: image.monochrome, priority: .utility)
                    }
                }
            }
        }
    }

    /// The grey, dimmed version of an image (an offline film), made once from the colour one.
    private func makeMonochrome(_ path: String, _ kind: ImageKind, _ memoryKey: String) async -> DecodedImage? {
        guard let color = await image(path, kind, monochrome: false, priority: Task.currentPriority, waiting: false) else { return nil }
        let source = color.cgImage
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        guard let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(source, in: rect)
        context.setFillColor(gray: 0, alpha: 0.45)
        context.fill(rect)
        guard let grey = context.makeImage() else { return nil }
        let decoded = DecodedImage(cgImage: grey)
        memory(for: kind).setObject(decoded, forKey: memoryKey as NSString, cost: decoded.cost)
        return decoded
    }

    private func fetch(_ path: String, _ kind: ImageKind, _ key: String) async -> DecodedImage? {
        let base = lock.withLock { folder }
        let file = base?.appendingPathComponent(key)
        if let file, let stored = try? Data(contentsOf: file) {
            if let decoded = Self.decode(stored, maxPixels: kind.maxPixels) {
                Self.markUsed(file)
                memory(for: kind).setObject(decoded, forKey: key as NSString, cost: decoded.cost)
                return decoded
            }
            // A damaged file would hide the image on every launch: fetched again below.
            try? FileManager.default.removeItem(at: file)
        }
        guard let url = TMDBImage.url(path, size: kind.tmdbSize) else { return nil }
        // Reading ahead never takes the last places from an image someone is waiting for.
        let background = Task.currentPriority.rawValue <= TaskPriority.utility.rawValue
        await gate.enter(key, background: background)
        // Loaded meanwhile by a view's own request (it doesn't wait on reading ahead).
        if let loaded = memory(for: kind).object(forKey: key as NSString) {
            await gate.leave()
            return loaded
        }
        let downloaded = try? await session.data(from: url)
        await gate.leave()
        // Offline or timed out: worth trying again later.
        guard let (data, response) = downloaded, let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        guard status == 200, let decoded = Self.decode(data, maxPixels: kind.maxPixels) else {
            // Not there, or broken: not worth asking again (a server error might pass).
            if status < 500 { lock.withLock { _ = missing.insert(key) } }
            return nil
        }
        // Only an image that decodes is kept on disk.
        if let file { try? data.write(to: file, options: .atomic) }
        memory(for: kind).setObject(decoded, forKey: key as NSString, cost: decoded.cost)
        return decoded
    }

    static func decode(_ data: Data, maxPixels: Int) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedImage(cgImage: cg)
    }

    // MARK: Cache folder

    /// Keeps the file's date fresh so the size limit removes images that haven't been used for
    /// the longest time. Touched at most once a day per file.
    private static func markUsed(_ file: URL) {
        let fm = FileManager.default
        guard let date = (try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
              date < Date().addingTimeInterval(-86_400) else { return }
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    }

    /// Runs in the background at launch: removes images no film uses any more (after a week),
    /// then keeps the folder under the size limit.
    func maintain(keeping keys: Set<String>) {
        guard let base = lock.withLock({ folder }) else { return }
        Task.detached(priority: .background) {
            if !keys.isEmpty {
                CacheMaintenance.removeUnreferenced(in: base, keep: keys, olderThan: Date().addingTimeInterval(-7 * 86_400))
            }
            CacheMaintenance.trim(base, limit: ImageStore.cacheLimit, target: ImageStore.cacheTarget)
        }
    }

    func diskSize() async -> Int64 {
        guard let base = lock.withLock({ folder }) else { return 0 }
        return await Task.detached(priority: .utility) { CacheMaintenance.size(of: base) }.value
    }

    func clear() {
        small.removeAllObjects()
        large.removeAllObjects()
        guard let base = lock.withLock({ folder }) else { return }
        Task.detached(priority: .utility) { CacheMaintenance.clear(base) }
    }
}

/// A few downloads at a time; the images views are waiting for go first, and reading ahead
/// always leaves `keepFree` places for them.
actor DownloadGate {
    private let limit: Int
    private let keepFree: Int
    /// Whether a view is still waiting for the image (by its download key).
    private let wanted: @Sendable (String) -> Bool
    private var active = 0
    private var waiting: [(key: String, background: Bool, go: CheckedContinuation<Void, Never>)] = []

    init(limit: Int, keepFree: Int, wanted: @escaping @Sendable (String) -> Bool) {
        self.limit = limit
        self.keepFree = keepFree
        self.wanted = wanted
    }

    func enter(_ key: String, background: Bool) async {
        if active < (background ? limit - keepFree : limit) {
            active += 1
            return
        }
        await withCheckedContinuation { waiting.append((key, background, $0)) }
    }

    /// Hands the place to the next one waiting, or frees it: images views on screen are waiting
    /// for first, in the order they were asked for (the top of the page first); then the rest
    /// (reading ahead, and posters scrolled away) in order, leaving `keepFree` places.
    func leave() {
        if let index = waiting.firstIndex(where: { !$0.background && wanted($0.key) })
            ?? (active <= limit - keepFree ? waiting.indices.first : nil) {
            waiting.remove(at: index).go.resume()
        } else {
            active -= 1
        }
    }
}

/// How many views are waiting for each image (by its download key).
final class Interest: @unchecked Sendable {
    /// One view's wait, released once (when it ends or the view goes away).
    final class Claim: @unchecked Sendable {
        let key: String
        var released = false

        init(key: String) {
            self.key = key
        }
    }

    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func claim(_ key: String) -> Claim {
        lock.withLock { counts[key, default: 0] += 1 }
        return Claim(key: key)
    }

    func release(_ claim: Claim) {
        lock.withLock {
            guard !claim.released else { return }
            claim.released = true
            let left = (counts[claim.key] ?? 1) - 1
            counts[claim.key] = left > 0 ? left : nil
        }
    }

    func isWanted(_ key: String) -> Bool {
        lock.withLock { counts[key] != nil }
    }
}

/// Shows a TMDB image through the ImageStore. Images already in memory appear instantly;
/// others fade in when they arrive.
struct CachedImage<Placeholder: View>: View {
    let path: String?
    let kind: ImageKind
    var fit = false
    var monochrome = false
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var loaded: DecodedImage?
    /// Which image `loaded` is (path and look), so a reused view never shows the wrong one.
    @State private var loadedKey: String?

    var body: some View {
        let image = current
        ZStack {
            if let image {
                // A CGImage draws straight from its pixels; already decoded at display size, so
                // medium quality scaling is enough and cheaper while scrolling.
                Image(decorative: image.cgImage, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: fit ? .fit : .fill)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: wanted) {
            guard let path, !(loadedKey == wanted && loaded != nil) else { return }
            // Already in memory (read ahead, or loaded for another view while this one waited
            // to start): kept here too, so the view redraws with it and keeps it if memory is
            // trimmed. (Returning without keeping it left the placeholder showing.)
            if let hit = ImageStore.shared.cached(path, kind, monochrome: monochrome) {
                loaded = hit
                loadedKey = wanted
                return
            }
            // A load can fail (the network not up yet after waking, a slow connection): it's
            // tried again for as long as the image is on screen, less often as time goes on,
            // instead of leaving the placeholder until Reel is reopened.
            var wait = 0
            while !Task.isCancelled, !ImageStore.shared.isMissing(path, kind) {
                if let fetched = await ImageStore.shared.image(path, kind, monochrome: monochrome) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        loaded = fetched
                        loadedKey = wanted
                    }
                    return
                }
                wait = min(max(wait * 2, 2), 30)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private var wanted: String? {
        path.map { monochrome ? $0 + "~mono" : $0 }
    }

    private var current: DecodedImage? {
        guard let path else { return nil }
        if loadedKey == wanted, let loaded { return loaded }
        return ImageStore.shared.cached(path, kind, monochrome: monochrome)
    }
}
#endif
