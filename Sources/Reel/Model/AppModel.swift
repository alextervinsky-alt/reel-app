#if os(macOS)
import AppKit
import Observation
import ReelCore

/// Library.json as written by Reel 0.2 (drives were plain paths).
private struct LegacyLibrary: Decodable {
    var drives: [String]
}

/// Reel's state. Split by topic over several files:
/// - AppModel.swift: state, start-up, the library as the grid sees it
/// - +Drives: drives, scanning, Backup check, grouping fixes
/// - +Lookup: film info from TMDB, OMDb and Wikipedia
/// - +Personal: watched, notes, wishlist, Year in Film
/// - +Recommended: the five picks and their moods
/// - +Web: lists, Explore, previews, playing and opening files
/// - +Saving: writing Reel's files
///
/// State is written only by the model; views read it.
@MainActor
@Observable
final class AppModel {
    // MARK: Stored state

    var films: [FilmEntry] = []
    var drives: [Drive] = []
    /// Drive id → where it is mounted right now.
    var mounted: [String: URL] = [:]
    /// Watched, favorites, watchlist, ratings and notes.
    let personal = PersonalStore()
    /// Films you don't own yet but want to see (from Explore, lists and sets).
    var wishlist: [WishlistFilm] = []
    var wishlistIDs: Set<Int> = []
    /// Wishlist films that turned up in the library recently.
    var wishlistArrivals: [WishlistArrival] = []
    var arrivedFromWishlist: Set<Int> = []
    /// Files regrouped by hand.
    var groupingFixes = GroupingFixes()
    /// IMDb rankings, award lists and sets for the Lists hub.
    let lists: ListsStore
    let folder: ReelFolder

    /// False until Library.json is read (the window shows nothing, and no drive is scanned, until then).
    var isLoaded = false

    // MARK: Derived state (rebuilt when films, drives or mounts change)

    var items: [LibraryItem] = []
    /// Whether the library has any film (the window's root reads this, not the whole library).
    var hasFilms = false
    var genres: [String] = []
    var checkCount = 0
    /// Moods that at least one film in the library has, in a fixed order.
    var moods: [Mood] = []
    /// Film key → when it arrived, for films that are new (see `Arrivals`).
    var arrivals: [String: Date] = [:]
    /// Film key → what's wrong with its Backup copy.
    var backupGaps: [String: BackupCheck.Problem] = [:]
    /// TMDB id → library item, for people pages and lists.
    var itemsByTMDB: [Int: LibraryItem] = [:]
    /// IMDb id → library item, for IMDb and award lists.
    var itemsByIMDb: [String: LibraryItem] = [:]
    /// TMDB ids of the films you own.
    var ownedIDs: Set<Int> = []
    /// The directors, cinematographers and franchises you own films of, most owned first.
    var setCandidates: [SetCandidate] = []
    /// Sidebar counts, kept up to date instead of being counted on every redraw.
    var shelfCounts: [Shelf: Int] = [:]
    /// The film in the banner for this session.
    var featured: LibraryItem?

    // MARK: Recommended

    var recommended: [LibraryItem] = []
    var recommendedChoice: MoodChoice = .any
    var recommendedChoices: [MoodChoiceCount] = []

    // MARK: Watching

    /// Story details of unwatched films are hidden (Settings › Spoilers).
    var spoilerSafe = true
    var player: PlayerChoice = .system
    var playFullScreen = true
    /// VLC was switched to IINA once (see `switchToIINAOnce`).
    @ObservationIgnored var switchedToIINA = false
    /// Year in Film counts films seen elsewhere too.
    var yearCountsElsewhere = true
    /// Explore's Picked for You for this launch (nil until worked out).
    var explorePicks: [ExplorePick]?
    /// What Picked for You can draw from this launch, and last launch's picks (left out).
    @ObservationIgnored var exploreCandidates: [ExploreCandidate] = []
    @ObservationIgnored var explorePicksBefore: Set<Int> = []
    /// Explore's three shelves for this launch (a loved film's, a country's, a decade or hidden gems).
    @ObservationIgnored var exploreShelvesChosen: [DiscoverList]?
    /// Explore's rows that rank by quality are reordered once per launch (within a rating band) by this.
    @ObservationIgnored let exploreLaunch = UUID().uuidString
    /// Best of a year from the Lists' sources (IMDb, award winners), as films to show.
    var bestOfLists: [String: [PreviewFilm]] = [:]
    var bestOfLoading: Set<String> = []
    /// What Picked for You showed last (saved, for the next launch to leave out).
    @ObservationIgnored var explorePicksShown: [Int] = []
    var explorePicksLoading = false
    /// Picked for You has been tried this launch (until then it shows as loading).
    var explorePicksTried = false
    /// Tonight's shortlist (film keys), cleared each new evening.
    var tonight: [String] = [] {
        didSet { tonightMarks.update(tonight) }
    }
    /// The same, per film (see `isTonight`).
    @ObservationIgnored let tonightMarks = TonightMarks()
    /// Film key → until when it's kept out of Recommended.
    var notTonight: [String: Date] = [:]
    /// Why each of the five picks is there ("From the director of Stalker").
    var recommendedReasons: [String: PickReason] = [:]
    /// "How was it?", asked after a film is marked watched.
    var ratingPrompt: RatingPrompt?
    /// Wikipedia articles for Behind the Film, per TMDB id (kept for the session).
    var articles: [Int: FilmArticle] = [:]
    var articlesLoading: Set<Int> = []
    var articlesMissing: Set<Int> = []
    /// What the Camera tab read beyond the article (interviews, the cinematographer's article), per session.
    var cameraReadings: [Int: CameraReading] = [:]
    var cameraReadingsLoading: Set<Int> = []

    // MARK: Cinema mode and playing

    /// The 10-foot view for the TV (see `setCinemaMode`).
    var cinemaMode = false
    /// A trailer playing over the window.
    var trailer: TrailerRequest?
    /// The trailer fills the screen (the toolbar steps aside, as in Cinema mode).
    var trailerFillsScreen = false
    /// A film to open on the page showing (Open Film under a trailer).
    var filmToOpen: String?
    /// A Cinema mode filter panel is open (it takes Esc first).
    @ObservationIgnored var cinemaPanelOpen = false
    /// Films (TMDB ids) none of whose official trailers play inside Reel: their buttons hide.
    var unplayableTrailers: Set<Int> = []
    /// False once three films in a row had no trailer that plays inside Reel: Cinema mode then
    /// stops offering trailers for the session rather than show broken ones.
    var trailersPlayInReel = true
    @ObservationIgnored var trailerFailuresInARow = 0
    /// Official videos fetched when a film page opens (English and the original language).
    var fetchedVideos: [Int: [TMDBVideo]] = [:]
    @ObservationIgnored var enteredFullScreen = false
    @ObservationIgnored var nowPlaying: NowPlaying?
    /// VLC was started ahead of Play this session (see `warmPlayer`).
    @ObservationIgnored var playerWarmed = false
    /// How long things took, for Settings › Performance.
    @ObservationIgnored var timings: [String: Duration] = [:]

    // MARK: Explore

    /// Explore lists, loaded on demand and kept for a few hours.
    var discover: [DiscoverList: [TMDBMovieSummary]] = [:]
    var discoverLoading: Set<DiscoverList> = []
    /// "More Like This" per TMDB id, loaded when a film page opens.
    var similar: [Int: [SimilarFilm]] = [:]
    /// TMDB's recommendations per TMDB id (film id → rank), for More Like This in your library.
    var recommendationRanks: [Int: [Int: Int]] = [:]
    /// How many films have each keyword (rare shared themes count more in More Like This).
    @ObservationIgnored var keywordCounts: [String: Int] = [:]
    /// The original languages in the library, most films first (for the Language filters).
    var languages: [String] = []
    /// Films whose fun facts are being fetched right now (the tab shows a spinner).
    var funFactsLoading: Set<Int> = []

    // MARK: Status

    /// Drives being read: drive id → "Reading Films… 1,240 files".
    var reading: [String: String] = [:]
    /// Film info being fetched, counted film by film.
    var work: WorkProgress?
    /// What it just finished ("3 new films on Films"); clears itself after a few seconds.
    var finished: String?
    var notice: String?
    var hasToken = false
    /// The OMDb key pasted in Settings (never built into the app, so public builds carry no key).
    var omdbKey = ""

    // MARK: Internal bookkeeping

    @ObservationIgnored var token = ""
    @ObservationIgnored var corrections: [String: Int] = [:]
    @ObservationIgnored var featuredKey: String?
    @ObservationIgnored var lastFeatured = ""
    /// Recommended picks per chip for this session.
    @ObservationIgnored var picks: [MoodChoice: [String]] = [:]
    /// Films shuffled away this session (shown less often until Reel quits).
    @ObservationIgnored var shuffledAway: Set<String> = []
    /// Last launch's picks (avoided this launch) and this launch's (saved for the next).
    @ObservationIgnored var previousPicks: Set<String> = []
    @ObservationIgnored var launchPicks: [String] = []
    /// What your ratings say you like (see `TasteProfile`), updated with Recommended.
    @ObservationIgnored var taste = TasteProfile(rated: [])
    @ObservationIgnored var tasteSignature = 0
    @ObservationIgnored var tasteMatches: [String: TasteMatch] = [:]
    /// The evening Tonight belongs to (it starts at 6 in the morning); Cinema mode's rows are
    /// shuffled again when it changes.
    var tonightEvening = ""
    @ObservationIgnored var eveningTimer: Task<Void, Never>?
    @ObservationIgnored var badgeCache: [Int: (version: Int, badges: [ListBadge])] = [:]
    /// From the Same People and More Like This per film page (see `relatedFilms`), until the library changes.
    @ObservationIgnored var relatedCache: [String: (stamp: String, films: RelatedFilms)] = [:]
    /// Cinema mode's home rows, kept until something they show changes.
    @ObservationIgnored var cinemaRowsCache: (stamp: CinemaRowsStamp, rows: [CinemaRow])?
    /// Goes up each time the library's films are built again (a cache key).
    @ObservationIgnored var libraryVersion = 0
    /// Every film on the lists, once each (see `listPicks`), until the lists change.
    @ObservationIgnored var listPicksCache: (stamp: Int, all: [ListPick], byFilm: [String: ListPick])?
    /// The Lists hub's Start Here (see `startHere`), until something it shows changes.
    @ObservationIgnored var startHereCache: (stamp: StartHereStamp, picks: Int,
                                              value: (onDrive: [ListSuggestion], toFind: [ListSuggestion]))?
    @ObservationIgnored var personCache: [Int: TMDBPerson] = [:]
    @ObservationIgnored var discoverLoadedAt: [DiscoverList: Date] = [:]
    @ObservationIgnored var similarLoadedAt: [Int: Date] = [:]
    @ObservationIgnored var previewCache: [Int: (details: TMDBMovieDetails?, ratings: ExternalRatings?)] = [:]
    @ObservationIgnored var lookupRunning = false
    @ObservationIgnored var rerunRequested = false
    /// Moods per film, worked out once per version of its info.
    @ObservationIgnored var moodCache: [String: [Mood]] = [:]
    /// Last built items, reused when nothing about a film changed (building a search index costs time).
    @ObservationIgnored var itemCache: [String: LibraryItem] = [:]
    @ObservationIgnored var scanning: Set<String> = []
    @ObservationIgnored var mountRefresh: Task<Void, Never>?
    @ObservationIgnored var workSerial = 0
    /// A rebuild waiting to run (background changes are gathered, see `setFilms`).
    @ObservationIgnored var rebuildTask: Task<Void, Never>?
    @ObservationIgnored var lastRebuild = Date.distantPast
    /// Set candidates wait for the end of a lookup run (see `rebuild`).
    @ObservationIgnored var candidatesDirty = false
    @ObservationIgnored var finishedClear: Task<Void, Never>?
    @ObservationIgnored var saveTasks: [SaveTarget: Task<Void, Never>] = [:]
    @ObservationIgnored var lastSafetyCopyDay = ""
    @ObservationIgnored var observers: [NSObjectProtocol] = []
    @ObservationIgnored let writer = FileWriter()
    /// False when a file exists but couldn't be opened: Reel then never writes over it.
    @ObservationIgnored var notesWritable = true
    @ObservationIgnored var settingsWritable = true
    @ObservationIgnored var warnedNotesReadOnly = false

    enum SaveTarget: Hashable {
        case library, notes, settings

        /// Library.json changes in bursts while films are looked up, so it waits longer.
        var delay: Duration {
            switch self {
            case .library: .seconds(2)
            case .notes, .settings: .milliseconds(500)
            }
        }
    }

    // MARK: - Start-up

    /// Settings and notes are small and read at once (they decide what the window shows). The
    /// library, the drive check and building the grid happen in the background, so the window
    /// opens immediately even with a large library or a sleeping drive.
    init() {
        // Rendering screens (CI) works in a temporary folder with a sample library, never your own.
        let rendering = ScreenRenderer.isRequested
        folder = rendering ? ScreenRenderer.folder : ReelFolder.standard
        lists = ListsStore(folder: folder.listData)
        // Nothing in Reel uses the system web cache; keep it in memory so no cache folder appears.
        URLCache.shared = URLCache(memoryCapacity: 2_000_000, diskCapacity: 0)
        if !rendering { StorageMigration.run(into: folder) }
        folder.prepare()
        ImageStore.shared.configure(folder: folder.imageCache)
        if rendering {
            Task { await ScreenRenderer.run(self) }
            return
        }
        loadSettingsAndNotes()
        observeSystem()
        Task { await measure("Open library", label: "Opening the library") { await openLibrary() } }
    }

    private func loadSettingsAndNotes() {
        let settings = readProtected(ReelSettings.self, from: folder.settings, label: "Settings")
        settingsWritable = settings.writable
        if let value = settings.value {
            token = value.tmdbToken
            omdbKey = value.omdbKey
            drives = value.drives
            lastFeatured = value.lastFeatured
            previousPicks = Set(value.lastRecommended)
            spoilerSafe = value.spoilerSafe
            player = PlayerChoice(rawValue: value.player) ?? .system
            switchedToIINA = value.switchedToIINA
            playFullScreen = value.playFullScreen
            yearCountsElsewhere = value.yearCountsElsewhere
            explorePicksBefore = Set(value.lastExplorePicks)
            explorePicksShown = value.lastExplorePicks
            tonightEvening = value.tonightEvening
            tonight = value.tonightEvening == Evening.of(Date()) ? value.tonight : []
            notTonight = value.notTonight.filter { $0.value > Date() }
        }
        hasToken = !token.isEmpty
        switchToIINAOnce()
        askForOMDbKey()

        let notes = readProtected(PersonalFile.self, from: folder.notes, label: "Your Notes")
        notesWritable = notes.writable
        if let value = notes.value {
            personal.load(value.records)
            corrections = value.corrections
            wishlist = value.wishlist
            wishlistIDs = Set(value.wishlist.map { $0.id })
            wishlistArrivals = WishlistCleanup.record([], into: value.wishlistArrivals, now: Date())
            arrivedFromWishlist = Set(wishlistArrivals.map { $0.id })
            groupingFixes = value.groupingFixes
        }
    }

    private func openLibrary() async {
        let libraryURL = folder.library
        let knownDrives = drives
        let (library, legacy, found, prebuilt) = await Task.detached(priority: .userInitiated) {
            let library = JSONStore.load(LibraryFile.self, from: libraryURL)
            let legacy = knownDrives.isEmpty && library?.drives == nil ? JSONStore.load(LegacyLibrary.self, from: libraryURL) : nil
            let found = DriveLocator.locate(knownDrives)
            // The grid's items are built here too (main drives first, as `rebuild` does), so the
            // first redraw only reuses them.
            let backups = Set(knownDrives.filter { $0.isBackup }.map { $0.id })
            let films = library?.films ?? []
            let ordered = films.filter { !backups.contains($0.driveID) } + films.filter { backups.contains($0.driveID) }
            let prebuilt = AppModel.makeItems(films: ordered, online: Set(found.keys)) { film in
                film.tmdb.map { MoodClassifier.moods(genres: $0.genreNames, keywords: $0.keywordNames, runtime: $0.runtime) } ?? []
            }.items
            return (library, legacy, found, prebuilt)
        }.value

        var loaded = library?.films ?? []
        // Lookups that failed or found nothing last time are retried (the file-name reader may
        // have improved since).
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        for i in loaded.indices {
            let unknown = loaded[i].matchState == .manual && loaded[i].tmdb == nil
                && (loaded[i].lastLookup ?? .distantPast) < weekAgo
            if loaded[i].matchState == .failed || unknown { loaded[i].matchState = .pending }
        }
        films = loaded
        itemCache = Dictionary(prebuilt.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        if drives.isEmpty, let older = library?.drives, !older.isEmpty {
            drives = older
            scheduleSave(.settings)
            scheduleSave(.library)
        } else if drives.isEmpty, let legacy {
            drives = legacy.drives.map { DriveLocator.makeDrive(for: URL(fileURLWithPath: $0)) }
            scheduleSave(.settings)
        }
        startArrivalsForExistingDrives()

        // Drives are found and scanned only from here on, so no scan works on an empty library.
        isLoaded = true
        watchEvenings()
        applyMounts(found)
        rebuild()
        // Once more in the background: catches drives connected or added while loading, and
        // drives moved over from an older Library.json. Only newly found drives are scanned.
        refreshMounts()
        ImageStore.shared.maintain(keeping: films.isEmpty ? [] : referencedImageKeys())
        startWebRefresh()
    }

    /// Keeps everything that comes from the web current on its own: film info, ratings, award
    /// lists, IMDb rankings and sets are refreshed now and every six hours while Reel is open
    /// (each only when it's due), even when no drive is connected.
    private func startWebRefresh() {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Library info and lists side by side, so a long library refresh doesn't hold up the lists.
                async let libraryRefresh: Void = self.lookUpPending()
                async let listsRefresh: Void = self.lists.refreshStale(sets: self.setCandidates, using: self.tmdb)
                _ = await (libraryRefresh, listsRefresh)
                try? await Task.sleep(for: .seconds(6 * 3600))
                // People and previews are fetched again when next opened.
                self.personCache = [:]
                self.previewCache = [:]
            }
        }
    }

    /// Loads a file the user can't easily recreate.
    /// - Missing: fine, start empty.
    /// - Can't be opened (e.g. a disk error or an iCloud file not downloaded): left untouched and
    ///   not written to during this session.
    /// - Opened but not readable as Reel data: moved aside under a dated name (never deleted),
    ///   and a fresh file is started.
    private func readProtected<T: Decodable>(_ type: T.Type, from url: URL, label: String) -> (value: T?, writable: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return (nil, true) }
        guard let data = try? Data(contentsOf: url) else {
            notice = "“\(url.lastPathComponent)” couldn't be opened, so Reel won't change it this time. Quit and reopen Reel to try again."
            return (nil, false)
        }
        if let value = try? JSONStore.decode(type, from: data) { return (value, true) }

        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let aside = folder.root.appendingPathComponent("\(label) (unreadable \(stamp)).json")
        do {
            try fm.moveItem(at: url, to: aside)
        } catch {
            notice = "“\(url.lastPathComponent)” couldn't be read, so Reel won't change it this time."
            return (nil, false)
        }
        notice = "“\(url.lastPathComponent)” couldn't be read, so it was set aside as “\(aside.lastPathComponent)”."
            + (label == "Your Notes" ? " Copies from earlier days are in Safety Copies." : "")
        return (nil, true)
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMounts() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveAllNow() }
        })
        // Back from the player: ask whether the film was finished.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.askIfFinished() }
        })
        // Left full screen by hand (green button, ⌃⌘F): leaving Cinema mode later must not
        // put the window back into full screen.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enteredFullScreen = false }
        })
    }

    // MARK: - Status

    /// Starts counting a stretch of work ("Finding film info", 8 films). Returns a counter that
    /// child tasks call as each film is done; counts from an earlier stretch are ignored.
    func beginWork(_ label: String, done: Int = 0, total: Int) -> @Sendable () -> Void {
        workSerial += 1
        let serial = workSerial
        work = WorkProgress(label: label, done: done, total: total)
        return { [weak self] in
            Task { @MainActor in
                guard let self, self.workSerial == serial, var current = self.work else { return }
                current.done = min(current.done + 1, current.total)
                self.work = current
            }
        }
    }

    func endWork() {
        workSerial += 1
        work = nil
    }

    /// Shows a short "done" line in the sidebar for a few seconds.
    func announce(_ message: String) {
        finished = message
        finishedClear?.cancel()
        finishedClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.finished = nil
        }
    }

    // MARK: - Derived data

    /// Replaces the library's files and saves them. Background work (film info arriving in
    /// batches) has the grid rebuilt at most twice a second; `urgent` (something you just did)
    /// rebuilds at once.
    func setFilms(_ newFilms: [FilmEntry], urgent: Bool = false) {
        guard newFilms != films else { return }
        films = newFilms
        if urgent { rebuild() } else { scheduleRebuild() }
        scheduleSave(.library)
    }

    func mutateFilms(urgent: Bool = false, _ change: (inout [FilmEntry]) -> Void) {
        var copy = films
        change(&copy)
        setFilms(copy, urgent: urgent)
    }

    func scheduleRebuild() {
        guard rebuildTask == nil else { return }
        let wait = max(0, Self.rebuildInterval - Date().timeIntervalSince(lastRebuild))
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled, self.rebuildTask != nil else { return }
            self.rebuild()
        }
    }

    static let rebuildInterval: TimeInterval = 0.5

    /// The same film on several drives becomes one item; unchanged items are reused.
    /// Returns how many items had to be built anew (0: nothing about any film changed).
    nonisolated static func makeItems(films: [FilmEntry], online: Set<String>, reuse: [String: LibraryItem] = [:],
                                      moods: (FilmEntry) -> [Mood]) -> (items: [LibraryItem], built: Int) {
        var groups: [String: [FilmEntry]] = [:]
        var order: [String] = []
        for film in films {
            let key = film.personalKey
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(film)
        }
        var built = 0
        let items: [LibraryItem] = order.compactMap { key in
            guard let copies = groups[key], let first = copies.first else { return nil }
            let onlineCopy = copies.first { online.contains($0.driveID) }
            let main = onlineCopy ?? first
            // The main copy is one of the copies, so comparing the copies covers it.
            if let cached = reuse[key], cached.isOnline == (onlineCopy != nil), cached.main.id == main.id, cached.copies == copies {
                return cached
            }
            built += 1
            return LibraryItem(key: key, main: main, copies: copies, isOnline: onlineCopy != nil, moods: moods(main))
        }
        return (items, built)
    }

    /// Brings everything the views show from the library up to date. Only what actually changed
    /// is published, so views that depend on something unchanged aren't redrawn.
    func rebuild() {
        measure("Rebuild", label: "Updating what the library shows") { rebuildNow() }
    }

    private func rebuildNow() {
        rebuildTask?.cancel()
        rebuildTask = nil
        lastRebuild = Date()

        // Main drives first, so the item shows (and plays) the main copy when both are connected.
        let online = Set(mounted.keys)
        let backups = Set(drives.filter { $0.isBackup }.map { $0.id })
        let ordered = films.filter { !backups.contains($0.driveID) } + films.filter { backups.contains($0.driveID) }
        let (fresh, newlyBuilt) = Self.makeItems(films: ordered, online: online, reuse: itemCache) { moodList(for: $0) }
        if newlyBuilt > 0 || fresh.count != items.count || !zip(fresh, items).allSatisfy({ $0.id == $1.id }) {
            items = fresh
            itemCache = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            updateIndexes()
        }
        // Crew changes (a film's info refreshed) update the sets once the lookups are done.
        if candidatesDirty && !lookupRunning { updateSetCandidates() }
        updateArrivals()
        updateBackupGaps(backups)
        recount()
        updateFeatured()
        updateRecommended()
    }

    /// Lookups, genres and sets, after the items changed.
    private func updateIndexes() {
        if hasFilms == items.isEmpty { hasFilms = !items.isEmpty }
        // Films' info may have changed: fits to your ratings are worked out again.
        tasteMatches = [:]
        relatedCache = [:]
        libraryVersion += 1
        keywordCounts = Likeness.keywordCounts(items.map { $0.likeness })
        var languageCounts: [String: Int] = [:]
        for item in items { if let language = item.language { languageCounts[language, default: 0] += 1 } }
        let newLanguages = languageCounts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { $0.key }
        if newLanguages != languages { languages = newLanguages }
        let newGenres = Set(items.flatMap { $0.genres }).sorted()
        if newGenres != genres { genres = newGenres }
        let newCheckCount = items.filter { $0.main.matchState.needsCheck }.count
        if newCheckCount != checkCount { checkCount = newCheckCount }
        let present = Set(items.flatMap { $0.moods })
        let newMoods = Mood.allCases.filter { present.contains($0) }
        if newMoods != moods { moods = newMoods }

        var byTMDB: [Int: LibraryItem] = [:]
        var byIMDb: [String: LibraryItem] = [:]
        var sure = Set<Int>()
        for item in items {
            guard let details = item.main.tmdb else { continue }
            byTMDB[details.id] = item
            if let imdb = details.imdbID, !imdb.isEmpty { byIMDb[imdb] = item }
            if !item.main.matchState.needsCheck { sure.insert(details.id) }
        }
        itemsByTMDB = byTMDB
        itemsByIMDb = byIMDb
        let owned = Set(byTMDB.keys)
        // Sets come from the crew of every film: worked out at once when the films you own
        // change, otherwise once film info has finished updating.
        if owned != ownedIDs || setCandidates.isEmpty {
            ownedIDs = owned
            updateSetCandidates()
        } else {
            candidatesDirty = true
        }
        removeArrivedWishes(owned: sure)
    }

    private func updateSetCandidates() {
        candidatesDirty = false
        let candidates = FilmSets.candidates(items.compactMap { item in
            item.main.tmdb.map { (collection: $0.collection, crew: $0.credits?.crew ?? []) }
        })
        if candidates.map({ "\($0.kind)\($0.id)\($0.owned)" }) != setCandidates.map({ "\($0.kind)\($0.id)\($0.owned)" }) {
            setCandidates = candidates
        }
    }

    private func updateArrivals() {
        let since = Dictionary(drives.map { ($0.id, $0.arrivalsSince) }, uniquingKeysWith: { first, _ in first })
        let now = Date()
        var result: [String: Date] = [:]
        for item in items {
            let copies = item.copies.map {
                Arrivals.Copy(addedAt: $0.addedAt, since: since[$0.driveID] ?? nil, regrouped: groupingFixes.films.contains($0.relativePath))
            }
            if let date = Arrivals.arrival(of: copies, now: now) { result[item.id] = date }
        }
        if result != arrivals { arrivals = result }
    }

    private func updateBackupGaps(_ backups: Set<String>) {
        var result: [String: BackupCheck.Problem] = [:]
        for gap in BackupCheck.gaps(in: films, backupDrives: backups) where result[gap.key] == nil {
            result[gap.key] = gap.problem
        }
        if result != backupGaps { backupGaps = result }
    }

    /// Counts for the sidebar.
    func count(_ shelf: Shelf) -> Int {
        shelfCounts[shelf] ?? 0
    }

    /// Recounts the sidebar after library changes and watched / watchlist / favorite changes.
    /// Only publishes when a number actually changed.
    func recount() {
        var counts: [Shelf: Int] = [.all: items.count, .needsCheck: checkCount, .wishlist: wishlist.count,
                                    .notOnBackup: backupGaps.count]
        var watched = 0, watchlist = 0, favorites = 0, new = 0
        for item in items {
            let key = item.id
            let isWatched = personal.watchedKeys.contains(key)
            if isWatched { watched += 1 }
            if personal.watchlistKeys.contains(key) { watchlist += 1 }
            if personal.favoriteKeys.contains(key) { favorites += 1 }
            if !isWatched && arrivals[key] != nil { new += 1 }
            for genre in item.genres { counts[.genre(genre), default: 0] += 1 }
            for driveID in Set(item.copies.map { $0.driveID }) { counts[.drive(driveID), default: 0] += 1 }
        }
        counts[.watched] = watched
        counts[.unwatched] = items.count - watched
        counts[.watchlist] = watchlist
        counts[.favorites] = favorites
        counts[.newArrivals] = new
        if counts != shelfCounts { shelfCounts = counts }
    }

    private func moodList(for film: FilmEntry) -> [Mood] {
        guard let d = film.tmdb else { return [] }
        let cacheKey = "\(d.id)|\(film.infoVersion)|\(d.keywords?.keywords.count ?? 0)"
        if let cached = moodCache[cacheKey] { return cached }
        let result = MoodClassifier.moods(genres: d.genreNames, keywords: d.keywordNames, runtime: d.runtime)
        moodCache[cacheKey] = result
        return result
    }

    func itemMoods(forKey key: String) -> [Mood] {
        itemCache[key]?.moods ?? []
    }

    func item(forKey key: String) -> LibraryItem? {
        itemCache[key]
    }

    /// Other films in your library from the same collection (e.g. Blade Runner Collection).
    func collectionItems(for film: FilmEntry) -> [LibraryItem] {
        guard let collection = film.tmdb?.collection?.id else { return [] }
        let key = film.personalKey
        return items
            .filter { $0.id != key && $0.main.tmdb?.collection?.id == collection }
            .sorted { ($0.main.displayYear ?? 0) < ($1.main.displayYear ?? 0) }
    }

    /// Films in your library most like this one (see `Likeness`): what viewers of it went on to
    /// like on TMDB (once the film page has loaded it), the people who made it, rare shared
    /// themes, tone, genre, and the same kind of audience.
    func similarItems(for film: FilmEntry, excluding excluded: Set<String> = [], limit: Int = 10) -> [LibraryItem] {
        guard let me = itemCache[film.personalKey] else { return [] }
        let recommended = film.tmdb.flatMap { recommendationRanks[$0.id] } ?? [:]
        let counts = keywordCounts
        let total = items.count
        let scored: [(item: LibraryItem, score: Double)] = items.compactMap { other in
            guard other.id != me.id, !excluded.contains(other.id) else { return nil }
            let score = Likeness.score(me.likeness, other.likeness, recommended: recommended,
                                       keywordCounts: counts, libraryCount: total)
            return score >= Likeness.threshold ? (other, score) : nil
        }
        return scored.sorted { $0.score > $1.score }.prefix(limit).map { $0.item }
    }

    /// The films of one sidebar shelf, searched (mood and length are filtered by the grid, which
    /// also counts them). With a search, best matches come first.
    func shelfItems(_ shelf: Shelf, matching query: String, sortedBy sort: LibrarySort) -> [LibraryItem] {
        var list: [LibraryItem]
        var order = sort
        switch shelf {
        case .all, .recommended, .explore, .lists, .wishlist, .yearInFilm, .tonight: list = items
        case .newArrivals:
            list = items.filter { arrivals[$0.id] != nil && !personal.watchedKeys.contains($0.id) }
            order = .added
        case .unwatched: list = items.filter { !personal.watchedKeys.contains($0.id) }
        case .watchlist: list = items.filter { personal.watchlistKeys.contains($0.id) }
        case .favorites: list = items.filter { personal.favoriteKeys.contains($0.id) }
        case .watched: list = items.filter { personal.watchedKeys.contains($0.id) }
        case .needsCheck: list = items.filter { $0.main.matchState.needsCheck }
        case .notOnBackup: list = items.filter { backupGaps[$0.id] != nil }
        case .genre(let genre): list = items.filter { $0.genres.contains(genre) }
        case .drive(let id): list = items.filter { item in item.copies.contains { copy in copy.driveID == id } }
        }

        switch order {
        case .title: list.sort { $0.sortTitle < $1.sortTitle }
        case .year: list.sort { ($0.main.displayYear ?? 0) > ($1.main.displayYear ?? 0) }
        case .rating: list.sort { ($0.score ?? 0) > ($1.score ?? 0) }
        case .added: list.sort { $0.firstAdded > $1.firstAdded }
        case .runtime: list.sort { ($0.runtime ?? .max) < ($1.runtime ?? .max) }
        }

        let terms = TitleSimilarity.normalize(query).split(separator: " ").map { String($0) }
        guard !terms.isEmpty else { return list }
        func ranked(allowTypos: Bool) -> [LibraryItem] {
            // Stable: equal relevance keeps the chosen sort order.
            list.enumerated()
                .compactMap { pair -> (Int, Int, LibraryItem)? in
                    let score = pair.element.search.relevance(terms, allowTypos: allowTypos)
                    return score > 0 ? (score, pair.offset, pair.element) : nil
                }
                .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
                .map { $0.2 }
        }
        let exact = ranked(allowTypos: false)
        return exact.count >= 3 ? exact : ranked(allowTypos: true)
    }

    /// Picks the banner film once per launch (never the same as last time). Runs in `rebuild()`,
    /// not while drawing. Only a well-rated, unwatched, connected film is kept for the session;
    /// until one exists (drive not connected yet, info still loading) a stand-in is shown.
    private func updateFeatured() {
        if let key = featuredKey, let item = itemCache[key] {
            if featured != item { featured = item }
            return
        }
        let withArt = items.filter { $0.main.tmdb?.backdropPath != nil }
        let preferred = withArt.filter { $0.isOnline && !personal.watchedKeys.contains($0.id) }
        if !preferred.isEmpty {
            let pool = Array(preferred.sorted { ($0.score ?? 0) > ($1.score ?? 0) }.prefix(15))
            let fresh = pool.filter { $0.id != lastFeatured }
            guard let pick = (fresh.isEmpty ? pool : fresh).randomElement() else { return }
            featuredKey = pick.id
            featured = pick
            if lastFeatured != pick.id {
                lastFeatured = pick.id
                scheduleSave(.settings)
            }
        } else if let current = featured, let updated = withArt.first(where: { $0.id == current.id }) {
            if updated != current { featured = updated }
        } else if featured == nil || !withArt.contains(where: { $0.id == featured?.id }) {
            featured = withArt.randomElement()
        }
    }
}
#endif
