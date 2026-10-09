#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

// MARK: - Explore

/// Finding new films: what's in cinemas, trending and newly out at home, three shelves that
/// change each time Reel opens (one of your loved films', a country's cinema, a decade or the
/// hidden gems), and the best of any year from the source you choose. Films you've seen are left
/// out. A mood chip narrows every row to that mood and adds the best-loved films of the mood
/// from any time. (Picked for You has its own page, For You.)
struct ExploreView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: NavigationPath
    @State private var preview: PreviewFilm?
    @State private var year = Calendar.current.component(.year, from: Date()) - 1
    @State private var source = BestOfSource.tmdb
    @State private var mood: Mood?
    /// A film looked up by name: its matches take the place of the rows while there's text.
    @State private var searchText = ""
    @State private var found: [TMDBMovieSummary]?
    @State private var searching = false
    @State private var searchFailed = false

    private var lists: [DiscoverList] {
        (mood.map { [DiscoverList.mood($0)] } ?? []) + [.inCinemas, .trending, .newAtHome] + model.exploreShelves
    }

    private static let moodChoices = [MoodChoiceCount(choice: .any, count: 0)]
        + Mood.allCases.map { MoodChoiceCount(choice: .mood($0), count: 0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 38) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Explore").font(.system(size: 30, weight: .bold))
                            Text("Find your next film. New shelves each time Reel opens; films you've seen are left out.")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 16)
                        ExploreSearchField(text: $searchText, searching: searching)
                            .padding(.top, 4)
                    }
                    if words.isEmpty {
                        MoodChips(choices: Self.moodChoices, selected: mood.map { .mood($0) } ?? .any, counted: false) { choice in
                            withAnimation(.easeOut(duration: 0.25)) {
                                if case .mood(let chosen) = choice { mood = chosen } else { mood = nil }
                            }
                        }
                    }
                }
                if !words.isEmpty {
                    searchResults
                } else {
                    ForEach(lists, id: \.self) { list in
                        DiscoverRow(list: list, mood: list.mood == nil ? mood : nil) { preview = $0 }
                    }
                    BestOfRow(year: $year, source: $source, mood: mood) { preview = $0 }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationTitle("Explore")
        .filmPreviewSheet($preview)
        .task { await model.lists.prepare() }
        .task(id: words) { await search() }
        .task(id: lists) {
            await withTaskGroup(of: Void.self) { group in
                for list in lists {
                    group.addTask { await model.loadDiscover(list) }
                }
            }
        }
    }
}

extension ExploreView {
    /// What's being looked up (spaces alone look up nothing).
    var words: String { searchText.trimmingCharacters(in: .whitespaces) }

    /// The films TMDB finds for the words, in its order (owned ones open their page).
    @ViewBuilder
    var searchResults: some View {
        if let found, !found.isEmpty {
            LazyVGrid(columns: LibraryGridView.columns, alignment: .leading, spacing: 30) {
                ForEach(found) { movie in
                    DiscoverCard(film: PreviewFilm(movie)) { preview = $0 }
                }
            }
        } else if searchFailed, !searching {
            Text("TMDB couldn't be reached. Check the connection and try again.")
                .foregroundStyle(.secondary)
                .frame(minHeight: 120, alignment: .leading)
        } else if found != nil, !searching {
            Text("No film found for “\(words)”.")
                .foregroundStyle(.secondary)
                .frame(minHeight: 120, alignment: .leading)
        }
    }

    /// After a short pause in typing.
    func search() async {
        let query = words
        guard !query.isEmpty else {
            found = nil
            searchFailed = false
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, let client = model.tmdb else { return }
        searching = true
        defer { searching = false }
        let results: [TMDBMovieSummary]
        do {
            results = try await client.searchMovies(query: query, year: nil)
        } catch {
            guard !Task.isCancelled else { return }
            found = nil
            searchFailed = true
            return
        }
        guard !Task.isCancelled else { return }
        searchFailed = false
        // Little-known entries (no poster, no votes) after the rest, each part in TMDB's order.
        func known(_ movie: TMDBMovieSummary) -> Bool { movie.posterPath != nil && (movie.voteCount ?? 0) > 0 }
        found = results.filter(known) + results.filter { !known($0) }
    }
}

/// Look up any film: a slim field beside Explore's title.
private struct ExploreSearchField: View {
    @Binding var text: String
    let searching: Bool

    var body: some View {
        HStack(spacing: 7) {
            if searching {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            TextField("Search any film", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 280, height: 32)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}

/// "Best of" a year, from the source you choose: TMDB's rating, IMDb's, the most popular, the
/// award winners or the hidden gems.
struct BestOfRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @Binding var year: Int
    @Binding var source: BestOfSource
    var mood: Mood?
    let onPreview: (PreviewFilm) -> Void

    var body: some View {
        let found = model.bestOf(year: year, source: source)
        let films = (found ?? []).filter { film in
            !model.hasSeen(film.id) && (mood.map { film.genres.isEmpty || MoodGenres.of($0).fits(film.genres) } ?? true)
        }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Best of \(String(year))").font(.system(size: 19, weight: .semibold))
                    Text(source.subtitle(year)).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                YearMenu(year: $year)
                SourceMenu(source: $source)
                Spacer()
                if !films.isEmpty { seeAll }
            }
            if films.isEmpty {
                HStack(spacing: 8) {
                    if found == nil, model.bestOfFailed(year: year, source: source), !model.isLoadingBestOf(year: year, source: source) {
                        Text("Couldn't load this list. Check the internet connection.").foregroundStyle(.secondary)
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(SecondaryCapsuleStyle())
                    } else if found == nil || model.isLoadingBestOf(year: year, source: source) {
                        ProgressView().controlSize(.small)
                        Text(source == .imdb && !model.lists.imdbIsReady ? "Getting IMDb's ratings (the first time takes a minute)…" : "Loading…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(source == .awards ? "No award winners from \(String(year)) in the lists." : "Nothing found for \(String(year)).")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 120)
            } else if isSnapshot {
                HStack(alignment: .top, spacing: 18) { cards(films) }.snapshotRow()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18) { cards(films) }
                        .padding(.vertical, 6)
                }
            }
        }
        .task(id: "\(year)|\(source.rawValue)") { await load() }
    }

    private func load() async {
        await model.loadBestOf(year: year, source: source)
        // IMDb's ratings download the first time: look again once they're in (or failed).
        if source == .imdb, model.bestOf(year: year, source: source) == nil {
            while !Task.isCancelled, !model.lists.imdbIsReady, !model.lists.imdbFailed { try? await Task.sleep(for: .seconds(2)) }
            await model.loadBestOf(year: year, source: source)
        }
    }

    /// Where See All goes: the whole list on TMDB, or IMDb's Top 100 in Lists (the award
    /// winners are all in the row).
    @ViewBuilder
    private var seeAll: some View {
        switch source {
        case .tmdb, .popular, .gems:
            NavigationLink(value: DiscoverRoute(list: .bestOf(year: year, source: source), mood: mood)) { seeAllLabel }
                .buttonStyle(.plain)
        case .imdb:
            NavigationLink(value: ListRoute(kind: .imdbYear(year))) { seeAllLabel }
                .buttonStyle(.plain)
        case .awards:
            EmptyView()
        }
    }

    private var seeAllLabel: some View {
        HStack(spacing: 4) {
            Text("See All")
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.brand)
    }

    private func cards(_ films: [PreviewFilm]) -> some View {
        // Ranked by the whole list, seen films included (only they're left out of the row).
        let all = model.bestOf(year: year, source: source) ?? []
        return ForEach(films.prefix(20)) { film in
            DiscoverCard(film: film, width: 146,
                         rank: source == .tmdb || source == .imdb ? all.firstIndex { $0.id == film.id }.map { $0 + 1 } : nil,
                         reason: source == .awards ? film.note : nil, onPreview: onPreview)
        }
    }
}

/// Where the best of a year comes from.
struct SourceMenu: View {
    @Environment(\.isSnapshot) private var isSnapshot
    @Binding var source: BestOfSource
    /// Only TMDB's sources (a list page of TMDB films).
    var tmdbOnly = false

    var body: some View {
        if isSnapshot {
            FilterPill(icon: "line.3.horizontal.decrease", text: source.title, active: false)
        } else {
            menu
        }
    }

    private var menu: some View {
        Menu {
            // Inline: the choices themselves, not a "Source" item opening them.
            Picker("Source", selection: $source) {
                ForEach(BestOfSource.allCases.filter { !tmdbOnly || $0.isTMDB }) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            FilterPill(icon: "line.3.horizontal.decrease", text: source.title, active: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// One Explore list as a horizontal row with "See All".
struct DiscoverRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    let list: DiscoverList
    /// Only the films of this mood (by their genres); a row left empty by it isn't shown.
    var mood: Mood? = nil
    let onPreview: (PreviewFilm) -> Void

    var body: some View {
        let all = model.discover[list] ?? []
        let films = model.exploreFilms(list, mood: mood)
        if mood == nil || !films.isEmpty || all.isEmpty {
            row(films)
        }
    }

    private func row(_ films: [TMDBMovieSummary]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.title).font(.system(size: 19, weight: .semibold))
                    Text(list.subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                Spacer()
                if !films.isEmpty {
                    NavigationLink(value: DiscoverRoute(list: list, mood: mood)) {
                        HStack(spacing: 4) {
                            Text("See All")
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
            if films.isEmpty {
                HStack(spacing: 8) {
                    if model.discoverLoading.contains(list) {
                        ProgressView().controlSize(.small)
                        Text("Loading…").foregroundStyle(.secondary)
                    } else {
                        Text(model.hasToken ? "Couldn't load this list. Check the internet connection." : "Connect TMDB in Settings to explore.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 120)
            } else if isSnapshot {
                HStack(alignment: .top, spacing: 18) { cards(films) }.snapshotRow()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18) { cards(films) }
                        .padding(.vertical, 6)
                }
            }
        }
    }
}

extension DiscoverRow {
    private func cards(_ films: [TMDBMovieSummary]) -> some View {
        ForEach(films.prefix(20)) { movie in
            DiscoverCard(film: PreviewFilm(movie), width: 146, onPreview: onPreview)
        }
    }
}

/// All films of one Explore list.
struct DiscoverListPage: View {
    @Environment(AppModel.self) private var model
    @State private var list: DiscoverList
    /// Only the films of this mood (from Explore's mood chips).
    let mood: Mood?
    @State private var year: Int
    @State private var source: BestOfSource
    @State private var preview: PreviewFilm?

    init(list: DiscoverList, mood: Mood? = nil) {
        self.mood = mood
        _list = State(initialValue: list)
        if case .bestOf(let y, let s) = list {
            _year = State(initialValue: y)
            _source = State(initialValue: s)
        } else {
            _year = State(initialValue: Calendar.current.component(.year, from: Date()) - 1)
            _source = State(initialValue: .tmdb)
        }
    }

    var body: some View {
        let films = model.exploreFilms(list, mood: mood)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(mood.map { "\(list.title) · \($0.title)" } ?? list.title).font(.system(size: 30, weight: .bold))
                    if case .bestOf = list {
                        YearMenu(year: $year)
                        SourceMenu(source: Binding(get: { source }, set: { source = $0.isTMDB ? $0 : source }), tmdbOnly: true)
                    }
                    Spacer()
                }
                Text(list.subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
                if films.isEmpty && model.discoverLoading.contains(list) {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
                LazyVGrid(columns: LibraryGridView.columns, alignment: .leading, spacing: 30) {
                    let all = model.discover[list] ?? []
                    ForEach(films) { movie in
                        // Ranked by the whole list, seen films included.
                        DiscoverCard(film: PreviewFilm(movie), rank: isRanked ? all.firstIndex { $0.id == movie.id }.map { $0 + 1 } : nil) {
                            preview = $0
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
        }
        .background(Theme.background)
        .navigationTitle(list.title)
        .filmPreviewSheet($preview)
        .task(id: list) { await model.loadDiscover(list) }
        .onChange(of: "\(year)|\(source.rawValue)") {
            if case .bestOf = list { list = .bestOf(year: year, source: source) }
        }
    }

    private var isRanked: Bool {
        if case .bestOf(_, let source) = list { return source == .tmdb }
        return false
    }
}

/// A year to choose: the pill opens a short list (about ten years at a time) that scrolls,
/// opened at the year shown.
struct YearMenu: View {
    @Binding var year: Int
    @State private var open = false
    /// The row the list opens at: the chosen year, in the middle.
    @State private var shown: Int?
    private let years = Array((1920...Calendar.current.component(.year, from: Date())).reversed())

    var body: some View {
        Button {
            shown = year
            open.toggle()
        } label: {
            FilterPill(icon: "calendar", text: String(year), active: false)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $open, arrowEdge: .bottom) { list }
    }

    private var list: some View {
        ScrollView {
                VStack(spacing: 2) {
                    ForEach(years, id: \.self) { option in
                        Button {
                            year = option
                            open = false
                        } label: {
                            HStack {
                                Text(String(option)).monospacedDigit()
                                Spacer()
                                if option == year { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                            }
                            .font(.system(size: 13.5, weight: option == year ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(option == year ? Theme.brand.opacity(0.25) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(option)
                    }
                }
                .scrollTargetLayout()
                .padding(6)
        }
        .scrollPosition(id: $shown, anchor: .center)
        .frame(width: 130, height: 10 * 30 + 12)
    }
}

/// A poster for a film from outside the library. Films you own open their page; others a preview.
struct DiscoverCard: View {
    @Environment(AppModel.self) private var model
    let film: PreviewFilm
    var width: CGFloat?
    var rank: Int?
    /// Top-left label, e.g. "92%".
    var badge: String?
    /// Why it's suggested, in Reel's colour under the title ("From the director of Her").
    var reason: String?
    let onPreview: (PreviewFilm) -> Void
    @State private var hovering = false

    var body: some View {
        let owned = model.itemsByTMDB[film.id]
        VStack(alignment: .leading, spacing: 7) {
            opening(owned) {
                Poster(path: film.posterPath, title: film.title, cornerRadius: 12)
                    .overlay(alignment: .topTrailing) { marker(owned: owned != nil) }
                    .overlay(alignment: .topLeading) { badgeLabel }
            }
            // Seen and Wishlist right on the poster: a sibling of the link, so clicks reach them.
            .overlay(alignment: .bottomTrailing) {
                if hovering { quickActions(owned: owned != nil) }
            }
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: hovering)
            opening(owned) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(film.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let reason {
                        Text(reason)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.brand)
                            .lineLimit(2, reservesSpace: true)
                    }
                    Text(caption)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .frame(width: width)
        .onHover { hovering = $0 }
    }

    /// Films you own open their page; others open the preview.
    @ViewBuilder
    private func opening<Label: View>(_ owned: LibraryItem?, @ViewBuilder label: () -> Label) -> some View {
        if let owned {
            NavigationLink(value: FilmRoute(id: owned.main.id)) { label() }
                .buttonStyle(.plain)
        } else {
            Button { onPreview(film) } label: { label() }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var badgeLabel: some View {
        if let label = badge ?? rank.map({ "#\($0)" }) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.65)))
                .foregroundStyle(Color.white)
                .padding(7)
        }
    }

    private func quickActions(owned: Bool) -> some View {
        let seen = model.isSeen(film.id)
        let wished = model.isWishlisted(film.id)
        return HStack(spacing: 6) {
            HoverAction(symbol: seen ? "eye.fill" : "eye", isOn: seen, onColor: Theme.brand,
                        help: seen ? "Seen" : "Mark as seen") { model.toggleSeen(film.id) }
            if !owned {
                HoverAction(symbol: wished ? "star.fill" : "star", isOn: wished, onColor: .yellow,
                            help: wished ? "On your wishlist" : "Add to wishlist") { model.toggleWishlist(film) }
            }
        }
        .padding(8)
        .transition(.opacity)
    }

    @ViewBuilder
    private func marker(owned: Bool) -> some View {
        if owned {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Theme.brand)
                .padding(7)
                .help("In your library")
        } else if model.isWishlisted(film.id) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black, Color.yellow)
                .padding(7)
                .help("On your wishlist")
        } else if model.isSeen(film.id) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black, Color.white)
                .padding(7)
                .help("Seen")
        }
    }

    /// "2024 · ★ 7.8 · Drama"
    private var caption: String {
        var parts: [String] = []
        if let year = film.year { parts.append(String(year)) }
        if let vote = film.voteAverage, vote > 0, film.voteCount >= 20 { parts.append("★ " + Format.rating(vote)) }
        if let genre = film.genres.first { parts.append(LibraryItem.shortGenreNames[genre] ?? genre) }
        return parts.joined(separator: " · ")
    }
}

/// A small frosted round button shown over a poster on hover.
struct HoverAction: View {
    let symbol: String
    let isOn: Bool
    let onColor: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isOn ? onColor : Color.white)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Wishlist

struct WishlistView: View {
    @Environment(AppModel.self) private var model
    @State private var preview: PreviewFilm?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Wishlist").font(.system(size: 30, weight: .bold))
                    Text(model.wishlist.count == 1 ? "1 film" : "\(model.wishlist.count) films")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if model.wishlist.isEmpty {
                    ContentUnavailableView("Your wishlist is empty", systemImage: "star",
                                           description: Text("Add films you'd like to see from Explore, people pages or More Like This."))
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVGrid(columns: LibraryGridView.columns, alignment: .leading, spacing: 30) {
                        ForEach(model.wishlist) { wish in
                            DiscoverCard(film: PreviewFilm(wish)) { preview = $0 }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
        }
        .background(Theme.background)
        .navigationTitle("Wishlist")
        .filmPreviewSheet($preview)
    }
}

// MARK: - Preview of a film you don't own

extension View {
    /// Shows a film you don't own as a card over the page. Its trailer plays in the window's own
    /// large player, over the card.
    func filmPreviewSheet(_ preview: Binding<PreviewFilm?>) -> some View {
        cardOverlay(item: preview) { film in
            FilmPreview(film: film) { preview.wrappedValue = nil }
        }
    }

    /// A card over the page (a film's preview): the page dims behind it, and a click outside it
    /// or Esc closes it.
    func cardOverlay<Item: Identifiable, Card: View>(item: Binding<Item?>,
                                                      @ViewBuilder card: @escaping (Item) -> Card) -> some View {
        modifier(CardOverlay(item: item, card: card))
    }
}

private struct CardOverlay<Item: Identifiable, Card: View>: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var item: Item?
    let card: (Item) -> Card

    func body(content: Content) -> some View {
        content
            .overlay {
                if let shown = item {
                    ZStack {
                        Color.black.opacity(0.55)
                            .contentShape(Rectangle())
                            .onTapGesture { item = nil }
                        card(shown)
                            .background(Theme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
                            .shadow(color: Color.black.opacity(0.5), radius: 40, y: 18)
                            .padding(40)
                            .id(shown.id)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onReelKey { key in
                        // A trailer over the card takes Esc first, and Cinema mode its own.
                        guard key == .escape, model.trailer == nil, !model.cinemaMode else { return false }
                        item = nil
                        return true
                    }
                }
            }
            .animation(.easeOut(duration: 0.18), value: item == nil)
            .onChange(of: model.cinemaMode) { item = nil }
    }
}

struct FilmPreview: View {
    @Environment(AppModel.self) private var model
    let film: PreviewFilm
    let close: () -> Void
    @State private var details: TMDBMovieDetails?
    @State private var ratings: ExternalRatings?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            info
        }
        .frame(width: 600)
        .task {
            let info = await model.previewInfo(for: film.id)
            details = info.details
            ratings = info.ratings
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
                .frame(height: 250)
                .overlay {
                    CachedImage(path: film.backdropPath ?? details?.backdropPath, kind: .backdrop) { Color(white: 0.08) }
                }
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
                }
            HStack(alignment: .bottom, spacing: 16) {
                Poster(path: film.posterPath, title: film.title, cornerRadius: 10)
                    .frame(width: 96)
                    .shadow(color: Color.black.opacity(0.5), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(film.title).font(.system(size: 26, weight: .bold)).lineLimit(2)
                    Text(metaLine).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(22)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            RatingStrip(ratings: ratings, tmdbVote: film.voteAverage ?? details?.voteAverage)
                .font(.system(size: 13))
            if let note = film.note, !note.isEmpty {
                Text(note).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.brand)
            }
            if let overview {
                Text(overview)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                // Always in place, so the buttons don't jump when the details arrive. Official
                // trailers only (see `Trailers`).
                let videos = trailerVideos
                Button {
                    model.trailer = TrailerRequest(videos: videos.map(\.key), title: film.title, filmID: nil, tmdbID: film.id,
                                                   backdropPath: film.backdropPath ?? details?.backdropPath,
                                                   origin: nil, offersFilmPage: false)
                } label: {
                    Label(videos.first.map(Trailers.isTeaser) == true ? "Teaser" : "Trailer", systemImage: "play.rectangle")
                }
                .buttonStyle(PrimaryCapsuleStyle())
                .disabled(videos.isEmpty)
                .opacity(videos.isEmpty ? 0.45 : 1)
                .help(details == nil ? "Loading…" : (videos.isEmpty ? "No official trailer that plays here" : "Watch the trailer"))
                Button {
                    model.toggleWishlist(film)
                } label: {
                    Label(model.isWishlisted(film.id) ? "On Wishlist" : "Wishlist",
                          systemImage: model.isWishlisted(film.id) ? "star.fill" : "star")
                }
                .buttonStyle(SecondaryCapsuleStyle())
                SeenButton(tmdbID: film.id) { seen in
                    Label(seen ? "Seen" : "Seen It?", systemImage: seen ? "eye.fill" : "eye")
                }
                .buttonStyle(SecondaryCapsuleStyle())
                if let url = URL(string: "https://www.themoviedb.org/movie/\(film.id)") {
                    Button("TMDB") { NSWorkspace.shared.open(url) }
                        .buttonStyle(SecondaryCapsuleStyle())
                }
                Spacer()
                Button("Close", action: close)
                    .buttonStyle(SecondaryCapsuleStyle())
            }
            if model.isSeen(film.id) { seenLine }
        }
        .padding(22)
    }

    /// Seen elsewhere: when, and your stars (both count in Year in Film).
    private var seenLine: some View {
        let record = model.record(forKey: "tmdb:\(film.id)")
        return HStack(spacing: 10) {
            Text(record.watchedOn.map { "Seen in \($0.formatted(.dateTime.month(.wide).year()))" } ?? "Seen")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            StarRating(rating: record.rating) { model.setSeenRating($0, tmdbID: film.id) }
        }
    }

    /// The film's trailers (see `Trailers`) unless they all failed to play here this session.
    private var trailerVideos: [TMDBVideo] {
        guard let details, !model.unplayableTrailers.contains(film.id) else { return [] }
        return Trailers.candidates(details.videos?.results ?? [], title: details.title, preferTeaser: model.spoilerSafe,
                                   originalLanguage: details.originalLanguage)
    }

    private var overview: String? {
        if let text = film.overview, !text.isEmpty { return text }
        if let text = details?.overview, !text.isEmpty { return text }
        return nil
    }

    private var metaLine: String {
        var parts: [String] = []
        if let year = film.year { parts.append(String(year)) }
        if let rated = ratings?.rated, rated != "N/A", rated != "Not Rated" { parts.append(rated) }
        if let runtime = details?.runtime, runtime > 0 { parts.append(Format.runtime(runtime)) }
        let genres = film.genres.isEmpty ? (details?.genreNames ?? []) : film.genres
        if !genres.isEmpty { parts.append(genres.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: - Film page additions

/// "More Like This": TMDB recommendations with how closely they match.
struct SimilarRow: View {
    let films: [SimilarFilm]
    let onPreview: (PreviewFilm) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Theme.sectionTitle("More Like This, Beyond Your Library")
                Text("Liked by people who liked this film")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(films) { similar in
                        DiscoverCard(film: PreviewFilm(similar.movie, note: "\(similar.match)% match"),
                                     width: 120, badge: "\(similar.match)%", onPreview: onPreview)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}
#endif
