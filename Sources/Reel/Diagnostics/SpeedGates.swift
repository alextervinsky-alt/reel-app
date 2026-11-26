#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

/// How many times views were evaluated (only counted; read by `SpeedGates` on CI).
@MainActor
enum ViewCounts {
    static var filmPage = 0
}

/// Which images are drawn as their placeholder (only while CI renders): one that has reached
/// memory and still shows its placeholder seconds later is stuck there.
@MainActor
enum PlaceholderWatch {
    static let isOn = ScreenRenderer.isRequested

    private final class Entry {
        weak var view: AnyObject?
        let path: String?
        let kind: ImageKind
        let monochrome: Bool
        let showing: Bool

        init(view: AnyObject, path: String?, kind: ImageKind, monochrome: Bool, showing: Bool) {
            self.view = view
            self.path = path
            self.kind = kind
            self.monochrome = monochrome
            self.showing = showing
        }
    }

    private static var entries: [ObjectIdentifier: Entry] = [:]

    static func note(_ view: AnyObject, path: String?, kind: ImageKind, monochrome: Bool, showing: Bool) {
        entries[ObjectIdentifier(view)] = Entry(view: view, path: path, kind: kind, monochrome: monochrome, showing: showing)
    }

    static func reset() { entries.removeAll() }

    /// Images views still alive are drawing, and how many of those are their placeholder although
    /// the image is in memory.
    static func count() -> (shown: Int, stuck: Int, waiting: Int) {
        var shown = 0, stuck = 0, waiting = 0
        for entry in entries.values where entry.view != nil {
            if entry.showing {
                shown += 1
            } else if let path = entry.path {
                if ImageStore.shared.cached(path, entry.kind, monochrome: entry.monochrome) != nil { stuck += 1 } else { waiting += 1 }
            }
        }
        return (shown, stuck, waiting)
    }
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

    /// All Films as Reel opens: nothing in memory, the posters in the Image Cache folder, read
    /// ahead while the grid appears. Every image that has reached memory must be drawn, not its
    /// placeholder (1.11.0 left the posters read ahead blank on Alex's first launch).
    static func postersAppear(_ model: AppModel) async {
        for attempt in 1...2 {
            ImageStore.shared.forgetMemory()
            PlaceholderWatch.reset()
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: ScrollTiming.size),
                                  styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            let host = NSHostingView(rootView: RootView()
                .environment(model)
                .environment(\.colorScheme, .dark)
                .frame(width: ScrollTiming.size.width, height: ScrollTiming.size.height))
            window.contentView = host
            window.orderFrontRegardless()
            try? await Task.sleep(for: .seconds(6))
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let (shown, stuck, waiting) = PlaceholderWatch.count()
            gate("posters appear as Reel opens (All Films, nothing in memory, try \(attempt))",
                 "\(stuck) stuck on the placeholder with the image in memory, target 0 (\(shown) drawn, \(waiting) still loading)",
                 pass: stuck == 0 && shown > 0)
            window.close()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// What AppKit asks the window on every frame while a page scrolls (where's the cursor, which
    /// view takes this scroll event): a hit test of the view under the pointer. On Alex's Mac this
    /// was half the main thread's work while All Films scrolled (sample, 26 Nov: 1,348 of 2,691
    /// busy samples), as SwiftUI walked every card's click, hover and text areas (1.11.2).
    static func hitTesting(_ model: AppModel) async {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: ScrollTiming.size),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: RootView()
            .environment(model)
            .environment(\.colorScheme, .dark)
            .frame(width: ScrollTiming.size.width, height: ScrollTiming.size.height))
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(6))
        guard let frame = host.superview else { window.close(); return }
        // Points over the page right of the sidebar, and apart: the sidebar, the banner, the posters
        // (in the window's own coordinates, from the bottom).
        let height = ScrollTiming.size.height
        func points(x: ClosedRange<Double>, fromTop y: ClosedRange<Double>) -> [NSPoint] {
            stride(from: x.lowerBound, through: x.upperBound, by: 60).flatMap { px in
                stride(from: y.lowerBound, through: y.upperBound, by: 60).map { NSPoint(x: px, y: height - $0) }
            }
        }
        func median(_ points: [NSPoint]) -> (median: Double, worst: Double) {
            _ = points.map { frame.hitTest($0) }
            var times: [Double] = []
            for _ in 0..<5 {
                for point in points {
                    let start = ContinuousClock.now
                    _ = frame.hitTest(point)
                    times.append(ms(ContinuousClock.now - start) * 1000)
                }
            }
            times.sort()
            return (times[times.count / 2], times.last ?? 0)
        }
        let page = median(points(x: 320...(ScrollTiming.size.width - 40), fromTop: 160...(height - 40)))
        let sidebar = median(points(x: 40...200, fromTop: 120...(height - 120)))
        let banner = median(points(x: 320...(ScrollTiming.size.width - 40), fromTop: 80...300))
        let posters = median(points(x: 320...(ScrollTiming.size.width - 40), fromTop: 560...(height - 40)))
        window.close()
        // The floor: the same in a window of 600 plain tiles (SwiftUI's own cost on this machine).
        let plainWindow = NSWindow(contentRect: NSRect(origin: .zero, size: ScrollTiming.size),
                                   styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        plainWindow.isReleasedWhenClosed = false
        let plainHost = NSHostingView(rootView: ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 205), spacing: 22)], spacing: 30) {
                ForEach(0..<600, id: \.self) { _ in RoundedRectangle(cornerRadius: 12).fill(Color.gray).aspectRatio(2 / 3, contentMode: .fit) }
            }.padding(32)
        }.frame(width: ScrollTiming.size.width, height: ScrollTiming.size.height))
        plainWindow.contentView = plainHost
        plainWindow.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(2))
        var plain = (median: 0.0, worst: 0.0)
        if let plainFrame = plainHost.superview {
            _ = (0..<20).map { _ in plainFrame.hitTest(NSPoint(x: 400, y: 400)) }
            var times: [Double] = []
            for point in points(x: 320...(ScrollTiming.size.width - 40), fromTop: 160...(height - 40)) {
                let start = ContinuousClock.now
                _ = plainFrame.hitTest(point)
                times.append(ms(ContinuousClock.now - start) * 1000)
            }
            times.sort()
            plain = (times[times.count / 2], times.last ?? 0)
        }
        plainWindow.close()
        gate("hit test over a window of plain tiles (the floor)", String(format: "median %.0f us", plain.median), pass: nil)
        gate("hit test over All Films (500 films), as AppKit asks each frame while scrolling",
             String(format: "median %.0f us, worst %.0f us; sidebar %.0f, banner %.0f, posters %.0f us (medians)",
                    page.median, page.worst, sidebar.median, banner.median, posters.median), pass: nil)
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
