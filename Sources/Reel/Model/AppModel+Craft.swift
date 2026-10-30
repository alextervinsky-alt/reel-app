#if os(macOS)
import Foundation
import ReelCore

/// Searching by craft: each film's Wikipedia article and the interviews and craft articles about
/// it are read in the background, two films at a time (see `CraftReader`), and the names of the
/// gear and techniques are kept, with the sentence behind each Shot on (see `CraftIndex`).
extension AppModel {
    /// Reads the films not read yet, read by older rules or long ago, and those whose last reading
    /// was incomplete when it's due again (see `CraftQueue`). Runs after film info is looked up, when
    /// a planned retry comes due (`scheduleCraftWake`), and when the network comes back or the Mac
    /// wakes (`resumeMaintenance`); stops when offline, and carries on next time: what's due is worked
    /// out from what's stored. Every decision is `CraftRun`'s; this fetches and writes.
    func readCraft() async {
        guard !craftRunning else { return }
        craftRunning = true
        var run = CraftRun()
        craftRun = run
        defer {
            craftRun = nil
            craftRunning = false
            if craftPending != 0 { craftPending = 0 }
            scheduleCraftWake()
        }
        // Kept and written in batches: the library is rebuilt once per batch, not per film.
        func write(force: Bool) {
            if let writes = run.takeWrites(force: force) { storeCraft(writes.read, failed: writes.failed) }
            craftRun = run
        }
        defer { write(force: true) }
        while !Task.isCancelled {
            // Films whose info and Wikipedia facts are in (the article's title comes with the facts),
            // one for each film, the longest since tried first; two at a time (each reads its article
            // and camera sources side by side).
            let batch = run.nextBatch(films)
            let pending = run.pending(films) + batch.count
            if craftPending != pending { craftPending = pending }
            craftRun = run
            guard !batch.isEmpty else { return }
            // Their collections first (cached for two weeks), so a sequel's articles aren't read.
            for film in batch { if let details = film.tmdb { await loadCollection(of: details) } }
            var unknownCollection = Set<Int>()
            let results = await withTaskGroup(of: (Int, CraftReader.Reading?, String).self) { group in
                for film in batch {
                    guard let details = film.tmdb else { continue }
                    let title = film.funFacts?.articleTitle
                    let colour = film.funFacts?.quick?.colour
                    let others = otherTitles(of: details)
                    // Its collection couldn't be read (offline, no token): read again later with it.
                    let collectionKnown = details.collection == nil || collectionLoaded(of: details)
                    group.addTask {
                        (details.id, await CraftReader.read(details, articleTitle: title, colour: colour, otherTitles: others),
                         CraftLog.fileName(for: details))
                    }
                    if !collectionKnown { unknownCollection.insert(details.id) }
                }
                var all: [(Int, CraftReader.Reading?, String)] = []
                for await result in group { all.append(result) }
                return all
            }
            for (id, reading, logName) in results {
                // As it is now (the tab may have stored a reading meanwhile), its newest copy.
                let film = CraftQueue.representatives(of: films.filter { $0.tmdb?.id == id }).first
                var found = reading?.index
                if unknownCollection.contains(id) { found?.discovery = CraftIndex.currentDiscovery - 1 }
                // Tag by tag: what a site that didn't answer said before is carried over, marked so,
                // and read again later (see `CraftIndex.merge`). Nothing reached: tried again later
                // (its log still says what's stored), so it doesn't come first again next time.
                if let merged = run.record(id, stored: film, reading: found), let reading {
                    // What was read and why, and what's stored, beside the library (see `CraftLog`).
                    writeCraftLog(reading.log + CraftLog.stored(merged), named: logName)
                }
            }
            craftRun = run
            // Several in a row: offline, not these films. The rest wait for the network (or the next run).
            if run.offline { return }
            write(force: false)
            // A short pause between batches, whatever the size of the library.
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Writes the readings a run has made and not written yet: when Reel quits mid-run they're kept
    /// rather than read again.
    func flushCraft() {
        guard var run = craftRun, let writes = run.takeWrites(force: true) else { return }
        craftRun = run
        storeCraft(writes.read, failed: writes.failed)
    }

    /// Wakes the queue when the next planned reading comes due (a site that didn't answer, a try
    /// that came to nothing), rather than at the next six-hourly refresh. One wake at a time; each
    /// run plans the next. Beyond six hours the regular refresh comes first.
    func scheduleCraftWake() {
        craftWake?.cancel()
        guard let next = CraftQueue.nextDue(films) else { return }
        let wait = max(60, next.timeIntervalSinceNow + 5)
        guard wait < 6 * 3600 else { return }
        craftWake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.readCraft()
        }
    }

    func writeCraftLog(_ log: String, named name: String) {
        let file = folder.shotOnReadings.appendingPathComponent(name)
        writer.enqueue { try? Data(log.utf8).write(to: file, options: .atomic) }
    }

    /// Fetches the film's collection from TMDB when it isn't kept yet (two weeks; see `ListsStore`).
    func loadCollection(of details: TMDBMovieDetails) async {
        guard let collection = details.collection, hasToken else { return }
        _ = await lists.loadFranchise(collection.id, using: TMDBClient(token: token))
    }

    func collectionLoaded(of details: TMDBMovieDetails) -> Bool {
        guard let collection = details.collection else { return true }
        return lists.sets[FilmSet.id(.franchise, collection.id)] != nil
    }

    /// The other films of its collection, whose articles aren't read for it: The Matrix
    /// Resurrections' for The Matrix.
    func otherTitles(of details: TMDBMovieDetails) -> [String] {
        guard let collection = details.collection, let set = lists.sets[FilmSet.id(.franchise, collection.id)] else { return [] }
        return set.films.filter { $0.id != details.id }.map(\.title)
    }

    /// Shot on as shown for a film: what was read, less what you said is wrong.
    func shownShotOn(_ film: FilmEntry) -> [ShotOn] {
        let removed = film.tmdb.flatMap { removedShotOn[$0.id] } ?? []
        // Before its craft is read, what Wikidata or TMDB already say (black and white).
        let read = film.craft?.shotOn ?? ShotOn.allCases.filter { LibraryItem.shotOnKnown(film).contains($0) }
        return read.filter { !removed.contains($0) }
    }

    /// You said a Shot on tag is wrong for this film: it's no longer shown, filtered or searched
    /// for it (kept in Your Notes; Settings lists it to put back).
    func removeShotOn(_ kind: ShotOn, from film: FilmEntry) {
        guard let id = film.tmdb?.id else { return }
        removedShotOn[id, default: []].insert(kind)
        scheduleSave(.notes)
        scheduleRebuild()
    }

    func restoreShotOn(_ kind: ShotOn, for id: Int) {
        removedShotOn[id]?.remove(kind)
        if removedShotOn[id]?.isEmpty == true { removedShotOn[id] = nil }
        scheduleSave(.notes)
        scheduleRebuild()
    }

    /// How much of the library Shot on covers (Settings › Performance): live-action films, each
    /// once (see `CraftQueue.coverage`).
    func craftCoverage() -> CraftQueue.Coverage {
        CraftQueue.coverage(of: films, removed: removedShotOn)
    }

    /// Puts new readings in the library, and the tries that came to nothing, noting each film whose
    /// Shot on changed (Settings › Performance lists them, so a change can be checked).
    func storeCraft(_ batch: [Int: CraftIndex], failed: [Int: CraftAttempt] = [:]) {
        guard !batch.isEmpty || !failed.isEmpty else { return }
        var changes: [CraftChange] = []
        mutateFilms { list in
            for change in CraftRun.apply(read: batch, failed: failed, to: &list) {
                changes.append(CraftChange(title: list[change.index].displayTitle, before: change.before,
                                           after: list[change.index].craft?.shotOn ?? []))
            }
        }
        if !changes.isEmpty { craftChanges = Array((changes + craftChanges).prefix(200)) }
    }

    /// What the Cinematography tab just read becomes the film's summary too, so the Shot on filter
    /// and search say what the tab shows, merged tag by tag as the background reading is, with its
    /// log written the same way.
    /// Only while the film is due: the tab's reading is kept for the session, and a newer reading
    /// in the background isn't replaced by it.
    func craftRead(for film: FilmEntry, article: FilmArticle?, reading: CameraReading?) {
        guard let details = film.tmdb, article != nil || reading != nil else { return }
        let stored = CraftQueue.representatives(of: films.filter { $0.tmdb?.id == details.id }).first ?? film
        let current = stored.craft
        // Its sources couldn't be reached (offline, every site asking to wait): the stored reading stands.
        if current != nil, reading == nil { return }
        guard current == nil || CraftQueue.isDue(craft: current, attempt: stored.craftAttempt, hasFacts: true,
                                                 inCollection: details.collection != nil) else { return }
        // The article didn't come (not: there's no such article): Wikipedia didn't answer.
        let articleFailed = film.funFacts?.articleTitle != nil && article == nil && !articlesMissing.contains(details.id)
        let read = CraftReader.reading(of: details, articleTitle: film.funFacts?.articleTitle, article: article, reading: reading,
                                       colour: film.funFacts?.quick?.colour, otherTitles: otherTitles(of: details), articleFailed: articleFailed)
        let merged = CraftIndex.merging(old: current, new: read.index)
        // The same as kept: nothing to write (the log already says what's stored, and opening the
        // tab again doesn't put off a planned reading).
        if let current, current.version == merged.index.version, current.discovery == merged.index.discovery,
           current.shotOn == merged.index.shotOn,
           current.names == merged.index.names, current.evidence == merged.index.evidence,
           current.unanswered == merged.index.unanswered, current.limits == merged.index.limits {
            return
        }
        storeCraft([details.id: merged.index])
        writeCraftLog(read.log + CraftLog.stored(merged), named: CraftLog.fileName(for: details))
    }
}

/// A film whose Shot on changed when it was read again.
struct CraftChange: Identifiable {
    let id = UUID()
    let title: String
    let before: [ShotOn]
    let after: [ShotOn]
}
#endif
