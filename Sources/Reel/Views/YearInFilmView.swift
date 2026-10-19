#if os(macOS)
import Charts
import SwiftUI
import ReelCore

/// Your year of watching: how much, when, what kind, by whom, and every film in order.
/// Built from the films you marked as watched, and the ones you saw elsewhere when they count.
struct YearInFilmView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var chosenYear: Int?
    @State private var preview: PreviewFilm?

    var body: some View {
        let all = model.yearFilms()
        let elsewhere = model.seenElsewhereFilms
        let calendar = Calendar.current
        // A year with only films seen elsewhere is still one to look back on (and rate them in).
        let years = Array(Set(YearInFilm.years(in: all)).union(elsewhere.map { calendar.component(.year, from: $0.date) }))
            .sorted(by: >)
        let year = chosenYear.flatMap { years.contains($0) ? $0 : nil } ?? years.first
        let page = VStack(alignment: .leading, spacing: 30) {
                header(years: years, year: year, hasElsewhere: !elsewhere.isEmpty)
                if let year {
                    // This year so far against last year by the same day (a whole past year against its whole).
                    let thisYear = year == calendar.component(.year, from: Date())
                    let cutoff = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
                    let before = YearInFilm(year: year - 1, from: thisYear ? all.filter { $0.watchedOn <= cutoff } : all)
                    YearSummary(summary: YearInFilm(year: year, from: all), previous: before.films.isEmpty ? nil : before,
                                soFar: thisYear,
                                elsewhere: model.seenElsewhere(in: year), counted: model.yearCountsElsewhere) { preview = $0 }
                } else {
                    ContentUnavailableView("Your year starts with a film", systemImage: "calendar",
                                           description: Text("Mark films as watched and they'll be counted here, month by month."))
                        .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
            .frame(maxWidth: 1120, alignment: .leading)
        // Drawn to an image (the CI screens), the page as it is: a scroll view draws nothing there.
        Group {
            if isSnapshot {
                page.frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView { page }
            }
        }
        .background(Theme.background)
        .navigationTitle("Year in Film")
        .filmPreviewSheet($preview)
        // Titles, running times and genres of films seen elsewhere, the first time they're needed.
        .task {
            await model.lists.prepare()
            await model.loadSeenFilms()
        }
    }

    private func header(years: [Int], year: Int?, hasElsewhere: Bool) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(year.map { "\(String($0)) in Film" } ?? "Year in Film")
                    .font(.system(size: 30, weight: .bold))
                Text(model.yearCountsElsewhere && hasElsewhere
                     ? "Everything you watched, on your drives and elsewhere, from the first film of the year to the last."
                     : "Everything you marked as watched, from the first film of the year to the last.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if hasElsewhere {
                Toggle("Count films seen elsewhere", isOn: Binding(get: { model.yearCountsElsewhere },
                                                                   set: { model.setYearCountsElsewhere($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 13))
                    .fixedSize()
                    .help("Films you marked as seen somewhere else, like the cinema, in the numbers and highlights")
                    .padding(.trailing, years.count > 1 ? 14 : 0)
            }
            if years.count > 1, let year {
                Picker("Year", selection: Binding(get: { year }, set: { chosenYear = $0 })) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }
}

private struct YearSummary: View {
    @Environment(AppModel.self) private var model
    let summary: YearInFilm
    /// The year before, when it has films: to compare with.
    let previous: YearInFilm?
    /// The year isn't over: compared with the year before up to the same day.
    let soFar: Bool
    /// This year's films seen elsewhere, newest first.
    let elsewhere: [SeenElsewhere]
    /// They're in the numbers (otherwise only listed, to rate and date).
    let counted: Bool
    let preview: (PreviewFilm) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if !summary.films.isEmpty {
                numbers
                months
                inNumbers
                highlights
                if summary.starCounts.reduce(0, +) >= 3 || summary.weekdays.reduce(0, +) >= 5 { starsAndNights }
                if !summary.warmerThanMost.isEmpty || !summary.coolerThanMost.isEmpty { youAndTheCritics }
                tastes
                everyFilm
            }
            if !elsewhere.isEmpty { seenElsewhere }
        }
    }

    /// Opens a film of the year: its page when it's in the library, otherwise its preview.
    @ViewBuilder
    private func opening<Label: View>(_ film: YearFilm, @ViewBuilder label: () -> Label) -> some View {
        if let item = model.item(forKey: film.key) {
            NavigationLink(value: FilmRoute(id: item.main.id)) { label() }
                .buttonStyle(.plain)
        } else if let id = PersonalStore.tmdbID(film.key), let seen = model.lists.briefs[id] {
            Button { preview(PreviewFilm(id: id, seen: seen)) } label: { label() }
                .buttonStyle(.plain)
        }
    }

    private func posterPath(_ film: YearFilm) -> String? {
        if let item = model.item(forKey: film.key) { return item.main.tmdb?.posterPath }
        return PersonalStore.tmdbID(film.key).flatMap { model.lists.briefs[$0]?.posterPath }
    }

    private func backdropPath(_ film: YearFilm) -> String? {
        if let item = model.item(forKey: film.key) { return item.main.tmdb?.backdropPath }
        return PersonalStore.tmdbID(film.key).flatMap { model.lists.briefs[$0]?.backdropPath }
    }

    // MARK: Numbers

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
            BigNumber(value: "\(summary.uniqueFilms.count)", label: summary.uniqueFilms.count == 1 ? "film" : "films")
            BigNumber(value: hours, label: "hours of film")
            if let genre = summary.topGenres.first {
                BigNumber(value: genre.name, label: "most watched genre")
            }
            if let decade = summary.decades.max(by: { $0.count < $1.count }) {
                BigNumber(value: decade.name, label: "favourite decade")
            }
            }
            if let previous { comparison(with: previous) }
        }
    }

    /// "4 more films and 9 more hours than in 2025"
    private func comparison(with previous: YearInFilm) -> some View {
        let films = summary.uniqueFilms.count - previous.uniqueFilms.count
        let hours = Int((Double(summary.minutes - previous.minutes) / 60).rounded())
        func part(_ n: Int, _ one: String, _ many: String) -> String? {
            n == 0 ? nil : "\(abs(n)) \(n > 0 ? "more" : "fewer") \(abs(n) == 1 ? one : many)"
        }
        let parts = [part(films, "film", "films"), part(hours, "hour", "hours")]
            .compactMap { $0 }
        let when = soFar ? "by this time in \(String(previous.year))" : "in \(String(previous.year))"
        let text = parts.isEmpty ? "As many films as \(when)" : parts.joined(separator: " and ") + " than \(when)"
        return Label(text, systemImage: films >= 0 ? "arrow.up.right" : "arrow.down.right")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .help("\(String(previous.year))\(soFar ? " to this date" : ""): \(previous.uniqueFilms.count) films, \(Int((Double(previous.minutes) / 60).rounded())) hours")
    }

    private var hours: String {
        let h = Double(summary.minutes) / 60
        return h < 10 ? String(format: "%.1f", h) : String(Int(h.rounded()))
    }

    // MARK: In numbers

    /// The smaller figures, in one quiet panel: only those the year has.
    @ViewBuilder
    private var inNumbers: some View {
        let figures = smallFigures
        if !figures.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Theme.sectionTitle("In Numbers")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 0, alignment: .topLeading)], alignment: .leading, spacing: 0) {
                    ForEach(figures, id: \.label) { figure in
                        FigureCell(value: figure.value, label: figure.label)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
            }
        }
    }

    private var smallFigures: [(value: String, label: String)] {
        var figures: [(value: String, label: String)] = []
        if let minutes = summary.averageRuntime { figures.append((Format.runtime(minutes), "an average film")) }
        if let stars = summary.averageStars { figures.append(("★ " + String(format: "%.1f", stars), "your average rating")) }
        if summary.newReleases > 0 {
            figures.append(("\(summary.newReleases)", summary.newReleases == 1 ? "film from \(String(summary.year))" : "films from \(String(summary.year))"))
        }
        if let month = summary.busiestMonth {
            figures.append((Calendar.current.monthSymbols[month], "your busiest month · \(summary.months[month]) films"))
        }
        if let day = summary.favouriteWeekday {
            figures.append((Calendar.current.weekdaySymbols[day - 1] + "s", "your film night"))
        }
        if summary.languageCount > 1 { figures.append(("\(summary.languageCount)", "Languages")) }
        if let run = summary.longestRun {
            let span = run.start.formatted(.dateTime.day().month(.abbreviated)) + "–" + run.end.formatted(.dateTime.day().month(.abbreviated))
            figures.append(("\(run.nights) nights", "your longest run · \(span)"))
        }
        if let age = summary.averageAge {
            figures.append((age == 1 ? "1 year" : "\(age) years", "how old a film was, on average, when you saw it"))
        }
        let rated = summary.starCounts.reduce(0, +)
        if rated > 0 { figures.append(("\(rated) of \(summary.uniqueFilms.count)", "films you gave stars")) }
        if summary.rewatches > 0 {
            figures.append((summary.rewatches == 1 ? "1 rewatch" : "\(summary.rewatches) rewatches", "films you watched again"))
        }
        return figures
    }


    // MARK: Months

    private var months: some View {
        let names = Calendar.current.shortMonthSymbols
        return VStack(alignment: .leading, spacing: 12) {
            Theme.sectionTitle("Month by Month")
            Chart {
                ForEach(0..<12, id: \.self) { i in
                    BarMark(x: .value("Month", names[i]), y: .value("Films", summary.months[i]))
                        .foregroundStyle(Theme.brandGradient)
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            if summary.months[i] > 0 {
                                Text("\(summary.months[i])")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 11)) }
            }
            .frame(height: 150)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        }
    }

    // MARK: Highlights

    @ViewBuilder
    private var highlights: some View {
        let picks = highlightPicks
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Theme.sectionTitle("Highlights")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(picks, id: \.label) { pick in
                        opening(pick.film) {
                            HighlightCard(label: pick.label, title: pick.film.title, detail: pick.detail,
                                          backdrop: backdropPath(pick.film))
                        }
                    }
                }
            }
        }
    }

    /// Each film once: a card is left out when its film already has one (with two films, the
    /// favourite can also be the longest and the oldest).
    private var highlightPicks: [Highlight] {
        var picks: [Highlight] = []
        func add(_ pick: Highlight) {
            if !picks.contains(where: { $0.film.key == pick.film.key }) { picks.append(pick) }
        }
        if let film = summary.favourite {
            add(film.yourRating.map { Highlight(label: "Your favourite", film: film, detail: String(repeating: "★", count: $0)) }
                ?? Highlight(label: "Best reviewed", film: film, detail: film.score.map { "★ " + Format.rating($0) } ?? ""))
        }
        if let film = summary.longest {
            add(Highlight(label: "Longest", film: film, detail: film.runtime.map { Format.runtime($0) } ?? ""))
        }
        if let film = summary.oldest {
            add(Highlight(label: "Oldest", film: film, detail: film.releaseYear.map(String.init) ?? ""))
        }
        if let film = summary.shortest {
            add(Highlight(label: "Shortest", film: film, detail: film.runtime.map { Format.runtime($0) } ?? ""))
        }
        if let film = summary.newest {
            add(Highlight(label: "Newest", film: film, detail: film.releaseYear.map(String.init) ?? ""))
        }
        if let film = summary.uniqueFilms.first(where: { !$0.elsewhere }) {
            add(Highlight(label: "First of the year", film: film, detail: film.watchedOn.formatted(.dateTime.day().month(.wide))))
        }
        return picks
    }

    // MARK: Stars and nights

    /// How you rated the year (one star to five), and which nights you watched.
    private var starsAndNights: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            if summary.starCounts.reduce(0, +) >= 3 {
                CountChart(title: "Your Stars", labels: (1...5).map { String(repeating: "★", count: $0) }, counts: summary.starCounts,
                           note: "Every film you rated this year")
            }
            if summary.weekdays.reduce(0, +) >= 5 {
                let calendar = Calendar.current
                // In the week's own order here (Monday first in Estonia).
                let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
                CountChart(title: "Your Film Nights", labels: order.map { calendar.shortWeekdaySymbols[$0] },
                           counts: order.map { summary.weekdays[$0] }, note: "Films watched from your drives, by day of the week")
            }
        }
    }

    // MARK: You and the critics

    /// Films you rated well above or below their average score (IMDb, else TMDB): ★★★★★ is 10.
    private var youAndTheCritics: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Theme.sectionTitle("You and Everyone Else")
                Text("Your stars against each film's average score (IMDb, else TMDB), with five stars as 10")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                if !summary.warmerThanMost.isEmpty { gapPanel("You liked more than most", summary.warmerThanMost) }
                if !summary.coolerThanMost.isEmpty { gapPanel("You liked less than most", summary.coolerThanMost) }
            }
        }
    }

    private func gapPanel(_ title: String, _ gaps: [RatingGap]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            ForEach(gaps) { gap in
                opening(gap.film) {
                    HStack(spacing: 12) {
                        Poster(path: posterPath(gap.film), title: "", kind: .thumbnail, cornerRadius: 4)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gap.film.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text("You " + String(repeating: "★", count: max(1, min(5, gap.stars))) + " · average " + Format.rating(gap.score))
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
    }

    // MARK: Genres, people, decades and lists

    /// The great lists your films of the year are on (from your drives: winners and members only).
    private var onTheLists: [Tally] {
        var names: [String] = []
        for film in summary.uniqueFilms {
            guard let item = model.item(forKey: film.key) else { continue }
            names += Set(model.badges(for: item.main).filter(\.isWin).map { $0.kind.title })
        }
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5).map { Tally(name: $0.key, count: $0.value) }
    }

    @ViewBuilder
    private var tastes: some View {
        let lists = onTheLists
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            if !summary.topGenres.isEmpty {
                TallyPanel(title: "Genres", tallies: summary.topGenres)
            }
            if summary.decades.count > 1 {
                TallyPanel(title: "Decades", tallies: summary.decades)
            }
            if !summary.topDirectors.isEmpty {
                TallyPanel(title: "Directors you came back to", tallies: summary.topDirectors)
            }
            if !summary.topCinematographers.isEmpty {
                TallyPanel(title: "Cinematographers you came back to", tallies: summary.topCinematographers)
            }
            if !summary.topComposers.isEmpty {
                TallyPanel(title: "Composers you came back to", tallies: summary.topComposers)
            }
            if !lists.isEmpty {
                TallyPanel(title: "On the great lists", tallies: lists)
            }
            // Only when the year goes beyond one language.
            if summary.languageCount > 1 {
                TallyPanel(title: "Languages", tallies: summary.languages)
            }
            if !summary.topActors.isEmpty {
                TallyPanel(title: "Faces you saw most", tallies: summary.topActors)
            }
        }
    }

    // MARK: Every film

    private var everyFilm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Theme.sectionTitle("Every Film, in Order")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 130), spacing: 16, alignment: .top)],
                      alignment: .leading, spacing: 20) {
                ForEach(summary.films) { film in
                    opening(film) {
                        VStack(alignment: .leading, spacing: 6) {
                            Poster(path: posterPath(film), title: film.title, cornerRadius: 8)
                                .overlay(alignment: .topTrailing) {
                                    // Seen elsewhere, not on a drive.
                                    if model.item(forKey: film.key) == nil {
                                        Image(systemName: "eye.fill")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(6)
                                            .background(Circle().fill(Color.black.opacity(0.65)))
                                            .padding(6)
                                    }
                                }
                            Text(film.watchedOn.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help(film.title)
                }
            }
        }
    }

    // MARK: Seen elsewhere

    /// The year's films seen elsewhere, each with when and your stars, to change in place.
    private var seenElsewhere: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Theme.sectionTitle("Seen Elsewhere")
                Text(counted ? "Counted above. Set when you saw each one and how it was."
                             : "Not counted above (see the switch at the top). Set when you saw each one and how it was.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                // It dates films marked this month, so it's offered on this year's page.
                if summary.year == Calendar.current.component(.year, from: Date()) { DateByReleaseButton() }
            }
            LazyVStack(spacing: 0) {
                ForEach(elsewhere) { entry in
                    if entry.id != elsewhere.first?.id {
                        Divider().overlay(Theme.hairline).padding(.leading, 74)
                    }
                    SeenElsewhereRow(id: entry.id, date: entry.date, film: entry.film, preview: preview)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
        }
    }
}

/// One film seen elsewhere: poster, title, when (click to change) and your stars.
private struct SeenElsewhereRow: View {
    @Environment(AppModel.self) private var model
    let id: Int
    let date: Date
    let film: FilmBrief?
    let preview: (PreviewFilm) -> Void
    @State private var editing = false

    var body: some View {
        let key = "tmdb:\(id)"
        HStack(spacing: 14) {
            Button {
                if let film { preview(PreviewFilm(id: id, seen: film)) }
            } label: {
                HStack(spacing: 14) {
                    Poster(path: film?.posterPath, title: "", kind: .thumbnail, cornerRadius: 5)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(film?.title ?? "Loading…")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(film == nil)
            Button(date.formatted(.dateTime.month(.wide).year())) { editing = true }
                .buttonStyle(SecondaryCapsuleStyle())
                .help("When you saw it")
                .popover(isPresented: $editing) {
                    WatchedDateEditor(title: "Seen in", date: date, save: { model.setSeenDate($0, tmdbID: id) },
                                      done: { editing = false })
                }
            StarRating(rating: model.record(forKey: key).rating) { model.setSeenRating($0, tmdbID: id) }
                .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 74)
    }

    /// "2019 · Bong Joon-ho"
    private var detail: String {
        [film?.year.map(String.init), film?.directors.first].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct Highlight {
    let label: String
    let film: YearFilm
    let detail: String
}

private struct BigNumber: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
    }
}

private struct HighlightCard: View {
    let label: String
    let title: String
    let detail: String
    let backdrop: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FocusedBackdrop(path: backdrop)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.brand)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A short ranking (genres, directors, languages, faces): each with how many films, and a bar
/// measured against the first, so the longest bar is the one that leads.
private struct TallyPanel: View {
    let title: String
    let tallies: [Tally]

    var body: some View {
        let most = max(tallies.map(\.count).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            ForEach(tallies) { tally in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tally.name).font(.system(size: 13))
                        Spacer()
                        Text(tally.count == 1 ? "1 film" : "\(tally.count) films")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(Color.white.opacity(0.07))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.brandGradient)
                                    .frame(width: max(6, geometry.size.width * CGFloat(tally.count) / CGFloat(most)))
                            }
                    }
                    .frame(height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// Films seen elsewhere that were all dated the month they were marked (before Reel dated them
/// by release): one click dates each the month after it came out.
private struct DateByReleaseButton: View {
    @Environment(AppModel.self) private var model
    @State private var working = false

    var body: some View {
        let films = model.seenThisMonthByDefault()
        if !films.isEmpty {
            Button {
                working = true
                Task {
                    await model.dateSeenByRelease(films)
                    working = false
                }
            } label: {
                Label(working ? "Dating…" : "Date \(films.count) by Release", systemImage: "calendar.badge.clock")
            }
            .buttonStyle(SecondaryCapsuleStyle())
            .disabled(working)
            .help("These were all dated this month. Date each one the month after it came out in cinemas instead (you can still change any of them).")
        }
    }
}
/// A small bar chart of counts (stars, nights of the week), each bar with its number.
private struct CountChart: View {
    let title: String
    let labels: [String]
    let counts: [Int]
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Chart {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    BarMark(x: .value("Kind", label), y: .value("Films", counts[index]))
                        .foregroundStyle(Theme.brandGradient)
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            if counts[index] > 0 {
                                Text("\(counts[index])")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 11)) } }
            .frame(height: 120)
            Text(note).font(.system(size: 11.5)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// One figure of In Numbers: the number, and what it counts.
private struct FigureCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
