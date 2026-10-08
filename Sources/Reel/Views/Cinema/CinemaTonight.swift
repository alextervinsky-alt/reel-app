#if os(macOS)
import SwiftUI
import ReelCore

/// Tonight's shortlist on the TV: the films side by side in aligned rows, large enough to
/// compare from the sofa, with Decide for Us.
struct CinemaTonight: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    let open: (String) -> Void
    @State private var chosen: String?
    @State private var width: CGFloat = 1400

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
    }

    private func page(_ items: [LibraryItem]) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .center, spacing: 16) {
                Text("Tonight").font(.system(size: Cinema.title, weight: .bold))
                Spacer()
                if items.count > 1 {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { chosen = items.randomElement()?.id }
                    } label: {
                        Label("Decide for Us", systemImage: "dice")
                    }
                    .buttonStyle(CinemaButtonStyle(primary: true))
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
                ScrollView(.horizontal) { columns(items) }
                    .scrollIndicators(.hidden)
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
            }
        }
        .padding(.horizontal, Cinema.gutter)
        .padding(.vertical, 10)
    }
}
#endif
