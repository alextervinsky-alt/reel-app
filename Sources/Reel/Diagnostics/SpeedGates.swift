#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

/// How many times views were evaluated (only counted; read by `SpeedGates` on CI).
@MainActor
enum ViewCounts {
    static var filmPage = 0
}

/// The 1.11 smoothness gates (spec §9.3), measured on CI's Mac after the screens: each is a GATE
/// line saying PASS or FAIL with its number. The 8.3 ms budget is the 120 Hz screen's; CI's
/// runner has no such screen, so those lines are reported, not required.
@MainActor
enum SpeedGates {
    private static var lines: [String] = []

    private static func ms(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }

    private static func gate(_ name: String, _ value: String, pass: Bool?) {
        let verdict = pass.map { $0 ? "PASS" : "FAIL" } ?? "REPORT"
        lines.append("GATE \(verdict) \(name): \(value)")
    }

    /// A film page in a window: its first layout and drawing (the first page of the session, then
    /// another), and whether another film's change redraws an open page.
    static func filmPages(_ model: AppModel) async {
        let films = model.items.prefix(9).map(\.main)
        guard films.count >= 9 else { return }
        var times: [Double] = []
        for film in [films[0], films[8]] {
            let (window, host) = open(FilmPage(filmID: film.id), model: model)
            let start = ContinuousClock.now
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            times.append(ms(ContinuousClock.now - start))
            try? await Task.sleep(for: .seconds(3))
            window.close()
        }
        gate("film page opens (first of the session)", String(format: "%.0f ms", times[0]), pass: nil)
        gate("film page opens (another)", String(format: "%.0f ms, target < 100 ms", times[1]), pass: times[1] < 100)

        // An open page, and background info arriving for another film.
        let (window, host) = open(FilmPage(filmID: films[4].id), model: model)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try? await Task.sleep(for: .seconds(3))
        let before = ViewCounts.filmPage
        let other = films[2].id
        model.mutateFilms(urgent: true) { list in
            if let i = list.firstIndex(where: { $0.id == other }) { list[i].lastLookup = Date() }
        }
        try? await Task.sleep(for: .milliseconds(800))
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let redraws = ViewCounts.filmPage - before
        gate("open film page redrawn when another film changes", "\(redraws) times, target 0", pass: redraws == 0)
        window.close()
    }

    /// Library.json at 300 films (570 copies, the sample under other ids): what opening it costs on a Mac.
    static func library(_ model: AppModel, copies: ([FilmEntry], Int, [String]) -> [FilmEntry]) {
        let drive = model.drives.first?.id ?? "Main"
        let films = copies(model.films.filter { $0.tmdb != nil }, 300, [drive, "Backup"])
        guard !films.isEmpty else { return }
        let data = (try? JSONStore.encode(LibraryFile(films: films))) ?? Data()
        var start = ContinuousClock.now
        let opening = LibraryOpening.decide(data)
        let decode = ms(ContinuousClock.now - start)
        gate("Library.json at 300 films (\(films.count) copies, \(data.count / 1024) KB) opens",
             String(format: "%.0f ms, target < 500 ms (%d read)", decode, opening.films.count), pass: decode < 500)
        start = ContinuousClock.now
        _ = try? JSONSerialization.jsonObject(with: data)
        let json = ms(ContinuousClock.now - start)
        start = ContinuousClock.now
        for film in films { _ = FilenameParser.parse(film.fileName) }
        let names = ms(ContinuousClock.now - start)
        gate("…of which", String(format: "reading the JSON alone %.0f ms; reading %d file names %.0f ms", json, films.count, names), pass: nil)
        start = ContinuousClock.now
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gates-library-\(ProcessInfo.processInfo.processIdentifier).json")
        try? JSONStore.save(LibraryFile(films: films), to: url)
        let save = ms(ContinuousClock.now - start)
        try? FileManager.default.removeItem(at: url)
        gate("Library.json at 300 films saved", String(format: "%.0f ms, target < 150 ms", save), pass: save < 150)
        start = ContinuousClock.now
        let built = AppModel.makeItems(films: films, online: []) { _ in [] }.items
        gate("grid items built at 300 films", String(format: "%.0f ms, target < 300 ms (%d items)", ms(ContinuousClock.now - start), built.count),
             pass: ms(ContinuousClock.now - start) < 300)
    }

    /// The scroll gates from the pages timed, then every line. CI's virtual Mac is slow at drawing
    /// new images, so a page of posters there misses frames whatever Reel does: All Films is
    /// judged against the same posters drawn bare in the same grid (what the cards add), and the
    /// other pages are reported for stage 5's check on Alex's Mac (Settings › Diagnostics).
    static func report(log: (String) -> Void) {
        let results = ScrollTiming.results
        let bare = results.first { $0.name.hasPrefix("Posters alone") }
        for result in results where !result.name.hasPrefix("Plain") && !result.name.hasPrefix("Posters alone") && !result.name.hasPrefix("Grid test") {
            for (label, pass) in [("first", result.first), ("again", result.second)] where !pass.steps.isEmpty {
                let limit = max(1, pass.steps.count / 100)
                if result.name.hasPrefix("All Films"), let bare {
                    let base = (label == "first" ? bare.first : bare.second).over(16.7)
                    gate("\(result.name) scroll, \(label), what the cards add", "\(pass.over(16.7)) of \(pass.steps.count) steps over 16.7 ms "
                         + "against \(base) for the posters alone, target ≤ \(base + limit)", pass: pass.over(16.7) <= base + limit)
                } else if result.name == "Film page" {
                    gate("\(result.name) scroll, \(label)", "\(pass.over(16.7)) of \(pass.steps.count) steps over 16.7 ms, target ≤ \(limit)",
                         pass: pass.over(16.7) <= limit)
                } else {
                    gate("\(result.name) scroll, \(label)", "\(pass.over(16.7)) of \(pass.steps.count) steps over 16.7 ms (pages of images: judged on the Mac)",
                         pass: nil)
                }
                gate("\(result.name) scroll at 120 Hz, \(label)", "\(pass.over(8.3)) of \(pass.steps.count) steps over 8.3 ms", pass: nil)
            }
        }
        if let bare {
            gate("Posters alone (the machine)", "\(bare.first.over(16.7)) and \(bare.second.over(16.7)) of 400 steps over 16.7 ms", pass: nil)
        }
        for line in lines { log(line) }
    }

    private static func open(_ view: some View, model: AppModel) -> (NSWindow, NSView) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: ScrollTiming.size),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: NavigationStack { view }
            .environment(model)
            .environment(\.colorScheme, .dark)
            .frame(width: ScrollTiming.size.width, height: ScrollTiming.size.height))
        window.contentView = host
        window.orderFrontRegardless()
        return (window, host)
    }
}
#endif
