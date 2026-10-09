import Foundation

/// Where Explore's "Best of" list comes from.
public enum BestOfSource: String, CaseIterable, Hashable, Sendable, Identifiable {
    case tmdb, imdb, popular, awards, gems

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tmdb: "TMDB Rating"
        case .imdb: "IMDb Rating"
        case .popular: "Most Popular"
        case .awards: "Award Winners"
        case .gems: "Hidden Gems"
        }
    }

    public func subtitle(_ year: Int) -> String {
        switch self {
        case .tmdb: "The best-rated films of \(year) on TMDB"
        case .imdb: "IMDb's Top 100 of \(year), by rating and number of votes"
        case .popular: "The films of \(year) the most people watched"
        case .awards: "What won the big prizes for \(year): the Oscars, Cannes, Venice, Berlin, BAFTA, César and more"
        case .gems: "Films of \(year) loved by those who saw them, but seen by few"
        }
    }

    /// Read from TMDB (the others come from the Lists' IMDb ratings and award lists).
    public var isTMDB: Bool { self == .tmdb || self == .popular || self == .gems }
}

/// The film lists in Explore.
public enum DiscoverList: Hashable, Sendable {
    /// In cinemas now.
    case inCinemas
    /// Most popular this week.
    case trending
    /// Popular films released three to five months ago: by now out on Blu-ray and digital.
    case newAtHome
    /// The best films of one year, by a source (from TMDB; IMDb and award winners come from Lists).
    case bestOf(year: Int, source: BestOfSource = .tmdb)
    /// Well-loved films of one mood, from any time (Explore's mood chips).
    case mood(Mood)
    // Shelves that change each time Reel opens:
    /// The best-loved films from one country's cinema.
    case country(code: String)
    /// The best-loved films of one decade (1970 for the 1970s).
    case decade(Int)
    /// What people who loved one of your favourites went on to love.
    case because(id: Int, title: String)
    /// Rated highly by the few who've seen them.
    case hiddenGems
    /// Films with one of TMDB's themes (Lists' search): "Heist", "Time Travel".
    case theme(ListSearch.Theme)

    /// Countries whose cinema Explore offers a shelf of, one each time Reel opens.
    public static let countries: [(code: String, name: String)] = [
        ("JP", "Japan"), ("KR", "South Korea"), ("FR", "France"), ("IT", "Italy"), ("DE", "Germany"), ("ES", "Spain"),
        ("MX", "Mexico"), ("IR", "Iran"), ("DK", "Denmark"), ("SE", "Sweden"), ("IN", "India"), ("BR", "Brazil"),
        ("AR", "Argentina"), ("TW", "Taiwan"), ("HK", "Hong Kong"), ("PL", "Poland"), ("RO", "Romania"), ("BE", "Belgium"),
        ("GB", "Britain"), ("IE", "Ireland"), ("NO", "Norway"), ("FI", "Finland"), ("EE", "Estonia"), ("CN", "China"),
        ("TR", "Turkey"), ("GR", "Greece"), ("HU", "Hungary"), ("CZ", "the Czech Republic"), ("AU", "Australia"), ("CA", "Canada"),
    ]
    public static let decades = [1940, 1950, 1960, 1970, 1980, 1990, 2000, 2010]

    public var title: String {
        switch self {
        case .inCinemas: "In Cinemas Now"
        case .trending: "Trending This Week"
        case .newAtHome: "New at Home"
        case .bestOf(let year, _): "Best of \(year)"
        case .mood(let mood): "\(mood.title) Films"
        case .country(let code): "Cinema from \(Self.countries.first { $0.code == code }?.name ?? code)"
        case .decade(let start): "The Best of the \(start)s"
        case .because(_, let title): "Because You Loved \(title)"
        case .hiddenGems: "Hidden Gems"
        case .theme(let theme): theme.title
        }
    }

    public var subtitle: String {
        switch self {
        case .inCinemas: "Playing in cinemas right now"
        case .trending: "What everyone is watching this week"
        case .newAtHome: "Big films from 3–5 months ago, now out on Blu-ray and digital"
        case .bestOf(let year, let source): source.subtitle(year)
        case .mood(let mood): "The best-loved \(mood.title.lowercased()) films, from any time"
        case .country: "Its best-loved films, from any time · a different country each time Reel opens"
        case .decade: "The decade's best-loved films · a different decade each time Reel opens"
        case .because: "What people who loved it went on to love · a different film of yours each time"
        case .hiddenGems: "Rated highly by the few who've seen them, from any time"
        case .theme(let theme): "Films about \(theme.name), the best-rated first"
        }
    }

    /// Shelves whose order may change each time Reel opens (within films of about the same rating):
    /// the ones that rank by quality, not by the week's news or a list's own order.
    public var reshuffles: Bool {
        switch self {
        case .mood, .country, .decade, .hiddenGems: true
        default: false
        }
    }

    /// TMDB path, query and number of pages (20 films each).
    public func request(today: Date = Date()) -> (path: String, query: [URLQueryItem], pages: Int) {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        func daysAgo(_ n: Int) -> String { day.string(from: today.addingTimeInterval(-Double(n) * 86_400)) }
        let noAdult = URLQueryItem(name: "include_adult", value: "false")

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
                noAdult,
            ], 3)
        case .bestOf(let year, let source):
            // Older years have fewer votes on TMDB, so the bar is lower for them.
            let old = year < 2000
            let year = URLQueryItem(name: "primary_release_year", value: String(year))
            switch source {
            case .popular:
                return ("/discover/movie", [year, URLQueryItem(name: "sort_by", value: "popularity.desc"),
                                            URLQueryItem(name: "vote_count.gte", value: "50"), noAdult], 3)
            case .gems:
                return ("/discover/movie", [year, URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                                            URLQueryItem(name: "vote_average.gte", value: "7"),
                                            URLQueryItem(name: "vote_count.gte", value: old ? "40" : "80"),
                                            URLQueryItem(name: "vote_count.lte", value: old ? "400" : "900"), noAdult], 3)
            case .tmdb, .imdb, .awards:
                return ("/discover/movie", [year, URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                                            URLQueryItem(name: "vote_count.gte", value: old ? "150" : "400"), noAdult], 5)
            }
        case .mood(let mood):
            return ("/discover/movie", MoodGenres.of(mood).query + [
                URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                URLQueryItem(name: "vote_count.gte", value: "1500"),
                noAdult,
            ], 3)
        case .country(let code):
            return ("/discover/movie", [
                URLQueryItem(name: "with_origin_country", value: code),
                URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                URLQueryItem(name: "vote_count.gte", value: code == "GB" ? "2000" : "250"),
                noAdult,
            ], 3)
        case .decade(let start):
            return ("/discover/movie", [
                URLQueryItem(name: "primary_release_date.gte", value: "\(start)-01-01"),
                URLQueryItem(name: "primary_release_date.lte", value: "\(start + 9)-12-31"),
                URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                URLQueryItem(name: "vote_count.gte", value: start < 1970 ? "400" : "1200"),
                noAdult,
            ], 3)
        case .because(let id, _):
            return ("/movie/\(id)/recommendations", [], 2)
        case .hiddenGems:
            return ("/discover/movie", [
                URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                URLQueryItem(name: "vote_average.gte", value: "7.4"),
                URLQueryItem(name: "vote_count.gte", value: "150"),
                URLQueryItem(name: "vote_count.lte", value: "1200"),
                URLQueryItem(name: "primary_release_date.gte", value: "1950-01-01"),
                noAdult,
            ], 5)
        case .theme(let theme):
            return ("/discover/movie", [
                URLQueryItem(name: "with_keywords", value: String(theme.id)),
                URLQueryItem(name: "sort_by", value: "vote_average.desc"),
                URLQueryItem(name: "vote_count.gte", value: "60"),
                noAdult,
            ], 3)
        }
    }

    /// The mood a list keeps to, when it's a mood's own list.
    public var mood: Mood? {
        if case .mood(let mood) = self { return mood }
        return nil
    }

    /// Three shelves for this launch, by chance: one of your loved films' (when there are
    /// any), a country's cinema, and a decade or the hidden gems.
    public static func shelves<G: RandomNumberGenerator>(loved: [(id: Int, title: String)], using generator: inout G) -> [DiscoverList] {
        var shelves: [DiscoverList] = []
        if let film = loved.randomElement(using: &generator) { shelves.append(.because(id: film.id, title: film.title)) }
        if let country = countries.randomElement(using: &generator) { shelves.append(.country(code: country.code)) }
        if Bool.random(using: &generator), let decade = decades.randomElement(using: &generator) {
            shelves.append(.decade(decade))
        } else {
            shelves.append(.hiddenGems)
        }
        return shelves
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
