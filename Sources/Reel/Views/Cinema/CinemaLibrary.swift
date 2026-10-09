#if os(macOS)
import SwiftUI
import ReelCore

/// Every film, in large posters: one row of five filters (sort, mood, length, language,
/// unwatched only), each opening a large panel of choices, and the matches when something is
/// typed in the search field. The pointer and the arrow keys share one highlight.
struct CinemaLibrary: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @Binding var searchText: String
    /// Set by ⌘F: the search field takes the focus.
    @Binding var focusSearch: Bool
    let query: String
    /// False while a film page or a trailer is open over it.
    let active: Bool
    let open: (String) -> Void
    @State private var sort: LibrarySort = .rating
    @State private var mood: Mood?
    @State private var length: LengthBand = .any
    @State private var language: String?
    @State private var unwatchedOnly = true
    @State private var panel: FilterPanel?

    private enum FilterPanel: Identifiable {
        case sort, mood, length, language
        var id: Self { self }
    }

    private static let sorts: [LibrarySort] = [.rating, .random, .added, .year, .title]

    private static func title(_ sort: LibrarySort) -> String {
        switch sort {
        case .random: "Random"
        case .rating: "Best Rated"
        case .added: "Recently Added"
        case .year: "Newest"
        case .title: "A–Z"
        case .runtime: "Shortest"
        }
    }

    var body: some View {
        // A search looks through everything, watched films included.
        let searching = !query.isEmpty
        let films = model.cinemaLibrary(matching: query, sort: sort, mood: searching ? nil : mood,
                                        length: searching ? .any : length, language: searching ? nil : language,
                                        unwatchedOnly: !searching && unwatchedOnly)
        Group {
            if isSnapshot {
                content(films, scrollTo: { _ in }).snapshotPage()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        content(films) { id in
                            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .overlay {
            if let panel { panelView(panel).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.18), value: panel)
        .onChange(of: panel) { _, shown in model.cinemaPanelOpen = shown != nil }
        .onDisappear {
            // Leaving All Films (a tab, Exit Cinema) with a panel open closes it, so Esc works again.
            panel = nil
            model.cinemaPanelOpen = false
        }
        .onReelKey { key in
            guard panel != nil, key == .escape else { return false }
            panel = nil
            return true
        }
    }

    private func content(_ films: [LibraryItem], scrollTo: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            header(count: films.count)
            if films.isEmpty {
                Text(query.isEmpty ? "No films fit all of that. Try another filter." : "Nothing in your library matches.")
                    .font(.system(size: Cinema.body))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Cinema.gutter)
            } else {
                CinemaLibraryGrid(films: films, active: active && panel == nil, open: open, scrollTo: scrollTo)
            }
        }
        .padding(.top, 130)
        .padding(.bottom, 80)
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text(query.isEmpty ? "All Films" : "“\(query)”")
                    .font(.system(size: Cinema.title, weight: .bold))
                    .lineLimit(1)
                Text(count == 1 ? "1 film" : "\(count) films")
                    .font(.system(size: Cinema.body))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 20)
                CinemaSearchField(text: $searchText, focusRequested: $focusSearch)
            }
            // Filters step aside while searching (a search looks through everything).
            if query.isEmpty { filters }
        }
        .padding(.horizontal, Cinema.gutter)
    }

    /// One row: each filter shows its choice and opens a large panel.
    private var filters: some View {
        let row = HStack(spacing: 12) {
            CinemaChip(title: Self.title(sort) + "  ▾", symbol: "arrow.up.arrow.down", isOn: false) { panel = .sort }
            CinemaChip(title: (mood?.title ?? "Any Mood") + "  ▾", symbol: mood?.symbol ?? "sparkles", isOn: mood != nil) { panel = .mood }
            CinemaChip(title: (length == .any ? "Any Length" : length.title) + "  ▾", symbol: "clock", isOn: length != .any) {
                panel = .length
            }
            if model.languages.count > 1 {
                CinemaChip(title: (language.map(FilmLanguage.name) ?? "Any Language") + "  ▾", symbol: "globe", isOn: language != nil) {
                    panel = .language
                }
            }
            CinemaChip(title: "Unwatched", symbol: unwatchedOnly ? "checkmark" : nil, isOn: unwatchedOnly) {
                unwatchedOnly.toggle()
            }
        }
        return Group {
            if isSnapshot {
                row.snapshotRow()
            } else {
                ScrollView(.horizontal) { row }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
            }
        }
    }

    /// A large panel of choices in the middle of the screen: one click picks and closes it.
    private func panelView(_ panel: FilterPanel) -> some View {
        ZStack {
            Color.black.opacity(0.75)
                .contentShape(Rectangle())
                .onTapGesture { self.panel = nil }
            VStack(alignment: .leading, spacing: 26) {
                Text(panelTitle(panel)).font(.system(size: Cinema.rowTitle, weight: .bold))
                FlowChips {
                    switch panel {
                    case .sort:
                        ForEach(Self.sorts) { option in
                            choice(Self.title(option), isOn: sort == option) { sort = option }
                        }
                    case .mood:
                        choice("Any Mood", symbol: "sparkles", isOn: mood == nil) { mood = nil }
                        ForEach(model.moods, id: \.self) { option in
                            choice(option.title, symbol: option.symbol, isOn: mood == option) { mood = option }
                        }
                    case .length:
                        ForEach(LengthBand.allCases) { option in
                            choice(option.title, isOn: length == option) { length = option }
                        }
                    case .language:
                        choice("Any Language", isOn: language == nil) { language = nil }
                        ForEach(model.languages, id: \.self) { code in
                            choice(FilmLanguage.name(code), isOn: language == code) { language = code }
                        }
                    }
                }
                Button("Close") { self.panel = nil }
                    .buttonStyle(CinemaButtonStyle(compact: true))
            }
            .padding(40)
            .frame(maxWidth: 1000, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.background))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    private func panelTitle(_ panel: FilterPanel) -> String {
        switch panel {
        case .sort: "Sort By"
        case .mood: "Mood"
        case .length: "Length"
        case .language: "Language"
        }
    }

    private func choice(_ title: String, symbol: String? = nil, isOn: Bool, pick: @escaping () -> Void) -> some View {
        CinemaChip(title: title, symbol: symbol, isOn: isOn) {
            pick()
            panel = nil
        }
    }
}

/// Search in Cinema mode: a large field, read from the sofa; the clear button is big too.
private struct CinemaSearchField: View {
    @Binding var text: String
    @Binding var focusRequested: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: Cinema.body))
                .focused($focused)
                // Return or Esc hand the keys back to the posters.
                .onSubmit { focused = false }
                .onExitCommand { focused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .frame(width: 440, height: 64)
        .background(Capsule().fill(Color.white.opacity(focused ? 0.16 : 0.1)))
        .overlay(Capsule().strokeBorder(focused ? Theme.brand.opacity(0.7) : .clear, lineWidth: 2))
        .onAppear(perform: takeFocus)
        .onChange(of: focusRequested) { takeFocus() }
    }

    private func takeFocus() {
        guard focusRequested else { return }
        focusRequested = false
        Task { @MainActor in focused = true }
    }
}

/// Chips that wrap onto as many lines as they need.
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlowLayout(spacing: 12) { content }
    }
}

/// Lays its children out left to right, wrapping at the edge.
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// The posters, with the highlight kept here (pointing at a poster never sorts the library
/// again). The arrow keys move the same highlight, row by row as the grid lays them out.
private struct CinemaLibraryGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    let films: [LibraryItem]
    let active: Bool
    let open: (String) -> Void
    let scrollTo: (String) -> Void
    @State private var selected: String?
    /// The highlight was moved with the arrow keys, so the pointer leaving a poster keeps it.
    @State private var byKeys = false
    @State private var pointer = PointerWatch()
    @State private var width: CGFloat = 0

    private static let spacing: CGFloat = 26

    /// How many posters fit in a row at this width.
    private var columns: Int {
        max(1, Int((width + Self.spacing) / (Cinema.posterWidth + Self.spacing)))
    }

    var body: some View {
        Group {
            if isSnapshot {
                // Drawn to an image: the first rows, without the lazy grid.
                VStack(alignment: .leading, spacing: 36) {
                    ForEach(Array(stride(from: 0, to: min(films.count, 15), by: 5)), id: \.self) { start in
                        HStack(alignment: .top, spacing: Self.spacing) {
                            ForEach(films[start..<min(start + 5, films.count)]) { tile($0) }
                        }
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Cinema.posterWidth, maximum: Cinema.posterWidth),
                                             spacing: Self.spacing, alignment: .top)],
                          alignment: .leading, spacing: 36) {
                    ForEach(films) { tile($0) }
                }
                .padding(.vertical, 10)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            }
        }
        .padding(.horizontal, Cinema.gutter)
        .onReelKey { key in active && move(key) }
    }

    private func tile(_ item: LibraryItem) -> some View {
        CinemaPosterTile(item: item, marks: CinemaTileMarks(model: model, key: item.id), reason: nil, caption: nil,
                         selected: selected == item.id) {
            open(item.main.id)
        }
        .equatable()
        .onHover { inside in
            if inside {
                // Not a poster the grid scrolled under a resting pointer.
                guard pointer.moved() else { return }
                selected = item.id
                byKeys = false
            } else if selected == item.id, !byKeys {
                selected = nil
            }
        }
        .id(item.id)
    }

    /// Arrows move through the grid (the first press shows the highlight); Return, Space and T
    /// act on the highlighted film.
    private func move(_ key: ReelKey) -> Bool {
        guard !films.isEmpty else { return false }
        let current = selected.flatMap { id in films.firstIndex { $0.id == id } }
        var index = current ?? 0
        switch key {
        case .left where current != nil: index -= 1
        case .right where current != nil: index += 1
        case .up where current != nil: index -= columns
        case .down where current != nil: index += columns
        case .left, .right, .up, .down: break
        case .enter, .space, .tonight:
            guard let current else { return false }
            return CinemaActions.perform(key, on: films[current], model: model, open: open)
        case .escape, .fullScreen: return false
        }
        let id = films[min(max(index, 0), films.count - 1)].id
        selected = id
        byKeys = true
        pointer.keysMoved()
        scrollTo(id)
        return true
    }
}
#endif
