#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

/// Scrolling and hover, shared by a grid and its posters. Nothing here is observed, so starting or
/// stopping a scroll redraws no poster except the one under the pointer, which is told to settle.
@Observable @MainActor
final class ScrollState {
    @ObservationIgnored var isScrolling = false
    /// Settles the lifted poster (set by the poster the pointer is on).
    @ObservationIgnored var endHover: (() -> Void)?
    /// The poster that came under the pointer while scrolling: lifted when the scroll stops.
    @ObservationIgnored var waiting: (id: String, lift: () -> Void)?
    /// The poster under the pointer, for Space (Quick Look).
    @ObservationIgnored var pointed: LibraryItem?
}

struct LibraryGridView: View {
    @Environment(AppModel.self) private var model
    let shelf: Shelf
    /// The search field under the title; `query` follows it after a short pause.
    @Binding var searchText: String
    /// Set by ⌘F (from anywhere on the desk): the field takes the focus.
    @Binding var focusSearch: Bool
    let query: String
    @Binding var sort: LibrarySort
    @Binding var moods: Set<Mood>
    @Binding var length: LengthBand
    @Binding var language: String?
    @Binding var shotOn: ShotOn?
    /// The posters' width (the slider beside Sort) and posters or a list, for this session.
    @Binding var posterSize: Double
    @Binding var asList: Bool
    @Binding var path: NavigationPath
    @State private var scroll = ScrollState()
    @State private var readAhead = PosterReadAhead()
    /// The film being made an extra of another one (right-click › This Is an Extra Of…).
    @State private var regrouping: LibraryItem?
    /// Quick Look: Space on the poster under the pointer, or right-click.
    @State private var previewing: LibraryItem?
    /// Seen It? (Unwatched): one poster at a time.
    @State private var sweeping = false

    /// The posters' columns elsewhere (Explore, lists): the default size.
    static let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24, alignment: .top)]

    /// As many columns as fit at the chosen poster size.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: posterSize, maximum: posterSize * 1.22), spacing: 22, alignment: .top)]
    }

    var body: some View {
        // Shelf + search, then language, what it was shot on, length and moods. Each filter's
        // counts reflect the others.
        let all = model.shelfItems(shelf, matching: query, sortedBy: sort)
        let inLanguage = language.map { code in all.filter { $0.language == code } } ?? all
        let inShot = shotOn.map { kind in inLanguage.filter { $0.shotOn.contains(kind) } } ?? inLanguage
        let lengthFiltered = length == .any ? inShot : inShot.filter { length.contains($0.runtime) }
        let shown = moods.isEmpty ? lengthFiltered : lengthFiltered.filter { moods.isSubset(of: $0.moods) }
        let moodFiltered = moods.isEmpty ? inShot : inShot.filter { moods.isSubset(of: $0.moods) }
        let featured = shelf == .all && query.isEmpty && !filtering ? model.featured : nil

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let featured {
                    FeaturedBanner(item: featured) {
                        path.append(FilmRoute(id: featured.main.id))
                    } showTrailer: {
                        model.showTrailer(for: featured.main)
                    }
                }
                header(shown: shown, moodBase: lengthFiltered, lengthBase: moodFiltered, languageBase: all,
                       shotBase: shotOn == nil ? shown : inLanguage.filter { item in
                           (length == .any || length.contains(item.runtime)) && moods.isSubset(of: item.moods)
                       })
                    .padding(.horizontal, 32)
                    .padding(.top, featured == nil ? 18 : 6)
                if let about = shelfDescription {
                    Text(about)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 32)
                        .padding(.top, 10)
                }
                if shelf == .unwatched, query.isEmpty, !shown.isEmpty {
                    HStack(spacing: 10) {
                        Text("Seen some of these before they came to Reel?")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Button("Seen It?  One at a Time") { sweeping = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.brand)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 10)
                }
                if shown.isEmpty {
                    emptyState.frame(maxWidth: .infinity, minHeight: 360)
                } else if asList {
                    FilmList(items: shown, sort: $sort, sortable: shelf != .notOnBackup)
                        .padding(.horizontal, 32)
                        .padding(.top, 18)
                        .padding(.bottom, 40)
                } else if shelf == .watched && query.isEmpty {
                    watchedByMonth(shown)
                } else {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 30) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            card(item).onAppear { readAhead.warm(at: index, in: shown) }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onScrollPhaseChange { _, phase in
            let isScrolling = phase.isScrolling
            if isScrolling && !scroll.isScrolling {
                scroll.endHover?()
                scroll.endHover = nil
            }
            let stopped = !isScrolling && scroll.isScrolling
            scroll.isScrolling = isScrolling
            if stopped {
                scroll.waiting?.lift()
                scroll.waiting = nil
            }
        }
        .environment(scroll)
        .background(Theme.background)
        // The banner reaches the top of the window, like a film page's backdrop.
        .ignoresSafeArea(.container, edges: featured == nil ? [] : .top)
        .navigationTitle(title)
        .sheet(item: $regrouping) { item in
            RegroupSheet(item: item)
        }
        .sheet(isPresented: $sweeping) { SeenSweep() }
        .cardOverlay(item: $previewing) { item in
            QuickPreview(item: item) { previewing = nil } openFilm: { path.append(FilmRoute(id: item.main.id)) }
        }
        // Another shelf or a search: the card was about the list before.
        .onChange(of: shelf) { previewing = nil }
        .onChange(of: query) { previewing = nil }
        .onReelKey { key in
            // Only while the grid is what's showing (not a film page pushed over it).
            guard key == .space, path.isEmpty, !model.cinemaMode, model.trailer == nil, let item = scroll.pointed else { return false }
            previewing = item
            return true
        }
        .onDisappear { scroll.pointed = nil }
    }

    private func card(_ item: LibraryItem) -> some View {
        NavigationLink(value: FilmRoute(id: item.main.id)) {
            PosterCard(item: item, note: note(for: item), isNew: shelf != .newArrivals && model.arrivals[item.id] != nil && !model.isWatched(item.id),
                       regroup: { regrouping = item }, preview: { previewing = item })
                .equatable()
        }
        .buttonStyle(.plain)
    }

    /// A line under the poster on shelves where something else matters more than the genre.
    private func note(for item: LibraryItem) -> CardNote? {
        switch shelf {
        case .newArrivals:
            if model.cameFromWishlist(item) {
                return CardNote(text: "From your wishlist", symbol: "star.fill", tint: Theme.brand)
            }
            return model.arrivals[item.id].map { CardNote(text: Arrivals.label($0, now: Date()), symbol: nil, tint: nil) }
        case .notOnBackup:
            switch model.backupGaps[item.id] {
            case .incomplete: return CardNote(text: "Incomplete copy on Backup", symbol: "exclamationmark.triangle.fill", tint: .orange)
            case .missing: return CardNote(text: "Not on Backup", symbol: nil, tint: nil)
            case nil: return nil
            }
        default:
            return nil
        }
    }

    // MARK: Header and filters

    /// Moods in front (how you choose); length, language and sort as compact menus at the right.
    private var filtering: Bool { !moods.isEmpty || length != .any || language != nil || shotOn != nil }

    private func header(shown: [LibraryItem], moodBase: [LibraryItem], lengthBase: [LibraryItem], languageBase: [LibraryItem],
                        shotBase: [LibraryItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.3)
                    .lineLimit(1)
                Text(summary(shown))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer(minLength: 12)
                LibrarySearchField(text: $searchText, focusRequested: $focusSearch)
            }
            HStack(spacing: 6) {
                MoodFilterButton(selected: $moods, base: moodBase, available: model.moods)
                ForEach(Mood.allCases.filter { moods.contains($0) }) { mood in
                    RemovableChip(title: mood.title) { moods.remove(mood) }
                }
                if !model.shotOnKinds.isEmpty || shotOn != nil {
                    ShotOnFilterMenu(shotOn: $shotOn, base: shotBase, kinds: model.shotOnKinds)
                }
                LengthFilterMenu(length: $length, base: lengthBase)
                if model.languages.count > 1 {
                    LanguageFilterMenu(language: $language, base: languageBase, languages: model.languages)
                }
                if filtering {
                    Button("Clear") {
                        moods = []
                        length = .any
                        language = nil
                        shotOn = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .padding(.leading, 4)
                }
                Spacer(minLength: 12)
                if !asList { PosterSizeSlider(size: $posterSize) }
                // Not on Backup is a checklist, always by title.
                if shelf != .notOnBackup { SortMenu(sort: $sort) }
                ViewModeToggle(asList: $asList)
            }
        }
    }

    /// "84 films · 78 unwatched · 6 watched · 50 new · 187 hours": the shelf at a glance.
    private func summary(_ shown: [LibraryItem]) -> String {
        var parts = [shown.count == 1 ? "1 film" : "\(shown.count) films"]
        if shelf == .all, query.isEmpty, !filtering {
            parts += ["\(model.count(.unwatched)) unwatched", "\(model.count(.watched)) watched"]
            if model.count(.newArrivals) > 0 { parts.append("\(model.count(.newArrivals)) new") }
        }
        let minutes = shown.reduce(0) { $0 + ($1.runtime ?? 0) }
        if minutes >= 120 { parts.append("\(minutes / 60) hours") }
        return parts.joined(separator: " · ")
    }

    // MARK: Watched diary

    private func watchedByMonth(_ shown: [LibraryItem]) -> some View {
        let dates = model.personal.watchedDates
        let groups = Self.monthGroups(shown) { dates[$0.id] }
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 30, pinnedViews: []) {
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        card(item).onAppear { readAhead.warm(at: index, in: group.items) }
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(group.title).font(.system(size: 19, weight: .semibold))
                        Text("\(group.items.count)").font(.system(size: 13)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 14)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 6)
        .padding(.bottom, 40)
    }

    /// Films grouped by the month they were watched, newest first.
    static func monthGroups(_ items: [LibraryItem], date: (LibraryItem) -> Date?) -> [(title: String, items: [LibraryItem])] {
        let calendar = Calendar.current
        var buckets: [Date: [LibraryItem]] = [:]
        var undated: [LibraryItem] = []
        for item in items {
            if let watched = date(item), let month = calendar.dateInterval(of: .month, for: watched)?.start {
                buckets[month, default: []].append(item)
            } else {
                undated.append(item)
            }
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        var result = buckets.keys.sorted(by: >).map { month in
            (title: formatter.string(from: month),
             items: (buckets[month] ?? []).sorted { (date($0) ?? .distantPast) > (date($1) ?? .distantPast) })
        }
        if !undated.isEmpty { result.append((title: "Earlier", items: undated)) }
        return result
    }

    // MARK: Empty states

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            if model.craftPending > 0 {
                // Gear and techniques are still being read: a craft search finds more soon.
                ContentUnavailableView {
                    Label("No Results for “\(query)” Yet", systemImage: "magnifyingglass")
                } description: {
                    Text("Reel is still reading how your films were shot (\(model.craftPending) to go). Searches for gear and techniques such as anamorphic or 16mm find more once that's done.")
                }
            } else {
                ContentUnavailableView.search(text: query)
            }
        } else if filtering {
            ContentUnavailableView {
                Label("No films match these filters", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Clear Filters") {
                    moods = []
                    length = .any
                    language = nil
                    shotOn = nil
                }
            }
        } else {
            switch shelf {
            case .newArrivals:
                ContentUnavailableView("Nothing new in the last 14 days", systemImage: "shippingbox",
                                       description: Text("Films that turn up on your drives appear here for two weeks."))
            case .notOnBackup:
                ContentUnavailableView("Everything is on the Backup", systemImage: "checkmark.shield",
                                       description: Text("Every film on your main drive has a full copy on the Backup."))
            case .watchlist:
                ContentUnavailableView("Nothing on your watchlist", systemImage: "bookmark",
                                       description: Text("Use the bookmark button on a film's page."))
            case .favorites:
                ContentUnavailableView("No favorites yet", systemImage: "heart",
                                       description: Text("Use the heart button on a film's page."))
            case .watched:
                ContentUnavailableView("Nothing marked as watched", systemImage: "checkmark.circle",
                                       description: Text("Use the checkmark button on a film's page."))
            case .unwatched:
                ContentUnavailableView("You've seen them all", systemImage: "popcorn")
            default:
                ContentUnavailableView("No films here", systemImage: "film",
                                       description: Text("Connect the drive or press ⌘R to rescan."))
            }
        }
    }

    private var title: String {
        switch shelf {
        case .all: "All Films"
        case .tonight: "Tonight"
        case .recommended: "Recommended"
        case .newArrivals: "New Arrivals"
        case .unwatched: "Unwatched"
        case .watchlist: "Watchlist"
        case .favorites: "Favorites"
        case .watched: "Watched"
        case .needsCheck: "Check Matches"
        case .notOnBackup: "Not on Backup"
        case .yearInFilm: "Year in Film"
        case .genre(let genre): genre
        case .drive(let id): model.drive(id)?.name ?? "Drive"
        case .forYou: "For You"
        case .explore: "Explore"
        case .lists: "Lists"
        case .wishlist: "Wishlist"
        }
    }

    /// A line under the title on shelves that need explaining.
    private var shelfDescription: String? {
        switch shelf {
        case .newArrivals:
            return "Films found on your drives in the last 14 days."
        case .notOnBackup:
            // Fixed words (a date, not "5 minutes ago"), so the line never changes length by itself.
            let backups = model.backupDrives
            if backups.contains(where: { model.reading[$0.id] != nil }) {
                return "Reading the Backup. The list is updated when it's done."
            }
            let read = model.lastBackupScan.map { " The Backup was last read on \($0.formatted(date: .abbreviated, time: .shortened))." } ?? ""
            let connected = backups.contains { model.mounted[$0.id] != nil }
            return "Films on your main drive without a full copy on the Backup, compared by file size." + read
                + (connected ? "" : " It isn't connected now: this is from that reading.")
        case .drive(let id) where model.mounted[id] == nil:
            let scanned = model.drive(id)?.lastScanned.map { " (last read \($0.formatted(.relative(presentation: .named))))" } ?? ""
            return "Not connected. These are its films from the last scan\(scanned)."
        default:
            return nil
        }
    }
}

// MARK: - Filters

/// "Mood" button: a checklist with live counts. Ticking several shows films that have all of them.
struct MoodFilterButton: View {
    @Binding var selected: Set<Mood>
    /// Films before the mood filter.
    let base: [LibraryItem]
    let available: [Mood]
    @State private var open = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            FilterPill(icon: "theatermasks", text: label, active: !selected.isEmpty)
        }
        .buttonStyle(.plain)
        .disabled(available.isEmpty)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            MoodChecklist(selected: $selected, base: base, available: available)
        }
    }

    private var label: String {
        switch selected.count {
        case 0: "Mood"
        case 1: selected.first?.title ?? "Mood"
        default: "\(selected.count) moods"
        }
    }
}

struct MoodChecklist: View {
    @Binding var selected: Set<Mood>
    let base: [LibraryItem]
    let available: [Mood]

    var body: some View {
        let current = selected.isEmpty ? base : base.filter { selected.isSubset(of: $0.moods) }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Mood").font(.system(size: 14, weight: .semibold))
                Text("\(current.count) films").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if !selected.isEmpty {
                    Button("Clear") { selected = [] }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.brand)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            ForEach(available) { mood in
                let isOn = selected.contains(mood)
                let count = isOn ? current.count : current.filter { $0.moods.contains(mood) }.count
                Button {
                    if isOn { selected.remove(mood) } else { selected.insert(mood) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isOn ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isOn ? Theme.brand : Color.secondary)
                        Image(systemName: mood.symbol)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text(mood.title)
                        Spacer()
                        Text("\(count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(count == 0 && !isOn)
                .opacity(count == 0 && !isOn ? 0.4 : 1)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

/// Length menu with how many films fall into each band.
struct LengthFilterMenu: View {
    @Binding var length: LengthBand
    /// Films before the length filter.
    let base: [LibraryItem]

    var body: some View {
        Menu {
            Picker("Length", selection: $length) {
                ForEach(LengthBand.allCases) { band in
                    let count = band == .any ? base.count : base.filter { band.contains($0.runtime) }.count
                    Text("\(band.title)  (\(count))").tag(band)
                }
            }
            .pickerStyle(.inline)
        } label: {
            FilterPill(icon: "clock", text: length == .any ? "Length" : length.title, active: length != .any)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct LanguageFilterMenu: View {
    @Binding var language: String?
    /// Films before the language filter.
    let base: [LibraryItem]
    let languages: [String]

    var body: some View {
        Menu {
            Button("Any Language  (\(base.count))") { language = nil }
            Divider()
            ForEach(languages, id: \.self) { code in
                let count = base.filter { $0.language == code }.count
                if count > 0 {
                    Button("\(FilmLanguage.name(code))  (\(count))") { language = code }
                }
            }
        } label: {
            FilterPill(icon: "globe", text: language.map(FilmLanguage.name) ?? "Language", active: language != nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// What the films were shot on (film, digital, anamorphic, IMAX, black and white), as read about
/// them in the background; only what's in the library is offered.
struct ShotOnFilterMenu: View {
    @Binding var shotOn: ShotOn?
    /// Films before this filter.
    let base: [LibraryItem]
    let kinds: [ShotOn]

    var body: some View {
        Menu {
            Button("Anything  (\(base.count))") { shotOn = nil }
            Divider()
            ForEach(kinds) { kind in
                let count = base.filter { $0.shotOn.contains(kind) }.count
                if count > 0 || kind == shotOn {
                    Button("\(kind.title)  (\(count))") { shotOn = kind }
                }
            }
        } label: {
            FilterPill(icon: "camera.aperture", text: shotOn?.title ?? "Shot on", active: shotOn != nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct SortMenu: View {
    @Binding var sort: LibrarySort

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(LibrarySort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Text(sort.title)
                Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).opacity(0.7)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.8))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct FilterPill: View {
    let icon: String
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text)
            Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).opacity(0.6)
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(active ? Theme.brand.opacity(0.14) : Theme.field))
        .overlay(Capsule().strokeBorder(active ? Theme.brand.opacity(0.5) : Color.white.opacity(0.07)))
        .foregroundStyle(active ? Theme.brand : Color.white.opacity(0.85))
        .contentShape(Capsule())
    }
}

/// The posters' size: small to large, as in Photos.
struct PosterSizeSlider: View {
    @Binding var size: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.portrait").font(.system(size: 8, weight: .semibold))
            Slider(value: $size, in: 130...240)
                .controlSize(.mini)
                .frame(width: 84)
            Image(systemName: "rectangle.portrait").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .tint(Theme.brand)
        .help("Poster size")
    }
}

/// Posters or a list.
struct ViewModeToggle: View {
    @Binding var asList: Bool

    var body: some View {
        HStack(spacing: 2) {
            option("square.grid.2x2", list: false, help: "Posters")
            option("list.bullet", list: true, help: "List")
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
    }

    private func option(_ symbol: String, list: Bool, help: String) -> some View {
        Button {
            asList = list
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(asList == list ? Color.white : Color.secondary)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(asList == list ? Color.white.opacity(0.12) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct RemovableChip: View {
    let title: String
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().strokeBorder(Theme.hairline).background(Capsule().fill(Theme.panel)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Search the library: a slim field beside the title (titles, people, places, moods, years).
struct LibrarySearchField: View {
    @Binding var text: String
    @Binding var focusRequested: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search films, people, craft", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onExitCommand { focused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 260, height: 32)
        .background(Capsule().fill(Color.white.opacity(focused ? 0.11 : 0.07)))
        .overlay(Capsule().strokeBorder(focused ? Theme.brand.opacity(0.6) : Theme.hairline))
        .animation(.easeOut(duration: 0.15), value: focused)
        // ⌘F (RootView), also when it brought All Films up for it.
        .onAppear(perform: takeFocus)
        .onChange(of: focusRequested) { takeFocus() }
    }

    private func takeFocus() {
        guard focusRequested else { return }
        focusRequested = false
        Task { @MainActor in focused = true }
    }
}

// MARK: - Banner

/// Large backdrop banner for one film, like the top of the Apple TV app.
struct FeaturedBanner: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem
    let open: () -> Void
    let showTrailer: () -> Void
    static let height: CGFloat = 440

    var body: some View {
        let film = item.main
        VStack(alignment: .leading, spacing: 12) {
            TitleArt(film: film, maxWidth: 400, maxHeight: 110, fontSize: 40)
            HStack(spacing: 16) {
                Text(Format.metaLine(film))
                    .foregroundStyle(Theme.secondaryText)
                RatingStrip(film: film)
            }
            .font(.system(size: 13))
            // The whole synopsis: what the film is about, to decide from here.
            if let overview = film.tmdb?.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 600, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button(action: open) {
                    Label("Details", systemImage: "info.circle")
                }
                .buttonStyle(PrimaryCapsuleStyle())
                if model.offersTrailer(for: film) {
                    Button {
                        showTrailer()
                    } label: {
                        Label(model.trailerLabel(for: film), systemImage: "play.rectangle")
                    }
                    .buttonStyle(SecondaryCapsuleStyle())
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.top, 76)
        .padding(.bottom, 28)
        // At least the usual height; a long synopsis makes the banner taller instead of being cut.
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .bottomLeading)
        // Anywhere on the picture opens the film (the buttons do their own thing).
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .background {
            Color.black
                .overlay { FocusedBackdrop(path: film.tmdb?.backdropPath) }
                .clipped()
                .overlay {
                    LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0)], startPoint: .leading, endPoint: .center)
                }
                .overlay {
                    // Darker along the top, so the label there reads on any picture.
                    LinearGradient(stops: [.init(color: Color.black.opacity(0.5), location: 0), .init(color: .clear, location: 0.3),
                                           .init(color: .clear, location: 0.5), .init(color: Theme.background, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .overlay(alignment: .topLeading) {
            Label("From Your Library", systemImage: "film.stack")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
                .padding(.leading, 32)
                .padding(.top, 24)
        }
        .clipped()
    }
}

// MARK: - Poster card

/// Loads the posters of the next rows while the grid scrolls, so they're in memory before they
/// come into view (instead of keeping the whole library in memory, which doesn't fit). Only asks
/// again once the scroll has moved past most of what it read last time.
@MainActor
final class PosterReadAhead {
    private var warmed: Range<Int> = 0..<0
    private var listID: [String] = []

    func warm(at index: Int, in list: [LibraryItem]) {
        // A different list (another shelf, sort or search) starts over.
        let id = [list.first?.id ?? "", list.last?.id ?? "", String(list.count)]
        if id != listID {
            listID = id
            warmed = 0..<0
        }
        // Ask again only when fewer than ~5 rows are ready ahead (or the scroll went back up).
        let needAhead = index + 30 > warmed.upperBound && warmed.upperBound < list.count
        let needBehind = index - 6 < warmed.lowerBound && warmed.lowerBound > 0
        guard warmed.isEmpty || needAhead || needBehind else { return }
        let range = max(0, index - 12)..<min(list.count, index + 48)
        let wanted = list[range].compactMap { item in
            item.main.tmdb?.posterPath.map { (path: $0, monochrome: !item.isOnline) }
        }
        warmed = range
        ImageStore.shared.warm(wanted, .poster)
    }
}

/// A line that replaces the caption under a poster.
struct CardNote: Equatable {
    let text: String
    let symbol: String?
    let tint: Color?
}

struct PosterCard: View, Equatable {
    @Environment(AppModel.self) private var model
    @Environment(ScrollState.self) private var scroll
    let item: LibraryItem
    var note: CardNote? = nil
    /// Arrived in the last two weeks and not watched: a NEW tag on the poster.
    var isNew = false
    /// Opens "This Is an Extra Of…" (the grid shows the sheet); not offered when nil.
    var regroup: (() -> Void)? = nil
    /// Opens Quick Look; not offered when nil.
    var preview: (() -> Void)? = nil
    @State private var hovering = false

    /// This film's notes only: a change to another film never redraws this card.
    private var record: PersonalRecord { model.record(forKey: item.id) }
    /// Lifted under the pointer, never while scrolling. The shadow is only drawn when lifted.
    private var lifted: Bool { hovering }

    /// Cards only redraw when what they show changes (their own state still updates them).
    nonisolated static func == (lhs: PosterCard, rhs: PosterCard) -> Bool {
        lhs.item.id == rhs.item.id && lhs.item.stamp == rhs.item.stamp && lhs.note == rhs.note && lhs.isNew == rhs.isNew
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            poster
                .background {
                    if lifted {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black)
                            .shadow(color: Color.black.opacity(0.6), radius: 18, y: 12)
                    }
                }
                .scaleEffect(lifted ? 1.04 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: lifted)

            // Title; year, length and director; the ratings: what you need without opening it.
            VStack(alignment: .leading, spacing: 3) {
                Text(item.main.displayTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                caption
                    .font(.system(size: 12))
                    .lineLimit(1)
                RatingsLine(film: item.main)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            // Read here, not while drawing: scrolling never redraws the cards.
            let hover = $hovering
            let scroll = scroll
            let lift = {
                hover.wrappedValue = true
                scroll.endHover = { hover.wrappedValue = false }
            }
            if inside { scroll.pointed = item } else if scroll.pointed?.id == item.id { scroll.pointed = nil }
            if !inside {
                hovering = false
                if scroll.waiting?.id == item.id { scroll.waiting = nil }
            } else if scroll.isScrolling {
                scroll.waiting = (item.id, lift)
            } else {
                lift()
            }
        }
        .contextMenu { menu }
    }

    /// Built from this card's own data only (its film and its notes), so it costs nothing extra
    /// while scrolling and redraws with the card.
    @ViewBuilder
    private var menu: some View {
        let film = item.main
        Button("Play") { model.play(film) }
            .disabled(!item.isOnline)
        Button(record.watched ? "Mark as Unwatched" : "Mark as Watched") {
            model.toggle(\.watched, for: film)
        }
        // Built from the card's own data: no library-wide work while cards are drawn.
        Menu("Play With") {
            ForEach(PlayerChoice.installed) { player in
                Button(player.title) { model.play(film, with: player) }
            }
        }
        .disabled(!item.isOnline)
        Button(model.isTonight(item.id) ? "Remove from Tonight" : "Add to Tonight") { model.toggleTonight(item.id) }
        Button("Show in Finder") { model.showInFinder(film) }
            .disabled(!item.isOnline)
        if let preview {
            Button("Quick Look", action: preview)
        }
        Divider()
        if let regroup {
            Button("This Is an Extra Of…", action: regroup)
        }
        if model.isRegrouped(film.relativePath) {
            Button("Undo Regrouping") { model.resetGrouping(film.relativePath) }
        }
    }

    /// In colour whether or not its drive is connected (the line under it says when it isn't),
    /// with its quality in the corner and NEW while it's new.
    private var poster: some View {
        Poster(path: item.main.tmdb?.posterPath, title: item.main.displayTitle, cornerRadius: 12)
            .overlay {
                if lifted { HoverDetails(item: item).transition(.opacity) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let tag = Format.posterTag(item.main) { QualityTag(text: tag).padding(8) }
            }
            .overlay(alignment: .topTrailing) {
                // Under the pointer: add to (or take off) tonight's shortlist in one click.
                if lifted {
                    TonightButton(key: item.id, size: 30).padding(7).transition(.opacity)
                } else {
                    marks
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isNew && !lifted {
                    Text("NEW")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.brand))
                        .padding(9)
                }
            }
    }

    /// "2017 · 2h 44m · Denis Villeneuve": what the film is, at a glance.
    @ViewBuilder
    private var caption: some View {
        if let note {
            HStack(spacing: 4) {
                if let symbol = note.symbol { Image(systemName: symbol).font(.system(size: 9.5)) }
                Text(note.text)
            }
            .foregroundStyle(note.tint ?? Color.secondary)
        } else if item.main.matchState.needsCheck {
            Text("Check match").foregroundStyle(Color.orange)
        } else {
            let director = item.main.tmdb?.directors.first
            let line = [Format.glanceLine(year: item.main.displayYear, runtime: item.runtime), director]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            Text(item.isOnline ? line : (line.isEmpty ? "Drive not connected" : line + " · Offline"))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var marks: some View {
        let tonight = model.isTonight(item.id)
        if record.favorite || record.watched || record.watchlist || tonight {
            HStack(spacing: 5) {
                if tonight { Image(systemName: "moon.fill") }
                if record.watchlist && !record.watched { Image(systemName: "bookmark.fill") }
                if record.favorite { Image(systemName: "heart.fill").foregroundStyle(Color.pink) }
                if record.watched { Image(systemName: "checkmark") }
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .padding(8)
        }
    }
}
#endif
