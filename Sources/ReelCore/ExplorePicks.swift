import Foundation

/// A film you loved that Picked for You starts from.
public struct ExploreSeed: Sendable {
    public let id: Int
    public let title: String
    public let year: Int?
    public let genres: Set<String>
    /// Its people, themes and tone, when it's in the library (see `Likeness`).
    public let features: LikenessFeatures?

    public init(id: Int, title: String, year: Int?, genres: [String], features: LikenessFeatures?) {
        self.id = id
        self.title = title
        self.year = year
        self.genres = Set(genres)
        self.features = features
    }
}

/// A film Explore's Picked for You might show, and why.
public struct ExploreCandidate: Sendable {
    public let movie: TMDBMovieSummary
    public let score: Double
    /// The loved film it follows most closely.
    public let seed: ExploreSeed
    /// It has a director of `seed`.
    public let sameDirector: Bool
    /// How it feels, when it was looked at closely (keywords too); otherwise its genres tell.
    public let moods: Set<Mood>?

    public init(movie: TMDBMovieSummary, score: Double, seed: ExploreSeed, sameDirector: Bool = false, moods: Set<Mood>? = nil) {
        self.movie = movie
        self.score = score
        self.seed = seed
        self.sameDirector = sameDirector
        self.moods = moods
    }

    /// Whether it has `mood` (Explore's mood chips).
    public func fits(_ mood: Mood) -> Bool {
        // Looked at closely but no mood stood out: its genres tell instead.
        if let moods, !moods.isEmpty { return moods.contains(mood) }
        return MoodGenres.of(mood).fits(movie.genreNames)
    }

    /// "From the director of Her", or "Because you loved Her".
    public var reason: PickReason {
        sameDirector ? .director(film: seed.title) : .alike(film: seed.title)
    }
}

/// Picked for You: films that people who loved your favourites went on to love (TMDB's
/// recommendations), kept only when they're truly alike (the same kind of film, from about the
/// same time, sharing people, themes or tone), a different dozen each time Reel opens.
public enum ExplorePicks {
    /// The films recommended after films you loved: the higher on a film's list and the more
    /// lists it's on, the stronger; being well rated helps. A film sharing no genre with the film
    /// it was recommended after doesn't count for it, and one from a much earlier or later time
    /// counts less. Films not out yet, little known (under 150 votes) or rated under 6.8 are left
    /// out, and so is anything `excluding` says (films you have, have seen or wished for).
    public static func candidates(from sources: [(seed: ExploreSeed, recommended: [TMDBMovieSummary])],
                                  excluding: (Int) -> Bool, today: String) -> [ExploreCandidate] {
        var strength: [Int: Double] = [:]
        var strongest: [Int: (weight: Double, seed: ExploreSeed)] = [:]
        var movies: [Int: TMDBMovieSummary] = [:]
        for source in sources {
            for (rank, movie) in source.recommended.enumerated() {
                guard movie.posterPath != nil, (movie.voteCount ?? 0) >= 150, (movie.voteAverage ?? 0) >= 6.8,
                      let released = movie.releaseDate, !released.isEmpty, released <= today,
                      !excluding(movie.id) else { continue }
                let genres = Set(movie.genreNames)
                if !source.seed.genres.isEmpty, !genres.isEmpty, source.seed.genres.isDisjoint(with: genres) { continue }
                let weight = 1 / (1 + Double(rank) / 6) * era(source.seed.year, movie.year)
                strength[movie.id, default: 0] += weight
                movies[movie.id] = movie
                if weight > (strongest[movie.id]?.weight ?? 0) { strongest[movie.id] = (weight, source.seed) }
            }
        }
        return movies.values
            .compactMap { movie in
                guard let seed = strongest[movie.id]?.seed else { return nil }
                return ExploreCandidate(movie: movie, score: (strength[movie.id] ?? 0) + quality(movie.voteAverage), seed: seed)
            }
            .sorted(by: order)
    }

    /// How much closer in time counts: full within 12 years, then less and less (a 1938 comedy
    /// is a poor pick after a 2024 one).
    static func era(_ a: Int?, _ b: Int?) -> Double {
        guard let a, let b else { return 1 }
        return 1 / (1 + Double(max(0, abs(a - b) - 12)) / 12)
    }

    static func quality(_ vote: Double?) -> Double {
        ((vote ?? 7) - 7) * 0.5
    }

    public static func order(_ a: ExploreCandidate, _ b: ExploreCandidate) -> Bool {
        a.score != b.score ? a.score > b.score : a.movie.id < b.movie.id
    }

    /// The strongest candidates looked at closely (`details` for each, with credits and
    /// keywords): how alike each really is to the loved film it follows (`Likeness`: people,
    /// rare themes, tone, kind of film). Those barely alike are left out while enough remain.
    public static func refine(_ candidates: [ExploreCandidate], details: [Int: TMDBMovieDetails], keep: Int,
                              keywordCounts: [String: Int], libraryCount: Int) -> [ExploreCandidate] {
        var scored: [(candidate: ExploreCandidate, likeness: Double)] = []
        for candidate in candidates {
            guard let seen = candidate.seed.features, let detail = details[candidate.movie.id] else {
                scored.append((candidate, Likeness.threshold))
                continue
            }
            let features = LikenessFeatures(details: detail)
            let likeness = Likeness.score(seen, features, keywordCounts: keywordCounts, libraryCount: libraryCount)
            let sameDirector = !seen.directors.isDisjoint(with: features.directors)
            scored.append((ExploreCandidate(movie: candidate.movie, score: candidate.score + 0.35 * likeness,
                                            seed: candidate.seed, sameDirector: sameDirector, moods: features.moods), likeness))
        }
        let alike = scored.filter { $0.likeness >= Likeness.threshold }.map(\.candidate)
        let rest = scored.filter { $0.likeness < Likeness.threshold }.map(\.candidate)
        // Barely alike ones only make up the numbers.
        return alike.sorted(by: order) + (alike.count >= keep ? [] : Array(rest.sorted(by: order).prefix(keep - alike.count)))
    }

    /// `count` of the strongest, drawn by chance (the stronger, the likelier), best first. Films
    /// shown last time are left out while there are enough others.
    public static func sample<G: RandomNumberGenerator>(_ candidates: [ExploreCandidate], count: Int,
                                                         avoiding previous: Set<Int>, using generator: inout G) -> [ExploreCandidate] {
        var pool = Array(candidates.filter { !previous.contains($0.movie.id) }.prefix(count * 3))
        var chosen: [ExploreCandidate] = []
        while chosen.count < count, !pool.isEmpty {
            let weights = pool.map { max(0.05, $0.score) * max(0.05, $0.score) }
            var target = Double.random(in: 0..<weights.reduce(0, +), using: &generator)
            var index = 0
            while index < pool.count - 1, target >= weights[index] {
                target -= weights[index]
                index += 1
            }
            chosen.append(pool.remove(at: index))
        }
        // Too few new ones: the strongest of the rest fill up.
        for candidate in candidates where chosen.count < count && !chosen.contains(where: { $0.movie.id == candidate.movie.id }) {
            chosen.append(candidate)
        }
        return chosen.sorted(by: order)
    }
}

extension LikenessFeatures {
    /// A film outside the library, from its TMDB details (with credits and keywords).
    public init(details d: TMDBMovieDetails) {
        self.init(tmdbID: d.id, directors: d.directors, writers: d.writers, cinematographers: d.cinematographers,
                  cast: d.topCast.prefix(5).map(\.name), composers: d.people(forJobs: TMDBMovieDetails.composerJobs).map(\.name),
                  genres: d.genreNames, keywords: d.keywordNames,
                  moods: MoodClassifier.moods(genres: d.genreNames, keywords: d.keywordNames, runtime: d.runtime), year: d.year)
    }
}
