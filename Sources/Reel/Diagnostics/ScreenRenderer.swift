#if os(macOS)
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import ReelCore

/// Draws Cinema mode's screens to PNG files, for checking the layout at the sizes the TV shows
/// (CI runs this after the build). Only runs when REEL_RENDER_SCREENS names an output folder:
/// Reel then works from a temporary folder with a sample library made from real TMDB info,
/// renders, and quits. Nothing in Documents › Reel is read or written, and no drive is touched.
@MainActor
enum ScreenRenderer {
    static var outputFolder: URL? {
        ProcessInfo.processInfo.environment["REEL_RENDER_SCREENS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static var isRequested: Bool { outputFolder != nil }

    /// Where the sample library lives while rendering.
    static let folder = ReelFolder(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("Reel Screens \(ProcessInfo.processInfo.processIdentifier)", isDirectory: true))

    /// The laptop's own size (what the TV shows when mirroring), 1080p and 4K.
    private static let sizes: [(name: String, width: CGFloat, height: CGFloat, scale: CGFloat)] = [
        ("laptop", 1470, 956, 2),
        ("1080p", 1920, 1080, 1),
        ("4K", 1920, 1080, 2),
    ]

    /// Well-known films with logos, backdrops and trailers on TMDB.
    private static let sampleIDs = [603, 27205, 680, 155, 496243, 129, 120467, 324857, 545611, 872585, 419430, 194, 238, 14160,
                                    550, 13, 769, 157336, 11324, 1124, 77, 273481, 335984, 438631, 76341, 666277, 10681, 862]

    static func run(_ model: AppModel) async {
        guard let output = outputFolder else { return }
        log("started")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        guard let token = ProcessInfo.processInfo.environment["TMDB_TOKEN"], !token.isEmpty else {
            log("TMDB_TOKEN is not set, nothing rendered.")
            finish()
            return
        }
        let films = await model.loadScreenSample(ids: sampleIDs, token: token)
        log("\(model.films.count) sample films loaded")
        guard let first = films.first else {
            log("no sample films could be loaded.")
            finish()
            return
        }
        await preloadImages(for: model.films)
        log("backdrops framed")

        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let tonight = model.tonightItems.first?.main ?? first
        for size in sizes {
            let screens: [(String, AnyView)] = [
                ("cinema-home", AnyView(CinemaView(searchText: .constant(""), query: ""))),
                ("cinema-film", AnyView(CinemaView(searchText: .constant(""), query: "", path: [first.id]))),
                ("cinema-tonight", AnyView(CinemaView(searchText: .constant(""), query: "", tab: .tonight))),
                ("cinema-library", AnyView(CinemaView(searchText: .constant(""), query: "", tab: .library))),
            ]
            log("drawing \(size.name)")
            for (name, view) in screens {
                render(view.frame(width: size.width, height: size.height).clipped(), model: model, scale: size.scale,
                       to: output.appendingPathComponent("\(name)-\(size.name).png"))
            }
        }
        // Sheets at their own size, on the dark window they open over (system buttons and
        // materials can't be drawn to an image and show as blank shapes).
        let item = model.item(forKey: first.personalKey)
        if let item {
            render(QuickPreview(item: item, close: {}, openFilm: {}).background(Theme.panel).background(Theme.background), model: model, scale: 2, to: output.appendingPathComponent("quick-look.png"))
            // A Cinema poster under the pointer, beside one that isn't.
            let neighbours = model.items.filter { $0.id != item.id }.prefix(2)
            render(HStack(alignment: .top, spacing: 26) {
                CinemaPosterTile(item: item, marks: CinemaTileMarks(model: model, key: item.id), reason: nil, caption: nil,
                                 selected: true) {}
                ForEach(Array(neighbours)) { other in
                    CinemaPosterTile(item: other, marks: CinemaTileMarks(model: model, key: other.id),
                                     reason: model.pickReason(forKey: other.id)?.short, caption: nil, selected: false) {}
                }
            }
            .padding(40)
            .background(Theme.background), model: model, scale: 2, to: output.appendingPathComponent("cinema-poster-pointed.png"))
        }
        // The library view's Tonight comparison (the same aligned rows as Cinema mode's).
        let slots = TonightSlots(model.tonightItems, model: model)
        render(HStack(alignment: .top, spacing: 16) {
            ForEach(model.tonightItems) { item in
                TonightCompareColumn(item: item, slots: slots, width: TonightSlots.width(for: 2, in: 900, large: false),
                                     chosen: false, dimmed: false, large: false) {}
            }
        }
        .padding(32)
        .background(Theme.background), model: model, scale: 2, to: output.appendingPathComponent("library-tonight.png"))
        render(HowWasItSheet(prompt: RatingPrompt(id: tonight.personalKey, filmID: tonight.id, askFinished: true))
                .background(Theme.panel).background(Theme.background),
               model: model, scale: 2, to: output.appendingPathComponent("did-you-finish.png"))
        // Behind the Film for the first film, once its facts and article are fetched.
        await model.loadArticle(for: first)
        if let film = model.film(id: first.id) {
            render(BehindTheFilmTab(film: film) { _, _ in }
                    .padding(32)
                    .frame(width: 900)
                    .background(Theme.background),
                   model: model, scale: 2, to: output.appendingPathComponent("behind-the-film.png"))
            render(CameraTab(film: film)
                    .padding(32)
                    .frame(width: 900)
                    .background(Theme.background),
                   model: model, scale: 2, to: output.appendingPathComponent("camera.png"))
        }
        // Explore's Picked for You (from the sample's watched films), with its posters loaded.
        await model.loadExplorePicks()
        for pick in model.explorePicks ?? [] {
            if let path = pick.film.posterPath { _ = await ImageStore.shared.image(path, .poster) }
        }
        render(PickedForYouRow { _ in }
                .padding(32)
                .frame(width: 1300)
                .background(Theme.background),
               model: model, scale: 2, to: output.appendingPathComponent("picked-for-you.png"))
        // All Films' banner and a Recommended card, each with the whole synopsis.
        if let item = model.featured ?? model.items.first {
            render(VStack(alignment: .leading, spacing: 30) {
                        FeaturedBanner(item: item, open: {}, showTrailer: {})
                        RecommendationCard(number: 1, item: item).padding(.horizontal, 32)
                    }
                    .padding(.bottom, 32)
                    .frame(width: 1300)
                    .background(Theme.background),
                   model: model, scale: 2, to: output.appendingPathComponent("banner-and-card.png"))
        }
        // Explore in one mood: Picked for You narrowed to it, and the mood's own row.
        await model.loadDiscover(.mood(.dark))
        let moodPosters = (model.discover[.mood(.dark)] ?? []).prefix(8).compactMap(\.posterPath)
            + model.explorePicks(in: .dark).compactMap(\.film.posterPath)
        for path in moodPosters { _ = await ImageStore.shared.image(path, .poster) }
        render(VStack(alignment: .leading, spacing: 38) {
                    PickedForYouRow(mood: .dark) { _ in }
                    DiscoverRow(list: .mood(.dark)) { _ in }
                }
                .padding(32)
                .frame(width: 1300)
                .background(Theme.background),
               model: model, scale: 2, to: output.appendingPathComponent("explore-mood.png"))
        log("rendered \((try? FileManager.default.contentsOfDirectory(atPath: output.path).count) ?? 0) screens")
        finish()
    }

    /// Images must be in memory before drawing: a rendered view can't wait for a download.
    private static func preloadImages(for films: [FilmEntry]) async {
        let details = films.compactMap { $0.tmdb }
        await withTaskGroup(of: Void.self) { group in
            for info in details {
                group.addTask {
                    for (path, kind) in [(info.posterPath, ImageKind.poster), (info.logoPath, .logo), (info.backdropPath, .backdrop)] {
                        if let path { _ = await ImageStore.shared.image(path, kind) }
                    }
                }
            }
        }
        log("images loaded")
        // Framing backdrops around faces, given a minute at most (a slow runner draws the
        // default framing instead of waiting for ever).
        let framing = Task { @MainActor in
            for info in details {
                guard let path = info.backdropPath, let image = ImageStore.shared.cached(path, .backdrop) else { continue }
                _ = await BackdropFocus.peopleTop(path: path, image: image)
            }
        }
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline {
            if details.allSatisfy({ $0.backdropPath.map { BackdropFocus.known($0) != nil } ?? true }) { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        framing.cancel()
    }

    private static func render(_ view: some View, model: AppModel, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view
            .environment(model)
            .environment(\.isSnapshot, true)
            .environment(\.colorScheme, .dark))
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            log("couldn't render \(url.lastPathComponent)")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) { log("couldn't write \(url.lastPathComponent)") }
    }

    /// Progress as a GitHub notice, written at once (the CI step stops Reel if it hangs).
    private static let started = ContinuousClock.now

    private static func log(_ message: String) {
        let seconds = (ContinuousClock.now - started).components.seconds
        FileHandle.standardOutput.write(Data("::notice::Screens: \(message) (\(seconds) s)\n".utf8))
    }

    private static func finish() {
        try? FileManager.default.removeItem(at: folder.root)
        exit(0)
    }
}

extension AppModel {
    /// A small library on a pretend "Films" drive: some films new, some watched and rated,
    /// two on tonight's shortlist. Returns the films in the order of `ids` that loaded.
    func loadScreenSample(ids: [Int], token: String) async -> [FilmEntry] {
        self.token = token
        hasToken = true
        let client = TMDBClient(token: token)
        let details = await withTaskGroup(of: (Int, TMDBMovieDetails?).self) { group in
            for id in ids {
                group.addTask { (id, try? await client.movieDetails(id: id).trimmed()) }
            }
            var found: [Int: TMDBMovieDetails] = [:]
            for await (id, value) in group { found[id] = value }
            return found
        }

        let now = Date()
        let drive = Drive(name: "Films", volumeUUID: nil, folderInVolume: "", lastKnownPath: ScreenRenderer.folder.root.path,
                          arrivalsSince: now.addingTimeInterval(-90 * 86_400), lastScanned: now)
        let sample: [FilmEntry] = ids.enumerated().compactMap { index, id in
            guard let info = details[id] else { return nil }
            let year = info.releaseDate.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } ?? ""
            let name = "\(info.title) (\(year))"
            var film = FilmEntry(driveID: drive.id, relativePath: "\(name)/\(name).mkv", fileName: "\(name).mkv",
                                 size: 18_000_000_000, modified: now,
                                 // The last three arrived this week.
                                 addedAt: index >= ids.count - 3 ? now.addingTimeInterval(-2 * 86_400) : now.addingTimeInterval(-200 * 86_400),
                                 matchState: .confirmed, tmdb: info)
            film.infoVersion = FilmEntry.currentInfoVersion
            film.infoUpdatedAt = now
            return film
        }

        // Four watched and rated (Recommended learns from them), two on tonight's shortlist, all
        // before the first build, as when Reel opens.
        for (film, stars) in zip(sample.prefix(4), [5, 4, 5, 3]) {
            _ = personal.set(PersonalRecord(watched: true, rating: stars, watchedOn: now), forKey: film.personalKey)
        }
        startNewEveningIfNeeded()
        tonight = sample.dropFirst(4).prefix(2).map { $0.personalKey }
        drives = [drive]
        mounted = [drive.id: ScreenRenderer.folder.root]
        films = sample
        isLoaded = true
        rebuild()
        return sample.filter { !personal.watchedKeys.contains($0.personalKey) }
    }
}
#endif
