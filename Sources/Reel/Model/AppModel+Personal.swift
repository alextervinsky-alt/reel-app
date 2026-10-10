#if os(macOS)
import Foundation
import ReelCore

extension AppModel {
    // MARK: - Notes per film

    /// One film's notes, for a view (it redraws when this film changes, and only then).
    func record(forKey key: String) -> PersonalRecord {
        personal.record(forKey: key)
    }

    func record(for film: FilmEntry) -> PersonalRecord {
        record(forKey: film.personalKey)
    }

    func isWatched(_ key: String) -> Bool {
        personal.watchedKeys.contains(key)
    }

    func toggle(_ keyPath: WritableKeyPath<PersonalRecord, Bool>, for film: FilmEntry) {
        var r = personal.stored(film.personalKey)
        r[keyPath: keyPath].toggle()
        if keyPath == \PersonalRecord.watched {
            r.watchedOn = r.watched ? Date() : nil
            if r.watched { r.watchlist = false }
        }
        setRecord(r, forKey: film.personalKey)
        // Just watched a film from the library you haven't rated: ask how it was.
        if keyPath == \PersonalRecord.watched, r.watched, r.rating == nil, let item = itemCache[film.personalKey] {
            ratingPrompt = RatingPrompt(id: item.id, filmID: item.main.id)
        }
    }

    func setRating(_ rating: Int?, for film: FilmEntry) {
        var r = personal.stored(film.personalKey)
        r.rating = rating
        setRecord(r, forKey: film.personalKey)
    }

    func setNote(_ note: String, for film: FilmEntry) {
        var r = personal.stored(film.personalKey)
        r.note = note
        setRecord(r, forKey: film.personalKey)
    }

    /// The month you watched it (editable on the film page).
    func setWatchedDate(_ date: Date, for film: FilmEntry) {
        var r = personal.stored(film.personalKey)
        r.watched = true
        r.watchlist = false
        r.watchedOn = date
        setRecord(r, forKey: film.personalKey)
    }

    func setRecord(_ r: PersonalRecord, forKey key: String) {
        let old = personal.set(r, forKey: key)
        // Only watched / watchlist / favorite change what the sidebar counts (a note doesn't).
        if old.watched != r.watched || old.watchlist != r.watchlist || old.favorite != r.favorite { recount() }
        // The chips count unwatched films, and ratings teach Recommended (the five on show stay).
        if old.watched != r.watched || old.rating != r.rating { updateRecommended() }
        warnIfNotesReadOnly()
        scheduleSave(.notes)
    }

    func warnIfNotesReadOnly() {
        guard !notesWritable && !warnedNotesReadOnly else { return }
        warnedNotesReadOnly = true
        notice = "Your Notes.json couldn't be opened at launch, so changes made now won't be saved. Quit and reopen Reel to try again."
    }

    /// Carries notes over when a file gets identified or re-identified.
    func migratePersonal(from oldKey: String, to newKey: String) {
        guard oldKey != newKey, personal.records[oldKey] != nil else { return }
        personal.migrate(from: oldKey, to: newKey, oldKeyStillUsed: films.contains { $0.personalKey == oldKey })
        recount()
        scheduleSave(.notes)
    }

    // MARK: - Seen

    /// Watched, whether the film is on a drive or was seen elsewhere (cinema, streaming).
    func isSeen(_ tmdbID: Int?) -> Bool {
        tmdbID.map { personal.watchedIDs.contains($0) } ?? false
    }

    /// Marks a film as seen or not. For a film you own this is the same as Watched (today). A
    /// film seen elsewhere is dated the month after it came out, when it was most likely seen in
    /// the cinema (or today, for a film still showing); the editor that opens changes it.
    func toggleSeen(_ tmdbID: Int) {
        let key = "tmdb:\(tmdbID)"
        let elsewhere = itemCache[key] == nil
        var r = personal.stored(key)
        r.watched.toggle()
        let guess = elsewhere ? SeenDate.afterRelease(lists.briefs[tmdbID]?.released) : nil
        r.watchedOn = r.watched ? guess ?? Date() : nil
        if r.watched { r.watchlist = false }
        setRecord(r, forKey: key)
        guard r.watched, elsewhere else { return }
        let dated = r.watchedOn
        Task {
            // Not known yet: dated once the release date arrives, unless it was changed meanwhile.
            if guess == nil {
                let released = await lists.releaseDate(of: tmdbID, using: tmdb)
                let now = personal.record(forKey: key)
                if let date = SeenDate.afterRelease(released), now.watched, now.watchedOn == dated {
                    setSeenDate(date, tmdbID: tmdbID)
                }
            }
            await loadSeenFilms()
        }
    }

    /// Films seen elsewhere dated this month that came out before last month: marked seen before
    /// Reel dated them by their release, which Year in Film offers to do. Only offered for three
    /// or more (one or two old films really seen this month are left alone).
    func seenThisMonthByDefault() -> [SeenElsewhere] {
        let calendar = Calendar.current
        let found = seenElsewhereFilms.filter { entry in
            guard calendar.isDate(entry.date, equalTo: Date(), toGranularity: .month) else { return false }
            // Release date not kept yet (briefs from before 1.7): it's looked up when dating.
            guard let released = entry.film?.released else { return true }
            return SeenDate.afterRelease(released).map { !calendar.isDate($0, equalTo: entry.date, toGranularity: .month) } ?? false
        }
        return found.count >= 3 ? found : []
    }

    /// Dates each of `films` the month after it came out (fetching release dates not known yet).
    func dateSeenByRelease(_ films: [SeenElsewhere]) async {
        for entry in films {
            let released = await lists.releaseDate(of: entry.id, using: tmdb)
            guard let date = SeenDate.afterRelease(released) else { continue }
            // Left alone if it was changed meanwhile.
            guard personal.record(forKey: entry.key).watchedOn == entry.date else { continue }
            setSeenDate(date, tmdbID: entry.id)
        }
    }

    /// When you saw a film elsewhere (the month; Year in Film counts it then).
    func setSeenDate(_ date: Date, tmdbID: Int) {
        let key = "tmdb:\(tmdbID)"
        var r = personal.stored(key)
        r.watched = true
        r.watchlist = false
        r.watchedOn = date
        setRecord(r, forKey: key)
    }

    /// Your stars for a film seen elsewhere: the same shared rating as any other film.
    func setSeenRating(_ rating: Int?, tmdbID: Int) {
        let key = "tmdb:\(tmdbID)"
        var r = personal.stored(key)
        r.rating = rating
        setRecord(r, forKey: key)
    }

    /// Films marked seen that aren't on a drive, with when you saw them (and, once fetched,
    /// what they are).
    var seenElsewhereFilms: [SeenElsewhere] {
        let seen = lists.briefs
        return personal.watchedDates.compactMap { key, date in
            guard itemCache[key] == nil, let id = PersonalStore.tmdbID(key) else { return nil }
            return SeenElsewhere(id: id, date: date, film: seen[id])
        }
    }

    /// Fetches what Year in Film needs about films seen elsewhere (once; kept in List Data).
    func loadSeenFilms() async {
        guard let client = tmdb else { return }
        await lists.fetchBriefs(seenElsewhereFilms.map { $0.id }, using: client, refreshingOld: true)
    }

    func setYearCountsElsewhere(_ on: Bool) {
        yearCountsElsewhere = on
        scheduleSave(.settings)
    }

    // MARK: - Wishlist

    func isWishlisted(_ id: Int?) -> Bool {
        id.map { wishlistIDs.contains($0) } ?? false
    }

    func toggleWishlist(_ film: PreviewFilm) {
        if wishlistIDs.contains(film.id) {
            setWishlist(wishlist.filter { $0.id != film.id })
        } else {
            addToWishlist([film.wishlistEntry])
        }
    }

    /// Adds films (e.g. everything missing from a set) in one go; ones already there or already
    /// in the library are skipped.
    func addToWishlist(_ films: [WishlistFilm]) {
        var seen = wishlistIDs
        let new = films.filter { itemsByTMDB[$0.id] == nil && seen.insert($0.id).inserted }
        guard !new.isEmpty else { return }
        setWishlist(new + wishlist)
    }

    func setWishlist(_ list: [WishlistFilm]) {
        warnIfNotesReadOnly()
        wishlist = list
        wishlistIDs = Set(list.map { $0.id })
        recount()
        scheduleSave(.notes)
    }

    /// A wishlist film found in the library leaves the wishlist, and New Arrivals tags it
    /// "From your wishlist". Only films Reel is sure about count (never "Check match").
    func removeArrivedWishes(owned: Set<Int>) {
        let now = Date()
        let (kept, arrived) = WishlistCleanup.split(wishlist, owned: owned)
        let recorded = WishlistCleanup.record(arrived, into: wishlistArrivals, now: now)
        guard !arrived.isEmpty || recorded != wishlistArrivals else { return }
        wishlistArrivals = recorded
        arrivedFromWishlist = Set(recorded.map { $0.id })
        if !arrived.isEmpty {
            wishlist = kept
            wishlistIDs = Set(kept.map { $0.id })
            if arrived.count == 1, let film = arrived.first {
                announce("\(film.title) arrived from your wishlist")
            } else {
                announce("\(arrived.count) films arrived from your wishlist")
            }
        }
        scheduleSave(.notes)
    }

    /// Whether this library film is one you had on your wishlist (New Arrivals shows it).
    func cameFromWishlist(_ item: LibraryItem) -> Bool {
        item.main.tmdb.map { arrivedFromWishlist.contains($0.id) } ?? false
    }

    // MARK: - Year in Film

    /// Every film watched on a known date: the library's, and those seen elsewhere when Year in
    /// Film counts them (read by Year in Film, which then follows your ratings and dates).
    func yearFilms() -> [YearFilm] {
        let library: [YearFilm] = personal.watchedDates.compactMap { key, date in
            guard let item = itemCache[key] else { return nil }
            let d = item.main.tmdb
            return YearFilm(id: key, title: item.main.displayTitle, releaseYear: item.main.displayYear, watchedOn: date,
                            runtime: d?.runtime, genres: d?.genreNames ?? [], directors: d?.directors ?? [],
                            yourRating: personal.record(forKey: key).rating, score: item.score, language: d?.originalLanguage,
                            cast: YearFilm.leads(d))
        }
        guard yearCountsElsewhere else { return library }
        return library + seenElsewhereFilms.compactMap { entry in
            entry.film?.yearFilm(id: entry.key, watchedOn: entry.date, yourRating: personal.record(forKey: entry.key).rating)
        }
    }

    /// Films seen elsewhere in a year, newest first.
    func seenElsewhere(in year: Int) -> [SeenElsewhere] {
        let calendar = Calendar.current
        return seenElsewhereFilms.filter { calendar.component(.year, from: $0.date) == year }.sorted { $0.date > $1.date }
    }
}

/// A film marked seen that isn't on a drive (the cinema, streaming).
struct SeenElsewhere: Identifiable {
    let id: Int
    let date: Date
    /// What it is, once fetched (see `ListsStore.briefs`).
    let film: FilmBrief?

    var key: String { "tmdb:\(id)" }
}
#endif
