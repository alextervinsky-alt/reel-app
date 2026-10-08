#if os(macOS)
import SwiftUI
import ReelCore

// MARK: - One list

/// A whole list, ranked, with what you own and have seen. Films you own open their page; the
/// others open a preview where they can go on the wishlist or be marked as seen.
struct ListPage: View {
    @Environment(AppModel.self) private var model
    @State private var kind: FilmListKind
    @State private var year: Int
    @State private var filter: Filter = .all
    @State private var order: Order = .list
    @State private var withNominees = false
    @State private var preview: PreviewFilm?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", owned = "In Your Library", unseen = "Not Seen", missing = "Not in Library"
        var id: String { rawValue }
    }

    /// The list's own order, or what's most likely to be your next film first.
    enum Order: String, CaseIterable, Identifiable {
        case list = "List Order", fit = "Best for You", rating = "Highest Rated", newest = "Newest", oldest = "Oldest"
        var id: String { rawValue }
    }

    init(kind: FilmListKind) {
        _kind = State(initialValue: kind)
        if case .imdbYear(let y) = kind {
            _year = State(initialValue: y)
        } else {
            _year = State(initialValue: Calendar.current.component(.year, from: Date()) - 1)
        }
    }

    var body: some View {
        let lists = model.lists
        let all = lists.films(for: kind)
        let films = kind.hasNominees && !withNominees ? all.filter { $0.isWinner } : all
        let progress = model.progress(of: films)
        let ranked = Array(films.enumerated())
        let picks = model.listPicks().byFilm
        let shown = sorted(ranked.filter { matches($0.element) }, picks: picks)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(progress, films: films)
                if !films.isEmpty {
                    HStack(spacing: 8) {
                        if kind.hasNominees {
                            FilterChip(title: "Winners", isOn: !withNominees) { withNominees = false }
                            FilterChip(title: "Winners & Nominees", isOn: withNominees) { withNominees = true }
                            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18).padding(.horizontal, 6)
                        }
                        ForEach(Filter.allCases) { option in
                            FilterChip(title: option.rawValue, isOn: filter == option) { filter = option }
                        }
                        Spacer(minLength: 12)
                        Picker("Sort", selection: $order) {
                            ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .help("Best for You: films on several lists, by directors and in genres you rate highly, and well rated, first")
                    }
                }
                if films.isEmpty {
                    emptyState
                } else if shown.isEmpty {
                    Text("Nothing here with this filter.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(shown, id: \.element.id) { index, film in
                            if film.id != shown.first?.element.id {
                                Divider().overlay(Theme.hairline).padding(.leading, 140)
                            }
                            ListRow(film: film, badge: badge(film, index: index), detail: detail(film, pick: picks[film.id]),
                                    trophy: withNominees && film.won == true) { preview = $0 }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
                }
                Text(attribution)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(kind.title)
        .filmPreviewSheet($preview)
        // Runs again when the list arrives (first IMDb download, a refresh): posters for up to
        // 250 films are looked up straight away, the rest as their rows come into view.
        .task(id: "\(kind)|\(films.count)") {
            await lists.load(kind)
            if let client = model.tmdb { await lists.resolve(Array(lists.films(for: kind).prefix(250)), using: client) }
        }
        .onChange(of: year) {
            if case .imdbYear = kind { kind = .imdbYear(year) }
        }
    }

    // MARK: Header

    private func header(_ progress: ListProgress, films: [ListFilm]) -> some View {
        HStack(alignment: .center, spacing: 28) {
            ZStack {
                ProgressRing(fraction: progress.seenFraction, lineWidth: 8)
                VStack(spacing: 0) {
                    Text("\(progress.seen)")
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                    Text("of \(progress.total)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 112, height: 112)
            .opacity(films.isEmpty ? 0.3 : 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(kind.title).font(.system(size: 30, weight: .bold))
                    if case .imdbYear = kind { YearMenu(year: $year) }
                }
                Text(kind.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                if let note = kind.coverageNote {
                    Label(note, systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !films.isEmpty {
                    Text(statsLine(progress))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                    let missing = missingFilms(films)
                    if !missing.isEmpty {
                        Button {
                            model.addToWishlist(missing)
                        } label: {
                            Label("Add \(missing.count) to Wishlist", systemImage: "star")
                        }
                        .buttonStyle(SecondaryCapsuleStyle())
                        .help("Every film on this list that you don't own and haven't seen")
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func statsLine(_ progress: ListProgress) -> String {
        var parts = ["\(progress.seen) seen", "\(progress.owned) in your library"]
        if progress.wishlisted > 0 { parts.append("\(progress.wishlisted) on your wishlist") }
        return parts.joined(separator: "  ·  ")
    }

    /// Films not owned, not seen and not on the wishlist yet (once their TMDB id is known).
    private func missingFilms(_ films: [ListFilm]) -> [WishlistFilm] {
        films.compactMap { film in
            guard model.libraryItem(film) == nil, let art = model.lists.resolved(film),
                  !model.isSeen(art.tmdbID), !model.isWishlisted(art.tmdbID) else { return nil }
            return PreviewFilm(film, art: art).wishlistEntry
        }
    }

    // MARK: Rows

    private func matches(_ film: ListFilm) -> Bool {
        switch filter {
        case .all: return true
        case .owned: return model.libraryItem(film) != nil
        case .missing: return model.libraryItem(film) == nil
        case .unseen:
            let id = model.libraryItem(film)?.main.tmdb?.id ?? model.lists.tmdbID(film)
            return !model.isSeen(id)
        }
    }

    /// Position for IMDb rankings; the poll rank, award year or spine number for the others.
    private func badge(_ film: ListFilm, index: Int) -> String {
        film.rank ?? "\(index + 1)"
    }

    /// Best for You and the other orders; the number in front stays the list's own.
    private func sorted(_ rows: [(offset: Int, element: ListFilm)], picks: [String: ListPick]) -> [(offset: Int, element: ListFilm)] {
        func year(_ film: ListFilm) -> Int { film.year ?? 0 }
        switch order {
        case .list: return rows
        case .newest: return rows.sorted { year($0.element) > year($1.element) }
        case .oldest: return rows.sorted { year($0.element) < year($1.element) }
        case .rating: return rows.sorted { rating($0.element) > rating($1.element) }
        case .fit:
            let scored = rows.map { row -> (row: (offset: Int, element: ListFilm), score: Double) in
                (row, fit(row.element, pick: picks[row.element.id]))
            }
            return scored.sorted { $0.score > $1.score }.map { $0.row }
        }
    }

    private func rating(_ film: ListFilm) -> Double {
        model.libraryItem(film)?.score ?? model.lists.resolved(film)?.voteAverage ?? 0
    }

    /// How likely a film is to be your next one: the lists it's on, how it fits your ratings,
    /// how it's rated; films you've seen go last.
    private func fit(_ film: ListFilm, pick: ListPick?) -> Double {
        let item = model.libraryItem(film)
        let art = model.lists.resolved(film)
        let tmdbID = item?.main.tmdb?.id ?? art?.tmdbID ?? film.tmdbID
        if model.isSeen(tmdbID) { return -10 }
        let taste = item.map { model.tasteMatch($0)?.score ?? 0 } ?? model.listFit(tmdbID: tmdbID, genres: art?.genres).score
        let rated = rating(film)
        return (pick?.weight ?? 0) + 1.5 * taste + (rated > 0 ? (rated - 7) * 0.4 : 0)
    }

    private func detail(_ film: ListFilm, pick: ListPick?) -> String {
        var parts: [String] = []
        if let year = film.year { parts.append(String(year)) }
        if kind.usesIMDb {
            if let note = film.note { parts.append("IMDb " + note) }
        } else {
            if case .award(let award) = kind, award != .criterion, let note = film.note { parts.append(note) }
            if let vote = model.lists.resolved(film)?.voteAverage, vote > 0 { parts.append("★ " + Format.rating(vote)) }
        }
        // The other lists it's on: a film many lists agree on is a surer choice.
        let others = (pick?.lists ?? []).filter { $0 != kind }
        if !others.isEmpty { parts.append("also " + ListConsensus.summary(others)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var emptyState: some View {
        let lists = model.lists
        if kind.usesIMDb, !(lists.imdbFilmsLoading), lists.films(for: kind).isEmpty, !isReady {
            IMDbSetupCard()
        } else if lists.isLoading(kind) || lists.imdbFilmsLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        } else {
            ContentUnavailableView("Couldn't load this list", systemImage: "wifi.exclamationmark",
                                   description: Text("Check the internet connection and try again."))
                .frame(minHeight: 240)
        }
    }

    private var isReady: Bool {
        if case .ready = model.lists.imdbState { return true }
        return false
    }

    private var attribution: String {
        switch kind {
        case .imdbYear, .imdbAllTime: IMDbDataset.attribution
        case .sightAndSound: "The Sight and Sound critics' poll, 2022 (bfi.org.uk). Posters from TMDB."
        case .award: "From Wikidata (wikidata.org), free to use under CC0. Posters from TMDB."
        }
    }
}

/// One film on a list: rank, poster, title, and buttons for Seen and Wishlist.
struct ListRow: View {
    @Environment(AppModel.self) private var model
    let film: ListFilm
    let badge: String
    let detail: String
    /// Marks the winner when nominees are shown too.
    var trophy = false
    let onPreview: (PreviewFilm) -> Void
    @State private var hovering = false

    var body: some View {
        let art = model.lists.resolved(film)
        let item = model.libraryItem(film)
        let tmdbID = item?.main.tmdb?.id ?? art?.tmdbID ?? film.tmdbID

        HStack(spacing: 14) {
            Group {
                if let item {
                    NavigationLink(value: FilmRoute(id: item.main.id)) { summary(art: art, poster: item.main.tmdb?.posterPath, owned: true) }
                } else {
                    Button {
                        if let art { onPreview(PreviewFilm(film, art: art)) }
                    } label: {
                        summary(art: art, poster: art?.posterPath, owned: false)
                    }
                    .disabled(art == nil)
                }
            }
            .buttonStyle(.plain)

            if let tmdbID {
                SeenButton(tmdbID: tmdbID) { seen in
                    IconToggle.face(symbol: seen ? "eye.fill" : "eye", isOn: seen, onColor: Theme.brand)
                }
                .buttonStyle(.plain)
            } else {
                IconToggle.face(symbol: "eye", isOn: false, onColor: Theme.brand).opacity(0.3)
            }
            if item == nil {
                let wished = model.isWishlisted(tmdbID)
                IconToggle(symbol: "star", onSymbol: "star.fill", isOn: wished,
                           help: wished ? "On your wishlist" : "Add to wishlist", onColor: .yellow) {
                    if let art { model.toggleWishlist(PreviewFilm(film, art: art)) }
                }
                .disabled(art == nil)
                .opacity(art == nil ? 0.3 : 1)
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 84)
        .background(hovering ? Color.white.opacity(0.035) : Color.clear)
        .onHover { hovering = $0 }
        .onAppear {
            if art == nil, let client = model.tmdb { model.lists.want(film, using: client) }
        }
    }

    private func summary(art: ResolvedFilm?, poster: String?, owned: Bool) -> some View {
        HStack(spacing: 16) {
            Text(badge)
                .font(.system(size: badge.count > 4 ? 15 : 19, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .trailing)
            Poster(path: poster, title: "", kind: .thumbnail, cornerRadius: 5)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(film.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if trophy {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.yellow)
                            .help("Winner")
                    }
                }
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if owned {
                Text("In Library")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.brand.opacity(0.18)))
                    .foregroundStyle(Theme.brand)
            }
        }
        .contentShape(Rectangle())
    }
}

/// A small round on/off button (Seen, Wishlist) for rows.
struct IconToggle: View {
    let symbol: String
    let onSymbol: String
    let isOn: Bool
    let help: String
    var onColor: Color = Theme.brand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Self.face(symbol: isOn ? onSymbol : symbol, isOn: isOn, onColor: onColor)
        }
        .buttonStyle(.plain)
        .help(help)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }

    /// The round face, also used by buttons that open a popover (Seen).
    static func face(symbol: String, isOn: Bool, onColor: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? onColor : Color.white.opacity(0.55))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(isOn ? 0.1 : 0.05)))
            .contentShape(Circle())
    }
}

// MARK: - Sets

/// "You have 6 of 10" with a ring, and a button to put the rest on the wishlist.
struct SetProgressHeader: View {
    @Environment(AppModel.self) private var model
    let title: String
    let set: FilmSet

    var body: some View {
        let progress = model.progress(of: set)
        let missing = set.films(owned: model.ownedIDs)
            .filter { model.itemsByTMDB[$0.id] == nil && !model.isSeen($0.id) && !model.isWishlisted($0.id) }
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(fraction: progress.ownedFraction, lineWidth: 6)
                Text("\(progress.owned)/\(progress.total)")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(line(progress))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            if !missing.isEmpty {
                Button {
                    model.addToWishlist(missing.map { PreviewFilm($0).wishlistEntry })
                } label: {
                    Label("Add \(missing.count) Missing to Wishlist", systemImage: "star")
                }
                .buttonStyle(SecondaryCapsuleStyle())
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
        .frame(maxWidth: 820, alignment: .leading)
    }

    private func line(_ progress: ListProgress) -> String {
        if progress.owned >= progress.total { return "You have all \(progress.total). Set complete." }
        var text = "You have \(progress.owned) of \(progress.total) in your library"
        if progress.seen > 0 { text += " · \(progress.seen) seen" }
        return text
    }
}

/// A franchise: every film in it, what you own and what's missing.
struct FranchisePage: View {
    @Environment(AppModel.self) private var model
    let route: FranchiseRoute
    @State private var preview: PreviewFilm?
    @State private var failed = false

    var body: some View {
        let set = model.lists.set(FilmSet.id(.franchise, route.id))
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(route.name).font(.system(size: 30, weight: .bold))
                if let set {
                    SetProgressHeader(title: "Your set", set: set)
                    LazyVGrid(columns: LibraryGridView.columns, alignment: .leading, spacing: 30) {
                        ForEach(set.films) { film in
                            DiscoverCard(film: PreviewFilm(film)) { preview = $0 }
                        }
                    }
                } else if failed {
                    ContentUnavailableView("Couldn't load this series", systemImage: "wifi.exclamationmark",
                                           description: Text(model.hasToken ? "Check the internet connection and try again."
                                                                            : "Connect TMDB in Settings."))
                        .frame(minHeight: 240)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
        }
        .background(Theme.background)
        .navigationTitle(route.name)
        .filmPreviewSheet($preview)
        .task(id: route.id) {
            guard let client = model.tmdb else {
                failed = true
                return
            }
            let loaded = await model.lists.loadFranchise(route.id, using: client)
            failed = !loaded
        }
    }
}
#endif
