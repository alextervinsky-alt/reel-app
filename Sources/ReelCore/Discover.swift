import Foundation

/// The film lists in Explore.
public enum DiscoverList: Hashable, Sendable {
    /// In cinemas now.
    case inCinemas
    /// Most popular this week.
    case trending
    /// Popular films released three to five months ago: by now out on Blu-ray and digital.
    case newAtHome
    /// The best-rated films of one year (top 100).
    case bestOf(year: Int)
    /// Well-loved films of one mood, from any time (Explore's mood chips).
    case mood(Mood)

    public var title: String {
        switch self {
        case .inCinemas: "In Cinemas Now"
        case .trending: "Trending This Week"
        case .newAtHome: "New at Home"
        case .bestOf(let year): "Best of \(year)"
        case .mood(let mood): "\(mood.title) Films"
        }
    }

    public var subtitle: String {
        switch self {
        case .inCinemas: "Playing in cinemas right now"
        case .trending: "What everyone is watching this week"
        case .newAtHome: "Big films from 3–5 months ago, now out on Blu-ray and digital"
        case .bestOf: "The 100 best-rated films of the year on TMDB"
        case .mood(let mood): "The best-loved \(mood.title.lowercased()) films, from any time"
        }
    }

    /// TMDB path, query and number of pages (20 films each).
    public func request(today: Date = Date()) -> (path: String, query: [URLQueryItem], pages: Int) {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        func daysAgo(_ n: Int) -> String { day.string(from: today.addingTimeInterval(-Double(n) * 86_400)) }

        switch self {
        case .inCinemas:
            // US releases: the same big films that reach European cinemas, without obscure entries.
            return ("/movie/now_playing", [URLQueryItem(name: "region", value: "US")], 2)
        case .trending:
            return ("/trending/movie/week", [], 2)
        case .newAtHome:
            return ("/discover/movie", [
                URLQueryItem(name: "primary_release_date.gte", value: daysAgo(150)),
                URLQueryItem(name: "primary_release_date.lte", value: daysAgo(90)),
                URLQueryItem(name: "sort_by", value: "popularity.desc"),
                URLQueryItem(name: "vote_count.gte", value: "100"),
                URLQueryItem(name: "include_adult", value: "false"),
            ], 3)
        case .bestOf(let year):
            // Older years have fewer votes on TMDB, so the bar is lower for them.
            let minimumVotes = year >= 2000 ? 400 : 150
            return ("/discover/movie", [
                URLQueryItem(name: "primary_release_year", value: String(year)),
                URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                URLQueryItem(name: "vote_count.gte", value: String(minimumVotes)),
                URLQueryItem(name: "include_adult", value: "false"),
            ], 5)
        case .mood(let mood):
            return ("/discover/movie", MoodGenres.of(mood).query + [
                URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                URLQueryItem(name: "vote_count.gte", value: "1500"),
                URLQueryItem(name: "include_adult", value: "false"),
            ], 3)
        }
    }

    /// The mood a list keeps to, when it's a mood's own list.
    public var mood: Mood? {
        if case .mood(let mood) = self { return mood }
        return nil
    }
}

/// A recommended film with how closely it matches the one you're looking at.
public struct SimilarFilm: Identifiable, Equatable, Sendable {
    public let movie: TMDBMovieSummary
    /// 55–98.
    public let match: Int
    public var id: Int { movie.id }
}

public enum SimilarFilms {
    /// Merges TMDB's recommendations (ranked by what people who liked this film also liked) and
    /// "similar" films (same keywords and genres) into one list with a match percentage:
    /// rank in the recommendations plus genre overlap with the original film.
    public static func rank(recommendations: [TMDBMovieSummary], similar: [TMDBMovieSummary],
                            genres: Set<String>, excluding excluded: Int) -> [SimilarFilm] {
        var scores: [Int: (movie: TMDBMovieSummary, score: Double)] = [:]
        func genreOverlap(_ movie: TMDBMovieSummary) -> Double {
            let other = Set(movie.genreNames)
            let union = other.union(genres)
            return union.isEmpty ? 0 : Double(other.intersection(genres).count) / Double(union.count)
        }
        for (rank, movie) in recommendations.enumerated() where movie.id != excluded {
            let position = 1 - Double(rank) / Double(max(recommendations.count, 1)) * 0.5
            scores[movie.id] = (movie, 0.6 * position + 0.4 * genreOverlap(movie))
        }
        // "Similar" alone (not also recommended) is noisier, so it needs a well-known film.
        for movie in similar where movie.id != excluded && (scores[movie.id] != nil || (movie.voteCount ?? 0) >= 300) {
            let score = 0.6 * 0.55 + 0.4 * genreOverlap(movie)
            if let existing = scores[movie.id] {
                scores[movie.id] = (existing.movie, min(1, existing.score + 0.08))
            } else {
                scores[movie.id] = (movie, score)
            }
        }
        return scores.values
            .filter { ($0.movie.voteCount ?? 0) >= 50 }
            .sorted { $0.score != $1.score ? $0.score > $1.score : ($0.movie.voteCount ?? 0) > ($1.movie.voteCount ?? 0) }
            .prefix(20)
            .map { SimilarFilm(movie: $0.movie, match: Int((55 + $0.score * 43).rounded())) }
    }
}

/// A film you don't own yet but want to (from Explore, people pages or recommendations).
public struct WishlistFilm: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var year: Int?
    public var posterPath: String?
    public var backdropPath: String?
    public var addedAt: Date

    public init(id: Int, title: String, year: Int?, posterPath: String?, backdropPath: String?, addedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.year = year
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.addedAt = addedAt
    }
}
