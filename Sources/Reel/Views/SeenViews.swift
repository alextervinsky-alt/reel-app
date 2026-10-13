#if os(macOS)
import SwiftUI
import ReelCore

// MARK: - When you watched it

/// The month and year you watched a film. Saves with Save (or Return).
struct WatchedDateEditor: View {
    let title: String
    let save: (Date) -> Void
    let done: () -> Void
    @State private var month: Int
    @State private var year: Int

    init(title: String, date: Date, save: @escaping (Date) -> Void, done: @escaping () -> Void) {
        self.title = title
        self.save = save
        self.done = done
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        _month = State(initialValue: parts.month ?? 1)
        _year = State(initialValue: parts.year ?? 2026)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .semibold))
            MonthYearPicker(month: $month, year: $year)
            HStack {
                Spacer()
                Button("Save") {
                    save(MonthYearPicker.date(month: month, year: year))
                    done()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

/// A month and a year, the way Year in Film counts a viewing.
struct MonthYearPicker: View {
    @Binding var month: Int
    @Binding var year: Int
    /// Up to this year, worked out when drawn (Reel left open over New Year gets the new one).
    private var years: [Int] {
        Array((min(1950, year)...max(Calendar.current.component(.year, from: Date()), year)).reversed())
    }

    var body: some View {
        HStack {
            Picker("Month", selection: $month) {
                ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)
            Picker("Year", selection: $year) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 90)
        }
    }

    /// The middle of the month, or today for the current month (never a day still to come).
    static func date(month: Int, year: Int, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.year, .month], from: now)
        if today.year == year, today.month == month { return now }
        // A month still to come counts as now.
        return min(calendar.date(from: DateComponents(year: year, month: month, day: 15)) ?? now, now)
    }
}

// MARK: - Seen elsewhere

/// For a film you saw somewhere else (the cinema, streaming): when, your stars, or not seen
/// after all. Changes are kept as they're made.
struct SeenEditor: View {
    @Environment(AppModel.self) private var model
    let tmdbID: Int
    let done: () -> Void
    @State private var month: Int
    @State private var year: Int

    init(tmdbID: Int, date: Date?, done: @escaping () -> Void) {
        self.tmdbID = tmdbID
        self.done = done
        let parts = Calendar.current.dateComponents([.year, .month], from: date ?? Date())
        _month = State(initialValue: parts.month ?? 1)
        _year = State(initialValue: parts.year ?? 2026)
    }

    var body: some View {
        let key = "tmdb:\(tmdbID)"
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Seen in").font(.system(size: 14, weight: .semibold))
                MonthYearPicker(month: $month, year: $year)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Your rating").font(.system(size: 14, weight: .semibold))
                StarRating(rating: model.record(forKey: key).rating) { model.setSeenRating($0, tmdbID: tmdbID) }
            }
            HStack {
                Button("Not Seen") {
                    model.toggleSeen(tmdbID)
                    done()
                }
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 270)
        // Its own buttons, whatever style the eye that opened it has.
        .buttonStyle(.automatic)
        .onChange(of: month) { save() }
        .onChange(of: year) { save() }
        // Dated by its release once that's known (just marked seen): the pickers follow.
        .onChange(of: model.record(forKey: key).watchedOn) { _, date in
            guard let date else { return }
            let parts = Calendar.current.dateComponents([.year, .month], from: date)
            if let m = parts.month, m != month { month = m }
            if let y = parts.year, y != year { year = y }
        }
    }

    private func save() {
        model.setSeenDate(MonthYearPicker.date(month: month, year: year), tmdbID: tmdbID)
    }
}

/// The eye on a list row or a preview: marks a film seen, then asks when and how it was
/// (both optional); on a film already seen it opens the same questions. Styled by the
/// button style around it.
struct SeenButton<Label: View>: View {
    @Environment(AppModel.self) private var model
    let tmdbID: Int
    @ViewBuilder let label: (Bool) -> Label
    @State private var editing = false

    var body: some View {
        let seen = model.isSeen(tmdbID)
        Button {
            if !seen { model.toggleSeen(tmdbID) }
            editing = true
        } label: {
            label(seen)
        }
        // A film on a drive: seen is the same as watched.
        .help(model.itemsByTMDB[tmdbID] != nil
              ? (seen ? "Watched: change when, or your rating" : "Mark as watched (it's on your drive)")
              : (seen ? "Seen: change when, or your rating" : "Mark as seen"))
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            SeenEditor(tmdbID: tmdbID, date: model.record(forKey: "tmdb:\(tmdbID)").watchedOn) { editing = false }
        }
    }
}

// MARK: - Seen it? sweep

/// Unwatched films one poster at a time, the best known first: seen or not, and your stars if
/// you like. Quick for marking what you'd seen before the films came to Reel. Uses only your
/// own answers: a film marked seen here has no date (it was before), and Undo takes an answer back.
struct SeenSweep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The films to ask about, in order (worked out once, when the sweep opens).
    @State private var queue: [String]
    @State private var position = 0
    /// Each answer, to take back: the film and how its notes were before.
    @State private var answers: [(key: String, before: PersonalRecord)] = []
    @State private var seenCount = 0

    /// `queue`: the films to ask about (worked out when it opens when not given).
    init(queue: [String] = []) {
        _queue = State(initialValue: queue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Seen It?").font(.system(size: 22, weight: .bold))
                Spacer()
                if !queue.isEmpty {
                    Text("\(min(position + 1, queue.count)) of \(queue.count)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let key = queue.indices.contains(position) ? queue[position] : nil, let item = model.item(forKey: key) {
                question(item)
            } else {
                done
            }
            HStack {
                Button("Undo") { undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(answers.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 600)
        .onAppear(perform: start)
    }

    private func question(_ item: LibraryItem) -> some View {
        HStack(alignment: .top, spacing: 24) {
            Poster(path: item.main.tmdb?.posterPath, title: item.main.displayTitle, cornerRadius: 12)
                .frame(width: 210)
                .id(item.id)
                .transition(.opacity)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.main.displayTitle)
                        .font(.system(size: 20, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.byline(item.main))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seen it? Your stars, if you remember:")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { stars in
                            Button {
                                answer(item, seen: true, stars: stars)
                            } label: {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Color.yellow.opacity(0.85))
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(KeyEquivalent(Character(String(stars))), modifiers: [])
                            .help("Seen, \(stars) of 5 (\(stars))")
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button("Not Seen") { answer(item, seen: false, stars: nil) }
                        .buttonStyle(SecondaryCapsuleStyle())
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .help("Not seen (←)")
                    Button("Seen It") { answer(item, seen: true, stars: nil) }
                        .buttonStyle(PrimaryCapsuleStyle())
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .help("Seen, no stars (→)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 315)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(queue.isEmpty ? "Every film here is marked already." : "That's all of them.")
                .font(.system(size: 17, weight: .semibold))
            Text(seenCount == 0 ? "Nothing was marked as seen." : seenCount == 1 ? "1 film marked as seen." : "\(seenCount) films marked as seen.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 315, alignment: .center)
    }

    /// "1999 · Directed by Lana Wachowski, Lilly Wachowski"
    static func byline(_ film: FilmEntry) -> String {
        let directors = film.tmdb?.directors ?? []
        return [film.displayYear.map(String.init), directors.isEmpty ? nil : "Directed by " + directors.prefix(2).joined(separator: ", ")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func start() {
        if queue.isEmpty { queue = model.seenSweepQueue() }
    }

    private func answer(_ item: LibraryItem, seen: Bool, stars: Int?) {
        let before = model.record(forKey: item.id)
        answers.append((item.id, before))
        if seen {
            model.markSeenBefore(item.id, stars: stars)
            seenCount += 1
        }
        withAnimation(.easeOut(duration: 0.15)) { position += 1 }
    }

    private func undo() {
        guard let last = answers.popLast() else { return }
        if model.record(forKey: last.key) != last.before {
            model.setRecord(last.before, forKey: last.key)
            seenCount -= 1
        }
        withAnimation(.easeOut(duration: 0.15)) { position = max(position - 1, 0) }
    }
}
#endif
