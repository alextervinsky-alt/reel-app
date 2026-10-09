#if os(macOS)
import SwiftUI
import ReelCore

/// A film in Cinema mode: what you need to decide, readable from the sofa, and big buttons to
/// play it, watch the trailer, or keep it for tonight. Spoiler-safe like the desk page (the
/// overview is TMDB's premise; nothing from the story is shown).
struct CinemaFilmPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    let filmID: String
    /// False while a trailer plays over it (its keys then belong to the trailer).
    let active: Bool
    let open: (String) -> Void

    var body: some View {
        if let film = model.film(id: filmID) {
            GeometryReader { geometry in
                // The decision fits one screen; the rows below peek in at the bottom.
                let heroHeight = max(560, geometry.size.height - 200)
                Group {
                    if isSnapshot {
                        content(film, heroHeight: heroHeight).snapshotPage()
                    } else {
                        ScrollView { content(film, heroHeight: heroHeight) }
                            .scrollIndicators(.hidden)
                    }
                }
            }
            // What viewers of this film went on to like (More Like This).
            .onAppear {
                model.warmPlayer()
                TrailerEngine.shared.warm()
            }
            .task(id: film.tmdb?.id) { await model.loadSimilar(for: film) }
            .onReelKey { key in
                guard active else { return false }
                switch key {
                case .enter:
                    guard model.onlineCopy(of: film) != nil else { return false }
                    model.play(film)
                case .space:
                    guard model.offersTrailer(for: film) else { return false }
                    model.showTrailer(for: film)
                case .tonight:
                    model.toggleTonight(film.personalKey)
                default:
                    return false
                }
                return true
            }
        } else {
            Text("This film is no longer in the library.")
                .font(.system(size: Cinema.body))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(_ film: FilmEntry, heroHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 44) {
            hero(film, height: heroHeight)
            CinemaReviews(film: film)
            CinemaFilmRows(film: film, open: open)
        }
        .padding(.bottom, 80)
    }

    /// Title → year · running time · genres → ratings, two list badges and why it's offered →
    /// verdict → premise (three lines at most) → when it would end, subtitles, quality → Play,
    /// Trailer, Tonight, Watched.
    private func hero(_ film: FilmEntry, height: CGFloat) -> some View {
        let record = model.record(for: film)
        let versions = model.versions(of: film)
        let badges = model.badges(for: film)
        let reason = model.pickReason(forKey: film.personalKey)
        return ZStack(alignment: .bottomLeading) {
            Color.black
                .frame(height: height)
                .overlay { FocusedBackdrop(path: film.tmdb?.backdropPath) }
                .clipped()
                .overlay {
                    LinearGradient(colors: [Color.black.opacity(0.85), Color.black.opacity(0)], startPoint: .leading, endPoint: .trailing)
                }
                .overlay {
                    LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: Theme.background, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }

            VStack(alignment: .leading, spacing: 16) {
                TitleArt(film: film, maxWidth: 760, maxHeight: 160, fontSize: 64)
                HStack(spacing: 18) {
                    Text(Format.metaLine(film))
                        .font(.system(size: Cinema.body))
                        .foregroundStyle(Theme.secondaryText)
                    // HDR or SDR, to set the TV before pressing Play.
                    PictureRangeTag(copies: model.copies(of: film), large: true)
                }
                HStack(spacing: 16) {
                    RatingStrip(film: film).environment(\.ratingScale, 1.6)
                    ForEach(badges.prefix(2)) { badge in
                        Label(badge.text, systemImage: badge.symbol)
                            .font(.system(size: Cinema.body, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(Capsule().fill(Color.black.opacity(0.4)))
                    }
                    if let reason {
                        Text(reason.long)
                            .font(.system(size: Cinema.body))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                if let verdict = ReceptionVerdict.sentence(ratings: film.ratings, tmdbVote: film.tmdb?.voteAverage,
                                                           reception: film.reception, cinemaScore: film.funFacts?.cinemaScore) {
                    Text(verdict)
                        .font(.system(size: Cinema.body, weight: .medium))
                        .foregroundStyle(Theme.brand)
                        .lineLimit(2)
                        .frame(maxWidth: 980, alignment: .leading)
                }
                if let overview = film.tmdb?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: Cinema.body))
                        .lineSpacing(5)
                        .lineLimit(3)
                        .foregroundStyle(Color.white.opacity(0.88))
                        .frame(maxWidth: 980, alignment: .leading)
                }
                if let ends = Format.endsLine(film, runtime: film.tmdb?.runtime) {
                    Text(ends)
                        .font(.system(size: Cinema.body))
                        .foregroundStyle(.secondary)
                }
                buttons(film, record: record, versions: versions)
                    .padding(.top, 4)
            }
            .padding(.horizontal, Cinema.gutter)
            .padding(.bottom, 10)
        }
    }

    private func buttons(_ film: FilmEntry, record: PersonalRecord, versions: [FilmEntry]) -> some View {
        HStack(spacing: 14) {
            if versions.count > 1 {
                // One big button per version: menus are too small to hit from the sofa.
                ForEach(versions) { copy in
                    Button {
                        model.play(film, version: copy)
                    } label: {
                        // Long file names are cut in the middle, so every button stays on screen.
                        Label("Play \(model.versionTitle(copy))", systemImage: "play.fill")
                            .truncationMode(.middle)
                            .frame(maxWidth: 300)
                    }
                    .buttonStyle(CinemaButtonStyle(primary: copy.id == versions.first?.id))
                }
            } else if !versions.isEmpty {
                Button {
                    model.play(film)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(CinemaButtonStyle(primary: true))
            } else {
                Label("Connect the drive to play", systemImage: "externaldrive")
                    .font(.system(size: Cinema.body))
                    .foregroundStyle(.secondary)
            }
            if model.offersTrailer(for: film) {
                Button {
                    model.showTrailer(for: film)
                } label: {
                    Label(model.trailerLabel(for: film), systemImage: "play.rectangle")
                }
                .buttonStyle(CinemaButtonStyle())
            }
            Button {
                model.toggleTonight(film.personalKey)
            } label: {
                Label(model.isTonight(film.personalKey) ? "On Tonight" : "Tonight",
                      systemImage: model.isTonight(film.personalKey) ? "moon.fill" : "moon")
            }
            .buttonStyle(CinemaButtonStyle())
            Button {
                model.toggle(\.watched, for: film)
            } label: {
                Label(record.watched ? "Watched" : "Mark Watched",
                      systemImage: record.watched ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(CinemaButtonStyle())
        }
    }
}

/// Reviews, read from the sofa: the critics' consensus, then what people like and don't like,
/// each with someone's words. Spoiler-safe like the desk's Reviews tab.
private struct CinemaReviews: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry

    var body: some View {
        let hiding = model.hidesSpoilers(for: film)
        let consensus = film.funFacts?.consensus.flatMap { hiding && Spoilers.mentionsPlot($0) ? nil : $0 }
        let reception = film.reception?.withoutRepeats
        let liked = reception?.liked ?? []
        let disliked = reception?.disliked ?? []
        if consensus != nil || !liked.isEmpty || !disliked.isEmpty {
            VStack(alignment: .leading, spacing: 22) {
                Text("Reviews")
                    .font(.system(size: Cinema.rowTitle, weight: .bold))
                if let consensus {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CRITICS' CONSENSUS")
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.brand)
                        Text("“\(consensus)”")
                            .font(.system(size: Cinema.body + 2, design: .serif))
                            .italic()
                            .lineSpacing(5)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .frame(maxWidth: 1300, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !liked.isEmpty || !disliked.isEmpty {
                    HStack(alignment: .top, spacing: 24) {
                        column("What people like", symbol: "hand.thumbsup.fill", tint: .green, points: liked, hiding: hiding)
                        column("What people don't like", symbol: "hand.thumbsdown.fill", tint: .orange, points: disliked, hiding: hiding)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let awards = film.ratings?.awards {
                    Label(awards, systemImage: "trophy")
                        .font(.system(size: Cinema.body))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, Cinema.gutter)
        }
    }

    private func column(_ title: String, symbol: String, tint: Color, points: [ReceptionPoint], hiding: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(title, systemImage: symbol)
                .font(.system(size: Cinema.body, weight: .semibold))
                .foregroundStyle(tint)
            if points.isEmpty {
                Text("Nothing stands out.").font(.system(size: Cinema.body)).foregroundStyle(.secondary)
            }
            ForEach(points.prefix(3), id: \.aspect) { point in
                VStack(alignment: .leading, spacing: 6) {
                    Text(point.aspect).font(.system(size: Cinema.body, weight: .semibold))
                    if let quote = point.quote, !(hiding && Spoilers.mentionsPlot(quote)) {
                        Text("“\(quote)”")
                            .font(.system(size: Cinema.body - 2))
                            .italic()
                            .lineSpacing(4)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.panel))
    }
}

/// The rows under a film: From the Same People (each poster says how it's connected), then More
/// Like This without those films (kept by `AppModel.relatedFilms` until the library changes).
private struct CinemaFilmRows: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let open: (String) -> Void

    var body: some View {
        let related = model.relatedFilms(to: film, limit: 24)
        let people = related.people
        let similar = related.similar
        VStack(alignment: .leading, spacing: 40) {
            if !people.isEmpty {
                CinemaHoverRow(title: "From the Same People", items: people.map { $0.item },
                               captions: related.captions, open: open)
            }
            if !similar.isEmpty {
                CinemaHoverRow(title: "More Like This", items: similar, open: open)
            }
        }
    }
}
#endif
