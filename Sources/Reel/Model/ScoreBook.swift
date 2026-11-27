#if os(macOS)
import Foundation
import Observation
import ReelCore

/// The scores of films outside the library, for the pointer and for previews (1.11.4, Alex: films
/// under Discover showed no ratings on hover, and a clicked one took a while to show them). A
/// card asks for its film as it appears; the films asked within a moment go to Wikidata in one
/// query (IMDb id, Tomatometer and Metascore by TMDB id), and IMDb's rating and votes come from
/// IMDb's own files (Lists). A preview's OMDb answer is kept here too. Each film is asked once a
/// session; one Wikidata can't be reached for is asked again next time.
@MainActor
@Observable
final class ScoreBook {
    /// Observed by the cards under the pointer and by previews only.
    private(set) var ratings: [Int: ExternalRatings] = [:]
    /// TMDB id → IMDb id, as Wikidata gives it (a preview's OMDb request can start at once).
    @ObservationIgnored private(set) var imdbIDs: [Int: String] = [:]
    @ObservationIgnored private var asked: Set<Int> = []
    @ObservationIgnored private var waiting: [Int] = []
    @ObservationIgnored private var flushing: Task<Void, Never>?
    @ObservationIgnored private let lists: ListsStore

    init(lists: ListsStore) {
        self.lists = lists
    }

    /// A card showing this film (TMDB id) appeared.
    func want(_ id: Int) {
        guard id > 0, !asked.contains(id) else { return }
        asked.insert(id)
        waiting.append(id)
        guard flushing == nil else { return }
        flushing = Task { [weak self] in
            // The other cards of the row appear in the same moment: one query for all of them.
            try? await Task.sleep(for: .milliseconds(120))
            await self?.flush()
        }
    }

    private func flush() async {
        while !waiting.isEmpty {
            let ids = Array(waiting.prefix(WikidataScores.batch))
            waiting.removeFirst(ids.count)
            guard let found = try? await WikidataScores.scores(tmdbIDs: ids) else {
                asked.subtract(ids)
                continue
            }
            var added: [Int: ExternalRatings] = [:]
            for (id, scores) in found {
                if let imdbID = scores.imdbID { imdbIDs[id] = imdbID }
                var imdb: IMDbFilm?
                if let imdbID = scores.imdbID { imdb = await lists.imdbFilm(imdbID) }
                let found = ExternalRatings(imdb: imdb?.rating, imdbVotes: imdb?.votes,
                                            rottenTomatoes: scores.rottenTomatoes, metacritic: scores.metacritic)
                if !found.isEmpty { added[id] = found }
            }
            if !added.isEmpty {
                // One change for the whole batch.
                var all = ratings
                for (id, found) in added { all[id] = ExternalRatings.merged(all[id], over: found) }
                ratings = all
            }
        }
        flushing = nil
    }

    /// A preview's own answer (OMDb, and Wikidata's Tomatometer): newer, so it wins.
    func keep(_ answer: ExternalRatings?, for id: Int) {
        guard let answer, !answer.isEmpty else { return }
        ratings[id] = ExternalRatings.merged(answer, over: ratings[id])
    }
}
#endif
