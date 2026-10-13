#if os(macOS)
import SwiftUI
import ReelCore

/// A film in Cinema mode: what you need to decide, readable from the sofa, and big buttons to
/// play it, watch the trailer, or keep it for tonight. Spoiler-safe like the desk page (the
/// overview is TMDB's premise; nothing from the story is shown).
struct CinemaFilmPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(CinemaBar.self) private var bar
    let filmID: String
    /// False while a trailer plays over it (its keys then belong to the trailer).
    let active: Bool
    let open: (String) -> Void
    /// Where the arrow keys are: a button (row 0), or a poster in a row below (rows 1…).
    @State private var focus: (row: Int, index: Int)?

    var body: some View {
        if let film = model.film(id: filmID) {
            let rows = rowItems(film)
            GeometryReader { geometry in
                // The decision fits one screen; the rows below peek in at the bottom.
                let heroHeight = max(560, geometry.size.height - 200)
                Group {
                    if isSnapshot {
                        content(film, heroHeight: heroHeight).snapshotPage()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView { content(film, heroHeight: heroHeight) }
                                .scrollIndicators(.hidden)
                                .onChange(of: focus?.row) { _, row in
                                    guard let row else { return }
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        if row == 0 { proxy.scrollTo(Self.top, anchor: .top) } else { proxy.scrollTo("row\(row)", anchor: .center) }
                                    }
                                }
                        }
                    }
                }
            }
            // What viewers of this film went on to like (More Like This), and its facts and
            // article for Did You Know?.
            .onAppear {
                model.warmPlayer()
                TrailerEngine.shared.warm()
            }
            .task(id: film.tmdb?.id) {
                await model.loadSimilar(for: film)
                await model.loadFunFacts(for: film)
                await model.loadArticle(for: film)
            }
            .onReelKey { key in active && handle(key, film: film, rows: rows) }
            .onChange(of: bar.returned) { _, back in
                guard back?.page == "film:" + filmID else { return }
                focus = (0, 0)
            }
        } else {
            Text("This film is no longer in the library.")
                .font(.system(size: Cinema.body))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static let top = "cinema-film-top"

    private func content(_ film: FilmEntry, heroHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 44) {
            hero(film, height: heroHeight).id(Self.top)
            CinemaReviews(film: film)
            CinemaDidYouKnow(film: film)
            CinemaFilmRows(film: film, keyFocus: focus.flatMap { $0.row > 0 ? ($0.row - 1, $0.index) : nil }, open: open)
        }
        .padding(.bottom, 80)
    }

    /// The posters in the rows under the film, as the keys move through them.
    private func rowItems(_ film: FilmEntry) -> [[LibraryItem]] {
        let related = model.relatedFilms(to: film, limit: 24)
        return [related.people.map { $0.item }, related.similar].filter { !$0.isEmpty }
    }

    /// The buttons and the rows: left and right along them, up and down between them (Up from
    /// the buttons goes to the top bar). Return presses the button or opens the poster; with
    /// nothing highlighted Return plays, Space shows the trailer and T keeps it for tonight.
    private func handle(_ key: ReelKey, film: FilmEntry, rows: [[LibraryItem]]) -> Bool {
        let actions = buttonActions(film)
        // The rows changed under the highlight (More Like This arrived, a film left): start at the buttons.
        if let place = focus, place.row > rows.count || (place.row > 0 && !rows[place.row - 1].indices.contains(place.index)) {
            focus = (0, 0)
        }
        guard let place = focus else {
            switch key {
            case .left, .right, .down:
                focus = (0, 0)
            case .up:
                bar.takeKeys()
            case .enter:
                guard model.onlineCopy(of: film) != nil else { return false }
                model.play(film)
            case .space:
                guard model.offersTrailer(for: film) else { return false }
                model.showTrailer(for: film)
            case .tonight:
                model.toggleTonight(film.personalKey)
            case .escape, .fullScreen:
                return false
            }
            return true
        }
        let count = place.row == 0 ? actions.count : rows[place.row - 1].count
        switch key {
        case .left: focus = (place.row, max(place.index - 1, 0))
        case .right: focus = (place.row, min(place.index + 1, max(count - 1, 0)))
        case .up where place.row == 0:
            focus = nil
            bar.takeKeys()
        case .up: focus = (place.row - 1, place.row - 1 == 0 ? 0 : min(place.index, rows[place.row - 2].count - 1))
        case .down where place.row < rows.count: focus = (place.row + 1, min(place.index, rows[place.row].count - 1))
        case .down: break
        case .enter where place.row == 0, .space where place.row == 0:
            guard actions.indices.contains(place.index) else { return false }
            actions[place.index].action()
        case .tonight where place.row == 0:
            model.toggleTonight(film.personalKey)
        case .enter, .space, .tonight:
            let row = rows[place.row - 1]
            guard row.indices.contains(place.index) else { return false }
            return CinemaActions.perform(key, on: row[place.index], model: model, open: open)
        case .escape:
            focus = nil
            return false
        case .fullScreen: return false
        }
        return true
    }

    /// Title → year · running time · genres → ratings, two list badges and why it's offered →
    /// verdict → premise (three lines at most) → when it would end, subtitles, quality → Play,
    /// Trailer, Tonight, Watched.
    private func hero(_ film: FilmEntry, height: CGFloat) -> some View {
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
                buttons(film, versions: versions)
                    .padding(.top, 4)
            }
            .padding(.horizontal, Cinema.gutter)
            .padding(.bottom, 10)
        }
    }

    /// One of the big buttons under the film.
    private struct PageButton {
        let title: String
        let symbol: String
        var primary = false
        let action: () -> Void
    }

    /// Play (one per version: menus are too small to hit from the sofa), Trailer, Tonight, Watched.
    private func buttonActions(_ film: FilmEntry) -> [PageButton] {
        let versions = model.versions(of: film)
        var list: [PageButton] = []
        if versions.count > 1 {
            for copy in versions {
                list.append(PageButton(title: "Play \(model.versionTitle(copy))", symbol: "play.fill",
                                       primary: copy.id == versions.first?.id) { model.play(film, version: copy) })
            }
        } else if !versions.isEmpty {
            list.append(PageButton(title: "Play", symbol: "play.fill", primary: true) { model.play(film) })
        }
        if model.offersTrailer(for: film) {
            list.append(PageButton(title: model.trailerLabel(for: film), symbol: "play.rectangle") { model.showTrailer(for: film) })
        }
        let tonight = model.isTonight(film.personalKey)
        list.append(PageButton(title: tonight ? "On Tonight" : "Tonight", symbol: tonight ? "moon.fill" : "moon") {
            model.toggleTonight(film.personalKey)
        })
        let watched = model.record(for: film).watched
        list.append(PageButton(title: watched ? "Watched" : "Mark Watched",
                               symbol: watched ? "checkmark.circle.fill" : "checkmark.circle") {
            model.toggle(\.watched, for: film)
        })
        return list
    }

    private func buttons(_ film: FilmEntry, versions: [FilmEntry]) -> some View {
        HStack(spacing: 14) {
            if versions.isEmpty {
                Label("Connect the drive to play", systemImage: "externaldrive")
                    .font(.system(size: Cinema.body))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(buttonActions(film).enumerated()), id: \.offset) { index, button in
                Button(action: button.action) {
                    // Long file names are cut in the middle, so every button stays on screen.
                    Label(button.title, systemImage: button.symbol)
                        .truncationMode(.middle)
                        .frame(maxWidth: versions.count > 1 && button.symbol == "play.fill" ? 300 : nil)
                }
                .buttonStyle(CinemaButtonStyle(primary: button.primary, focused: focus.map { $0.row == 0 && $0.index == index } ?? false))
            }
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
    /// The poster the arrow keys are on: which row (of those shown) and where in it.
    let keyFocus: (row: Int, index: Int)?
    let open: (String) -> Void
    /// The poster under the pointer, by row and film.
    @State private var hovered: (row: Int, id: String)?

    var body: some View {
        let related = model.relatedFilms(to: film, limit: 24)
        let rows: [(title: String, items: [LibraryItem], captions: [String: String])] = [
            ("From the Same People", related.people.map { $0.item }, related.captions),
            ("More Like This", related.similar, [:]),
        ].filter { !$0.items.isEmpty }
        VStack(alignment: .leading, spacing: 40) {
            ForEach(Array(rows.enumerated()), id: \.offset) { number, row in
                let pointed = hovered.flatMap { $0.row == number ? row.items.firstIndex(where: { item in item.id == $0.id }) : nil }
                CinemaRowView(title: row.title, items: row.items,
                              selected: keyFocus.flatMap { $0.row == number ? $0.index : nil } ?? pointed,
                              followSelection: keyFocus?.row == number, captions: row.captions,
                              hover: { index, inside in
                                  guard row.items.indices.contains(index) else { return }
                                  if inside {
                                      hovered = (number, row.items[index].id)
                                  } else if hovered?.row == number, hovered?.id == row.items[index].id {
                                      hovered = nil
                                  }
                              },
                              open: { open($0.main.id) })
                    .id("row\(number + 1)")
            }
        }
    }
}

/// Did You Know? on the TV: three short things worth knowing about the making of the film, large,
/// under the reviews. Spoiler-safe like Behind the Film (until watched, nothing that tells of the
/// story, nor anything from the article's story sections).
private struct CinemaDidYouKnow: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry

    var body: some View {
        let facts = Self.facts(film: film, article: film.tmdb.flatMap { model.articles[$0.id] },
                               articleKnown: film.tmdb.map { model.articles[$0.id] != nil || model.articlesMissing.contains($0.id) } ?? false,
                               hiding: model.hidesSpoilers(for: film))
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 22) {
                Label("Did You Know?", systemImage: "sparkles")
                    .font(.system(size: Cinema.rowTitle, weight: .bold))
                HStack(alignment: .top, spacing: 24) {
                    ForEach(facts, id: \.text) { fact in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(fact.category.uppercased())
                                .font(.system(size: 17, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(Theme.brand)
                            Text(fact.text)
                                .font(.system(size: Cinema.body + 2, weight: .medium))
                                .lineSpacing(6)
                                .foregroundStyle(Color.white.opacity(0.94))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.panel))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Cinema.gutter)
        }
    }

    /// The three most worth knowing that are short enough to read from the sofa. While spoilers
    /// are hidden they wait for the article (its story sections are left out).
    static func facts(film: FilmEntry, article: FilmArticle?, articleKnown: Bool, hiding: Bool) -> [FunFact] {
        guard var facts = film.funFacts.map({ BehindTheFilmTab.withoutStory($0, hiding: hiding) }) else { return [] }
        if hiding {
            guard articleKnown else { return [] }
            if let article { facts.facts = Digest.leftover(facts.facts, sections: article.after) }
        }
        return Array(BehindTheFilmTab.didYouKnow(facts).filter { $0.text.count <= 200 }.prefix(3))
    }
}
#endif
