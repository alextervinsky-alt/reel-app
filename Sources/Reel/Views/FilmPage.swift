#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

struct StillSelection: Identifiable {
    let id = UUID()
    let paths: [String]
    let index: Int
}

struct FilmPage: View {
    @Environment(AppModel.self) private var model
    let filmID: String
    @State private var tab: FilmTab = .overview
    @State private var fixing = false
    @State private var showingFile = false
    @State private var still: StillSelection?
    @State private var preview: PreviewFilm?
    /// The toolbar gets its background back once the page scrolls past the backdrop.
    @State private var pastHero = false

    var body: some View {
        if let film = model.film(id: filmID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FilmHero(film: film, onFix: { fixing = true }, onFile: { showingFile = true })
                    VStack(alignment: .leading, spacing: 0) {
                        TabStrip(selection: Binding(get: { shownTab(for: film) }, set: { tab = $0 }), tabs: tabs(for: film))
                        Divider().overlay(Theme.hairline)
                        Group {
                            switch shownTab(for: film) {
                            case .overview: OverviewTab(film: film) { preview = $0 }
                            case .reviews: ReceptionTab(film: film)
                            case .behindTheFilm:
                                BehindTheFilmTab(film: film) { paths, index in
                                    still = StillSelection(paths: paths, index: index)
                                }
                            case .camera: CameraTab(film: film)
                            case .extras: ExtrasTab(film: film)
                            }
                        }
                        .padding(.top, 26)
                        .padding(.bottom, 48)
                    }
                    .padding(.horizontal, 40)
                    .frame(maxWidth: 1180, alignment: .leading)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 520
            } action: { _, isPast in
                pastHero = isPast
            }
            .background(Theme.background)
            .ignoresSafeArea(.container, edges: .top)
            .toolbarBackgroundVisibility(pastHero ? .visible : .hidden, for: .windowToolbar)
            .navigationTitle("")
            .sheet(isPresented: $fixing) { MatchFixer(film: film) }
            .sheet(isPresented: $showingFile) { FileInfoSheet(film: film) }
            .sheet(item: $still) { selection in
                StillViewer(paths: selection.paths, index: selection.index)
            }
            .filmPreviewSheet($preview)
            .onChange(of: filmID) { tab = .overview }
            // The Lists hub's saved data, for the badges under the title (read once per launch).
            .task { await model.lists.prepare() }
            .onAppear {
                model.warmPlayer()
                TrailerEngine.shared.warm()
            }
        } else {
            ContentUnavailableView("Film not found", systemImage: "film",
                                   description: Text("It may have been removed by a rescan."))
        }
    }

    /// Falls back to Overview when the chosen tab no longer applies (e.g. no extras after a rescan).
    private func shownTab(for film: FilmEntry) -> FilmTab {
        tabs(for: film).contains(tab) ? tab : .overview
    }

    private func tabs(for film: FilmEntry) -> [FilmTab] {
        FilmTab.allCases.filter { tab in
            switch tab {
            case .overview: true
            case .reviews, .behindTheFilm, .camera: film.tmdb != nil
            case .extras: model.extrasSource(for: film) != nil
            }
        }
    }
}

// MARK: - Hero

/// What you need to decide, in the same order as everywhere in Reel: title, year · running time
/// · genres, ratings (with up to two list badges), the verdict, why it's offered, when it would
/// end. Then Play, Trailer and Tonight; your own marks after them.
struct FilmHero: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let onFix: () -> Void
    let onFile: () -> Void

    var body: some View {
        let record = model.record(for: film)
        let canPlay = model.onlineCopy(of: film) != nil
        let versions = model.versions(of: film)
        let badges = model.badges(for: film)
        let verdict = ReceptionVerdict.sentence(ratings: film.ratings, tmdbVote: film.tmdb?.voteAverage,
                                                reception: film.reception, cinemaScore: film.funFacts?.cinemaScore)
        ZStack(alignment: .bottomLeading) {
            Color.black
                .frame(maxWidth: .infinity)
                .frame(height: 600)
                .overlay { FocusedBackdrop(path: film.tmdb?.backdropPath) }
                .clipped()
                .overlay {
                    LinearGradient(colors: [Color.black.opacity(0.8), Color.black.opacity(0)], startPoint: .leading, endPoint: .center)
                }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.35), location: 0),
                            .init(color: .clear, location: 0.22),
                            .init(color: .clear, location: 0.45),
                            .init(color: Theme.background, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }

            VStack(alignment: .leading, spacing: 11) {
                TitleArt(film: film)
                Text(Format.metaLine(film))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                HStack(spacing: 16) {
                    RatingStrip(film: film)
                    if !badges.isEmpty { BadgeRow(badges: badges) }
                }
                .font(.system(size: 13.5))
                if let verdict {
                    Text(verdict)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.brand)
                        .frame(maxWidth: 760, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let reason = model.pickReason(forKey: film.personalKey) {
                    Text(reason.long)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryText)
                }
                if let ends = Format.endsLine(film, runtime: film.tmdb?.runtime) {
                    Label(ends, systemImage: "clock")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                if film.matchState.needsCheck { matchBanner }

                HStack(spacing: 10) {
                    if versions.count > 1 {
                        // Two versions of the film: choose which one.
                        Menu {
                            ForEach(versions) { copy in
                                Button("Play \(model.versionTitle(copy))") { model.play(film, version: copy) }
                            }
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .menuStyle(.button)
                        .buttonStyle(PrimaryCapsuleStyle())
                        .menuIndicator(.visible)
                        .fixedSize()
                        .help("This film is here in \(versions.count) versions")
                    } else if canPlay {
                        Button {
                            model.play(film)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryCapsuleStyle())
                        .help(model.player == .system ? "Opens the film in your default player" : "Opens the film in \(model.player.title)")
                    }
                    if model.offersTrailer(for: film) {
                        Button {
                            model.showTrailer(for: film)
                        } label: {
                            Label(model.trailerLabel(for: film), systemImage: "play.rectangle")
                        }
                        .buttonStyle(SecondaryCapsuleStyle())
                    }
                    RoundToggle(symbol: "moon", onSymbol: "moon.fill", isOn: model.isTonight(film.personalKey),
                                help: model.isTonight(film.personalKey) ? "On tonight's shortlist" : "Add to Tonight") {
                        model.toggleTonight(film.personalKey)
                    }
                    // Your own marks, a little apart from the decision.
                    HStack(spacing: 8) {
                        WatchedControl(film: film, record: record)
                        RoundToggle(symbol: "heart", onSymbol: "heart.fill", isOn: record.favorite, help: "Favorite") {
                            model.toggle(\.favorite, for: film)
                        }
                        RoundToggle(symbol: "bookmark", onSymbol: "bookmark.fill", isOn: record.watchlist, help: "Watchlist") {
                            model.toggle(\.watchlist, for: film)
                        }
                        StarRating(rating: record.rating) { model.setRating($0, for: film) }
                            .padding(.horizontal, 6)
                        moreMenu
                    }
                    .padding(.leading, 14)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 26)
        }
        .frame(height: 600)
    }

    private var matchBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle.fill").foregroundStyle(Color.orange)
            Text(film.tmdb == nil ? "Reel couldn't tell which film this is." : "Is this the right film?")
            if film.tmdb != nil {
                Button("Yes") { model.confirm(film) }
            }
            Button(film.tmdb == nil ? "Find Film…" : "Choose Another…", action: onFix)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// Everything about the file and the match, out of the way.
    private var moreMenu: some View {
        let onlineCopy = model.onlineCopy(of: film)
        return Menu {
            PlayWithMenu(film: film)
            Button("Show in Finder") { if let copy = onlineCopy { model.showInFinder(copy) } }
                .disabled(onlineCopy == nil)
            Button("Copy File Path") { model.copyPath(onlineCopy ?? film) }
            Button("File Info…", action: onFile)
            Divider()
            Button("Fix Match…", action: onFix)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .foregroundStyle(Color.white)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}

/// Watched: a tick to mark it; once watched, a menu with the month you watched it (to change)
/// and Mark as Unwatched.
struct WatchedControl: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let record: PersonalRecord
    @State private var editingDate = false

    var body: some View {
        if record.watched {
            Menu {
                Button("Watched \(record.watchedOn.map { $0.formatted(.dateTime.month(.wide).year()) } ?? "") – Change…") {
                    editingDate = true
                }
                Button("Mark as Unwatched") { model.toggle(\.watched, for: film) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white))
                    .foregroundStyle(Color.black)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(record.watchedOn.map { "Watched in \($0.formatted(.dateTime.month(.wide).year()))" } ?? "Watched")
            .popover(isPresented: $editingDate) {
                WatchedDateEditor(title: "Watched in", date: record.watchedOn ?? Date(),
                                  save: { model.setWatchedDate($0, for: film) }, done: { editingDate = false })
            }
        } else {
            RoundToggle(symbol: "checkmark", isOn: false, help: "Mark as watched") {
                model.toggle(\.watched, for: film)
            }
        }
    }
}

// MARK: - Tabs

struct TabStrip: View {
    @Binding var selection: FilmTab
    let tabs: [FilmTab]

    var body: some View {
        HStack(spacing: 30) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = tab }
                } label: {
                    VStack(spacing: 9) {
                        Text(tab.title)
                            .font(.system(size: 15, weight: selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? Color.white : Theme.secondaryText)
                        Capsule()
                            .fill(selection == tab ? Color.white : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 6)
    }
}

struct OverviewTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let onPreview: (PreviewFilm) -> Void

    var body: some View {
        let details = film.tmdb
        let collection = model.collectionItems(for: film)
        let related = model.relatedFilms(to: film, excluding: Set(collection.map { $0.id }), limit: 10)
        let people = related.people
        let similar = related.similar
        let moods = model.itemMoods(forKey: film.personalKey)

        VStack(alignment: .leading, spacing: 36) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 56) {
                    story(details, moods: moods).frame(width: 560, alignment: .leading)
                    credits(details).frame(width: 300, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 28) {
                    story(details, moods: moods)
                    credits(details)
                }
            }
            if let details, !details.topCast.isEmpty { cast(details) }
            if !people.isEmpty {
                PosterRow(title: "From the Same People", items: people.map { $0.item }, captions: related.captions)
            }
            if let series = details?.collection {
                let route = FranchiseRoute(id: series.id, name: series.name)
                if collection.isEmpty {
                    NavigationLink(value: route) {
                        Label("Part of the \(series.name). See which films you have.", systemImage: "square.stack")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.brand)
                    }
                    .buttonStyle(.plain)
                } else {
                    PosterRow(title: "More in \(series.name)", items: collection, seeAll: route)
                }
            }
            if !similar.isEmpty {
                // The row shows the closest ten; See All lists every close match.
                PosterRow(title: "More Like This in Your Library", items: similar,
                          seeSimilar: similar.count >= 10 ? SimilarRoute(filmID: film.id) : nil)
            }
            if let id = details?.id, let recommended = model.similar[id], !recommended.isEmpty {
                SimilarRow(films: recommended, onPreview: onPreview)
            }
            NotesEditor(film: film)
        }
        .task(id: details?.id) { await model.loadSimilar(for: film) }
    }

    @ViewBuilder
    private func story(_ details: TMDBMovieDetails?, moods: [Mood]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let tagline = details?.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            if let overview = details?.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !moods.isEmpty {
                HStack(spacing: 8) {
                    ForEach(moods) { Chip(text: $0.title, symbol: $0.symbol) }
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func credits(_ details: TMDBMovieDetails?) -> some View {
        if let d = details {
            let rows: [(String, [TMDBCrewMember])] = [
                ("Director", d.people(forJobs: ["Director"])),
                ("Director of Photography", d.people(forJobs: ["Director of Photography"])),
                ("Writers", Array(d.people(forJobs: TMDBMovieDetails.writerJobs).prefix(3))),
                ("Music", Array(d.people(forJobs: TMDBMovieDetails.composerJobs).prefix(2))),
                ("Editor", Array(d.people(forJobs: ["Editor"]).prefix(2))),
                ("Production Design", Array(d.people(forJobs: ["Production Design"]).prefix(2))),
            ].filter { !$0.1.isEmpty }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(rows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.0.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                        ForEach(row.1, id: \.name) { person in
                            PersonLink(name: person.name, id: person.id)
                        }
                    }
                }
            }
        }
    }

    private func cast(_ details: TMDBMovieDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Theme.sectionTitle("Cast")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(Array(details.topCast.enumerated()), id: \.offset) { _, person in
                        if let id = person.id {
                            NavigationLink(value: PersonRoute(id: id, name: person.name)) {
                                castCard(person)
                            }
                            .buttonStyle(.plain)
                            .help("See all films with \(person.name)")
                        } else {
                            castCard(person)
                        }
                    }
                }
            }
        }
    }

    private func castCard(_ person: TMDBCastMember) -> some View {
        VStack(spacing: 7) {
            Color(white: 0.14)
                .frame(width: 76, height: 76)
                .overlay {
                    CachedImage(path: person.profilePath, kind: .profile) {
                        Image(systemName: "person.fill").font(.title2).foregroundStyle(.tertiary)
                    }
                }
                .clipShape(Circle())
            Text(person.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text(person.character ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 96)
        .contentShape(Rectangle())
    }
}

/// A name that opens the person's page (underlined on hover).
struct PersonLink: View {
    let name: String
    let id: Int?
    @State private var hovering = false

    var body: some View {
        if let id {
            NavigationLink(value: PersonRoute(id: id, name: name)) {
                Text(name)
                    .font(.system(size: 13.5))
                    .underline(hovering, color: Theme.brand)
                    .foregroundStyle(hovering ? Theme.brand : Color.primary)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("See all films by \(name)")
        } else {
            Text(name).font(.system(size: 13.5))
        }
    }
}

struct NotesEditor: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry

    var body: some View {
        let record = model.record(for: film)
        VStack(alignment: .leading, spacing: 10) {
            Theme.sectionTitle("Your Notes")
            TextEditor(text: Binding(
                get: { model.record(for: film).note },
                set: { model.setNote($0, for: film) }
            ))
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 70, maxHeight: 180)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
            .overlay(alignment: .topLeading) {
                if record.note.isEmpty {
                    Text("Thoughts, who recommended it, who to watch it with…")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            if let watchedOn = record.watchedOn, record.watched {
                Text("Watched \(watchedOn.formatted(date: .long, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }
}

struct ReceptionTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry

    var body: some View {
        let verdict = ReceptionVerdict.sentence(ratings: film.ratings, tmdbVote: film.tmdb?.voteAverage,
                                                reception: film.reception, cinemaScore: film.funFacts?.cinemaScore)
        VStack(alignment: .leading, spacing: 30) {
            if let verdict {
                Text(verdict)
                    .font(.system(size: 19, weight: .medium))
                    .lineSpacing(5)
                    .frame(maxWidth: 820, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            scores
            if let consensus = film.funFacts?.consensus, !(model.hidesSpoilers(for: film) && Spoilers.mentionsPlot(consensus)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CRITICS' CONSENSUS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.brand)
                    Text("“\(consensus)”")
                        .font(.system(size: 15))
                        .italic()
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 820, alignment: .leading)
            }
            if let awards = film.ratings?.awards {
                Label(awards, systemImage: "trophy")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
            if let reception = film.reception, !reception.liked.isEmpty || !reception.disliked.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        column("What people like", symbol: "hand.thumbsup.fill", tint: .green, points: reception.liked)
                            .frame(width: 440)
                        column("What people don't like", symbol: "hand.thumbsdown.fill", tint: .orange, points: reception.disliked)
                            .frame(width: 440)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        column("What people like", symbol: "hand.thumbsup.fill", tint: .green, points: reception.liked)
                        column("What people don't like", symbol: "hand.thumbsdown.fill", tint: .orange, points: reception.disliked)
                    }
                }
                Text(sourceLine(reception))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if film.tmdb != nil {
                Text("Not enough written reviews yet to say what people like or dislike.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sourceLine(_ reception: ReceptionSummary) -> String {
        var text = "Based on \(reception.reviewCount) reviews by TMDB users"
        if let critics = reception.criticCount { text += " and \(critics) critics' remarks quoted on Wikipedia" }
        return text + ", read on your Mac."
    }

    @ViewBuilder
    private var scores: some View {
        let r = film.ratings
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if let imdb = r?.imdb {
                    tile(Format.rating(imdb), source: "IMDb", detail: r?.imdbVotes.map { "\(Format.votes($0)) votes" })
                }
                if let rt = r?.rottenTomatoes {
                    tile("\(rt)%", source: "Rotten Tomatoes", detail: "Critics", accent: RatingStrip.tomatoColor(rt))
                }
                if let mc = r?.metacritic {
                    tile("\(mc)", source: "Metacritic", detail: "Critics", accent: RatingStrip.metacriticColor(mc))
                }
                if let grade = film.funFacts?.cinemaScore {
                    tile(grade, source: "CinemaScore", detail: "Opening-night audiences")
                }
                if let vote = film.tmdb?.voteAverage, vote > 0 {
                    tile(Format.rating(vote), source: "TMDB", detail: film.tmdb?.voteCount.map { "\(Format.votes($0)) votes" })
                }
            }
        }
    }

    private func tile(_ value: String, source: String, detail: String?, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(accent ?? Color.white)
            Text(source).font(.system(size: 12.5, weight: .medium))
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(minWidth: 128, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
    }

    private func column(_ title: String, symbol: String, tint: Color, points: [ReceptionPoint]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            if points.isEmpty {
                Text("Nothing stands out.").foregroundStyle(.secondary)
            }
            ForEach(points, id: \.aspect) { point in
                VStack(alignment: .leading, spacing: 5) {
                    Text(point.aspect).font(.system(size: 14, weight: .semibold))
                    if let quote = point.quote, !(model.hidesSpoilers(for: film) && Spoilers.mentionsPlot(quote)) {
                        Text("“\(quote)”")
                            .font(.system(size: 13))
                            .italic()
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
    }
}

/// The file behind the film (from the "…" menu): quality, audio, copies and where they are.
struct FileInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let film: FilmEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("File Info").font(.system(size: 20, weight: .bold))
            FileTab(film: film)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
    }
}

/// Frames from the film. TMDB mixes in posters and behind-the-scenes photos, so each image is
/// checked on the Mac once (no text, no film gear) and only the ones that pass are shown.
struct FilmStills: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let open: ([String], Int) -> Void
    @State private var passed: [String] = []
    @State private var checking = false
    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    var body: some View {
        let stills = film.checkedStills ?? passed
        VStack(alignment: .leading, spacing: 14) {
            if checking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Picking out real frames from the film…").font(.callout).foregroundStyle(.secondary)
                }
            } else if stills.isEmpty {
                Text("No frames from the film found yet.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(stills.enumerated()), id: \.element) { index, path in
                    StillTile(path: path) {
                        open(stills, index)
                    } hide: {
                        hide(path)
                    }
                }
            }
            if !stills.isEmpty {
                Text("Point at a picture that isn't from the film and press the eye button to remove it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: film.tmdb?.id) { await check() }
    }

    private func hide(_ path: String) {
        if let id = film.tmdb?.id { model.hideStill(path, forTMDB: id) }
        withAnimation(.easeOut(duration: 0.2)) { passed.removeAll { $0 == path } }
    }

    private func check() async {
        guard film.checkedStills == nil, let details = film.tmdb, !details.stillPaths.isEmpty else { return }
        checking = true
        defer { checking = false }
        passed = []
        var complete = true
        // The main backdrop is nearly always promotional art.
        for path in details.stillPaths where path != details.backdropPath {
            guard !Task.isCancelled else { return }
            guard let image = await ImageStore.shared.image(path, .still) else {
                complete = false
                continue
            }
            let keep = await Task.detached(priority: .utility) { StillFilter.looksLikeFrame(image.cgImage) }.value
            if keep { passed.append(path) }
        }
        // Only remembered when every image could be checked; otherwise it's tried again next time.
        if complete { model.setCheckedStills(passed, forTMDB: details.id) }
    }
}

/// One still: opens large on click; a button to remove it appears on hover.
private struct StillTile: View {
    let path: String
    let open: () -> Void
    let hide: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            Color(white: 0.1)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    CachedImage(path: path, kind: .still) { Color(white: 0.1) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: hide) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Not a frame from the film: remove it")
            .padding(8)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .contextMenu {
            Button("Not a Frame from the Film", action: hide)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct StillViewer: View {
    let paths: [String]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
            if paths.indices.contains(index) {
                CachedImage(path: paths[index], kind: .backdrop, fit: true) {
                    ProgressView()
                }
            }
            HStack {
                arrow("chevron.left", step: -1)
                Spacer()
                arrow("chevron.right", step: 1)
            }
            .padding(16)
            VStack {
                HStack {
                    Text("\(index + 1) of \(paths.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                Spacer()
            }
            .padding(16)
        }
        .frame(minWidth: 1000, minHeight: 620)
        .preferredColorScheme(.dark)
    }

    private func arrow(_ symbol: String, step: Int) -> some View {
        Button {
            move(step)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(step < 0 ? .leftArrow : .rightArrow, modifiers: [])
        .disabled(paths.count < 2)
    }

    private func move(_ step: Int) {
        guard !paths.isEmpty else { return }
        index = (index + step + paths.count) % paths.count
    }
}

struct FileTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry

    var body: some View {
        let parsed = film.parsed
        VStack(alignment: .leading, spacing: 18) {
            if !parsed.badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(parsed.badges, id: \.self) { Chip(text: $0) }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                if let source = parsed.source { row("Source", source) }
                if let res = parsed.resolution { row("Resolution", res) }
                if let hdr = parsed.hdr { row("HDR", hdr) }
                if let codec = parsed.videoCodec { row("Video", codec) }
                if !parsed.audioTracks.isEmpty {
                    row("Audio", parsed.audioTracks
                        .map { [$0.language, $0.format].compactMap { $0 }.joined(separator: " ") }
                        .joined(separator: "  ·  "))
                }
            }
            .font(.system(size: 13.5))
            if parsed.isIncomplete {
                Label("This file looks unfinished (still downloading or copying).", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.orange)
            }
            Text(film.fileName)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            VStack(spacing: 0) {
                ForEach(model.copies(of: film)) { copy in
                    let online = model.fileURL(copy) != nil
                    HStack(spacing: 12) {
                        Image(systemName: online ? "externaldrive.fill" : "externaldrive")
                            .foregroundStyle(online ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.drive(copy.driveID)?.name ?? "Drive").font(.system(size: 13.5, weight: .medium))
                            Text(online ? Format.bytes(copy.size) : "\(Format.bytes(copy.size)) · not connected")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Show in Finder") { model.showInFinder(copy) }
                            .disabled(!online)
                        Button("Copy Path") { model.copyPath(copy) }
                    }
                    .padding(14)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
            .frame(maxWidth: 760)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

// MARK: - Fixing a match

struct MatchFixer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let film: FilmEntry

    @State private var query = ""
    @State private var results: [TMDBMovieSummary] = []
    @State private var searching = false
    @State private var choosing: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which film is this?").font(.title3.bold())
            Text(film.fileName)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack {
                TextField("Title and year, e.g. Dune 2021", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                if searching { ProgressView().controlSize(.small) }
                Button("Search") { search() }
            }
            List(options) { movie in
                row(movie)
            }
            .listStyle(.inset)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 600, height: 560)
        .onAppear {
            query = film.parsed.title + (film.parsed.year.map { " \($0)" } ?? "")
            // Confident matches don't keep alternatives, so fetch some.
            if film.candidates.isEmpty { search() }
        }
    }

    private var options: [TMDBMovieSummary] {
        results.isEmpty ? film.candidates.map { $0.movie } : results
    }

    private func row(_ movie: TMDBMovieSummary) -> some View {
        Button {
            choosing = movie.id
            Task {
                await model.choose(movie, for: film)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Poster(path: movie.posterPath, title: "", kind: .thumbnail, cornerRadius: 4)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.title).font(.body.weight(.semibold))
                    Text(detailLine(movie))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if choosing == movie.id {
                    ProgressView().controlSize(.small)
                } else if movie.id == film.tmdb?.id {
                    Image(systemName: "checkmark").foregroundStyle(Color.green)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(choosing != nil)
    }

    private func detailLine(_ movie: TMDBMovieSummary) -> String {
        var parts: [String] = []
        if let year = movie.year { parts.append(String(year)) }
        if let original = movie.originalTitle, original != movie.title { parts.append(original) }
        if let overview = movie.overview, !overview.isEmpty { parts.append(overview) }
        return parts.joined(separator: " · ")
    }

    private func search() {
        searching = true
        let text = query
        Task {
            results = await model.search(text)
            searching = false
        }
    }
}
#endif
