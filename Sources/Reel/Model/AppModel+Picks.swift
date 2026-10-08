#if os(macOS)
import Foundation
import ReelCore

/// A film For You shows, and why.
struct ExplorePick: Identifiable {
    let film: PreviewFilm
    let reason: String

    var id: Int { film.id }
}

/// For You: films you don't have and haven't seen, which people who loved your favourites went
/// on to love, kept when they're truly alike (see `ExplorePicks`). A different fifteen each time
/// Reel opens (and New Picks draws again).
extension AppModel {
    static let forYouCount = 15

    func loadExplorePicks() async {
        guard explorePicks == nil, !explorePicksLoading, let client = tmdb else { return }
        explorePicksLoading = true
        defer {
            explorePicksLoading = false
            explorePicksTried = true
        }
        let seeds = exploreSeeds()
        let sources = await withTaskGroup(of: (seed: ExploreSeed, recommended: [TMDBMovieSummary])?.self) { group in
            for seed in seeds {
                group.addTask {
                    guard let found = try? await client.movies("/movie/\(seed.id)/recommendations", pages: 2) else { return nil }
                    return (seed, found)
                }
            }
            var all: [(seed: ExploreSeed, recommended: [TMDBMovieSummary])] = []
            for await source in group { if let source { all.append(source) } }
            return all
        }
        // Offline: what the lists agree on stands in for this time (nothing is kept, so it's tried
        // again when Explore opens next); with nothing at all, the row offers to try again.
        guard !sources.isEmpty || seeds.isEmpty else {
            let fallback = listPicksForExplore(excluding: [])
            if !fallback.isEmpty { explorePicks = fallback }
            return
        }
        let seedIDs = Set(seeds.map(\.id))
        let today = Date().formatted(.iso8601.year().month().day())
        let found = ExplorePicks.candidates(from: sources, excluding: { id in
            seedIDs.contains(id) || self.itemsByTMDB[id] != nil || self.isSeen(id) || self.wishlistIDs.contains(id)
        }, today: today)
        // The strongest few dozen looked at closely: their people, themes and tone against the
        // loved film each follows.
        let closer = Array(found.prefix(70))
        let details = await withTaskGroup(of: (Int, TMDBMovieDetails?).self) { group in
            var all: [Int: TMDBMovieDetails] = [:]
            var started = 0
            for candidate in closer where candidate.seed.features != nil {
                if started >= 8, let next = await group.next(), let detail = next.1 { all[next.0] = detail }
                started += 1
                let id = candidate.movie.id
                group.addTask { (id, try? await client.likenessDetails(id: id)) }
            }
            for await (id, detail) in group { if let detail { all[id] = detail } }
            return all
        }
        exploreCandidates = ExplorePicks.refine(closer, details: details, keep: 48, keywordCounts: keywordCounts,
                                                libraryCount: items.count)
            + found.dropFirst(closer.count).filter { $0.seed.features == nil }
        drawExplorePicks(avoiding: explorePicksBefore)
    }

    /// For You in one mood (its chips): the strongest fifteen of the films found that
    /// have it, left out once seen or wished for.
    func explorePicks(in mood: Mood) -> [ExplorePick] {
        exploreCandidates
            .filter { $0.fits(mood) && !isSeen($0.movie.id) && !wishlistIDs.contains($0.movie.id) }
            .sorted(by: ExplorePicks.order)
            .prefix(Self.forYouCount)
            .map { ExplorePick(film: PreviewFilm($0.movie, note: $0.reason.long), reason: $0.reason.long) }
    }

    /// Fifteen others from the same films, none of the ones showing now.
    func shuffleExplorePicks() {
        drawExplorePicks(avoiding: Set(explorePicks?.map(\.id) ?? []).union(explorePicksBefore))
    }

    var canShuffleExplorePicks: Bool {
        exploreCandidates.count > (explorePicks?.count ?? 0)
    }

    private func drawExplorePicks(avoiding: Set<Int>) {
        var generator = SystemRandomNumberGenerator()
        // Films marked seen or wished for since they were found are left out.
        let open = exploreCandidates.filter { !isSeen($0.movie.id) && !wishlistIDs.contains($0.movie.id) }
        var picks = ExplorePicks.sample(open, count: Self.forYouCount, avoiding: avoiding, using: &generator).map { candidate in
            ExplorePick(film: PreviewFilm(candidate.movie, note: candidate.reason.long), reason: candidate.reason.long)
        }
        // Without loved films to start from (or too few found), what the lists agree on fills in.
        if picks.count < Self.forYouCount {
            picks += listPicksForExplore(excluding: Set(picks.map(\.id))).prefix(Self.forYouCount - picks.count)
        }
        explorePicks = picks
        explorePicksShown = picks.map(\.id)
        scheduleSave(.settings)
    }

    /// Films the lists agree on, from the Lists hub's Start Here.
    private func listPicksForExplore(excluding shown: Set<Int>) -> [ExplorePick] {
        startHere().toFind
            .filter { !shown.contains($0.film.id) && $0.film.id != 0 }
            .prefix(Self.forYouCount)
            .map { ExplorePick(film: $0.film, reason: $0.reason) }
    }

    /// Up to eight films you loved (4 or 5 stars, or a heart), drawn by chance, five stars twice as
    /// likely; without any, watched films that are well rated.
    private func exploreSeeds() -> [ExploreSeed] {
        func seed(_ key: String, _ id: Int) -> ExploreSeed? {
            if let item = itemCache[key] {
                return ExploreSeed(id: id, title: item.main.displayTitle, year: item.main.displayYear, genres: Array(item.genres),
                                   features: item.likeness)
            }
            return lists.briefs[id].map { ExploreSeed(id: id, title: $0.title, year: $0.year, genres: $0.genres, features: nil) }
        }
        var loved: [(seed: ExploreSeed, weight: Int)] = []
        for (key, record) in personal.records {
            guard let id = PersonalStore.tmdbID(key) else { continue }
            let stars = record.rating ?? (record.favorite ? 4 : 0)
            guard stars >= 4, let found = seed(key, id) else { continue }
            loved.append((found, stars == 5 ? 2 : 1))
        }
        if loved.isEmpty {
            loved = items
                .filter { personal.watchedKeys.contains($0.id) && ($0.score ?? 0) >= 7 }
                .compactMap { item in item.main.tmdb.flatMap { seed(item.id, $0.id) }.map { ($0, 1) } }
        }
        var chosen: [ExploreSeed] = []
        while chosen.count < 8, !loved.isEmpty {
            var target = Int.random(in: 0..<loved.reduce(0) { $0 + $1.weight })
            var index = 0
            while target >= loved[index].weight {
                target -= loved[index].weight
                index += 1
            }
            chosen.append(loved.remove(at: index).seed)
        }
        return chosen
    }
}
#endif
