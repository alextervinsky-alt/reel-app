#if os(macOS)
import AppKit
import OSLog
import ReelCore

/// The film that was opened in the player, to ask about it when you come back to Reel.
struct NowPlaying {
    let key: String
    let filmID: String
    let startedAt: Date
    let runtime: Int?

    /// Long enough to have watched it: 60% of the running time, at least 20 minutes.
    var minimumWatch: TimeInterval { max(20 * 60, Double(runtime ?? 90) * 60 * 0.6) }
}

/// A row of posters in Cinema mode.
struct CinemaRow: Identifiable {
    let id: String
    let title: String
    let items: [LibraryItem]
}

/// Everything Cinema mode's home rows depend on (see `AppModel.cinemaRows`).
struct CinemaRowsStamp: Equatable {
    let library: Int
    let films: Int
    let choice: MoodChoice
    let tonight: [String]
    let watched: Int
    /// When each was watched (Watch Again leaves out films watched lately).
    let watchedOn: Int
    let watchlist: Int
    let ratings: Int
    let recommended: [String]
    let arrivals: Int
    let evening: String
}

/// Cinema mode, playing on the TV, trailers and timings.
extension AppModel {
    // MARK: - Cinema mode

    /// Turns Cinema mode on or off. On also makes the window full screen; off undoes that only
    /// when Cinema mode was what made it full screen.
    func setCinemaMode(_ on: Bool) {
        guard on != cinemaMode else { return }
        cinemaMode = on
        // The trailer player gets ready in the background, so a trailer opens in about a second.
        if on {
            TrailerEngine.shared.warm()
            warmPlayer()
        }
        guard let window = Self.libraryWindow else { return }
        // Out of the search field, so the arrow keys and Return reach the view on screen.
        window.makeFirstResponder(nil)
        let isFullScreen = window.styleMask.contains(.fullScreen)
        if on, !isFullScreen {
            enteredFullScreen = true
            // A moment later, once Cinema mode is on screen: the window then goes full screen
            // with Cinema mode's toolbar (hidden until the pointer reaches the top).
            Task {
                try? await Task.sleep(for: .milliseconds(80))
                if cinemaMode, !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            }
        } else if !on, enteredFullScreen {
            enteredFullScreen = false
            if isFullScreen { window.toggleFullScreen(nil) }
        }
    }

    /// The library window (not Settings).
    static var libraryWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("library") == true } ?? NSApp.mainWindow
    }

    /// The rows of Cinema mode's home, always in the same order, at most 15: Tonight,
    /// Recommended, New Arrivals, Like the Films You Loved, Watchlist, up to 6 genres, up to 3
    /// languages, Under 100 Minutes, Acclaimed, Watch Again. The mood chip (shared with
    /// Recommended) narrows every row except Tonight. Rows sorted by rating look different each
    /// evening without losing their order (`EveningOrder`).
    /// Worked out again only when something they show changes: everything that can change them
    /// is read for the stamp, so the home page also redraws then (and only then).
    func cinemaRows(for choice: MoodChoice) -> [CinemaRow] {
        let stamp = CinemaRowsStamp(
            library: libraryVersion, films: items.count, choice: choice, tonight: tonight,
            watched: personal.watchedKeys.hashValue, watchedOn: personal.watchedDates.hashValue, watchlist: personal.watchlistKeys.hashValue,
            ratings: personal.ratingsVersion, recommended: recommended.map(\.id), arrivals: arrivals.hashValue,
            evening: tonightEvening)
        if let cached = cinemaRowsCache, cached.stamp == stamp { return cached.rows }
        let rows = buildCinemaRows(for: choice)
        cinemaRowsCache = (stamp, rows)
        return rows
    }

    private func buildCinemaRows(for choice: MoodChoice) -> [CinemaRow] {
        let pool = items.filter { $0.main.tmdb != nil && !personal.watchedKeys.contains($0.id) && Self.fits($0, choice) }
        // Read here, so the rows take the new evening's order at 6 in the morning.
        let evening = tonightEvening.isEmpty ? Evening.of(Date()) : tonightEvening
        let againAfter = Date().addingTimeInterval(-182 * 86_400)
        // Best first, in half-point bands shuffled for the evening (unrated films last).
        func best(_ list: [LibraryItem]) -> [LibraryItem] {
            EveningOrder.arrange(list, evening: evening, id: { $0.id }, score: { $0.score })
        }
        func row(_ id: String, _ title: String, _ list: [LibraryItem]) -> CinemaRow? {
            list.isEmpty ? nil : CinemaRow(id: id, title: title, items: Array(list.prefix(40)))
        }

        let head = [
            row("tonight", "Tonight", tonightItems),
            row("recommended", "Recommended for You", recommended),
            row("new", "New Arrivals", pool.filter { arrivals[$0.id] != nil }
                .sorted { (arrivals[$0.id] ?? .distantPast) > (arrivals[$1.id] ?? .distantPast) }),
            row("loved", "Like the Films You Loved", pool
                .compactMap { item in tasteMatch(item).flatMap { $0.score >= 1.5 ? (item, $0.score) : nil } }
                .sorted { $0.1 > $1.1 }.map { $0.0 }),
            row("watchlist", "Your Watchlist", best(pool.filter { personal.watchlistKeys.contains($0.id) })),
        ].compactMap { $0 }

        let tail = [
            choice == .short ? nil : row("short", "Under 100 Minutes", best(pool.filter { ($0.runtime ?? .max) < Recommender.shortRuntime })),
            row("acclaimed", "Acclaimed and Unwatched", best(pool)),
            // Films you loved and haven't seen for half a year or more (a film marked watched
            // last week isn't one to watch again yet).
            row("again", "Watch Again", items
                .filter { personal.watchedKeys.contains($0.id) && Self.fits($0, choice) }
                .compactMap { item -> (LibraryItem, Int)? in
                    let record = personal.record(forKey: item.id)
                    let stars = record.rating ?? (record.favorite ? 4 : 0)
                    let longAgo = (record.watchedOn ?? .distantPast) < againAfter
                    return stars >= 4 && longAgo ? (item, stars) : nil
                }
                .sorted { $0.1 > $1.1 }.map { $0.0 }),
        ].compactMap { $0 }

        // Languages: non-English, enough unwatched films (Estonian from fewer), largest first.
        var byLanguage: [String: [LibraryItem]] = [:]
        for item in pool {
            if let language = item.language, language != "en" { byLanguage[language, default: []].append(item) }
        }
        let languageRows = byLanguage
            .filter { $0.value.count >= ($0.key == "et" ? 3 : 6) }
            .sorted { ($0.key == "et" ? 1 : 0, $0.value.count) > ($1.key == "et" ? 1 : 0, $1.value.count) }
            .prefix(3)
            .compactMap { row("language-\($0.key)", "\(FilmLanguage.name($0.key)) Films", best($0.value)) }

        // Genres fill what's left of the 15, at most 6.
        var byGenre: [String: [LibraryItem]] = [:]
        for item in pool {
            for genre in item.genres { byGenre[genre, default: []].append(item) }
        }
        let room = min(6, max(0, 15 - head.count - tail.count - languageRows.count))
        let genreRows = byGenre
            .filter { $0.value.count >= 5 }
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
            .prefix(room)
            .compactMap { row("genre-\($0.key)", Self.genreRowTitles[$0.key] ?? $0.key, best($0.value)) }

        return head + genreRows + languageRows + tail
    }

    /// The rows under a film page: From the Same People, then More Like This without those films
    /// (or the ones in `excluding`, such as the film's series). Worked out once and kept until the
    /// library, TMDB's recommendations for the film or what you've watched change, so redrawing
    /// the page (Tonight, a rating, fun facts arriving) costs nothing.
    func relatedFilms(to film: FilmEntry, excluding excluded: Set<String> = [], limit: Int) -> RelatedFilms {
        // Read here, so the page redraws when any of them change.
        let stamp = "\(items.count)|\(film.tmdb.flatMap { recommendationRanks[$0.id]?.hashValue } ?? 0)|"
            + "\(personal.watchedKeys.count)|\(excluded.sorted().joined(separator: ","))"
        let key = "\(film.personalKey)|\(limit)"
        if let cached = relatedCache[key], cached.stamp == stamp { return cached.films }
        let people = samePeople(as: film)
        let similar = similarItems(for: film, excluding: excluded.union(people.map { $0.item.id }), limit: limit)
        let films = RelatedFilms(people: people, similar: similar)
        relatedCache[key] = (stamp, films)
        return films
    }

    /// Other films in the library by the people who made this one, each with how it's connected
    /// (director first, then writer, cinematographer, composer, lead actors). Unwatched first, at
    /// most 12.
    private func samePeople(as film: FilmEntry) -> [(item: LibraryItem, connection: Connection)] {
        guard let me = itemCache[film.personalKey] else { return [] }
        let found = items.compactMap { other -> (item: LibraryItem, connection: Connection)? in
            guard other.id != me.id, let connection = SamePeople.connection(of: me.likeness, to: other.likeness) else { return nil }
            return (other, connection)
        }
        return Array(found.sorted { a, b in
            let watchedA = personal.watchedKeys.contains(a.item.id), watchedB = personal.watchedKeys.contains(b.item.id)
            if watchedA != watchedB { return !watchedA }
            return (a.item.score ?? 0) > (b.item.score ?? 0)
        }.prefix(12))
    }

    /// The other films in the library shot by them, in the order they were made (the Cinematography
    /// tab); worked out once per library version.
    func filmsShot(by cinematographers: [String], besides film: FilmEntry) -> [LibraryItem] {
        // Read here, so the page redraws when the library changes.
        guard !items.isEmpty else { return [] }
        let key = cinematographers.joined(separator: "|") + "|" + film.personalKey
        if let cached = shotByCache[key], cached.version == libraryVersion { return cached.items }
        let wanted = Set(cinematographers)
        let found = items
            .filter { $0.id != film.personalKey && !wanted.isDisjoint(with: $0.main.tmdb?.cinematographers ?? []) }
            .sorted { ($0.main.displayYear ?? 0) < ($1.main.displayYear ?? 0) }
        shotByCache[key] = (libraryVersion, found)
        return found
    }

    /// The films for Cinema mode's All Films: search, sort, mood, length, and unwatched only.
    func cinemaLibrary(matching query: String, sort: LibrarySort, mood: Mood?, length: LengthBand, language: String?,
                       unwatchedOnly: Bool) -> [LibraryItem] {
        shelfItems(unwatchedOnly ? .unwatched : .all, matching: query, sortedBy: sort).filter { item in
            (mood.map { item.moods.contains($0) } ?? true) && length.contains(item.runtime)
                && (language.map { item.language == $0 } ?? true)
        }
    }

    static func fits(_ item: LibraryItem, _ choice: MoodChoice) -> Bool {
        switch choice {
        case .any: true
        case .mood(let mood): item.moods.contains(mood)
        case .short: (item.runtime ?? .max) < Recommender.shortRuntime
        }
    }

    static let genreRowTitles = [
        "Action": "Action", "Adventure": "Adventures", "Animation": "Animated Films", "Comedy": "Comedies",
        "Crime": "Crime", "Documentary": "Documentaries", "Drama": "Dramas", "Family": "For the Whole Family",
        "Fantasy": "Fantasy", "History": "History", "Horror": "Horror", "Music": "Music Films", "Mystery": "Mysteries",
        "Romance": "Romance", "Science Fiction": "Science Fiction", "Thriller": "Thrillers", "War": "War Films",
        "Western": "Westerns",
    ]

    // MARK: - After the film

    /// Remembers what was opened in the player (see `askIfFinished`).
    func notePlaying(_ film: FilmEntry) {
        nowPlaying = NowPlaying(key: film.personalKey, filmID: film.id, startedAt: Date(), runtime: film.tmdb?.runtime)
    }

    /// Coming back to Reel after watching long enough: "Did you finish it?". Too soon (a pause,
    /// a look at the film page) asks nothing and waits for the next time.
    func askIfFinished() {
        guard let playing = nowPlaying, ratingPrompt == nil else { return }
        let elapsed = Date().timeIntervalSince(playing.startedAt)
        if elapsed > 12 * 3600 || isWatched(playing.key) {
            nowPlaying = nil
        } else if elapsed >= playing.minimumWatch, itemCache[playing.key] != nil {
            nowPlaying = nil
            ratingPrompt = RatingPrompt(id: playing.key, filmID: playing.filmID, askFinished: true)
        }
    }

    /// "Yes, I finished it": watched today, without asking again (the open sheet asks for stars).
    func markFinished(_ prompt: RatingPrompt) {
        guard !isWatched(prompt.id) else { return }
        var r = personal.stored(prompt.id)
        r.watched = true
        r.watchlist = false
        r.watchedOn = Date()
        setRecord(r, forKey: prompt.id)
    }

    // MARK: - Timings

    static let signposter = OSSignposter(subsystem: "com.howbizzar.reel", category: "Performance")

    /// Times a piece of work: shown in Instruments (signposts) and in Settings › Performance.
    func measure<T>(_ name: StaticString, label: String, _ work: () -> T) -> T {
        // Its own ID: two drives scanned at once are two intervals.
        let state = Self.signposter.beginInterval(name, id: Self.signposter.makeSignpostID())
        let start = ContinuousClock.now
        defer {
            timings[label] = ContinuousClock.now - start
            Self.signposter.endInterval(name, state)
        }
        return work()
    }

    func measure<T>(_ name: StaticString, label: String, _ work: () async -> T) async -> T {
        // Its own ID: two drives scanned at once are two intervals.
        let state = Self.signposter.beginInterval(name, id: Self.signposter.makeSignpostID())
        let start = ContinuousClock.now
        let result = await work()
        timings[label] = ContinuousClock.now - start
        Self.signposter.endInterval(name, state)
        return result
    }
}
/// The rows under a film page (see `AppModel.relatedFilms`).
struct RelatedFilms {
    let people: [(item: LibraryItem, connection: Connection)]
    let similar: [LibraryItem]

    /// "Director · Yorgos Lanthimos" under each poster of From the Same People.
    var captions: [String: String] {
        Dictionary(people.map { ($0.item.id, $0.connection.label) }, uniquingKeysWith: { a, _ in a })
    }
}
#endif
