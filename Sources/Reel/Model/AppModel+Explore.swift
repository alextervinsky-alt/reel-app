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
        var generator = SystemRandomNumberGenerator()
        let chosen = DiscoverList.shelves(loved: lovedFilms(), using: &generator)
        exploreShelvesChosen = chosen
        return chosen
    }

    /// The films of an Explore list as shown: none you've seen, only the mood's when one is
    /// chosen, and in this launch's order when the list ranks by quality.
    func exploreFilms(_ list: DiscoverList, mood: Mood?) -> [TMDBMovieSummary] {
        var films = (discover[list] ?? []).filter { !isSeen($0.id) }
        if let mood { films = films.filter { MoodGenres.of(mood).fits($0.genreNames) } }
        if list.reshuffles {
            films = EveningOrder.arrange(films, evening: exploreLaunch, id: { String($0.id) }, score: { $0.voteAverage })
        }
        return films
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

    func isLoadingBestOf(year: Int, source: BestOfSource) -> Bool {
        source.isTMDB ? discoverLoading.contains(.bestOf(year: year, source: source))
            : bestOfLoading.contains(Self.bestOfKey(year, source)) || (source == .imdb && lists.isLoading(.imdbYear(year)))
    }

    /// Fetches the best of a year from a source: TMDB's directly; IMDb's Top 100 from the Lists'
    /// IMDb ratings (downloaded the first time); the award winners from the award lists. Each
    /// film's poster is found on TMDB.
    func loadBestOf(year: Int, source: BestOfSource) async {
        if source.isTMDB { return await loadDiscover(.bestOf(year: year, source: source)) }
        let key = Self.bestOfKey(year, source)
        guard bestOfLists[key] == nil, !bestOfLoading.contains(key), let client = tmdb else { return }
        bestOfLoading.insert(key)
        defer { bestOfLoading.remove(key) }
        var films: [(film: ListFilm, note: String?)] = []
        switch source {
        case .imdb:
            await lists.load(.imdbYear(year))
            films = lists.films(for: .imdbYear(year)).prefix(40).map { ($0, $0.note.map { "IMDb " + $0 }) }
        case .awards:
            await lists.loadAllAwards()
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
        // Nothing yet (the IMDb ratings still downloading, or offline): asked again next time.
        guard !films.isEmpty else { return }
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
