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
        let chosen = DiscoverList.shelves(loved: lovedFilms(), directors: lovedDirectors(), using: &generator)
        exploreShelvesChosen = chosen
        return chosen
    }

    /// The films of an Explore list as shown: none you've seen, only the mood's when one is
    /// chosen, and in this launch's order when the list ranks by quality.
    func exploreFilms(_ list: DiscoverList, mood: Mood?) -> [TMDBMovieSummary] {
        var films = (discover[list] ?? []).filter { !hasSeen($0.id) && !notForMe.contains($0.id) }
        // More from a director: the films you don't have yet.
        if case .director = list { films = films.filter { itemsByTMDB[$0.id] == nil } }
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

    /// Directors of films you loved on your drives, for "More from" (each once).
    private func lovedDirectors() -> [(id: Int, name: String)] {
        var found: [Int: String] = [:]
        for (key, record) in personal.records where (record.rating ?? (record.favorite ? 4 : 0)) >= 4 {
            for person in itemCache[key]?.main.tmdb?.credits?.crew ?? [] where person.job == "Director" {
                if let id = person.id { found[id] = person.name }
            }
        }
        return found.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
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
                || (source == .acclaimed && lists.isLoading(.acclaimed(year)))
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
        case .acclaimed:
            await loadAcclaimed(year: year)
            guard lists.imdbIsReady, lists.acclaimed[year] != nil else {
                if lists.imdbFailed || (lists.imdbIsReady && tmdb != nil) { bestOfMissing.insert(key) }
                return
            }
            films = lists.films(for: .acclaimed(year)).prefix(40).map { ($0, $0.note) }
        case .tmdb, .popular, .gems:
            return
        }
        // The lists are there, with nothing for the year: an empty row says so.
        guard !films.isEmpty else {
            bestOfLists[key] = []
            return
        }
        await lists.resolve(films.map(\.film), using: client)
        let prizes = source == .acclaimed ? acclaimedPrizes[year] ?? [:] : [:]
        bestOfLists[key] = films.compactMap { entry in
            guard let art = lists.resolved(entry.film) else { return nil }
            let preview = PreviewFilm(entry.film, art: art)
            return PreviewFilm(id: preview.id, title: preview.title, year: preview.year, posterPath: preview.posterPath,
                               backdropPath: preview.backdropPath, voteAverage: preview.voteAverage, voteCount: preview.voteCount,
                               genres: preview.genres, note: entry.note, reason: entry.film.imdbID.flatMap { prizes[$0] })
        }
    }

    // MARK: The most acclaimed

    /// Works out a year's most acclaimed films (see `Acclaim`), once a session: its best-known
    /// films and the award lists' films of the year, with TMDB's audience and, for the 40 most
    /// likely, the critics' scores (OMDb, kept a month). Without an OMDb key, audiences, how widely
    /// seen and the prizes decide. `askCritics` false (the Lists card): only critics' scores already
    /// kept, so browsing years there spends no OMDb requests; the list itself asks for the rest.
    /// Asked for twice at once, it's worked out once.
    func loadAcclaimed(year: Int, askCritics: Bool = true) async {
        let done = lists.acclaimed[year] != nil && (!askCritics || acclaimedWithCritics.contains(year))
        guard !done else { return }
        if let running = acclaimedTasks[year] {
            await running.value
            if !askCritics || acclaimedWithCritics.contains(year) { return }
        }
        let task = Task { await workOutAcclaimed(year: year, askCritics: askCritics) }
        acclaimedTasks[year] = task
        await task.value
        acclaimedTasks[year] = nil
    }

    private func workOutAcclaimed(year: Int, askCritics: Bool) async {
        let lists = self.lists
        guard let client = tmdb else { return }
        lists.setAcclaimedLoading(true, year: year)
        defer { lists.setAcclaimedLoading(false, year: year) }
        await lists.load(.acclaimed(year))
        guard lists.imdbIsReady else { return }
        await lists.loadAllAwards()
        let prizes = Acclaim.prizes(AwardList.allCases.map { ($0, lists.films(for: .award($0))) }, year: year)
        let pool = Acclaim.pool(lists.imdbFilms(year: year), year: year, awarded: Set(prizes.keys))
        guard !pool.isEmpty else {
            lists.setAcclaimed([], year: year)
            return
        }
        // TMDB's audience, from the posters' lookup.
        let entries = pool.map(ListFilm.init)
        await lists.resolve(entries, using: client)
        var candidates = zip(pool, entries).map { film, entry -> Acclaim.Candidate in
            let art = lists.resolved(entry)
            let prize = prizes[film.id]
            return Acclaim.Candidate(film: film, tmdbVote: art?.voteAverage, tmdbVotes: art?.voteCount,
                                     prize: prize?.prize, prizeName: prize?.name)
        }
        // The critics, for the films most likely to make the list (their scores are what's missing).
        if let omdb = omdbClient, askCritics {
            let likely = Acclaim.rank(candidates).prefix(40).map { $0.candidate.film.id }
            let wanted = likely.filter { lists.criticScores($0) == nil }
            var found: [String: CriticScores] = [:]
            var refused = false
            for start in stride(from: 0, to: wanted.count, by: 6) where !refused {
                let batch = Array(wanted[start..<min(start + 6, wanted.count)])
                let scores = await withTaskGroup(of: (String, CriticsAnswer).self, returning: [(String, CriticsAnswer)].self) { group in
                    for id in batch {
                        group.addTask {
                            // Answered with no scores: kept as none. Not reached: asked again next time.
                            do {
                                let ratings = try await omdb.ratings(imdbID: id)
                                return (id, .answered(CriticScores(metacritic: ratings?.metacritic, rottenTomatoes: ratings?.rottenTomatoes)))
                            } catch OMDbError.unauthorized {
                                return (id, .refused)
                            } catch {
                                return (id, .unreached)
                            }
                        }
                    }
                    var all: [(String, CriticsAnswer)] = []
                    for await result in group { all.append(result) }
                    return all
                }
                for (id, answer) in scores {
                    switch answer {
                    case .answered(let score): found[id] = score
                    // The day's requests are used up (or the key is wrong): no more asked now.
                    case .refused: refused = true
                    case .unreached: break
                    }
                }
            }
            lists.keepCriticScores(found)
        }
        // What the critics said, as far as it's known.
        for index in candidates.indices {
            guard let scores = lists.criticScores(candidates[index].film.id) else { continue }
            candidates[index].metacritic = scores.metacritic
            candidates[index].rottenTomatoes = scores.rottenTomatoes
        }
        if askCritics { acclaimedWithCritics.insert(year) }
        let ranked = Acclaim.rank(candidates).prefix(50)
        acclaimedPrizes[year] = Dictionary(ranked.compactMap { entry in entry.candidate.prizeName.map { (entry.candidate.film.id, $0) } },
                                           uniquingKeysWith: { first, _ in first })
        lists.setAcclaimed(ranked.map { entry in
            ListFilm(imdbID: entry.candidate.film.id, tmdbID: nil, title: entry.candidate.film.title, year: entry.candidate.film.year,
                     note: Acclaim.note(entry.candidate))
        }, year: year)
    }
}

/// OMDb's answer for one film's critics.
private enum CriticsAnswer: Sendable {
    case answered(CriticScores), refused, unreached
}
#endif
