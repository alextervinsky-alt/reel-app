#if os(macOS)
import Foundation
import ReelCore

/// A film the lists suggest: what it is, why, and whether it's already on a drive.
struct ListSuggestion: Identifiable {
    let pick: ListPick
    let film: PreviewFilm
    /// "From the director of Her", or the lists it's on.
    let reason: String
    let score: Double

    var id: String { pick.ids.first ?? film.title }
}

/// What the Lists hub's Start Here depends on (see `AppModel.startHere`).
struct StartHereStamp: Equatable {
    let library: Int
    let films: Int
    let art: Int
    let briefs: Int
    let seen: Int
    let wishlist: Int
    let ratings: Int
}

/// The Lists hub turned toward finding your next film: the films the lists agree on, ranked by
/// how many (and which) lists they're on, how well they fit what you've rated and how they're
/// rated, minus what you've seen, own and watched, or already wished for.
extension AppModel {
    /// The lists Start Here and the list pages weigh together (IMDb's year lists stay apart).
    private var consensusLists: [(kind: FilmListKind, films: [ListFilm])] {
        var all: [(kind: FilmListKind, films: [ListFilm])] = [(.sightAndSound, SightAndSound.films)]
        if lists.imdbIsReady { all.append((.imdbAllTime, lists.films(for: .imdbAllTime))) }
        for award in AwardList.allCases { all.append((.award(award), lists.films(for: .award(award)))) }
        return all
    }

    /// Every film on the lists, once each, weightiest first; and the same by each list film's id.
    func listPicks() -> (all: [ListPick], byFilm: [String: ListPick]) {
        let lists = consensusLists
        let stamp = lists.reduce(0) { $0 &+ $1.films.count } &+ self.lists.art.count
        if let cached = listPicksCache, cached.stamp == stamp { return (cached.all, cached.byFilm) }
        let picks = ListConsensus.gather(lists) { self.lists.tmdbID($0) }
        var byFilm: [String: ListPick] = [:]
        for pick in picks { for id in pick.ids { byFilm[id] = pick } }
        listPicksCache = (stamp, picks, byFilm)
        return (picks, byFilm)
    }

    /// The library film a list pick is, if any.
    func libraryItem(_ pick: ListPick) -> LibraryItem? {
        if let imdb = pick.film.imdbID, let item = itemsByIMDb[imdb] { return item }
        return pick.tmdbID.flatMap { itemsByTMDB[$0] }
    }

    /// How well a film outside the library fits your ratings, and the film you loved by the same
    /// director (from its brief when fetched, else its genres from the lists).
    func listFit(tmdbID: Int?, genres: [String]?) -> (score: Double, sameDirectorAs: String?) {
        let brief = tmdbID.flatMap { lists.briefs[$0] }
        return taste.fit(directors: brief?.directors ?? [], genres: brief?.genres ?? genres ?? [])
    }

    /// Start Here: films on your drives you haven't watched yet, and films worth finding.
    func startHere() -> (onDrive: [ListSuggestion], toFind: [ListSuggestion]) {
        let stamp = StartHereStamp(library: libraryVersion, films: items.count, art: lists.art.count, briefs: lists.briefs.count,
                                   seen: personal.watchedIDs.hashValue, wishlist: wishlistIDs.count, ratings: personal.ratingsVersion)
        let picks = listPicks().all
        if let cached = startHereCache, cached.stamp == stamp, cached.picks == picks.count { return cached.value }

        var onDrive: [ListSuggestion] = []
        var toFind: [ListSuggestion] = []
        for pick in picks {
            if let item = libraryItem(pick) {
                guard !personal.watchedKeys.contains(item.id), let details = item.main.tmdb else { continue }
                let match = tasteMatch(item)
                let reason = (match?.score ?? 0) >= 1 ? match?.reason?.long : nil
                let score = pick.weight + 0.9 * (match?.score ?? 0) + Self.quality(item.score)
                let film = PreviewFilm(id: details.id, title: item.main.displayTitle, year: item.main.displayYear,
                                       posterPath: details.posterPath, backdropPath: details.backdropPath,
                                       voteAverage: details.voteAverage, voteCount: details.voteCount ?? 0,
                                       genres: details.genreNames, note: nil)
                onDrive.append(ListSuggestion(pick: pick, film: film,
                                              reason: reason ?? ListConsensus.summary(pick.lists), score: score))
            } else {
                guard let id = pick.tmdbID, !isSeen(id), !wishlistIDs.contains(id) else { continue }
                let art = pick.ids.lazy.compactMap { self.lists.art[$0] }.first
                let brief = lists.briefs[id]
                guard art?.posterPath != nil || brief?.posterPath != nil else { continue }
                let fit = listFit(tmdbID: id, genres: art?.genres)
                let reason = fit.sameDirectorAs.map { PickReason.director(film: $0).long }
                let score = pick.weight + 0.9 * fit.score + Self.quality(brief?.voteAverage ?? art?.voteAverage)
                toFind.append(ListSuggestion(pick: pick, film: PreviewFilm(pick: pick, art: art, brief: brief),
                                             reason: reason ?? ListConsensus.summary(pick.lists), score: score))
            }
        }
        let value = (onDrive: Array(onDrive.sorted { $0.score > $1.score }.prefix(12)),
                     toFind: Array(toFind.sorted { $0.score > $1.score }.prefix(20)))
        startHereCache = (stamp, picks.count, value)
        return value
    }

    /// Looks up what Start Here needs about its likeliest films: their TMDB ids and posters, then
    /// their directors and genres (to see how they fit you). Only the top few dozen, once.
    func prepareStartHere() async {
        guard let client = tmdb else { return }
        let candidates = listPicks().all.filter { pick in
            guard libraryItem(pick) == nil else { return false }
            return pick.tmdbID.map { !isSeen($0) && !wishlistIDs.contains($0) } ?? true
        }
        .prefix(60)
        await lists.resolve(candidates.map(\.film), using: client)
        // The ids found just now are in the picks worked out again.
        let ids = listPicks().all.filter { libraryItem($0) == nil }.prefix(60).compactMap(\.tmdbID)
        await lists.fetchBriefs(Array(ids.prefix(40)), using: client)
    }

    /// A little for being well rated: 0 at 7/10, ±0.4 a point.
    private static func quality(_ score: Double?) -> Double {
        score.map { ($0 - 7) * 0.4 } ?? 0
    }
}

extension PreviewFilm {
    /// A film a list suggests, from what's known of it.
    init(pick: ListPick, art: ResolvedFilm?, brief: FilmBrief?) {
        self.init(id: pick.tmdbID ?? 0, title: pick.film.title, year: pick.film.year ?? brief?.year,
                  posterPath: art?.posterPath ?? brief?.posterPath, backdropPath: art?.backdropPath ?? brief?.backdropPath,
                  voteAverage: art?.voteAverage ?? brief?.voteAverage, voteCount: art?.voteCount ?? 0,
                  genres: brief?.genres ?? art?.genres ?? [], note: ListConsensus.summary(pick.lists, limit: 3))
    }
}
#endif
