#if os(macOS)
import SwiftUI
import ReelCore

/// Tonight's shortlist on the TV: the films side by side in aligned rows, large enough to
/// compare from the sofa, with Decide for Us.
struct CinemaTonight: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(CinemaBar.self) private var bar
    /// False while something is open over it.
    var active = true
    let open: (String) -> Void
    @State private var chosen: String?
    @State private var width: CGFloat = 1400
    /// Where the arrow keys are: Decide for Us, or a film's column.
    @State private var focus: Focus?

    private enum Focus: Equatable {
        case decide
        case film(String)
    }

    var body: some View {
        let items = model.tonightItems
        Group {
            if isSnapshot {
                page(items).snapshotPage()
            } else {
                // Tall columns scroll down; more films than fit scroll sideways.
                ScrollView(.vertical) { page(items) }
                    .scrollIndicators(.hidden)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear { model.startNewEveningIfNeeded() }
        .onReelKey { key in active && move(key, items: items) }
        .onChange(of: bar.returned) { _, back in
            guard back?.page == "tonight" else { return }
            focus = items.count > 1 ? .decide : items.first.map { .film($0.id) }
        }
    }

    private func decide(_ items: [LibraryItem]) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { chosen = items.randomElement()?.id }
    }

    /// Left and right along the films, Up to Decide for Us and the bar, Return opens the film
    /// (or decides); Space and T as on every poster.
    private func move(_ key: ReelKey, items: [LibraryItem]) -> Bool {
        let index = focus.flatMap { place -> Int? in
            if case .film(let id) = place { return items.firstIndex { $0.id == id } }
            return nil
        }
        switch key {
        case .up:
            if focus == nil || focus == .decide || items.count < 2 {
                focus = nil
                bar.takeKeys()
            } else {
                focus = .decide
            }
        case .down where focus == .decide || focus == nil:
            focus = items.first.map { .film($0.id) }
        case .down: break
        case .left, .right:
            guard !items.isEmpty else { return false }
            let next = (index ?? -1) + (key == .left ? -1 : 1)
            focus = .film(items[min(max(next, 0), items.count - 1)].id)
        case .enter, .space, .tonight:
            if focus == .decide, key != .tonight {
                decide(items)
                return true
            }
            guard let index else { return false }
            return CinemaActions.perform(key, on: items[index], model: model, open: open)
        case .escape:
            // Esc also goes back, as on every page.
            focus = nil
            return false
        case .fullScreen: return false
        }
        return true
    }

    private func page(_ items: [LibraryItem]) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .center, spacing: 16) {
                Text("Tonight").font(.system(size: Cinema.title, weight: .bold))
                Spacer()
                if items.count > 1 {
                    Button {
                        decide(items)
                    } label: {
                        Label("Decide for Us", systemImage: "dice")
                    }
                    .buttonStyle(CinemaButtonStyle(primary: true, focused: focus == .decide))
                }
            }
            .padding(.horizontal, Cinema.gutter)
            if items.isEmpty {
                Text("Nothing on tonight's shortlist yet. Point at a poster and click the moon, or open a film and choose Tonight.")
                    .font(.system(size: Cinema.body))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Cinema.gutter)
            } else if isSnapshot {
                columns(items).snapshotRow()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) { columns(items) }
                        .scrollIndicators(.hidden)
                        .onChange(of: focus) { _, place in
                            guard case .film(let id)? = place else { return }
                            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                        }
                }
            }
        }
        .padding(.top, 130)
        .padding(.bottom, 60)
    }

    private func columns(_ items: [LibraryItem]) -> some View {
        let picked = TonightPick.current(chosen, in: items)
        let slots = TonightSlots(items, model: model)
        let columnWidth = TonightSlots.width(for: items.count, in: width - Cinema.gutter * 2, large: true)
        return HStack(alignment: .top, spacing: 24) {
            ForEach(items) { item in
                TonightCompareColumn(item: item, slots: slots, width: columnWidth, chosen: picked == item.id,
                                     dimmed: picked != nil && picked != item.id, large: true) {
                    open(item.main.id)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: focus == .film(item.id) ? 4 : 0)
                        .padding(-10)
                }
                .id(item.id)
            }
        }
        .padding(.horizontal, Cinema.gutter)
        .padding(.vertical, 14)
    }
}
#endif
