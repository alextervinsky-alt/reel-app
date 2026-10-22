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
        // Every 20 seconds, from off the main thread: says whether the main thread still answers.
        Thread.detachNewThread {
            while true {
                Thread.sleep(forTimeInterval: 20)
                let main = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { main.signal() }
                let pool = DispatchSemaphore(value: 0)
                Task.detached { pool.signal() }
                let mainAnswers = main.wait(timeout: .now() + 5) == .success
                let poolAnswers = pool.wait(timeout: .now() + 5) == .success
                log("…still working (main thread \(mainAnswers ? "free" : "stuck"), task pool \(poolAnswers ? "free" : "stuck"))")
            }
        }
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

        // How the first few films were shot (as the background reading does it), for the Shot on
        // filters and a craft search; and the first film's article, for Did You Know on the TV.
        await readCraft(of: Array(model.films.prefix(4)), into: model)
        await model.loadArticle(for: first)
        log("article read")

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
        // The same on the TV, at 1080p: the stars, picked with the arrow keys.
        render(CinemaHowWasIt(prompt: RatingPrompt(id: tonight.personalKey, filmID: tonight.id))
                .frame(width: 1920, height: 1080).background(Theme.background),
               model: model, scale: 1, to: output.appendingPathComponent("cinema-how-was-it.png"))
        // Seen It? from Unwatched, and Pair It With on a film page.
        render(SeenSweep(queue: model.seenSweepQueue()).background(Theme.panel).background(Theme.background),
               model: model, scale: 2, to: output.appendingPathComponent("seen-it.png"))
        if let film = model.film(id: first.id), let pair = model.pairing(for: film) {
            render(PairItWith(film: film, partner: pair.item, reason: pair.reason).padding(32).frame(width: 900).background(Theme.background),
                   model: model, scale: 2, to: output.appendingPathComponent("pair-it-with.png"))
            log("pair for \(film.displayTitle): \(pair.item.main.displayTitle), \(pair.reason)")
        }
        // Behind the Film for the first film (its facts and article were fetched above).
        if let film = model.film(id: first.id) {
            render(BehindTheFilmTab(film: film)
                    .padding(32)
                    .frame(width: 900)
                    .background(Theme.background),
                   model: model, scale: 2, to: output.appendingPathComponent("behind-the-film.png"))
            // With the interviews it cites and the cinematographer's article.
            await model.loadCameraReading(for: film)
            log("interviews read")
            render(CinematographyTab(film: film) { _, _ in }
                    .padding(32)
                    .frame(width: 900)
                    .background(Theme.background),
                   model: model, scale: 2, to: output.appendingPathComponent("cinematography.png"))
        }
        // For You (from the sample's watched films): its first six, with their frames and details loaded.
        await model.loadExplorePicks()
        log("For You picked")
        let shown = Array((model.explorePicks ?? []).prefix(6))
        for pick in shown {
            if let path = pick.film.backdropPath { _ = await ImageStore.shared.image(path, .backdrop) }
            _ = await model.previewInfo(for: pick.id)
        }
        render(ForYouGrid(picks: Array(shown.prefix(3))) { _ in }
                .padding(32)
                .frame(width: 1300)
                .background(Theme.background),
               model: model, scale: 2, to: output.appendingPathComponent("for-you.png"))
        log("For You drawn")
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
        log("banner drawn")
        // The desk's posters (with their quality, ratings and NEW), the list, a film's At a
        // Glance and the sidebar's Tonight card.
        let deskItems = Array(model.items.prefix(6))
        render(HStack(alignment: .top, spacing: 22) {
                    ForEach(deskItems) { item in
                        PosterCard(item: item, isNew: model.arrivals[item.id] != nil).frame(width: 170)
                    }
                }
                .padding(32)
                .background(Theme.background)
                .environment(ScrollState()),
               model: model, scale: 2, to: output.appendingPathComponent("desk-posters.png"))
        // Under the pointer at the smallest, the usual and a large poster size: all three ratings
        // (the sample has no OMDb key, so a film is given three).
        if let sample = model.items.first {
            var rated = sample.main
            rated.ratings = ExternalRatings(imdb: 8.1, rottenTomatoes: 93, metacritic: 81)
            render(HStack(alignment: .bottom, spacing: 22) {
                        ForEach([130.0, 168.0, 205.0], id: \.self) { width in
                            Poster(path: rated.tmdb?.posterPath, title: rated.displayTitle, cornerRadius: 12)
                                .frame(width: width, height: width * 1.5)
                                .overlay(alignment: .bottom) { PosterHoverRatings(film: rated, runtime: sample.runtime) }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(32)
                    .background(Theme.background),
                   model: model, scale: 2, to: output.appendingPathComponent("desk-hover-ratings.png"))
        }
        render(FilmList(items: Array(model.items.prefix(10)), sort: .constant(.rating), sortable: true)
                .padding(32)
                .frame(width: 1240)
                .background(Theme.background),
               model: model, scale: 2, to: output.appendingPathComponent("desk-list.png"))
        if let film = model.film(id: first.id) {
            render(FilmFactSheet(film: film).frame(width: 340).padding(32).background(Theme.background),
                   model: model, scale: 2, to: output.appendingPathComponent("desk-at-a-glance.png"))
        }
        render(TonightCard(isSelected: false) {}.frame(width: 216).padding(20).background(Theme.sidebar).background(Theme.background),
               model: model, scale: 2, to: output.appendingPathComponent("desk-tonight-card.png"))
        log("desk drawn")
        render(YearInFilmView().frame(width: 1240, height: 2700).background(Theme.background),
               model: model, scale: 1, to: output.appendingPathComponent("year-in-film.png"))
        log("Year in Film: \(YearInFilm(year: Calendar.current.component(.year, from: Date()), from: model.yearFilms()).films.count) films")
        // Explore in one mood (the mood's own row), this launch's shelves, and the best of a year
        // (from the hidden gems: one TMDB request, where the award winners need all the award lists).
        let year = Calendar.current.component(.year, from: Date()) - 2
        log("Explore: loading")
        await model.loadDiscover(.mood(.dark))
        log("Explore: mood loaded")
        for shelf in model.exploreShelves {
            await model.loadDiscover(shelf)
            log("Explore: \(shelf.title) loaded")
        }
        await model.loadBestOf(year: year, source: .gems)
        log("Explore: best of loaded")
        var explorePosters = (model.discover[.mood(.dark)] ?? []).prefix(8).compactMap(\.posterPath)
        for shelf in model.exploreShelves { explorePosters += model.exploreFilms(shelf, mood: nil).prefix(8).compactMap(\.posterPath) }
        explorePosters += (model.bestOf(year: year, source: .gems) ?? []).prefix(8).compactMap(\.posterPath)
        // At most half a minute: CI's network has stalled a download here past every timeout,
        // and a poster that isn't in is drawn as its placeholder.
        let posters = Task.detached { for path in explorePosters { _ = await ImageStore.shared.image(path, .poster) } }
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline, explorePosters.contains(where: { ImageStore.shared.cached($0, .poster) == nil }) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        posters.cancel()
        log("Explore: \(explorePosters.filter { ImageStore.shared.cached($0, .poster) != nil }.count) of \(explorePosters.count) posters loaded")
        render(VStack(alignment: .leading, spacing: 38) {
                    DiscoverRow(list: .mood(.dark)) { _ in }
                    ForEach(model.exploreShelves, id: \.self) { shelf in DiscoverRow(list: shelf) { _ in } }
                    BestOfRow(year: .constant(year), source: .constant(.gems)) { _ in }
                }
                .padding(32)
                .frame(width: 1300)
                .background(Theme.background),
               model: model, scale: 2, to: output.appendingPathComponent("explore-mood.png"))
        await acclaimedScreens(model, output: output)
        log("rendered \((try? FileManager.default.contentsOfDirectory(atPath: output.path).count) ?? 0) screens")
        speedCheck(model.films)
        await scrollCheck(model, first: first, output: output)
        finish()
    }

    /// Last year's most acclaimed (in Explore and the Lists' rankings), once IMDb's ratings are in
    /// (downloaded here, two minutes at most), with the critics' scores when OMDB_KEY is set.
    private static func acclaimedScreens(_ model: AppModel, output: URL) async {
        let year = Calendar.current.component(.year, from: Date()) - 1
        if let key = ProcessInfo.processInfo.environment["OMDB_KEY"], !key.isEmpty { model.omdbKey = key }
        await model.lists.load(.acclaimed(year))
        let deadline = ContinuousClock.now + .seconds(120)
        while ContinuousClock.now < deadline, !model.lists.imdbIsReady, !model.lists.imdbFailed {
            try? await Task.sleep(for: .seconds(1))
        }
        guard model.lists.imdbIsReady else {
            log("acclaimed: IMDb's ratings didn't arrive")
            return
        }
        await model.loadBestOf(year: year, source: .acclaimed)
        let shown = (model.bestOf(year: year, source: .acclaimed) ?? []).prefix(8)
        for film in shown { if let path = film.posterPath { _ = await ImageStore.shared.image(path, .poster) } }
        log("acclaimed \(year): " + model.lists.films(for: .acclaimed(year)).prefix(12).map { "\($0.title) (\($0.note ?? ""))" }.joined(separator: "; "))
        render(BestOfRow(year: .constant(year), source: .constant(.acclaimed)) { _ in }
                .padding(32)
                .frame(width: 1300)
                .background(Theme.background),
               model: model, scale: 2, to: output.appendingPathComponent("explore-acclaimed.png"))
        if let client = model.tmdb {
            let kinds: [FilmListKind] = [.acclaimed(year), .imdbAllTime, .imdbYear(year), .imdbDecade(year / 10 * 10), .imdbMostVoted]
            await model.lists.resolve(kinds.flatMap { model.lists.films(for: $0).prefix(3) }, using: client)
            for kind in kinds {
                for film in model.lists.films(for: kind).prefix(3) {
                    if let path = model.lists.resolved(film)?.posterPath { _ = await ImageStore.shared.image(path, .poster) }
                }
            }
        }
        render(IMDbSection(columns: [GridItem(.adaptive(minimum: 330), spacing: 18, alignment: .top)])
                .padding(32)
                .frame(width: 1240)
                .background(Theme.background),
               model: model, scale: 2, to: output.appendingPathComponent("lists-rankings.png"))
    }

    /// How smoothly the pages scroll (see `ScrollTiming`): a film page, a person's page, Explore,
    /// Lists, then All Films with 500 films. Written to scroll.txt beside the screens.
    private static func scrollCheck(_ model: AppModel, first: FilmEntry, output: URL) async {
        // The machine itself: a page of plain tiles, laid out as All Films is, with nothing in them.
        let plain = AnyView(ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 205), spacing: 22)], spacing: 30) {
                ForEach(0..<600, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 12).fill(Color(hue: Double(index % 12) / 12, saturation: 0.4, brightness: 0.5))
                        .aspectRatio(2 / 3, contentMode: .fit)
                }
            }
            .padding(32)
        }.background(Theme.background))
        var pages = [ScrollTiming.Page(name: "Plain tiles (the machine)", view: plain),
                     ScrollTiming.Page(name: "Film page", view: AnyView(NavigationStack { FilmPage(filmID: first.id) }))]
        if let director = first.tmdb?.credits?.crew.first(where: { $0.job == "Director" }), let id = director.id {
            pages.append(ScrollTiming.Page(name: "Person page", view: AnyView(NavigationStack { PersonPage(route: PersonRoute(id: id, name: director.name)) })))
        }
        pages.append(ScrollTiming.Page(name: "Explore", view: AnyView(NavigationStack { ExploreView(path: .constant(NavigationPath())) })))
        pages.append(ScrollTiming.Page(name: "Lists", view: AnyView(NavigationStack { ListsView() })))
        var lines = await ScrollTiming.run(pages, model: model, log: log)
        // All Films as it opens, in the whole window, with 500 films on the drive.
        if let drive = model.drives.first {
            model.setFilms(copies(of: model.films, count: 500, drives: [drive.id]), urgent: true)
            for path in model.films.compactMap({ $0.tmdb?.posterPath }) { _ = await ImageStore.shared.image(path, .poster) }
            lines += await ScrollTiming.run([ScrollTiming.Page(name: "All Films, 500 films", view: AnyView(RootView()))], model: model, log: log)
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: output.appendingPathComponent("scroll.txt"), atomically: true, encoding: .utf8)
    }

    /// The sample, copied under other TMDB ids up to `count` films, on the given drives (every tenth
    /// copy missing from the second, as a Backup with gaps).
    private static func copies(of sample: [FilmEntry], count: Int, drives: [String]) -> [FilmEntry] {
        var films: [FilmEntry] = []
        for index in 0..<count {
            var source = sample[index % sample.count]
            if var details = source.tmdb { details.id = 1_000_000 + index; source.tmdb = details }
            let name = "Copy \(index) \(source.displayTitle)"
            for (number, drive) in drives.enumerated() where number == 0 || index % 10 != 0 {
                films.append(FilmEntry(driveID: drive, relativePath: "\(name)/\(name).mkv", fileName: "\(name).mkv",
                                       size: 18_000_000_000, modified: Date(), addedAt: Date(), matchState: .confirmed,
                                       tmdb: source.tmdb))
            }
        }
        return films
    }

    /// Reads how these films were shot, as `AppModel.readCraft` does in the background, and logs
    /// what was found and what a craft search finds.
    private static func readCraft(of sample: [FilmEntry], into model: AppModel) async {
        // Their Wikipedia facts first: they say which article is the film's.
        for film in sample { await model.loadFunFacts(for: film) }
        let films = sample.map { model.film(id: $0.id) ?? $0 }
        for film in films { if let details = film.tmdb { await model.loadCollection(of: details) } }
        let read = await withTaskGroup(of: (Int, CraftIndex?).self) { group in
            for film in films {
                guard let details = film.tmdb else { continue }
                let others = model.otherTitles(of: details)
                group.addTask {
                    (details.id, await CraftReader.read(details, articleTitle: film.funFacts?.articleTitle,
                                                        colour: film.funFacts?.quick?.colour, otherTitles: others)?.index)
                }
            }
            var found: [Int: CraftIndex] = [:]
            for await (id, index) in group { found[id] = index }
            return found
        }
        model.mutateFilms(urgent: true) { list in
            for i in list.indices { if let id = list[i].tmdb?.id, let index = read[id] { list[i].craft = index } }
        }
        for film in films {
            guard let index = film.tmdb.flatMap({ read[$0.id] }) else { continue }
            log("craft of \(film.displayTitle): \(index.shotOn.map(\.title).joined(separator: ", ")); \(index.names.prefix(8).joined(separator: ", "))")
            // The sentence behind each tag, so a build shows why (and a wrong one can be caught).
            for kind in index.shotOn {
                guard let why = index.evidence(for: kind) else { continue }
                log("why \(film.displayTitle) is \(index.label(for: kind)): \(why.source): \(why.text.prefix(200))")
            }
        }
        for query in ["anamorphic", "imax", "steadicam", "cartoon", "sci-fi"] {
            let found = model.shelfItems(.all, matching: query, sortedBy: .title).prefix(4).map(\.main.displayTitle)
            log("search “\(query)”: \(found.joined(separator: ", "))")
        }
    }

    /// How long the library's everyday work takes with 500 films (the sample, copied under other
    /// TMDB ids, on a main drive and a Backup): building the grid's items, sorting, searching,
    /// More Like This and the Backup comparison. Written to the log, for keeping Reel quick.
    private static func speedCheck(_ sample: [FilmEntry]) {
        guard !sample.isEmpty else { return }
        let films = copies(of: sample, count: 500, drives: ["Main", "Backup"])
        func time(_ work: () -> Void) -> Int {
            let start = ContinuousClock.now
            work()
            let elapsed = (ContinuousClock.now - start).components
            return Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
        }
        var items: [LibraryItem] = []
        let build = time {
            items = AppModel.makeItems(films: films, online: ["Main", "Backup"]) { film in
                film.tmdb.map { MoodClassifier.moods(genres: $0.genreNames, keywords: $0.keywordNames, runtime: $0.runtime) } ?? []
            }.items
        }
        let sort = time {
            _ = items.sorted { $0.sortTitle < $1.sortTitle }
            _ = items.map { (EveningOrder.stableHash("seed" + $0.id), $0) }.sorted { $0.0 < $1.0 }
        }
        let search = time {
            for query in ["blade", "nolan", "anamorphic", "cartoon", "villenueve"] {
                let terms = SearchQuery.terms(query)
                _ = items.filter { $0.search.relevance(terms, allowTypos: true) > 0 }
            }
        }
        let similar = time {
            let counts = Likeness.keywordCounts(items.map(\.likeness))
            for me in items.prefix(5) {
                _ = items.map { Likeness.score(me.likeness, $0.likeness, keywordCounts: counts, libraryCount: items.count) }
            }
        }
        let backup = time { _ = BackupCheck.gaps(in: films, backupDrives: ["Backup"]) }
        log("speed with \(items.count) films: building \(build) ms, sorting \(sort) ms, five searches \(search) ms, "
            + "More Like This for five films \(similar) ms, Backup comparison \(backup) ms")
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

    /// Progress as a GitHub notice, written at once (the CI step stops Reel if it hangs), and
    /// into progress.txt beside the screens (GitHub shows only a step's first ten notices; the
    /// file is published with the screens even when the step is stopped).
    private nonisolated static let started = ContinuousClock.now

    /// Callable from any thread: the watchdog writes while the main thread may be stuck.
    nonisolated static func log(_ message: String) {
        let seconds = (ContinuousClock.now - started).components.seconds
        let line = "Screens: \(message) (\(seconds) s)\n"
        FileHandle.standardOutput.write(Data(("::notice::" + line).utf8))
        guard let folder = ProcessInfo.processInfo.environment["REEL_RENDER_SCREENS"] else { return }
        let file = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent("progress.txt")
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
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
        // Three nights in a row and one a week before, for Year in Film; two more a month ago.
        let day: TimeInterval = 86_400
        for (film, (stars, ago)) in zip(sample.prefix(4), [(5, 0.0), (4, 1), (5, 2), (3, 9)]) {
            _ = personal.set(PersonalRecord(watched: true, rating: stars, watchedOn: now.addingTimeInterval(-ago * day)), forKey: film.personalKey)
        }
        for (film, (stars, ago)) in zip(sample.dropFirst(6).prefix(2), [(Optional(2), 40.0), (nil, 41)]) {
            _ = personal.set(PersonalRecord(watched: true, rating: stars, watchedOn: now.addingTimeInterval(-ago * day)), forKey: film.personalKey)
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
