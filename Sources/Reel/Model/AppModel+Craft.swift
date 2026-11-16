#if os(macOS)
import Foundation
import ReelCore

/// Collections for a film's articles, and the reading logs Reel 1.10 left behind. (The
/// Cinematography tab was cut from 1.11; what you said was wrong stays in Your Notes as it is.)
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
