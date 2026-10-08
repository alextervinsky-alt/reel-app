#if os(macOS)
import SwiftUI
import ReelCore

/// "This Is an Extra Of…": pick the film a file belongs to. Only Reel's view changes; the files
/// on the drive stay where they are.
struct RegroupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    @State private var query = ""

    var body: some View {
        let candidates = films
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("This Is an Extra Of…")
                    .font(.system(size: 17, weight: .semibold))
                Text("“\(item.main.fileName)” will be listed with the extras of the film you choose. Nothing on the drive changes.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Search your films", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(candidates) { film in
                        Button {
                            // The film's copy on the same drive: a fix needs both files on one drive.
                            let owner = film.copies.first { $0.driveID == item.main.driveID } ?? film.main
                            model.makeExtra(item.main, of: owner)
                            dismiss()
                        } label: {
                            RegroupRow(item: film)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 320)
            .overlay {
                if candidates.isEmpty {
                    Text(query.isEmpty ? "No other films on this drive." : "No films match.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    /// Films on the same drive (a film and its extras always share one), best matches first.
    private var films: [LibraryItem] {
        let drive = item.main.driveID
        let others = model.items.filter { other in
            other.id != item.id && other.copies.contains { $0.driveID == drive }
        }
        let terms = TitleSimilarity.normalize(query).split(separator: " ").map { String($0) }
        guard !terms.isEmpty else { return others.sorted { $0.sortTitle < $1.sortTitle } }
        return others
            .map { ($0, $0.search.relevance(terms, allowTypos: true)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.sortTitle < $1.0.sortTitle }
            .map { $0.0 }
    }
}

private struct RegroupRow: View {
    let item: LibraryItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Poster(path: item.main.tmdb?.posterPath, title: "", kind: .thumbnail, cornerRadius: 4)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.main.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(item.main.displayYear.map(String.init) ?? item.main.fileName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Color.white.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
#endif
