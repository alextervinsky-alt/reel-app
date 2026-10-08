#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

// MARK: - Explore

/// Finding new films: picked for you (new each launch), what's in cinemas, trending, newly out
/// at home, the best of any year. A mood chip narrows every row to that mood and adds the
/// best-loved films of the mood from any time.
struct ExploreView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: NavigationPath
    @State private var preview: PreviewFilm?
    @State private var year = Calendar.current.component(.year, from: Date()) - 1
    @State private var mood: Mood?

    private var lists: [DiscoverList] {
        (mood.map { [DiscoverList.mood($0)] } ?? []) + [.inCinemas, .trending, .newAtHome, .bestOf(year: year)]
    }

    private static let moodChoices = [MoodChoiceCount(choice: .any, count: 0)]
        + Mood.allCases.map { MoodChoiceCount(choice: .mood($0), count: 0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 38) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Explore").font(.system(size: 30, weight: .bold))
                        Text("Find your next film. Ones you own open straight away.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    MoodChips(choices: Self.moodChoices, selected: mood.map { .mood($0) } ?? .any, counted: false) { choice in
                        withAnimation(.easeOut(duration: 0.25)) {
                            if case .mood(let chosen) = choice { mood = chosen } else { mood = nil }
                        }
                    }
                }
                PickedForYouRow(mood: mood) { preview = $0 }
                ForEach(lists, id: \.self) { list in
                    DiscoverRow(list: list, mood: list.mood == nil ? mood : nil, year: isBestOf(list) ? $year : nil) { preview = $0 }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationTitle("Explore")
        .toolbar(removing: .title)
        .filmPreviewSheet($preview)
        .task {
            await model.lists.prepare()
            await model.loadExplorePicks()
        }
        .task(id: lists) {
            await withTaskGroup(of: Void.self) { group in
                for list in lists {
                    group.addTask { await model.loadDiscover(list) }
                }
            }
        }
    }

    private func isBestOf(_ list: DiscoverList) -> Bool {
        if case .bestOf = list { return true }
        return false
    }
}

/// Films people who loved your favourites went on to love, a different dozen each launch, each
/// saying which of your films it follows. Shuffle draws another dozen.
struct PickedForYouRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    /// Only films of this mood: the strongest of everything found, not the day's dozen.
    var mood: Mood? = nil
    let onPreview: (PreviewFilm) -> Void

    var body: some View {
        let picks = model.explorePicks.map { all in mood.map { model.explorePicks(in: $0) } ?? all }
        if picks?.isEmpty != true || (mood != nil && model.explorePicks?.isEmpty == false), model.hasToken {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Picked for You").font(.system(size: 19, weight: .semibold))
                        Text(mood.map { "From the films you loved, the \($0.title.lowercased()) ones" }
                             ?? "From the films you loved, new each time you open Reel")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if mood == nil, picks != nil, model.canShuffleExplorePicks {
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) { model.shuffleExplorePicks() }
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.brand)
                        }
                        .buttonStyle(.plain)
                        .help("Another dozen")
                    }
                }
                if let picks, picks.isEmpty, let mood {
                    Text("None of the films found from the ones you loved are \(mood.title.lowercased()). The rows below have more.")
                        .foregroundStyle(.secondary)
                        .frame(height: 60, alignment: .leading)
                } else if let picks {
                    if isSnapshot {
                        HStack(alignment: .top, spacing: 18) { cards(picks) }.snapshotRow()
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) { cards(picks) }
                                .padding(.vertical, 6)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        if model.explorePicksLoading || !model.explorePicksTried {
                            ProgressView().controlSize(.small)
                            Text("Finding films for you…").foregroundStyle(.secondary)
                        } else {
                            Text("Couldn't find picks. Check the internet connection.").foregroundStyle(.secondary)
                            Button("Try Again") { Task { await model.loadExplorePicks() } }
                                .buttonStyle(SecondaryCapsuleStyle())
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    private func cards(_ picks: [ExplorePick]) -> some View {
        ForEach(picks) { pick in
            DiscoverCard(film: pick.film, width: 146, reason: pick.reason, onPreview: onPreview)
        }
    }
}

/// One Explore list as a horizontal row with "See All".
struct DiscoverRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    let list: DiscoverList
    /// Only the films of this mood (by their genres); a row left empty by it isn't shown.
    var mood: Mood? = nil
    var year: Binding<Int>?
    let onPreview: (PreviewFilm) -> Void

    var body: some View {
        let all = model.discover[list] ?? []
        let films = mood.map { mood in all.filter { MoodGenres.of(mood).fits($0.genreNames) } } ?? all
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
                if let year { YearMenu(year: year) }
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
    @State private var preview: PreviewFilm?

    init(list: DiscoverList, mood: Mood? = nil) {
        self.mood = mood
        _list = State(initialValue: list)
        if case .bestOf(let y) = list {
            _year = State(initialValue: y)
        } else {
            _year = State(initialValue: Calendar.current.component(.year, from: Date()) - 1)
        }
    }

    var body: some View {
        let all = model.discover[list] ?? []
        let films = mood.map { mood in all.filter { MoodGenres.of(mood).fits($0.genreNames) } } ?? all
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(mood.map { "\(list.title) · \($0.title)" } ?? list.title).font(.system(size: 30, weight: .bold))
                    if case .bestOf = list { YearMenu(year: $year) }
                    Spacer()
                }
                Text(list.subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
                if films.isEmpty && model.discoverLoading.contains(list) {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
                LazyVGrid(columns: LibraryGridView.columns, alignment: .leading, spacing: 30) {
                    ForEach(Array(films.enumerated()), id: \.element.id) { index, movie in
                        DiscoverCard(film: PreviewFilm(movie), rank: isRanked ? index + 1 : nil) { preview = $0 }
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
        .onChange(of: year) {
            if case .bestOf = list { list = .bestOf(year: year) }
        }
    }

    private var isRanked: Bool {
        if case .bestOf = list { return true }
        return false
    }
}

struct YearMenu: View {
    @Binding var year: Int
    private let years = Array((1920...Calendar.current.component(.year, from: Date())).reversed())

    var body: some View {
        Menu {
            Picker("Year", selection: $year) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
        } label: {
            FilterPill(icon: "calendar", text: String(year), active: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
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
        .toolbar(removing: .title)
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
                    Label(videos.first?.type == "Teaser" ? "Teaser" : "Trailer", systemImage: "play.rectangle")
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

    /// The film's official trailers that haven't failed to play here this session.
    private var trailerVideos: [TMDBVideo] {
        guard let details, !model.unplayableTrailers.contains(film.id) else { return [] }
        return Trailers.candidates(details.videos?.results ?? [], preferTeaser: model.spoilerSafe,
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
