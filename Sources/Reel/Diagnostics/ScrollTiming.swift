#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

/// How smoothly Reel's pages scroll, measured on the build machine (CI runs it after the screens):
/// each page is opened in a real window and scrolled from top to bottom in steps, as a quick
/// two-finger scroll moves it, and the main thread's work for each step is timed. A step over
/// 16 ms is a frame missed at 60 Hz (8 ms at 120 Hz). Each page is scrolled twice: the first time
/// its posters and rows are made, the second time they're already there.
@MainActor
enum ScrollTiming {
    struct Page {
        let name: String
        let view: AnyView
    }

    /// One scroll from top to bottom: each step's work in milliseconds.
    struct Pass {
        var steps: [Double] = []

        var summary: String {
            guard !steps.isEmpty else { return "nothing to scroll" }
            let sorted = steps.sorted()
            func at(_ share: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * share))] }
            let slow = steps.filter { $0 > 16.7 }.count, missed120 = steps.filter { $0 > 8.3 }.count
            return String(format: "median %.1f ms, 95%% %.1f ms, worst %.1f ms, %d of %d over 16 ms (%d over 8 ms)",
                          at(0.5), at(0.95), sorted.last ?? 0, slow, steps.count, missed120)
        }
    }

    static let size = NSSize(width: 1470, height: 956)
    /// How far each step moves: a brisk scroll (about 1,700 points a second at 60 Hz).
    static let step: CGFloat = 28
    /// The time between steps, as between two frames.
    static let frame = Duration.milliseconds(8)

    /// Times each page and returns a line for each.
    static func run(_ pages: [Page], model: AppModel, log: (String) -> Void) async -> [String] {
        var lines: [String] = []
        for page in pages {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            let host = NSHostingView(rootView: page.view
                .environment(model)
                .environment(\.colorScheme, .dark)
                .frame(width: size.width, height: size.height))
            window.contentView = host
            window.orderFrontRegardless()
            // Its lists and posters load as when the page opens.
            try? await Task.sleep(for: .seconds(6))
            guard let scroll = mainScrollView(in: host) else {
                lines.append("\(page.name): no scrolling page found")
                window.close()
                continue
            }
            let height = scroll.documentView?.frame.height ?? 0
            let first = await pass(scroll, host: host)
            try? await Task.sleep(for: .seconds(1))
            let second = await pass(scroll, host: host)
            let line = "\(page.name) (\(Int(height)) pt): first \(first.summary) | again \(second.summary)"
            log("scroll " + line)
            lines.append(line)
            window.close()
        }
        return lines
    }

    /// From the top to the bottom, one step a frame. A step's time is its own work (the scroll, the
    /// rows made for it, the drawing) and whatever else held the main thread until the next frame.
    private static func pass(_ scroll: NSScrollView, host: NSView) async -> Pass {
        let clip = scroll.contentView
        let document = scroll.documentView?.frame.height ?? 0
        let bottom = max(0, document - clip.bounds.height)
        let flipped = scroll.documentView?.isFlipped ?? true
        // The top of the page: 0 in a flipped document, its height otherwise.
        func origin(_ fromTop: CGFloat) -> CGFloat { flipped ? fromTop : bottom - fromTop }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: origin(0)))
        scroll.reflectScrolledClipView(clip)
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))
        var result = Pass()
        var offset: CGFloat = 0
        let clock = ContinuousClock()
        while offset < bottom, result.steps.count < 400 {
            offset = min(bottom, offset + step)
            let start = clock.now
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: origin(offset)))
            scroll.reflectScrolledClipView(clip)
            host.layoutSubtreeIfNeeded()
            host.window?.displayIfNeeded()
            CATransaction.flush()
            let work = clock.now - start
            let slept = clock.now
            try? await Task.sleep(for: frame)
            let late = max(.zero, clock.now - slept - frame)
            result.steps.append(milliseconds(work + late))
        }
        return result
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }

    /// The page's own scrolling area: the largest that has more to show than fits.
    private static func mainScrollView(in view: NSView) -> NSScrollView? {
        func all(_ view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(all)
        }
        return all(view)
            .filter { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 100 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}
#endif
