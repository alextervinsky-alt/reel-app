#if os(macOS)
import SwiftUI
import ReelCore

// MARK: - Lists hub

/// Where to find your next film: Start Here (what the lists agree on, what fits you first),
/// then the rankings and award lists themselves, and the sets you're collecting, each with how
/// much of it you own and have seen.
struct ListsView: View {
    @Environment(AppModel.self) private var model
    @State private var setKind: FilmSet.Kind = .director
    @State private var preview: PreviewFilm?
    @State private var preparing = true

    private let cardColumns = [GridItem(.adaptive(minimum: 330), spacing: 18, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 46) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lists").font(.system(size: 30, weight: .bold))
                    Text("Critics' polls, festival winners and rankings, to find the next film worth watching.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                StartHereSection(preparing: preparing) { preview = $0 }
                awardsSection
                IMDbSection(columns: cardColumns)
                setsSection
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 48)
        }
        .background(Theme.background)
        .navigationTitle("Lists")
        .toolbar(removing: .title)
        .filmPreviewSheet($preview)
        .task {
            let lists = model.lists
            await lists.prepare()
            async let awards: Void = lists.loadAllAwards()
            async let sets: Void = model.refreshSets()
            async let imdb: Void = lists.load(.imdbAllTime)
            _ = await (awards, sets, imdb)
            await model.prepareStartHere()
            preparing = false
            // Three posters per card.
            if let client = model.tmdb {
                let firsts = AwardList.allCases.flatMap { lists.films(for: .award($0)).filter { $0.isWinner }.prefix(3) }
                    + SightAndSound.films.prefix(3)
                await lists.resolve(firsts, using: client)
            }
        }
    }

    // MARK: Complete the set

    private var setsSection: some View {
        let shown = visibleSets
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                SectionHeading(title: "Complete the Set",
                               subtitle: "The directors, cinematographers and franchises you've started collecting")
                Spacer()
                HStack(spacing: 6) {
                    ForEach(FilmSet.Kind.allCases, id: \.self) { kind in
                        FilterChip(title: kind.title, isOn: setKind == kind) { setKind = kind }
                    }
                }
            }
            if shown.isEmpty {
                HStack(spacing: 8) {
                    if model.lists.setsLoading {
                        ProgressView().controlSize(.small)
                        Text("Finding your sets…").foregroundStyle(.secondary)
                    } else {
                        Text(model.hasToken ? emptySetsText : "Connect TMDB in Settings to see your sets.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                .frame(height: 150, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: setKind == .franchise ? 20 : 26) {
                        ForEach(shown, id: \.set.id) { entry in
                            SetCard(set: entry.set, progress: entry.progress)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var emptySetsText: String {
        switch setKind {
        case .director: "Once you own two films by the same director, they show up here."
        case .cinematographer: "Once you own two films shot by the same cinematographer, they show up here."
        case .franchise: "Films you own that are part of a series show up here."
        }
    }

    /// Sets of the chosen kind in the order of how many of their films you own; finished sets last.
    private var visibleSets: [(set: FilmSet, progress: ListProgress)] {
        model.setCandidates
            .filter { $0.kind == setKind }
            .compactMap { model.lists.set(FilmSet.id($0.kind, $0.id)) }
            .map { (set: $0, progress: model.progress(of: $0)) }
            .filter { $0.progress.total >= 2 }
            .sorted { a, b in
                let aDone = a.progress.owned >= a.progress.total, bDone = b.progress.owned >= b.progress.total
                if aDone != bDone { return !aDone }
                return a.progress.owned != b.progress.owned ? a.progress.owned > b.progress.owned : a.set.name < b.set.name
            }
    }

    // MARK: Awards

    private var awardsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Critics, Awards & Festivals",
                           subtitle: "Sight and Sound's critics' poll, and winners and nominees from Wikidata, refreshed weekly")
            LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 18) {
                ListCard(kind: .sightAndSound, source: "Sight and Sound · 2022", symbol: "star.square.on.square")
                ForEach(AwardList.allCases) { award in
                    ListCard(kind: .award(award), source: award.source,
                             symbol: award == .criterion ? "square.stack.3d.up" : "laurel.leading")
                }
            }
        }
    }
}

/// The films the lists agree on and you haven't seen: those already on your drives, and those
/// worth finding. Each says why it's here: a film you loved by the same director, or its lists.
struct StartHereSection: View {
    @Environment(AppModel.self) private var model
    let preparing: Bool
    let preview: (PreviewFilm) -> Void

    var body: some View {
        let start = model.startHere()
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(title: "Start Here",
                           subtitle: "What the critics, festivals and rankings agree on, with what fits your ratings first")
            if !start.onDrive.isEmpty {
                row("Already on Your Drives", detail: "Acclaimed, and not watched yet", start.onDrive)
            }
            if !start.toFind.isEmpty {
                row("Worth Finding", detail: "Not in your library, not seen yet", start.toFind)
            } else {
                HStack(spacing: 8) {
                    if preparing && model.hasToken {
                        ProgressView().controlSize(.small)
                        Text("Finding films on several lists…")
                    } else {
                        Text(model.hasToken ? "Nothing new to suggest right now." : "Connect TMDB in Settings to see suggestions.")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: String, detail: String, _ suggestions: [ListSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(suggestions) { suggestion in
                        DiscoverCard(film: suggestion.film, width: 136,
                                     badge: suggestion.pick.lists.count > 1 ? "\(suggestion.pick.lists.count) lists" : nil,
                                     reason: suggestion.reason, onPreview: preview)
                            .help(ListConsensus.summary(suggestion.pick.lists, limit: 6))
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

/// IMDb's rankings, in its own view so download progress redraws only this part.
struct IMDbSection: View {
    @Environment(AppModel.self) private var model
    let columns: [GridItem]
    @State private var year = Calendar.current.component(.year, from: Date()) - 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                SectionHeading(title: "IMDb Rankings", subtitle: "Ranked by IMDb rating and number of votes")
                if case .ready = model.lists.imdbState { YearMenu(year: $year) }
                Spacer()
                if model.lists.imdbUpdating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Updating…")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                } else if case .ready(let date) = model.lists.imdbState {
                    Text("Updated \(date.formatted(date: .abbreviated, time: .omitted)) · refreshed monthly")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            switch model.lists.imdbState {
            case .ready:
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ListCard(kind: .imdbYear(year), source: "IMDb · \(year)", symbol: "calendar")
                    ListCard(kind: .imdbAllTime, source: "IMDb · All time", symbol: "trophy")
                }
            default:
                IMDbSetupCard()
            }
        }
        .task(id: postersKey) {
            // Three posters for each card.
            guard let client = model.tmdb else { return }
            let lists = model.lists
            await lists.resolve(Array(lists.films(for: .imdbYear(year)).prefix(3)) + lists.films(for: .imdbAllTime).prefix(3),
                                using: client)
        }
    }

    /// Changes when the year or the IMDb data does.
    private var postersKey: String {
        if case .ready(let date) = model.lists.imdbState { return "\(year)|\(date.timeIntervalSince1970)" }
        return "\(year)"
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 19, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Cards

/// A director or cinematographer (photo inside a ring that fills as you collect their films),
/// or a franchise (poster with a progress line).
struct SetCard: View {
    let set: FilmSet
    let progress: ListProgress
    @State private var hovering = false

    var body: some View {
        Group {
            if set.kind == .franchise {
                NavigationLink(value: FranchiseRoute(id: set.tmdbID, name: set.name)) { franchise }
            } else {
                NavigationLink(value: PersonRoute(id: set.tmdbID, name: set.name)) { person }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: hovering)
        .help("\(progress.owned) of \(progress.total) in your library, \(progress.seen) seen")
    }

    private var person: some View {
        VStack(spacing: 10) {
            ZStack {
                ProgressRing(fraction: progress.ownedFraction, lineWidth: 4)
                CachedImage(path: set.imagePath, kind: .profile) {
                    Image(systemName: "person.fill").font(.system(size: 38)).foregroundStyle(.tertiary)
                }
                .frame(width: 112, height: 112)
                .background(Color(white: 0.14))
                .clipShape(Circle())
            }
            .frame(width: 128, height: 128)
            VStack(spacing: 2) {
                Text(set.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(width: 140)
        .contentShape(Rectangle())
    }

    private var franchise: some View {
        VStack(alignment: .leading, spacing: 8) {
            Poster(path: set.imagePath, title: set.name, cornerRadius: 10)
            ProgressLine(fraction: progress.ownedFraction)
            Text(set.name.replacingOccurrences(of: " Collection", with: ""))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(caption)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(width: 132)
        .contentShape(Rectangle())
    }

    private var caption: String {
        var text = "\(progress.owned) of \(progress.total)"
        if progress.owned >= progress.total { text = "Complete · \(progress.total)" }
        if progress.seen > 0 { text += " · \(progress.seen) seen" }
        return text
    }
}

/// A list: three of its posters fanned out, its name, size and how much of it you've seen.
struct ListCard: View {
    @Environment(AppModel.self) private var model
    let kind: FilmListKind
    let source: String
    let symbol: String
    @State private var hovering = false

    var body: some View {
        let lists = model.lists
        let all = lists.films(for: kind)
        // Award cards count the winners; nominees are a tap away on the list.
        let films = kind.hasNominees ? all.filter { $0.isWinner } : all
        let progress = model.progress(of: films)
        let posters = films.prefix(3).map { lists.resolved($0)?.posterPath }
        NavigationLink(value: ListRoute(kind: kind)) {
            HStack(spacing: 20) {
                PosterFan(paths: posters, symbol: symbol)
                    .frame(width: 112, height: 128)
                VStack(alignment: .leading, spacing: 5) {
                    Text(source.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.brand)
                    Text(kind.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status(films.count, nominees: all.count - films.count))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    ProgressLine(fraction: progress.seenFraction)
                    Text(films.isEmpty ? " " : "\(progress.seen) seen · \(progress.owned) in your library")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(height: 168)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.08) : Theme.panel)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private func status(_ count: Int, nominees: Int) -> String {
        if count > 0 { return nominees > 0 ? "\(count) winners · \(nominees) nominees" : "\(count) films" }
        if model.lists.isLoading(kind) { return "Loading…" }
        if case .award(let award) = kind, model.lists.awardsFailed.contains(award) { return "Couldn't load. Try again later." }
        return "Loading…"
    }
}

/// Up to three posters fanned out like cards in a hand; an icon tile while none are loaded.
struct PosterFan: View {
    let paths: [String?]
    let symbol: String

    var body: some View {
        ZStack {
            if paths.allSatisfy({ $0 == nil }) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.brand.opacity(0.16))
                    .frame(width: 80, height: 120)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Theme.brand)
                    }
            } else {
                ForEach(Array(paths.enumerated().reversed()), id: \.offset) { index, path in
                    Poster(path: path, title: "", cornerRadius: 7)
                        .frame(width: 72)
                        .shadow(color: Color.black.opacity(0.45), radius: 6, y: 3)
                        .rotationEffect(.degrees(Double(index - 1) * 7), anchor: .bottom)
                        .offset(x: CGFloat(index - 1) * 20)
                }
            }
        }
    }
}

/// Explains the one-time IMDb download and shows its progress.
struct IMDbSetupCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.lists.imdbState
        HStack(alignment: .center, spacing: 20) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.96, green: 0.77, blue: 0.09))
                .frame(width: 64, height: 40)
                .overlay {
                    Text("IMDb").font(.system(size: 17, weight: .heavy)).foregroundStyle(Color.black)
                }
            VStack(alignment: .leading, spacing: 6) {
                Text("Top 100 for any year, and the Top 250 of all time")
                    .font(.system(size: 15, weight: .semibold))
                Text(detail(state))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .downloading(let progress) = state {
                    ProgressLine(fraction: progress).frame(maxWidth: 360)
                }
            }
            Spacer(minLength: 12)
            if case .failed = state {
                Button("Try Again") { Task { await model.lists.downloadIMDb() } }
                    .buttonStyle(PrimaryCapsuleStyle())
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
        .frame(maxWidth: 820, alignment: .leading)
    }

    private func detail(_ state: ListsStore.IMDbState) -> String {
        switch state {
        case .downloading(let progress):
            return "Downloading IMDb's ratings… \(Int(progress * 100))%"
        case .preparing:
            return "Picking out the feature films… this takes a few seconds."
        case .failed(let message):
            return message
        default:
            return "Getting IMDb's free ratings files (about 200 MB). Reel keeps a small copy of the feature films, removes the rest, and refreshes it every month on its own."
        }
    }
}

// MARK: - Progress

/// A ring that fills with Reel's colour.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}

/// A thin bar that fills with Reel's colour.
struct ProgressLine: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.1))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(Theme.brandGradient)
                        .frame(width: geometry.size.width * min(1, max(0, fraction)))
                }
            }
            .animation(.easeOut(duration: 0.35), value: fraction)
    }
}
#endif
