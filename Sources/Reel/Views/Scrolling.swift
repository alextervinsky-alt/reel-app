#if os(macOS)
import SwiftUI

/// Scrolling and hover, shared by a page and what's on it. Nothing here is observed, so starting or
/// stopping a scroll redraws nothing except the card under the pointer, which is told to settle.
@Observable @MainActor
final class ScrollState {
    @ObservationIgnored var isScrolling = false
    /// Settles the lifted card (set by the card the pointer is on).
    @ObservationIgnored var endHover: (() -> Void)?
    /// The card that came under the pointer while scrolling: lifted when the scroll stops.
    @ObservationIgnored var waiting: (id: UUID, lift: () -> Void)?
    /// The poster under the pointer, for Space (Quick Look).
    @ObservationIgnored var pointed: LibraryItem?
    /// The page, for counting its frames while it scrolls (Settings › Diagnostics).
    @ObservationIgnored var name = "Other pages"

    /// The scroll views moving now (a page, and a row scrolled inside it).
    @ObservationIgnored private var moving: Set<UUID> = []
    /// For a page with one scroll view of its own.
    nonisolated static let page = UUID()

    /// A scroll started or stopped: the lifted card settles as it starts; the card the pointer came
    /// to rest on lifts once every scroll has stopped. The library's updates wait meanwhile
    /// (`AppModel.userIsScrolling`).
    func phaseChanged(scrolling: Bool, of scroller: UUID = ScrollState.page, model: AppModel) {
        if scrolling { moving.insert(scroller) } else { moving.remove(scroller) }
        let now = !moving.isEmpty
        if now && !isScrolling {
            endHover?()
            endHover = nil
        }
        let stopped = !now && isScrolling
        if now && !isScrolling { ScrollFrames.shared.start(page: name, model: model) }
        if stopped { ScrollFrames.shared.stop() }
        isScrolling = now
        model.userIsScrolling = now
        if stopped {
            waiting?.lift()
            waiting = nil
        }
    }
}

extension View {
    /// Makes a scrolling page smooth: what's on it doesn't react to the pointer or fade in while it
    /// scrolls, and the library's updates wait until it stops. A row scrolling inside a page shares
    /// the page's state.
    /// - Parameter page: the page's name in Settings › Scrolling (1.11.2: frames missed per page);
    ///   a row inside a page counts with its page.
    func tracksScrolling(_ page: String? = nil) -> some View {
        modifier(TracksScrolling(page: page))
    }

    /// `hovering` follows the pointer, except while the page scrolls: a card passing under a still
    /// pointer isn't lifted (it is once the scroll stops, if the pointer is still on it), and a
    /// lifted card settles when a scroll starts. `changed` sees every move in and out.
    func scrollAwareHover(_ hovering: Binding<Bool>, changed: ((Bool) -> Void)? = nil) -> some View {
        modifier(ScrollAwareHover(hovering: hovering, changed: changed))
    }

    /// One pointer tracker for everything inside (1.11, spec §9.1): the cards in it say where they
    /// are once (a frame in this view's own space doesn't change while the page scrolls), and the
    /// card under the pointer is found from the pointer's position. Put on the content of a scroll
    /// view, not the scroll view itself. Without it, each card tracks the pointer itself, as before.
    func hoverRegion() -> some View {
        modifier(HoverRegion())
    }
}

/// The cards of one region and the one under the pointer (see `hoverRegion`). Nothing here is
/// observed: only the card that is lifted or settles is told, through its own state.
@MainActor
final class HoverField {
    struct Card {
        var frame: CGRect
        var set: (Bool) -> Void
        var changed: ((Bool) -> Void)?
    }

    let space = UUID()
    private var cards: [UUID: Card] = [:]
    private var current: UUID?
    /// The page's scroll state: nothing is lifted while it scrolls.
    weak var scroll: ScrollState?

    func place(_ id: UUID, frame: CGRect, set: @escaping (Bool) -> Void, changed: ((Bool) -> Void)?) {
        cards[id] = Card(frame: frame, set: set, changed: changed)
    }

    func remove(_ id: UUID) {
        if current == id { settle() }
        cards[id] = nil
    }

    /// The pointer moved to `point` (in the region's space), or left it.
    func pointer(at point: CGPoint?) {
        if scroll?.isScrolling == true {
            settle()
            return
        }
        let hit = point.flatMap { point in cards.first { $0.value.frame.contains(point) }?.key }
        guard hit != current else { return }
        settle()
        guard let hit, let card = cards[hit] else { return }
        current = hit
        card.set(true)
        card.changed?(true)
        // A scroll starting settles it (see `ScrollState.phaseChanged`).
        scroll?.endHover = { [weak self] in self?.settle() }
    }

    func settle() {
        guard let id = current else { return }
        current = nil
        if let card = cards[id] {
            card.set(false)
            card.changed?(false)
        }
    }
}

private struct HoverFieldKey: EnvironmentKey {
    static let defaultValue: HoverField? = nil
}

extension EnvironmentValues {
    var hoverField: HoverField? {
        get { self[HoverFieldKey.self] }
        set { self[HoverFieldKey.self] = newValue }
    }
}

private struct HoverRegion: ViewModifier {
    @Environment(ScrollState.self) private var scroll: ScrollState?
    @State private var field = HoverField()

    func body(content: Content) -> some View {
        let field = field
        let scroll = scroll
        content
            .environment(\.hoverField, field)
            .coordinateSpace(.named(field.space))
            .onContinuousHover(coordinateSpace: .local) { phase in
                field.scroll = scroll
                switch phase {
                case .active(let point): field.pointer(at: point)
                case .ended: field.pointer(at: nil)
                }
            }
            .onDisappear { field.settle() }
    }
}

private struct TracksScrolling: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(ScrollState.self) private var outer: ScrollState?
    @State private var own = ScrollState()
    @State private var id = UUID()
    let page: String?

    func body(content: Content) -> some View {
        let scroll = outer ?? own
        let page = outer == nil ? page : nil
        content
            .onScrollPhaseChange { _, phase in
                if let page { scroll.name = page }
                scroll.phaseChanged(scrolling: phase.isScrolling, of: id, model: model)
            }
            .environment(scroll)
            .onDisappear {
                if outer == nil { own.pointed = nil }
                scroll.phaseChanged(scrolling: false, of: id, model: model)
            }
    }
}

private struct ScrollAwareHover: ViewModifier {
    @Environment(ScrollState.self) private var scroll: ScrollState?
    @Environment(\.hoverField) private var field
    @Binding var hovering: Bool
    let changed: ((Bool) -> Void)?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        if let field {
            // In a region: say where it is (once, and again only if the layout moves it).
            let hover = $hovering
            let id = id
            let changed = changed
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(field.space)) } action: { frame in
                    field.place(id, frame: frame, set: { hover.wrappedValue = $0 }, changed: changed)
                }
                .onDisappear { field.remove(id) }
        } else {
            tracked(content)
        }
    }

    private func tracked(_ content: Content) -> some View {
        content.onHover { inside in
            // Read here, not while drawing: scrolling never redraws the cards.
            changed?(inside)
            let hover = $hovering
            guard let scroll else {
                hover.wrappedValue = inside
                return
            }
            let lift = {
                hover.wrappedValue = true
                scroll.endHover = { hover.wrappedValue = false }
            }
            if !inside {
                hover.wrappedValue = false
                if scroll.waiting?.id == id { scroll.waiting = nil }
            } else if scroll.isScrolling {
                scroll.waiting = (id, lift)
            } else {
                lift()
            }
        }
    }
}
#endif
