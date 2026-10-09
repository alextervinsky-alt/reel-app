#if os(macOS)
import Foundation
import ReelCore

/// Explore stays fresh: three shelves chosen each launch, films you've seen left out, rows that
/// rank by quality reordered each launch within films of about the same rating, and the best of
/// a year from the source you choose.
extension AppModel {
    /// This launch's shelves: one of your loved films', a country's cinema, a decade or the
    /// hidden gems. Chosen once, the first time Explore opens.
    var exploreShelves: [DiscoverList] {
        if let chosen = exploreShelvesChosen { return chosen }
        // Before your notes are read there are no loved films to start from: chosen once they are.
        guard isLoaded else { return [] }
        var generator = SystemRandomNumberGenerator()
        let chosen = DiscoverList.shelves(loved: lovedFilms(), using: &generator)
        exploreShelvesChosen = chosen
        return chosen
    }

    /// The films of an Explore list as shown: none you've seen, only the mood's when one is
    /// chosen, and in this launch's order when the list ranks by quality.
    func exploreFilms(_ list: DiscoverList, mood: Mood?) -> [TMDBMovieSummary] {
        var films = (discover[list] ?? []).filter { !hasSeen($0.id) }
        // What people went on to love after one of yours: only the well-liked (TMDB's own list
        // reaches far down).
        if case .because = list { films = films.filter { ($0.voteAverage ?? 0) >= 6.6 && ($0.voteCount ?? 0) >= 150 } }
        if let mood { films = films.filter { MoodGenres.of(mood).fits($0.genreNames) } }
        if list.reshuffles {
            films = EveningOrder.arrange(films, evening: exploreLaunch, id: { String($0.id) }, score: { $0.voteAverage })
        }
        return films
    }

    /// Seen elsewhere, or on your drives and watched.
    func hasSeen(_ tmdbID: Int) -> Bool {
        isSeen(tmdbID) || itemsByTMDB[tmdbID].map { personal.watchedKeys.contains($0.id) } == true
    }

    /// Films you loved (4 or 5 stars, or a heart), with their titles.
    private func lovedFilms() -> [(id: Int, title: String)] {
        personal.records.compactMap { key, record in
            guard (record.rating ?? (record.favorite ? 4 : 0)) >= 4, let id = PersonalStore.tmdbID(key) else { return nil }
            guard let title = itemCache[key]?.main.displayTitle ?? lists.briefs[id]?.title else { return nil }
            return (id, title)
        }
    }

    // MARK: Best of a year

    static func bestOfKey(_ year: Int, _ source: BestOfSource) -> String { "\(year)|\(source.rawValue)" }

    /// The best of a year from a source: nil while it's being found.
    func bestOf(year: Int, source: BestOfSource) -> [PreviewFilm]? {
        if source.isTMDB {
            return discover[.bestOf(year: year, source: source)].map { $0.map { PreviewFilm($0) } }
        }
        return bestOfLists[Self.bestOfKey(year, source)]
    }

    /// Tried and not found (offline, or IMDb's ratings failed to download).
    func bestOfFailed(year: Int, source: BestOfSource) -> Bool {
        bestOfMissing.contains(Self.bestOfKey(year, source))
    }

    func isLoadingBestOf(year: Int, source: BestOfSource) -> Bool {
        source.isTMDB ? discoverLoading.contains(.bestOf(year: year, source: source))
            : bestOfLoading.contains(Self.bestOfKey(year, source)) || (source == .imdb && lists.isLoading(.imdbYear(year)))
    }

    /// Fetches the best of a year from a source: TMDB's directly; IMDb's Top 100 from the Lists'
    /// IMDb ratings (downloaded the first time); the award winners from the award lists. Each
    /// film's poster is found on TMDB.
    func loadBestOf(year: Int, source: BestOfSource) async {
        let key = Self.bestOfKey(year, source)
        if source.isTMDB {
            bestOfMissing.remove(key)
            await loadDiscover(.bestOf(year: year, source: source))
            if discover[.bestOf(year: year, source: source)] == nil { bestOfMissing.insert(key) }
            return
        }
        guard bestOfLists[key] == nil, !bestOfLoading.contains(key), let client = tmdb else { return }
        bestOfLoading.insert(key)
        bestOfMissing.remove(key)
        defer { bestOfLoading.remove(key) }
        var films: [(film: ListFilm, note: String?)] = []
        switch source {
        case .imdb:
            await lists.load(.imdbYear(year))
            // Still downloading the first time: the row waits and asks again.
            guard lists.imdbIsReady else {
                if lists.imdbFailed { bestOfMissing.insert(key) }
                return
            }
            films = lists.films(for: .imdbYear(year)).prefix(40).map { ($0, $0.note.map { "IMDb " + $0 }) }
        case .awards:
            await lists.loadAllAwards()
            guard AwardList.allCases.contains(where: { !lists.films(for: .award($0)).isEmpty }) else {
                bestOfMissing.insert(key)
                return
            }
            for award in AwardList.allCases where award != .criterion {
                for film in lists.films(for: .award(award)) where film.year == year && film.isWinner {
                    if let index = films.firstIndex(where: { $0.film.id == film.id }) {
                        films[index].note = (films[index].note ?? "") + " · " + award.title
                    } else {
                        films.append((film, award.title))
                    }
                }
            }
        case .tmdb, .popular, .gems:
            return
        }
        // The lists are there, with nothing for the year: an empty row says so.
        guard !films.isEmpty else {
            bestOfLists[key] = []
            return
        }
        await lists.resolve(films.map(\.film), using: client)
        bestOfLists[key] = films.compactMap { entry in
            guard let art = lists.resolved(entry.film) else { return nil }
            let preview = PreviewFilm(entry.film, art: art)
            return PreviewFilm(id: preview.id, title: preview.title, year: preview.year, posterPath: preview.posterPath,
                               backdropPath: preview.backdropPath, voteAverage: preview.voteAverage, voteCount: preview.voteCount,
                               genres: preview.genres, note: entry.note)
        }
    }
}
#endif
