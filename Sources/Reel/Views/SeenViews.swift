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
#endif
