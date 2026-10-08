#if os(macOS)
import SwiftUI
import ReelCore

/// For You: fifteen films you don't have and haven't seen, which people who loved your
/// favourites went on to love, each saying which of your films it follows (see `ExplorePicks`).
/// Fifteen others each time Reel opens; New Picks draws again. Like Recommended, but for films
/// to find rather than films on your drives.
struct ForYouView: View {
    @Environment(AppModel.self) private var model
    @State private var preview: PreviewFilm?
    @State private var mood: Mood?

    private static let moodChoices = [MoodChoiceCount(choice: .any, count: 0)]
        + Mood.allCases.map { MoodChoiceCount(choice: .mood($0), count: 0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("For You").font(.system(size: 30, weight: .bold))
                        Text("Fifteen films you don't have yet, picked from the ones you loved. Fifteen others each time Reel opens.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if mood == nil, model.explorePicks?.isEmpty == false, model.canShuffleExplorePicks {
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) { model.shuffleExplorePicks() }
                        } label: {
                            Label("New Picks", systemImage: "shuffle")
                        }
                        .buttonStyle(SecondaryCapsuleStyle())
                        .help("Fifteen other films")
                    }
                }
                MoodChips(choices: Self.moodChoices, selected: mood.map { .mood($0) } ?? .any, counted: false) { choice in
                    withAnimation(.easeOut(duration: 0.25)) {
                        if case .mood(let chosen) = choice { mood = chosen } else { mood = nil }
                    }
                }
                content
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
            .frame(maxWidth: 1240, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("For You")
        .toolbar(removing: .title)
        .filmPreviewSheet($preview)
        .task {
            await model.lists.prepare()
            await model.loadExplorePicks()
        }
    }

    @ViewBuilder
    private var content: some View {
        let picks = model.explorePicks.map { all in mood.map { model.explorePicks(in: $0) } ?? all }
        if !model.hasToken {
            ContentUnavailableView("Connect TMDB to find films for you", systemImage: "sparkles",
                                   description: Text("Add your TMDB token in Settings (⌘,)."))
                .frame(maxWidth: .infinity, minHeight: 320)
        } else if let picks, picks.isEmpty, let mood {
            Text("None of the films found from the ones you loved are \(mood.title.lowercased()). Explore's \(mood.title) row has more.")
                .foregroundStyle(.secondary)
                .frame(minHeight: 120, alignment: .leading)
        } else if let picks {
            ForYouGrid(picks: picks) { preview = $0 }
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
            .frame(minHeight: 200)
        }
    }
}

/// The picks, two or three to a row.
struct ForYouGrid: View {
    let picks: [ExplorePick]
    let onPreview: (PreviewFilm) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 460), spacing: 22, alignment: .top)],
                  alignment: .leading, spacing: 26) {
            ForEach(Array(picks.enumerated()), id: \.element.id) { index, pick in
                ForYouCard(number: index + 1, pick: pick, onPreview: onPreview)
            }
        }
    }
}

/// One pick: its frame, why it's here, what it is, how it's rated and what it's about, with the
/// trailer, the wishlist and "Seen it?" at hand.
struct ForYouCard: View {
    @Environment(AppModel.self) private var model
    let number: Int
    let pick: ExplorePick
    let onPreview: (PreviewFilm) -> Void
    @State private var details: TMDBMovieDetails?
    @State private var ratings: ExternalRatings?
    @State private var hovering = false

    var body: some View {
        let film = pick.film
        let cached = model.previewCache[film.id]
        let details = self.details ?? cached.flatMap { $0.details }
        let ratings = self.ratings ?? cached.flatMap { $0.ratings }
        VStack(alignment: .leading, spacing: 10) {
            Button { onPreview(film) } label: {
                FocusedBackdrop(path: film.backdropPath ?? details?.backdropPath)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        Text("\(number)")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .shadow(color: Color.black.opacity(0.6), radius: 8)
                            .padding(.horizontal, 12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
                    .scaleEffect(hovering ? 1.015 : 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: hovering)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            Text(pick.reason.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(Theme.brand)
                .lineLimit(2)
            Text(film.title)
                .font(.system(size: 19, weight: .bold))
                .lineLimit(2)
            Text(metaLine(details))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            RatingStrip(ratings: ratings, tmdbVote: film.voteAverage ?? details?.voteAverage)
                .font(.system(size: 12))
            if let overview = film.overview ?? details?.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                let videos = trailerVideos(details)
                Button {
                    model.trailer = TrailerRequest(videos: videos.map(\.key), title: film.title, filmID: nil, tmdbID: film.id,
                                                   backdropPath: film.backdropPath ?? details?.backdropPath,
                                                   origin: nil, offersFilmPage: false)
                } label: {
                    Label(videos.first.map { Trailers.isTeaser($0) } == true ? "Teaser" : "Trailer", systemImage: "play.rectangle")
                }
                .buttonStyle(PrimaryCapsuleStyle())
                .disabled(videos.isEmpty)
                .opacity(videos.isEmpty ? 0.45 : 1)
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
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))
        .task(id: film.id) {
            let info = await model.previewInfo(for: film.id)
            self.details = info.details
            self.ratings = info.ratings
        }
    }

    /// "2019 · 2h 12m · Drama, Thriller"
    private func metaLine(_ details: TMDBMovieDetails?) -> String {
        var parts: [String] = []
        if let year = pick.film.year { parts.append(String(year)) }
        if let runtime = details?.runtime, runtime > 0 { parts.append(Format.runtime(runtime)) }
        let genres = pick.film.genres.isEmpty ? (details?.genreNames ?? []) : pick.film.genres
        if !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// The film's trailers (see `Trailers`), unless they all failed to play here this session.
    private func trailerVideos(_ details: TMDBMovieDetails?) -> [TMDBVideo] {
        guard let details, !model.unplayableTrailers.contains(pick.film.id) else { return [] }
        return Trailers.candidates(details.videos?.results ?? [], title: details.title, preferTeaser: model.spoilerSafe,
                                   originalLanguage: details.originalLanguage)
    }
}
#endif
