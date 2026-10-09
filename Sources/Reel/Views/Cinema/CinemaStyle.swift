#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

/// Sizes for reading from the sofa: the TV mirrors the laptop, so a point on the laptop is a
/// few millimetres on the TV, seen from three metres away. Nothing on the TV is smaller than `body`.
enum Cinema {
    static let posterWidth: CGFloat = 240
    static let gutter: CGFloat = 64
    static let title: CGFloat = 52
    static let rowTitle: CGFloat = 28
    static let body: CGFloat = 22
    static let buttonHeight: CGFloat = 60
}

/// Large buttons that are easy to hit with a phone's mouse.
struct CinemaButtonStyle: ButtonStyle {
    var primary = false
    /// Smaller, beside a row title.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Cinema.body, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, compact ? 22 : 30)
            .frame(height: compact ? 50 : Cinema.buttonHeight)
            .background(Capsule().fill(primary ? Color.white : Color.white.opacity(configuration.isPressed ? 0.3 : 0.16)))
            .foregroundStyle(primary ? Color.black : Color.white)
            .opacity(configuration.isPressed && primary ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

/// A large pill: a tab, a mood, a filter.
struct CinemaChip: View {
    let title: String
    var symbol: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let symbol { Image(systemName: symbol).font(.system(size: 20, weight: .semibold)) }
                Text(title)
            }
            .font(.system(size: Cinema.body, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(Capsule().fill(isOn ? Color.white : Color.white.opacity(0.12)))
            .foregroundStyle(isOn ? Color.black : Color.white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// IMDb and Rotten Tomatoes (TMDB when there are neither), readable from the sofa.
struct CinemaRatings: View {
    let film: FilmEntry

    var body: some View {
        let r = film.ratings
        HStack(spacing: 12) {
            if let imdb = r?.imdb {
                RatingBadge(tag: "IMDb", value: Format.rating(imdb), background: RatingStrip.imdbYellow, foreground: .black)
            }
            if let rt = r?.rottenTomatoes {
                RatingBadge(tag: "RT", value: "\(rt)%", background: RatingStrip.tomatoColor(rt), foreground: .white)
            }
            if r?.imdb == nil, r?.rottenTomatoes == nil, let vote = film.tmdb?.voteAverage, vote > 0 {
                RatingBadge(tag: "TMDB", value: Format.rating(vote), background: Color(red: 0.01, green: 0.71, blue: 0.89),
                            foreground: .black)
            }
        }
        .environment(\.ratingScale, 1.6)
        .lineLimit(1)
    }
}

// MARK: - Keys

/// The keys Reel listens for on its own (arrows, Return, Space, Esc, T, F).
enum ReelKey {
    case left, right, up, down, enter, space, escape
    /// T: add to Tonight, or take off.
    case tonight
    /// F: a trailer fills the screen, or goes back.
    case fullScreen

    init?(_ event: NSEvent) {
        switch event.keyCode {
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        case 36, 76: self = .enter
        case 49: self = .space
        case 53: self = .escape
        case 17: self = .tonight
        case 3: self = .fullScreen
        default: return nil
        }
    }
}

/// The latest handler, so the key monitor always sees the view as it is now.
@MainActor
private final class KeyHandlerBox {
    var handle: (@MainActor (ReelKey) -> Bool)?
    /// The window the view is in: keys pressed in other windows (Settings, an Open panel) are left alone.
    weak var window: NSWindow?
}

/// Tells the box which window the view is in.
private struct HostWindowReader: NSViewRepresentable {
    let box: KeyHandlerBox

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.box = box
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        weak var box: KeyHandlerBox?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box?.window = window
        }
    }
}

/// Handles keys while the view is on screen and its window has the keys, except while typing in
/// a text field, with ⌘, ⌥ or ⌃ held, or when a sheet is open over its window. Returns true when it used the key.
private struct KeyHandler: ViewModifier {
    let handle: @MainActor (ReelKey) -> Bool
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var box = KeyHandlerBox()
    @State private var monitor: Any?

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSnapshot {
            // Nothing to listen to in a picture (and the window reader can't be drawn).
            content
        } else {
            listening(content)
        }
    }

    private func listening(_ content: Content) -> some View {
        box.handle = handle
        let box = box
        return content
            .background(HostWindowReader(box: box))
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let used = MainActor.assumeIsolated { () -> Bool in
                        guard let key = ReelKey(event),
                              event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                              let window = event.window, window === box.window,
                              window.attachedSheet == nil,
                              !(window.firstResponder is NSText) else { return false }
                        return box.handle?(key) ?? false
                    }
                    return used ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    func onReelKey(_ handle: @escaping @MainActor (ReelKey) -> Bool) -> some View {
        modifier(KeyHandler(handle: handle))
    }
}

// MARK: - Rendering screens

private struct SnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while a screen is drawn to an image (no scroll views or animations then).
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

extension View {
    /// A page taller than the screen, drawn without its scroll view: starts at the top and is cut
    /// off at the bottom, as the scroll view would show it.
    func snapshotPage() -> some View {
        fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()
    }

    /// A row wider than the screen, drawn without its scroll view: starts at the left edge and is
    /// cut off at the right, as the scroll view would show it.
    func snapshotRow() -> some View {
        fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }
}
/// Tells the pointer moving from posters moving under a pointer that stayed put. When the arrow
/// keys move the highlight, the rows scroll to it and slide posters under the resting pointer;
/// those mustn't take the highlight back (it jumped to the row above). The pointer highlights
/// again once it really moves.
@MainActor
final class PointerWatch {
    private var restingAt: NSPoint?

    /// The keys moved the highlight: where the pointer rests now.
    func keysMoved() {
        restingAt = NSEvent.mouseLocation
    }

    /// Whether the pointer moved since the keys did (then it highlights again).
    func moved() -> Bool {
        guard let restingAt else { return true }
        let now = NSEvent.mouseLocation
        guard abs(now.x - restingAt.x) + abs(now.y - restingAt.y) > 3 else { return false }
        self.restingAt = nil
        return true
    }
}
#endif
