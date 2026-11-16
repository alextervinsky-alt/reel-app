#if os(macOS)
import AppKit
import QuartzCore

/// Frames shown and missed while a page scrolls, on this Mac's own screen (Settings ›
/// Diagnostics, 1.11): the real measure of smoothness, at the screen's own rate (120 Hz on a
/// ProMotion MacBook Pro). Counted with the display's own clock, only while scrolling.
@MainActor
final class ScrollFrames: NSObject {
    static let shared = ScrollFrames()

    struct Stat {
        var frames = 0
        var missed = 0
        var hertz = 0
    }

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var page = ""
    private var current = Stat()
    private weak var model: AppModel?

    func start(page: String, model: AppModel) {
        guard link == nil, !ScreenRenderer.isRequested,
              let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else { return }
        self.page = page
        self.model = model
        current = Stat()
        last = 0
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let frame = link.targetTimestamp - link.timestamp
        guard frame > 0 else { return }
        current.hertz = Int((1 / frame).rounded())
        if last > 0 {
            let gap = link.timestamp - last
            let shown = max(1, Int((gap / frame).rounded()))
            current.frames += shown
            current.missed += shown - 1
        }
        last = link.timestamp
    }

    func stop() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        guard current.frames > 0 else { return }
        model?.recordScroll(page, current)
    }
}

extension AppModel {
    /// Adds one scroll's frames to this session's count for the page (Settings › Diagnostics).
    func recordScroll(_ page: String, _ stat: ScrollFrames.Stat) {
        var total = scrollStats[page] ?? ScrollFrames.Stat()
        total.frames += stat.frames
        total.missed += stat.missed
        total.hertz = stat.hertz
        scrollStats[page] = total
    }
}
#endif
