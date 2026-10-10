#if os(macOS)
import Charts
import SwiftUI
import ReelCore

/// Your year of watching: how much, when, what kind, by whom, and every film in order.
/// Built from the films you marked as watched, and the ones you saw elsewhere when they count.
struct YearInFilmView: View {
    @Environment(AppModel.self) private var model
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
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header(years: years, year: year, hasElsewhere: !elsewhere.isEmpty)
                if let year {
                    YearSummary(summary: YearInFilm(year: year, from: all), elsewhere: model.seenElsewhere(in: year),
                                counted: model.yearCountsElsewhere) { preview = $0 }
                } else {
                    ContentUnavailableView("Your year starts with a film", systemImage: "calendar",
                                           description: Text("Mark films as watched and they'll be counted here, month by month."))
                        .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
            .frame(maxWidth: 1120, alignment: .leading)
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
                if !summary.topGenres.isEmpty || !summary.topDirectors.isEmpty || summary.languageCount > 1
                    || !summary.topActors.isEmpty { tastes }
                everyFilm
            }
            if !elsewhere.isEmpty { seenElsewhere }
        }
    }

    /// Opens a film of the year: its page when it's in the library, otherwise its preview.
    @ViewBuilder
    private func opening<Label: View>(_ film: YearFilm, @ViewBuilder label: () -> Label) -> some View {
        if let item = model.item(forKey: film.id) {
            NavigationLink(value: FilmRoute(id: item.main.id)) { label() }
                .buttonStyle(.plain)
        } else if let id = PersonalStore.tmdbID(film.id), let seen = model.lists.briefs[id] {
            Button { preview(PreviewFilm(id: id, seen: seen)) } label: { label() }
                .buttonStyle(.plain)
        }
    }

    private func posterPath(_ film: YearFilm) -> String? {
        if let item = model.item(forKey: film.id) { return item.main.tmdb?.posterPath }
        return PersonalStore.tmdbID(film.id).flatMap { model.lists.briefs[$0]?.posterPath }
    }

    private func backdropPath(_ film: YearFilm) -> String? {
        if let item = model.item(forKey: film.id) { return item.main.tmdb?.backdropPath }
        return PersonalStore.tmdbID(film.id).flatMap { model.lists.briefs[$0]?.backdropPath }
    }

    // MARK: Numbers

    private var numbers: some View {
        HStack(spacing: 14) {
            BigNumber(value: "\(summary.films.count)", label: summary.films.count == 1 ? "film" : "films")
            BigNumber(value: hours, label: "hours of film")
            if let genre = summary.topGenres.first {
                BigNumber(value: genre.name, label: "most watched genre")
            }
            if let decade = summary.decades.max(by: { $0.count < $1.count }) {
                BigNumber(value: decade.name, label: "favourite decade")
            }
        }
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
                HStack(alignment: .top, spacing: 16) {
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
            if !picks.contains(where: { $0.film.id == pick.film.id }) { picks.append(pick) }
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
        return picks
    }

    // MARK: Genres and directors

    private var tastes: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            if !summary.topGenres.isEmpty {
                TallyPanel(title: "Genres", tallies: summary.topGenres)
            }
            if !summary.topDirectors.isEmpty {
                TallyPanel(title: "Directors you came back to", tallies: summary.topDirectors)
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
                                    if model.item(forKey: film.id) == nil {
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
