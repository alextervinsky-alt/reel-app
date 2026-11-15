#if os(macOS)
import Foundation
import ReelCore

/// How films were shot (1.11): the facts sheet is stored with each film (`CraftFacts`) and shown
/// as stored; the Shot on you said is wrong is kept in Your Notes. Session 4 adds the background
/// reading of the facts.
extension AppModel {
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
        // Before its facts are read, what Wikidata or TMDB already say (black and white).
        let read = film.craftFacts?.shotOn ?? ShotOn.allCases.filter { LibraryItem.shotOnKnown(film).contains($0) }
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


    /// You said a fact on the Cinematography tab is wrong: that row is never shown for the film
    /// again (Your Notes, `removedFacts`).
    func removeFact(_ row: CraftFacts.Row, from film: FilmEntry) {
        guard let id = film.tmdb?.id else { return }
        removedFacts[id, default: []].insert(row.rawValue)
        scheduleSave(.notes)
    }

    /// The reading logs Reel 1.10 wrote (Shot On Readings.nosync): their size, or nil when gone.
    func oldReadingsSize() -> Int64? {
        let url = folder.shotOnReadings
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return CacheMaintenance.size(of: url)
    }

    /// Moves the old reading logs to the Trash (Settings › Diagnostics): never deleted outright.
    func trashOldReadings() {
        try? FileManager.default.trashItem(at: folder.shotOnReadings, resultingItemURL: nil)
    }
}
#endif
