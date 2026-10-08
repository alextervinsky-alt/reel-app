import Foundation

/// Everything Reel keeps lives in one folder: ~/Documents/Reel.
///
///     Reel/
///       About this folder.txt
///       Your Notes.json        watched, favorites, watchlist, ratings, notes, match fixes (irreplaceable)
///       Settings.json          TMDB token and your drives (readable only by your user)
///       Library.json           film info for your files (a cache: rebuilt by a rescan if deleted)
///       Safety Copies/         one copy of Your Notes per day, last 30 days
///       Image Cache.nosync/    posters and photos: size-limited, unused ones removed,
///                              never synced to iCloud or backed up by Time Machine
///       List Data.nosync/      IMDb ratings, award lists and sets (downloaded again if deleted)
public struct ReelFolder: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var standard: ReelFolder {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return ReelFolder(root: documents.appendingPathComponent("Reel", isDirectory: true))
    }

    public var notes: URL { root.appendingPathComponent("Your Notes.json") }
    public var settings: URL { root.appendingPathComponent("Settings.json") }
    public var library: URL { root.appendingPathComponent("Library.json") }
    public var safetyCopies: URL { root.appendingPathComponent("Safety Copies", isDirectory: true) }
    public var imageCache: URL { root.appendingPathComponent("Image Cache.nosync", isDirectory: true) }
    public var listData: URL { root.appendingPathComponent("List Data.nosync", isDirectory: true) }
    public var about: URL { root.appendingPathComponent("About this folder.txt") }

    /// Creates the folder structure. Cheap enough to run on every launch.
    public func prepare() {
        let fm = FileManager.default
        for folder in [imageCache, listData] {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            #if os(macOS)
            var cache = folder
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? cache.setResourceValues(values)
            #endif
        }
        let current = try? String(contentsOf: about, encoding: .utf8)
        if current != ReelFolder.aboutText {
            try? Data(ReelFolder.aboutText.utf8).write(to: about, options: .atomic)
        }
    }

    static let aboutText = """
    This folder belongs to the Reel app.

    Your Notes.json       Watched, favorites, watchlist, ratings, notes and the film
                          matches you fixed by hand. This is the file to keep.
    Settings.json         Your TMDB token and your film drives.
    Library.json          Film info for your files. If deleted, Reel rebuilds it.
    Safety Copies         A copy of Your Notes from each of the last 30 days.
    Image Cache.nosync    Posters and photos. Safe to delete any time. Limited to 400 MB,
                          cleaned up automatically, not synced to iCloud and not backed
                          up by Time Machine.
    List Data.nosync      IMDb ratings (a compact copy of IMDb's free files), award lists
                          and the sets you're collecting. Safe to delete: downloaded
                          again when needed.

    Reel never writes anything to your film drives.
    """
}

public enum JSONStore {
    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(type, from: data)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    /// Writes atomically: the old file stays intact until the new one is complete.
    /// `permissions` (e.g. 0o600) is applied to the new file.
    public static func save<T: Encodable>(_ value: T, to url: URL, permissions: Int? = nil) throws {
        let data = try encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }
}

/// Settings.json: the TMDB token and the list of film drives.
public struct ReelSettings: Codable, Equatable, Sendable {
    public var tmdbToken: String
    /// Optional. Empty means no ratings are fetched.
    public var omdbKey: String
    public var drives: [Drive]
    /// The film in the banner last time, so the next launch shows a different one.
    public var lastFeatured: String
    /// Last launch's recommendations, so the next launch picks different films.
    public var lastRecommended: [String]
    /// Hide story details of films you haven't watched (on unless turned off).
    public var spoilerSafe: Bool
    /// The app films open in: "system", "iina" or "vlc".
    public var player: String
    /// IINA and VLC start full screen (on unless turned off).
    public var playFullScreen: Bool
    /// Tonight's shortlist (film keys) and the evening it belongs to ("2026-10-06").
    public var tonight: [String]
    public var tonightEvening: String
    /// Film key → until when it's kept out of Recommended ("Not tonight").
    public var notTonight: [String: Date]
    /// Year in Film counts films seen elsewhere (cinema, streaming) along with the library's.
    public var yearCountsElsewhere: Bool
    /// The films Explore's Picked for You showed last time (left out next time).
    public var lastExplorePicks: [Int]
    /// VLC was switched to IINA once (Reel 1.7.1, for HDR on the TV); choosing VLC again is kept.
    public var switchedToIINA: Bool

    enum CodingKeys: String, CodingKey {
        case tmdbToken, omdbKey, drives, lastFeatured, lastRecommended, spoilerSafe, player, playFullScreen, tonight, tonightEvening
        case notTonight, yearCountsElsewhere, lastExplorePicks, switchedToIINA
    }

    public init(tmdbToken: String = "", omdbKey: String = "", drives: [Drive] = [], lastFeatured: String = "",
                lastRecommended: [String] = [], spoilerSafe: Bool = true, player: String = "system", playFullScreen: Bool = true,
                tonight: [String] = [], tonightEvening: String = "", notTonight: [String: Date] = [:],
                yearCountsElsewhere: Bool = true, lastExplorePicks: [Int] = [], switchedToIINA: Bool = false) {
        self.tmdbToken = tmdbToken
        self.omdbKey = omdbKey
        self.drives = drives
        self.lastFeatured = lastFeatured
        self.lastRecommended = lastRecommended
        self.spoilerSafe = spoilerSafe
        self.player = player
        self.playFullScreen = playFullScreen
        self.tonight = tonight
        self.tonightEvening = tonightEvening
        self.notTonight = notTonight
        self.yearCountsElsewhere = yearCountsElsewhere
        self.lastExplorePicks = lastExplorePicks
        self.switchedToIINA = switchedToIINA
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tmdbToken = try c.decodeIfPresent(String.self, forKey: .tmdbToken) ?? ""
        omdbKey = try c.decodeIfPresent(String.self, forKey: .omdbKey) ?? ""
        drives = try c.decodeIfPresent([Drive].self, forKey: .drives) ?? []
        lastFeatured = try c.decodeIfPresent(String.self, forKey: .lastFeatured) ?? ""
        lastRecommended = try c.decodeIfPresent([String].self, forKey: .lastRecommended) ?? []
        spoilerSafe = try c.decodeIfPresent(Bool.self, forKey: .spoilerSafe) ?? true
        player = try c.decodeIfPresent(String.self, forKey: .player) ?? "system"
        playFullScreen = try c.decodeIfPresent(Bool.self, forKey: .playFullScreen) ?? true
        tonight = try c.decodeIfPresent([String].self, forKey: .tonight) ?? []
        tonightEvening = try c.decodeIfPresent(String.self, forKey: .tonightEvening) ?? ""
        notTonight = try c.decodeIfPresent([String: Date].self, forKey: .notTonight) ?? [:]
        yearCountsElsewhere = try c.decodeIfPresent(Bool.self, forKey: .yearCountsElsewhere) ?? true
        lastExplorePicks = try c.decodeIfPresent([Int].self, forKey: .lastExplorePicks) ?? []
        switchedToIINA = try c.decodeIfPresent(Bool.self, forKey: .switchedToIINA) ?? false
    }
}

/// An evening runs until 6 in the morning, so a shortlist made at 21:00 is still there after midnight.
public enum Evening {
    public static func of(_ date: Date, calendar: Calendar = .current) -> String {
        let shifted = date.addingTimeInterval(-6 * 3600)
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Runs file writes one after another on a background queue, so saving never stalls the app.
public final class FileWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "reel.file-writer", qos: .utility)

    public init() {}

    public func enqueue(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Waits until every queued write has finished (used when the app quits).
    public func flush() {
        queue.sync {}
    }
}

public enum SafetyCopies {
    /// Local calendar day, e.g. "2026-10-05", as used in safety copy names.
    public static func day(_ date: Date) -> String {
        dayFormatter().string(from: date)
    }

    static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// Keeps one copy per day of `file` in `folder` ("Your Notes 2026-10-05.json") and deletes
    /// copies older than `keepDays`.
    public static func make(of file: URL, into folder: URL, now: Date = Date(), keepDays: Int = 30) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = dayFormatter()
        let stem = file.deletingPathExtension().lastPathComponent
        let target = folder.appendingPathComponent("\(stem) \(formatter.string(from: now)).json")
        if !fm.fileExists(atPath: target.path) {
            try? fm.copyItem(at: file, to: target)
        }

        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        let items = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for item in items where item.hasPrefix(stem + " ") && item.hasSuffix(".json") {
            let datePart = item.dropFirst(stem.count + 1).dropLast(5)
            if let date = formatter.date(from: String(datePart)), date < cutoff {
                try? fm.removeItem(at: folder.appendingPathComponent(item))
            }
        }
    }
}

public enum CacheMaintenance {
    /// Total size of the files in `folder`, in bytes.
    public static func size(of folder: URL) -> Int64 {
        files(in: folder).reduce(0) { $0 + $1.size }
    }

    /// If the folder is larger than `limit`, deletes the least recently used files until it is
    /// below `target`.
    @discardableResult
    public static func trim(_ folder: URL, limit: Int64, target: Int64) -> Int {
        let all = files(in: folder)
        var total = all.reduce(0) { $0 + $1.size }
        guard total > limit else { return 0 }
        var removed = 0
        for file in all.sorted(by: { $0.date < $1.date }) {
            if total <= target { break }
            if (try? FileManager.default.removeItem(at: file.url)) != nil {
                total -= file.size
                removed += 1
            }
        }
        return removed
    }

    /// Deletes files whose names are not in `keep` and that were last used before `cutoff`
    /// (posters of films no longer in the library, leftovers of interrupted downloads).
    @discardableResult
    public static func removeUnreferenced(in folder: URL, keep: Set<String>, olderThan cutoff: Date) -> Int {
        var removed = 0
        for file in files(in: folder) where !keep.contains(file.url.lastPathComponent) && file.date < cutoff {
            if (try? FileManager.default.removeItem(at: file.url)) != nil { removed += 1 }
        }
        return removed
    }

    /// Deletes every file in the folder but keeps the folder.
    public static func clear(_ folder: URL) {
        for file in files(in: folder) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    struct CachedFile {
        let url: URL
        let size: Int64
        let date: Date
    }

    /// All files in the folder, hidden ones included (so stray temporary files are cleaned too).
    static func files(in folder: URL) -> [CachedFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
            return CachedFile(url: url, size: Int64(v.fileSize ?? 0), date: v.contentModificationDate ?? .distantPast)
        }
    }
}
