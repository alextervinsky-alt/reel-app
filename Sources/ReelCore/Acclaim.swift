import Foundation

/// The year's most acclaimed films: the ones critics loved, audiences loved, that many people saw
/// and talked about, and that won or were up for the big prizes. No one source decides: a film
/// rated highly on one site alone (a large home audience voting, say) ranks below one that critics
/// and audiences everywhere agree on.
public enum Acclaim {
    /// The big prizes, as the award lists have them.
    public enum Prize: Int, Comparable, Sendable {
        case nominated = 1, won, topPrize

        public static func < (lhs: Prize, rhs: Prize) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The festivals' top prizes and Best Picture.
        static let top: Set<AwardList> = [.palmeDOr, .goldenLion, .goldenBear, .oscarBestPicture]

        var weight: Double {
            switch self {
            case .topPrize: 1
            case .won: 0.75
            case .nominated: 0.45
            }
        }
    }

    public struct Candidate: Equatable, Sendable {
        public var film: IMDbFilm
        /// TMDB's audience, worldwide: its average and how many voted.
        public var tmdbVote: Double?
        public var tmdbVotes: Int?
        /// The critics: Metacritic (out of 100) and Rotten Tomatoes (percent), via OMDb.
        public var metacritic: Int?
        public var rottenTomatoes: Int?
        /// Its best showing at the big prizes, and what it was ("Palme d'Or", "Nominated: Oscar for Best Picture").
        public var prize: Prize?
        public var prizeName: String?

        public init(film: IMDbFilm, tmdbVote: Double? = nil, tmdbVotes: Int? = nil, metacritic: Int? = nil, rottenTomatoes: Int? = nil,
                    prize: Prize? = nil, prizeName: String? = nil) {
            self.film = film
            self.tmdbVote = tmdbVote
            self.tmdbVotes = tmdbVotes
            self.metacritic = metacritic
            self.rottenTomatoes = rottenTomatoes
            self.prize = prize
            self.prizeName = prizeName
        }

        /// What critics said, 0 to 1 (nil when no critics' score is known).
        var critics: Double? {
            let scores = [metacritic.map { Acclaim.clamp((Double($0) - 50) / 40) }, rottenTomatoes.map { Acclaim.clamp((Double($0) - 60) / 40) }]
                .compactMap { $0 }
            return scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        }

        /// What audiences said, 0 to 1: IMDb's rating and TMDB's. When IMDb's is far above TMDB's,
        /// TMDB's counts twice: one site's voters alone don't make a film acclaimed.
        var audience: Double {
            let imdb = Acclaim.clamp((film.rating - 5.5) / 3)
            guard let tmdbVote, (tmdbVotes ?? 0) >= 100 else { return imdb }
            let tmdb = Acclaim.clamp((tmdbVote - 5.5) / 3)
            return film.rating - tmdbVote >= 1 ? (imdb + 2 * tmdb) / 3 : (imdb + tmdb) / 2
        }
    }

    /// Who's in the running for a year: its most-voted films (the ones that made themselves known)
    /// and every film the award lists have for it.
    public static func pool(_ films: [IMDbFilm], year: Int, awarded: Set<String>, size: Int = 120) -> [IMDbFilm] {
        let ofYear = films.filter { $0.year == year }
        let known = ofYear.sorted { $0.votes != $1.votes ? $0.votes > $1.votes : $0.id < $1.id }.prefix(size)
        let ids = Set(known.map(\.id))
        return Array(known) + ofYear.filter { awarded.contains($0.id) && !ids.contains($0.id) }
    }

    /// Ranked, the most acclaimed first: critics 35%, audiences 30%, how widely seen 20% (its place
    /// among the year's films by votes) and prizes 15%. With no critics' score, the critics' part
    /// counts half of what audiences said: a film critics never reviewed is less known for sure.
    public static func rank(_ candidates: [Candidate]) -> [(candidate: Candidate, score: Double)] {
        let byVotes = candidates.map(\.film.votes).sorted()
        func seen(_ votes: Int) -> Double {
            guard byVotes.count > 1 else { return 1 }
            let below = byVotes.firstIndex { $0 >= votes } ?? byVotes.count
            return Double(below) / Double(byVotes.count - 1)
        }
        return candidates
            .map { candidate in
                let audience = candidate.audience
                let critics = candidate.critics ?? audience / 2
                let score = 0.35 * critics + 0.30 * audience + 0.20 * seen(candidate.film.votes) + 0.15 * (candidate.prize?.weight ?? 0)
                return (candidate, score)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.candidate.film.votes > $1.candidate.film.votes }
    }

    /// "Metacritic 95 · IMDb 7.9": the critics' score when known, and the audience's.
    public static func note(_ candidate: Candidate) -> String {
        var parts: [String] = []
        if let metacritic = candidate.metacritic {
            parts.append("Metacritic \(metacritic)")
        } else if let rottenTomatoes = candidate.rottenTomatoes {
            parts.append("RT \(rottenTomatoes)%")
        }
        parts.append("IMDb " + String(format: "%.1f", candidate.film.rating))
        if parts.count == 1, let tmdbVote = candidate.tmdbVote, (candidate.tmdbVotes ?? 0) >= 100 {
            parts.append("TMDB " + String(format: "%.1f", tmdbVote))
        }
        return parts.joined(separator: " · ")
    }

    /// The best prize each film of the award lists had: a top prize won, another won, or nominated.
    public static func prizes(_ lists: [(award: AwardList, films: [ListFilm])], year: Int) -> [String: (prize: Prize, name: String)] {
        var best: [String: (prize: Prize, name: String)] = [:]
        for (award, films) in lists where award != .criterion {
            for film in films where film.year == year {
                guard let id = film.imdbID else { continue }
                let prize: Prize = film.isWinner ? (Prize.top.contains(award) ? .topPrize : .won) : .nominated
                let name = film.isWinner ? award.title : "Nominated: " + award.title
                if let known = best[id], known.prize >= prize { continue }
                best[id] = (prize, name)
            }
        }
        return best
    }

    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

/// The critics' scores of a film outside the library (via OMDb), kept for a month.
public struct CriticScores: Codable, Equatable, Sendable {
    public var metacritic: Int?
    public var rottenTomatoes: Int?
    public var checkedAt: Date

    public init(metacritic: Int?, rottenTomatoes: Int?, checkedAt: Date = Date()) {
        self.metacritic = metacritic
        self.rottenTomatoes = rottenTomatoes
        self.checkedAt = checkedAt
    }

    public static let maxAge: TimeInterval = 30 * 86_400
}
