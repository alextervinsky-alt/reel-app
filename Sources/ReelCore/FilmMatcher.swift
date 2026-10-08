import Foundation

public enum MatchConfidence: String, Codable, Sendable {
    /// Sure enough to accept without asking.
    case auto
    /// Probably right, but worth a glance.
    case review
    /// No good candidate; needs a manual search.
    case manual
}

public struct ScoredCandidate: Codable, Equatable, Sendable {
    public var movie: TMDBMovieSummary
    public var score: Double

    public init(movie: TMDBMovieSummary, score: Double) {
        self.movie = movie
        self.score = score
    }
}

public struct MatchResult: Sendable {
    public var best: ScoredCandidate?
    public var confidence: MatchConfidence
    public var candidates: [ScoredCandidate]
}

public enum TitleSimilarity {
    /// Lowercase, no accents, no punctuation, "&" → "and", no leading "the".
    public static func normalize(_ s: String) -> String {
        var t = s.lowercased()
        t = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        t = t.replacingOccurrences(of: "&", with: " and ")
        t = t.replacingOccurrences(of: "'", with: "")
        t = t.replacingOccurrences(of: "’", with: "")
        var cleaned = ""
        for ch in t {
            cleaned.append(ch.isLetter || ch.isNumber ? ch : " ")
        }
        var words = cleaned.split(separator: " ").map { String($0) }
        if words.count > 1 && words.first == "the" { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// 1.0 means the same title, 0 means nothing in common.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(normalize(a))
        let y = Array(normalize(b))
        if x.isEmpty || y.isEmpty { return 0 }
        if x == y { return 1 }
        let distance = levenshtein(x, y)
        return max(0, 1 - Double(distance) / Double(max(x.count, y.count)))
    }

    /// Edit distance between two strings (for typo-tolerant search).
    public static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        return levenshtein(x, y)
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

public struct FilmMatcher: Sendable {
    public static let autoThreshold = 0.90
    public static let reviewThreshold = 0.60

    let database: any MovieDatabase

    public init(database: any MovieDatabase) {
        self.database = database
    }

    /// Searches TMDB with title + year; if that finds nothing, tries the title alone.
    public func match(title: String, year: Int?) async throws -> MatchResult {
        var results = try await database.searchMovies(query: title, year: year)
        if results.isEmpty && year != nil {
            results = try await database.searchMovies(query: title, year: nil)
        }
        return Self.rank(results, title: title, year: year)
    }

    /// Tries each title in turn (file name, folder name…) until one gives a sure match; otherwise
    /// returns the best of them.
    public func match(titles: [String], year: Int?) async throws -> MatchResult {
        var best: MatchResult?
        for title in titles {
            let result = try await match(title: title, year: year)
            if result.confidence == .auto { return result }
            if let score = result.best?.score, score > (best?.best?.score ?? -1) { best = result }
        }
        return best ?? MatchResult(best: nil, confidence: .manual, candidates: [])
    }

    public static func score(_ movie: TMDBMovieSummary, title: String, year: Int?) -> Double {
        let titleScore = max(
            TitleSimilarity.similarity(title, movie.title),
            TitleSimilarity.similarity(title, movie.originalTitle ?? "")
        )
        let yearFactor: Double
        if let wanted = year {
            if let actual = movie.year {
                switch abs(wanted - actual) {
                case 0: yearFactor = 1.0
                case 1: yearFactor = 0.92
                default: yearFactor = 0.6
                }
            } else {
                yearFactor = 0.8
            }
        } else {
            yearFactor = 0.85
        }
        return titleScore * yearFactor
    }

    public static func rank(_ results: [TMDBMovieSummary], title: String, year: Int?) -> MatchResult {
        let scored = results
            .map { ScoredCandidate(movie: $0, score: score($0, title: title, year: year)) }
            .sorted {
                if abs($0.score - $1.score) > 0.0001 { return $0.score > $1.score }
                return ($0.movie.voteCount ?? 0) > ($1.movie.voteCount ?? 0)
            }
        guard let best = scored.first else {
            return MatchResult(best: nil, confidence: .manual, candidates: [])
        }

        var confidence: MatchConfidence
        if best.score >= autoThreshold, year != nil, best.movie.year == year {
            confidence = .auto
            // Two near-identical candidates (e.g. same title, same year): ask instead of guessing,
            // unless one is clearly the well-known film.
            if scored.count > 1 {
                let runnerUp = scored[1]
                let bestVotes = best.movie.voteCount ?? 0
                let runnerVotes = runnerUp.movie.voteCount ?? 0
                if best.score - runnerUp.score < 0.02 && runnerVotes * 4 > bestVotes {
                    confidence = .review
                }
            }
        } else if best.score >= reviewThreshold {
            confidence = .review
        } else {
            confidence = .manual
        }
        return MatchResult(best: best, confidence: confidence, candidates: Array(scored.prefix(8)))
    }
}
