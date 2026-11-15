#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

/// Code review 1.11, scratch branch `review-1.11` only (throwaway, never merged): how many times
/// the grid and its cards are evaluated while scrolling.
@MainActor
enum ReviewCount {
    static var grid = 0
    static var card = 0
    static func bumpGrid() { grid += 1 }
    static func bumpCard() { card += 1 }
}

/// Code review 1.11 measurements, run on CI's macOS runner with a synthetic library made from the
/// screen sample (real TMDB info, copied under other ids). Nothing of anyone's own library is used.
@MainActor
enum ReviewMeasure {
    private static func ms(since start: ContinuousClock.Instant) -> String {
        let parts = (ContinuousClock.now - start).components
        return String(format: "%.1f", Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15)
    }

    private static func log(_ message: String) { ScreenRenderer.log("REVIEW " + message) }

    static func run(_ model: AppModel, sample: [FilmEntry],
                    copies: ([FilmEntry], Int, [String]) -> [FilmEntry]) async {
        // Every copy gets a reading and facts from the films that have them, so each copy is about
        // as large as in a real library.
        let rich = model.films.filter { $0.craft != nil }
        let facts = model.films.filter { $0.funFacts != nil }
        let drive = model.drives.first?.id ?? "Main"
        var films = copies(model.films, 300, [drive, "Backup"])
        for i in films.indices {
            if !rich.isEmpty { films[i].craft = rich[i % rich.count].craft }
            if films[i].funFacts == nil, !facts.isEmpty { films[i].funFacts = facts[i % facts.count].funFacts }
        }
        let count = films.count
        log("synthetic library: 300 films, \(count) copies (\(rich.count) readings and \(facts.count) fact sets lent to every copy)")

        // Library.json at 300 films.
        var start = ContinuousClock.now
        let data = (try? JSONStore.encode(LibraryFile(films: films))) ?? Data()
        let encode = ms(since: start)
        start = ContinuousClock.now
        let decoded = try? JSONStore.decode(LibraryFile.self, from: data)
        let decode = ms(since: start)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("review-library-\(ProcessInfo.processInfo.processIdentifier).json")
        start = ContinuousClock.now
        try? JSONStore.save(LibraryFile(films: films), to: url)
        let save = ms(since: start)
        try? FileManager.default.removeItem(at: url)
        log("Library.json: \(data.count) bytes for \(count) copies; encode \(encode) ms, decode \(decode) ms (\(decoded?.films.count ?? 0) read back), "
            + "save (encode and atomic write) \(save) ms")
        let oneCopy = (try? JSONStore.encode(films[0]))?.count ?? 0
        let craftBytes = (try? JSONStore.encode(films.compactMap(\.craft)))?.count ?? 0
        let tmdbBytes = (try? JSONStore.encode(films.compactMap(\.tmdb)))?.count ?? 0
        log("Library.json parts: one copy \(oneCopy) bytes; all readings \(craftBytes) bytes; all TMDB info \(tmdbBytes) bytes")

        // The guard in `setFilms`: the whole library compared after one film changed.
        var changed = films
        changed[count / 2].lastLookup = Date()
        start = ContinuousClock.now
        let equal = changed == films
        log("comparing \(count) copies after one change: \(ms(since: start)) ms (equal: \(equal))")
        let again = films
        start = ContinuousClock.now
        let same = again == films
        log("comparing \(count) copies with an unchanged copy of the array: \(ms(since: start)) ms (equal: \(same))")

        // The model: the first build, a rebuild with nothing changed, one film's info changing.
        start = ContinuousClock.now
        model.setFilms(films, urgent: true)
        log("setFilms + first rebuild, all items built: \(ms(since: start)) ms, \(model.items.count) items")
        start = ContinuousClock.now
        model.rebuild()
        log("rebuild with nothing changed: \(ms(since: start)) ms")
        start = ContinuousClock.now
        model.mutateFilms(urgent: true) { list in list[list.count / 2].lastLookup = Date() }
        log("one film's info changed (copy, compare, rebuild): \(ms(since: start)) ms")
        start = ContinuousClock.now
        model.mutateFilms(urgent: true) { list in
            if let craft = list[list.count / 3].craft { list[list.count / 3].craft = craft }
            list[list.count / 3].craftAttempt = nil
            list[list.count / 3].lastLookup = Date()
        }
        log("another film's info changed (copy, compare, rebuild): \(ms(since: start)) ms")

        // What the grid's body works out each time it is evaluated.
        for (label, query) in [("no search", ""), ("search “nolan”", "nolan"), ("search with a slip “villenueve”", "villenueve")] {
            start = ContinuousClock.now
            for _ in 0..<10 { _ = model.shelfItems(.all, matching: query, sortedBy: .random) }
            log("shelfItems(All Films, \(label), random order) ×10: \(ms(since: start)) ms")
        }
        start = ContinuousClock.now
        for _ in 0..<10 { _ = model.shelfItems(.unwatched, matching: "", sortedBy: .title) }
        log("shelfItems(Unwatched, by title) ×10: \(ms(since: start)) ms")

        // A film page: hosted in a window, laid out and drawn for the first time.
        for film in [model.items.first?.main, model.items.dropFirst(7).first?.main].compactMap({ $0 }) {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: ScrollTiming.size),
                                  styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            start = ContinuousClock.now
            let host = NSHostingView(rootView: NavigationStack { FilmPage(filmID: film.id) }
                .environment(model)
                .environment(\.colorScheme, .dark)
                .frame(width: ScrollTiming.size.width, height: ScrollTiming.size.height))
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            log("film page \(film.displayTitle): first layout and drawing \(ms(since: start)) ms")
            try? await Task.sleep(for: .seconds(3))
            start = ContinuousClock.now
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            log("film page \(film.displayTitle): after its loads, layout and drawing again \(ms(since: start)) ms")
            window.close()
        }
        log("timings the app records itself: " + model.timings.map { "\($0.key) \($0.value)" }.sorted().joined(separator: "; "))
    }

    /// The same 300 posters in three layouts, each scrolled as All Films is: where the grid's time goes.
    static func layoutExperiments(_ model: AppModel) async {
        let items = model.items
        let width: CGFloat = 180
        let height = width * 1.5 + 9 + 40
        let asNow = AnyView(ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 205), spacing: 22, alignment: .top)], alignment: .leading, spacing: 30) {
                ForEach(items) { item in PosterCard(item: item) }
            }
            .padding(32)
        }
        .environment(ScrollState())
        .background(Theme.background))
        let fixed = AnyView(ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: width, maximum: width), spacing: 22, alignment: .top)], alignment: .leading, spacing: 30) {
                ForEach(items) { item in PosterCard(item: item).frame(width: width, height: height) }
            }
            .padding(32)
        }
        .environment(ScrollState())
        .background(Theme.background))
        let perRow = 7
        let rows = stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
        let stacked = AnyView(ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(rows[row]) { item in PosterCard(item: item).frame(width: width, height: height) }
                    }
                    .frame(height: height, alignment: .top)
                }
            }
            .padding(32)
        }
        .environment(ScrollState())
        .background(Theme.background))
        let equatable = AnyView(ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: width, maximum: width), spacing: 22, alignment: .top)], alignment: .leading, spacing: 30) {
                ForEach(items) { item in PosterCard(item: item).equatable().frame(width: width, height: height) }
            }
            .padding(32)
        }
        .environment(ScrollState())
        .background(Theme.background))
        _ = await ScrollTiming.run([
            ScrollTiming.Page(name: "Experiment: \(items.count) cards in the grid as now", view: asNow),
            ScrollTiming.Page(name: "Experiment: the same cards at a fixed size", view: fixed),
            ScrollTiming.Page(name: "Experiment: fixed-size cards in rows of a LazyVStack", view: stacked),
            ScrollTiming.Page(name: "Experiment: fixed size and .equatable()", view: equatable),
        ], model: model, log: { ScreenRenderer.log($0) })
    }
}
#endif
