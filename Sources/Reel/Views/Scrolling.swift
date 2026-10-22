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

    /// The scroll views moving now (a page, and a row scrolled inside it).
    @ObservationIgnored private var moving: Set<UUID> = []
    /// For a page with one scroll view of its own.
    static let page = UUID()

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
    func tracksScrolling() -> some View {
        modifier(TracksScrolling())
    }

    /// `hovering` follows the pointer, except while the page scrolls: a card passing under a still
    /// pointer isn't lifted (it is once the scroll stops, if the pointer is still on it), and a
    /// lifted card settles when a scroll starts. `changed` sees every move in and out.
    func scrollAwareHover(_ hovering: Binding<Bool>, changed: ((Bool) -> Void)? = nil) -> some View {
        modifier(ScrollAwareHover(hovering: hovering, changed: changed))
    }
}

private struct TracksScrolling: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(ScrollState.self) private var outer: ScrollState?
    @State private var own = ScrollState()
    @State private var id = UUID()

    func body(content: Content) -> some View {
        let scroll = outer ?? own
        content
            .onScrollPhaseChange { _, phase in scroll.phaseChanged(scrolling: phase.isScrolling, of: id, model: model) }
            .environment(scroll)
            .onDisappear {
                if outer == nil { own.pointed = nil }
                scroll.phaseChanged(scrolling: false, of: id, model: model)
            }
    }
}

private struct ScrollAwareHover: ViewModifier {
    @Environment(ScrollState.self) private var scroll: ScrollState?
    @Binding var hovering: Bool
    let changed: ((Bool) -> Void)?
    @State private var id = UUID()

    func body(content: Content) -> some View {
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
