#if os(macOS)
import AppKit
import ReelCore

/// The app films open in.
enum PlayerChoice: String, CaseIterable, Identifiable {
    case system, iina, vlc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Default App"
        case .iina: "IINA"
        case .vlc: "VLC"
        }
    }

    private var bundleID: String? {
        switch self {
        case .system: nil
        case .iina: "com.colliderli.iina"
        case .vlc: Self.vlcBundleID
        }
    }

    static let vlcBundleID = "org.videolan.vlc"

    /// Where the app is, when it's installed.
    var appURL: URL? {
        bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    var isInstalled: Bool { self == .system || appURL != nil }

    /// The players on this Mac, looked up once per launch (menus are drawn often).
    static let installed: [PlayerChoice] = allCases.filter { $0.isInstalled }
}

/// "How was it?" after marking a film watched.
struct RatingPrompt: Identifiable, Equatable {
    /// The film's personal key.
    let id: String
    let filmID: String
    /// Coming back from the player: ask "Did you finish it?" before the stars.
    var askFinished = false
}

/// Watching: spoilers, tonight's shortlist, playing, rating, and reading about films.
extension AppModel {
    // MARK: - Spoilers

    /// Story details of this film are hidden: spoiler-safe is on and you haven't watched it.
    func hidesSpoilers(for film: FilmEntry) -> Bool {
        spoilerSafe && !isWatched(film.personalKey)
    }

    func setSpoilerSafe(_ on: Bool) {
        spoilerSafe = on
        scheduleSave(.settings)
    }

    // MARK: - Tonight

    /// Tonight's shortlist (the Tonight page calls `startNewEveningIfNeeded` first: it clears at 6 in the morning).
    var tonightItems: [LibraryItem] {
        tonight.compactMap { itemCache[$0] }
    }

    /// Whether a film is on tonight's shortlist. A view that asks redraws when this film's place
    /// on the list changes, not when other films come and go.
    func isTonight(_ key: String) -> Bool {
        tonightMarks.isOn(key)
    }

    /// Adds a film ("Not Yet" when asked whether a film was finished).
    func addToTonight(_ key: String) {
        startNewEveningIfNeeded()
        guard !tonight.contains(key) else { return }
        tonight.append(key)
        scheduleSave(.settings)
    }

    func toggleTonight(_ key: String) {
        startNewEveningIfNeeded()
        if let i = tonight.firstIndex(of: key) {
            tonight.remove(at: i)
        } else {
            tonight.append(key)
        }
        scheduleSave(.settings)
    }

    func clearTonight() {
        tonight = []
        scheduleSave(.settings)
    }

    /// Clears the shortlist at 6 in the morning while Reel is open, then waits for the next one.
    func watchEvenings() {
        startNewEveningIfNeeded()
        eveningTimer?.cancel()
        eveningTimer = Task { [weak self] in
            var next = Calendar.current.date(bySettingHour: 6, minute: 0, second: 5, of: Date()) ?? Date()
            if next <= Date() { next = next.addingTimeInterval(86_400) }
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.watchEvenings()
        }
    }

    /// A new evening starts with an empty shortlist.
    func startNewEveningIfNeeded() {
        let evening = Evening.of(Date())
        guard evening != tonightEvening else { return }
        tonightEvening = evening
        if !tonight.isEmpty { tonight = [] }
        scheduleSave(.settings)
    }

    // MARK: - Not tonight

    static let notTonightDays = 14

    /// Keeps a film out of Recommended for two weeks; its place is filled at once.
    func notTonight(_ key: String) {
        notTonight[key] = Date().addingTimeInterval(Double(Self.notTonightDays) * 86_400)
        scheduleSave(.settings)
        dropFromPicks(key)
    }

    func isResting(_ key: String) -> Bool {
        (notTonight[key] ?? .distantPast) > Date()
    }

    // MARK: - Rating

    /// Saves "How was it?": stars, and a line added to the film's notes.
    func rate(_ prompt: RatingPrompt, stars: Int?, line: String) {
        guard let film = film(id: prompt.filmID) ?? films.first(where: { $0.personalKey == prompt.id }) else { return }
        if let stars { setRating(stars, for: film) }
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let note = record(for: film).note
            setNote(note.isEmpty ? text : note + "\n\n" + text, for: film)
        }
        ratingPrompt = nil
    }

    // MARK: - Playing

    func setPlayer(_ choice: PlayerChoice) {
        player = choice
        // A player chosen by hand is kept (no switch to IINA after it).
        switchedToIINA = true
        scheduleSave(.settings)
    }

    /// Films play in IINA rather than VLC: IINA plays HDR on the TV. Done once, when IINA is
    /// installed; picking VLC again in Settings is kept.
    func switchToIINAOnce() {
        guard player == .vlc, !switchedToIINA, PlayerChoice.iina.isInstalled else { return }
        player = .iina
        switchedToIINA = true
        scheduleSave(.settings)
        // A notice stays until it's closed (a line in the sidebar would pass during the first scan).
        notice = "Films now play in IINA, which plays HDR on your TV. VLC is still in Settings › Watching."
    }

    static let omdbNotice = "IMDb, Rotten Tomatoes and Metacritic ratings need your free OMDb key. Paste it once in Settings › Ratings (⌘,)."

    /// Builds carry no OMDb key, so until one is pasted in Settings each launch says how ratings come back.
    func askForOMDbKey() {
        guard hasToken, omdbKey.isEmpty, notice == nil else { return }
        notice = Self.omdbNotice
    }

    func setPlayFullScreen(_ on: Bool) {
        playFullScreen = on
        scheduleSave(.settings)
    }

    /// The film's different files on connected drives (a 4K and a 1080p copy, an extended cut).
    /// The same file on the Backup isn't another version.
    func versions(of film: FilmEntry) -> [FilmEntry] {
        var seen = Set<String>()
        return copies(of: film).filter { fileURL($0) != nil && seen.insert("\($0.fileName)|\($0.size)").inserted }
    }

    /// "4K · HDR", or the file name when the name says nothing about quality.
    func versionTitle(_ copy: FilmEntry) -> String {
        copy.qualityLabel ?? copy.fileName
    }

    /// Opens the film (read only) in the chosen player, or the one set in Settings. IINA and VLC
    /// start full screen (Settings › Watching, always in Cinema mode). Reel asks "Did you finish
    /// it?" when you come back.
    func play(_ film: FilmEntry, version: FilmEntry? = nil, with choice: PlayerChoice? = nil) {
        guard let copy = version ?? onlineCopy(of: film), let url = fileURL(copy) else { return }
        let app = choice ?? player
        let fullScreen = playFullScreen || cinemaMode
        notePlaying(film)
        if app == .iina, fullScreen, let link = Self.iinaFullScreenURL(for: url), NSWorkspace.shared.open(link) {
            return
        }
        if let appURL = app.appURL {
            let configuration = NSWorkspace.OpenConfiguration()
            // VLC only reads this when it isn't running yet; once the film is open it's asked
            // to go full screen as well, which works either way.
            if app == .vlc, fullScreen { configuration.arguments = ["--fullscreen"] }
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                guard error == nil, app == .vlc, fullScreen else { return }
                Self.askVLCForFullScreen {
                    Task { @MainActor in
                        self.notice = "VLC opened in a window: Reel isn't allowed to control VLC. Allow it in System Settings › Privacy & Security › Automation."
                    }
                }
            }
        } else {
            if app != .system { notice = "\(app.title) isn't installed, so the film opened in your default player." }
            NSWorkspace.shared.open(url)
        }
    }

    /// VLC takes a few seconds to start (it loads all its modules first). With VLC as the player,
    /// it's started out of sight the first time a film page opens (or Cinema mode does), so
    /// Play then opens the film at once. Once a session, and never when it's already running.
    func warmPlayer() {
        guard player == .vlc, !playerWarmed, let appURL = PlayerChoice.vlc.appURL else { return }
        playerWarmed = true
        guard NSRunningApplication.runningApplications(withBundleIdentifier: PlayerChoice.vlcBundleID).isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        // Read only at launch, so only for the standing setting: Cinema mode's full screen is
        // asked for when each film opens (askVLCForFullScreen).
        if playFullScreen { configuration.arguments = ["--fullscreen"] }
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    /// Asks VLC (through its AppleScript support) to go full screen once the film plays. VLC says
    /// it's playing a moment before its video window exists, and a request before then is lost,
    /// so it waits a little more and asks until VLC is full screen. macOS asks once whether Reel
    /// may control VLC; if that's declined the film plays in a window and `refused` says so.
    nonisolated static func askVLCForFullScreen(refused: @escaping @Sendable () -> Void) {
        // Stops as soon as VLC is quit (asking a closed VLC would open it again); a refusal
        // (-1743) ends it at once.
        let script = """
        repeat 60 times
            if not (application "VLC" is running) then return
            try
                tell application "VLC" to if playing then exit repeat
            on error message number code
                if code is -1743 then error message number code
            end try
            delay 0.25
        end repeat
        delay 0.8
        repeat 6 times
            if not (application "VLC" is running) then return
            tell application "VLC"
                if fullscreen mode then exit repeat
                set fullscreen mode to true
            end tell
            delay 0.7
        end repeat
        """
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        process.terminationHandler = { _ in
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // -1743: not allowed to send Apple events to VLC.
            if message.contains("-1743") { refused() }
        }
        try? process.run()
    }

    /// IINA's own link for opening a file full screen.
    static func iinaFullScreenURL(for file: URL) -> URL? {
        guard let encoded = file.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "iina://open?url=\(encoded)&full_screen=1")
    }

    // MARK: - Reading

    /// The film's Wikipedia article for Behind the Film (fetched when the tab opens, kept for the session).
    func loadArticle(for film: FilmEntry) async {
        guard let id = film.tmdb?.id, articles[id] == nil, !articlesLoading.contains(id) else { return }
        articlesLoading.insert(id)
        defer { articlesLoading.remove(id) }
        if film.funFacts == nil { await loadFunFacts(for: film) }
        let current = self.film(id: film.id) ?? film
        guard let facts = current.funFacts else { return } // offline: tried again next time the tab opens
        guard let title = facts.articleTitle else {
            articlesMissing.insert(id)
            return
        }
        do {
            if let article = try await WikipediaClient().article(title: title), !article.isEmpty {
                articles[id] = article
            } else {
                articlesMissing.insert(id)
            }
        } catch {
            // Offline or Wikipedia busy: nothing is remembered, so opening the tab again retries.
        }
    }

    /// The interviews and craft articles about how the film was shot, and the cinematographer's
    /// own article, for the Cinematography tab: once per session. Nothing found at all (offline) is tried
    /// again next time the tab opens.
    func loadCameraReading(for film: FilmEntry) async {
        guard let details = film.tmdb, cameraReadings[details.id] == nil, !cameraReadingsLoading.contains(details.id) else { return }
        cameraReadingsLoading.insert(details.id)
        defer { cameraReadingsLoading.remove(details.id) }
        if film.funFacts == nil { await loadFunFacts(for: film) }
        let current = self.film(id: film.id) ?? film
        let reading = await CameraSourcesClient().read(articleTitle: current.funFacts?.articleTitle, filmTitle: details.title,
                                                       cinematographers: details.cinematographers)
        guard !reading.sources.isEmpty || !reading.more.isEmpty || reading.cinematographer != nil else { return }
        cameraReadings[details.id] = reading
    }

    /// Searches for the film's reviews and essays on sites that have no free data to read in Reel.
    func readMoreLinks(for film: FilmEntry) -> [(title: String, url: URL)] {
        let words = [film.displayTitle, film.displayYear.map(String.init) ?? ""].joined(separator: " ")
        func search(_ site: String) -> URL? {
            var parts = URLComponents(string: "https://duckduckgo.com/")
            parts?.queryItems = [URLQueryItem(name: "q", value: "site:\(site) \(words)")]
            return parts?.url
        }
        var links: [(title: String, url: URL)] = []
        if let url = search("rogerebert.com") { links.append(("Roger Ebert's review", url)) }
        if let url = search("criterion.com/current") { links.append(("Criterion essays", url)) }
        if let url = search("bfi.org.uk") { links.append(("BFI", url)) }
        if let url = search("sensesofcinema.com") { links.append(("Senses of Cinema", url)) }
        if let id = film.tmdb?.id, let url = URL(string: "https://letterboxd.com/tmdb/\(id)") {
            links.append(("Letterboxd", url))
        }
        if let imdb = film.tmdb?.imdbID, let url = URL(string: "https://www.imdb.com/title/\(imdb)/") {
            links.append(("IMDb", url))
        }
        return links
    }

    /// Where a film's full technical specifications and its cinematographer's interviews are
    /// (the Cinematography tab): IMDb's, interviews, ShotOnWhat's and American Cinematographer's articles.
    func cameraLinks(for film: FilmEntry) -> [(title: String, url: URL)] {
        let words = [film.displayTitle, film.displayYear.map(String.init) ?? ""].joined(separator: " ")
        func search(_ site: String) -> URL? {
            var parts = URLComponents(string: "https://duckduckgo.com/")
            parts?.queryItems = [URLQueryItem(name: "q", value: "site:\(site) \(words)")]
            return parts?.url
        }
        var links: [(title: String, url: URL)] = []
        if let imdb = film.tmdb?.imdbID, let url = URL(string: "https://www.imdb.com/title/\(imdb)/technical/") {
            links.append(("IMDb Technical Specs", url))
        }
        // Interviews with the director of photography about the film's look.
        if let dp = film.tmdb?.cinematographers.first {
            var parts = URLComponents(string: "https://duckduckgo.com/")
            parts?.queryItems = [URLQueryItem(name: "q", value: "\"\(dp)\" \(film.displayTitle) cinematography lighting interview")]
            if let url = parts?.url { links.append(("Interviews with \(dp)", url)) }
        }
        if let url = search("shotonwhat.com") { links.append(("ShotOnWhat", url)) }
        if let url = search("theasc.com") { links.append(("American Cinematographer", url)) }
        return links
    }

    // MARK: - Badges

    /// The lists the film is on (from the Lists hub's data), wins first. Worked out once per film
    /// and kept until the lists change.
    func badges(for film: FilmEntry) -> [ListBadge] {
        guard let details = film.tmdb else { return [] }
        // Reading the award lists here also redraws the page when they arrive.
        let version = lists.awards.values.reduce(0) { $0 + $1.count } + (lists.imdbIsReady ? 1 : 0)
        if let cached = badgeCache[details.id], cached.version == version { return cached.badges }
        var all: [(kind: FilmListKind, films: [ListFilm])] = AwardList.allCases.map { (.award($0), lists.awards[$0] ?? []) }
        all.append((.sightAndSound, SightAndSound.films))
        all.append((.imdbAllTime, lists.films(for: .imdbAllTime)))
        let found = ListBadges.badges(imdbID: details.imdbID, tmdbID: details.id, title: film.displayTitle,
                                      year: film.displayYear, lists: all, tmdbIDOf: { self.lists.tmdbID($0) })
        badgeCache[details.id] = (version, found)
        return found
    }
}
#endif
