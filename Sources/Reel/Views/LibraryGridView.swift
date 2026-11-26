#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

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
    /// The posters' width (the slider beside Sort) and posters or a list, for this session.
    @Binding var posterSize: Double
    @Binding var asList: Bool
    @Binding var path: NavigationPath
    @State private var scroll = ScrollState()
    /// The grid's one pointer tracker and right-click menu (1.11).
    @State private var pointer = GridPointer()
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
        // Shelf + search, then language, length and moods. Each filter's counts reflect the others.
        let all = model.shelfItems(shelf, matching: query, sortedBy: sort)
        let inLanguage = language.map { code in all.filter { $0.language == code } } ?? all
        let lengthFiltered = length == .any ? inLanguage : inLanguage.filter { length.contains($0.runtime) }
        let shown = moods.isEmpty ? lengthFiltered : lengthFiltered.filter { moods.isSubset(of: $0.moods) }
        let moodFiltered = moods.isEmpty ? inLanguage : inLanguage.filter { moods.isSubset(of: $0.moods) }
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
                header(shown: shown, moodBase: lengthFiltered, lengthBase: moodFiltered, languageBase: all)
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
                    FilmList(items: shown, sort: $sort, sortable: query.isEmpty && shelf != .notOnBackup && shelf != .newArrivals)
                        .padding(.horizontal, 32)
                        .padding(.top, 18)
                        .padding(.bottom, 40)
                } else if shelf == .watched && query.isEmpty {
                    watchedByMonth(shown)
                } else {
                    let _ = (pointer.items = shown)
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 30) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            card(item)
                                .gridCell(index, in: pointer)
                                .onAppear { readAhead.warm(at: index, in: shown) }
                        }
                    }
                    .gridPointer(pointer) { item in posterMenu(item) }
                    .padding(.horizontal, 32)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .hoverRegion()
        }
        .onScrollPhaseChange { _, phase in
            scroll.name = "Library grid"
            scroll.phaseChanged(scrolling: phase.isScrolling, model: model)
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
        .onDisappear {
            scroll.pointed = nil
            scroll.phaseChanged(scrolling: false, model: model)
        }
        // The poster under the pointer is gone once the list replaces the grid.
        .onChange(of: asList) { scroll.pointed = nil }
    }

    /// A poster's right-click menu (one for the whole grid, see `GridPointer`): the same as the
    /// card's own menu elsewhere.
    private func posterMenu(_ item: LibraryItem) -> NSMenu? {
        let film = item.main
        let record = model.record(forKey: item.id)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(MenuAction.item("Play", enabled: item.isOnline) { model.play(film) })
        menu.addItem(MenuAction.item(record.watched ? "Mark as Unwatched" : "Mark as Watched") { model.toggle(\.watched, for: film) })
        let players = NSMenu()
        for player in PlayerChoice.installed {
            players.addItem(MenuAction.item(player.title) { model.play(film, with: player) })
        }
        let playWith = NSMenuItem(title: "Play With", action: nil, keyEquivalent: "")
        playWith.submenu = players
        playWith.isEnabled = item.isOnline
        menu.addItem(playWith)
        menu.addItem(MenuAction.item(model.isTonight(item.id) ? "Remove from Tonight" : "Add to Tonight") { model.toggleTonight(item.id) })
        menu.addItem(MenuAction.item("Show in Finder", enabled: item.isOnline) { model.showInFinder(film) })
        menu.addItem(MenuAction.item("Quick Look") { previewing = item })
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("This Is an Extra Of…") { regrouping = item })
        if model.isRegrouped(film.relativePath) {
            menu.addItem(MenuAction.item("Undo Regrouping") { model.resetGrouping(film.relativePath) })
        }
        return menu
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
    private var filtering: Bool { !moods.isEmpty || length != .any || language != nil }

    private func header(shown: [LibraryItem], moodBase: [LibraryItem], lengthBase: [LibraryItem], languageBase: [LibraryItem]) -> some View {
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
                LengthFilterMenu(length: $length, base: lengthBase)
                if model.languages.count > 1 {
                    LanguageFilterMenu(language: $language, base: languageBase, languages: model.languages)
                }
                if filtering {
                    Button("Clear") {
                        moods = []
                        length = .any
                        language = nil
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
        case .newReleases: "New Releases"
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

#endif
