import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Models

/// A film as it appears in TMDB search results.
public struct TMDBMovieSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var originalTitle: String?
    public var releaseDate: String?
    public var overview: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var popularity: Double?
    public var voteAverage: Double?
    public var voteCount: Int?
    public var genreIDs: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, popularity
        case genreIDs = "genre_ids"
        case originalTitle = "original_title"
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }

    public init(
        id: Int, title: String, originalTitle: String? = nil, releaseDate: String? = nil,
        overview: String? = nil, posterPath: String? = nil, backdropPath: String? = nil,
        popularity: Double? = nil, voteAverage: Double? = nil, voteCount: Int? = nil, genreIDs: [Int]? = nil
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.releaseDate = releaseDate
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.popularity = popularity
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.genreIDs = genreIDs
    }

    public var year: Int? { yearFromDate(releaseDate) }

    public var genreNames: [String] { (genreIDs ?? []).compactMap { TMDBGenreNames.byID[$0] } }
}

/// TMDB's fixed movie genre list (lists only carry the ids).
public enum TMDBGenreNames {
    public static let byID: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime", 99: "Documentary",
        18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
        9648: "Mystery", 10749: "Romance", 878: "Science Fiction", 10770: "TV Movie", 53: "Thriller",
        10752: "War", 37: "Western",
    ]
}

public struct TMDBGenre: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
}

public struct TMDBVideo: Codable, Equatable, Sendable {
    public var key: String
    public var site: String
    public var type: String
    public var name: String?
    /// Uploaded by the studio or distributor, as TMDB records it.
    public var official: Bool?
    /// "en", "ko"… (nil when the video has no language).
    public var language: String?
    /// "2019-05-28T09:00:00.000Z"; sorts by date as text.
    public var publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case key, site, type, name, official
        case language = "iso_639_1"
        case publishedAt = "published_at"
    }

    public init(key: String, site: String, type: String, name: String? = nil, official: Bool? = nil,
                language: String? = nil, publishedAt: String? = nil) {
        self.key = key
        self.site = site
        self.type = type
        self.name = name
        self.official = official
        self.language = language
        self.publishedAt = publishedAt
    }
}

public struct TMDBVideoList: Codable, Equatable, Sendable {
    public var results: [TMDBVideo]
}

public struct TMDBCastMember: Codable, Equatable, Sendable {
    public var id: Int?
    public var name: String
    public var character: String?
    public var profilePath: String?
    public var order: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, character, order
        case profilePath = "profile_path"
    }
}

public struct TMDBCrewMember: Codable, Equatable, Sendable {
    public var id: Int?
    public var name: String
    public var job: String?
}

public struct TMDBCredits: Codable, Equatable, Sendable {
    public var cast: [TMDBCastMember]
    public var crew: [TMDBCrewMember]
}

public struct TMDBCountry: Codable, Equatable, Sendable {
    public var name: String
}

public struct TMDBCollectionRef: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
}

/// A franchise ("Blade Runner Collection") with its films.
public struct TMDBCollection: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var posterPath: String?
    public var parts: [TMDBMovieSummary]

    enum CodingKeys: String, CodingKey {
        case id, name, parts
        case posterPath = "poster_path"
    }

    public init(id: Int, name: String, posterPath: String? = nil, parts: [TMDBMovieSummary]) {
        self.id = id
        self.name = name
        self.posterPath = posterPath
        self.parts = parts
    }
}

public struct TMDBKeyword: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
}

public struct TMDBKeywordList: Codable, Equatable, Sendable {
    public var keywords: [TMDBKeyword]
}

public struct TMDBImageInfo: Codable, Equatable, Sendable {
    public var filePath: String
    public var language: String?
    public var voteAverage: Double?
    public var voteCount: Int?
    public var width: Int?
    public var height: Int?

    enum CodingKeys: String, CodingKey {
        case width, height
        case filePath = "file_path"
        case language = "iso_639_1"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }
}

extension TMDBImageInfo {
    init(filePath: String, language: String? = nil) {
        self.init(filePath: filePath, language: language, voteAverage: nil, voteCount: nil, width: nil, height: nil)
    }
}

public struct TMDBImageSet: Codable, Equatable, Sendable {
    public var backdrops: [TMDBImageInfo]?
    public var logos: [TMDBImageInfo]?
}

public struct TMDBReview: Codable, Equatable, Sendable {
    public struct AuthorDetails: Codable, Equatable, Sendable {
        public var rating: Double?
    }

    public var content: String
    public var authorDetails: AuthorDetails?

    enum CodingKeys: String, CodingKey {
        case content
        case authorDetails = "author_details"
    }
}

public struct TMDBReviewList: Codable, Equatable, Sendable {
    public var results: [TMDBReview]
}

/// Full film information, fetched once per film and stored in the library.
public struct TMDBMovieDetails: Codable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var originalTitle: String?
    public var tagline: String?
    public var overview: String?
    public var runtime: Int?
    public var releaseDate: String?
    public var genres: [TMDBGenre]?
    public var posterPath: String?
    public var backdropPath: String?
    public var voteAverage: Double?
    public var voteCount: Int?
    public var imdbID: String?
    public var videos: TMDBVideoList?
    public var credits: TMDBCredits?
    public var keywords: TMDBKeywordList?
    public var images: TMDBImageSet?
    /// Only present right after fetching; turned into a reception summary and then dropped.
    public var reviews: TMDBReviewList?
    public var collection: TMDBCollectionRef?
    public var budget: Int?
    public var revenue: Int?
    public var originalLanguage: String?
    public var productionCountries: [TMDBCountry]?

    enum CodingKeys: String, CodingKey {
        case id, title, tagline, overview, runtime, genres, videos, credits, keywords, images, reviews, budget, revenue
        case collection = "belongs_to_collection"
        case originalLanguage = "original_language"
        case productionCountries = "production_countries"
        case originalTitle = "original_title"
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case imdbID = "imdb_id"
    }

    public init(id: Int, title: String, releaseDate: String? = nil) {
        self.id = id
        self.title = title
        self.releaseDate = releaseDate
    }

    public var year: Int? { yearFromDate(releaseDate) }

    public var genreNames: [String] { (genres ?? []).map { $0.name } }

    public var directors: [String] {
        (credits?.crew ?? []).filter { $0.job == "Director" }.map { $0.name }
    }

    public var writers: [String] { crew(Self.writerJobs) }

    private func crew(_ jobs: Set<String>) -> [String] {
        people(forJobs: jobs).map { $0.name }
    }

    /// Crew members with these jobs, once each, in credit order.
    public func people(forJobs jobs: Set<String>) -> [TMDBCrewMember] {
        var seen = Set<String>()
        return (credits?.crew ?? [])
            .filter { jobs.contains($0.job ?? "") }
            .filter { seen.insert($0.name).inserted }
    }

    public static let writerJobs: Set<String> = ["Screenplay", "Writer"]
    public static let composerJobs: Set<String> = ["Original Music Composer", "Music"]

    public var cinematographers: [String] { crew(["Director of Photography"]) }

    public var keywordNames: [String] { (keywords?.keywords ?? []).map { $0.name } }

    /// Frames from the film: backdrops without text on them, best first.
    public var stillPaths: [String] {
        (images?.backdrops ?? []).filter { $0.language == nil }.map { $0.filePath }
    }

    /// The film's title logo (transparent PNG), English first.
    public var logoPath: String? {
        let logos = images?.logos ?? []
        return (logos.first { $0.language == "en" } ?? logos.first)?.filePath
    }

    public var topCast: [TMDBCastMember] {
        Array((credits?.cast ?? []).sorted { ($0.order ?? 999) < ($1.order ?? 999) }.prefix(8))
    }

    static let keptCrewJobs: Set<String> = [
        "Director", "Screenplay", "Writer", "Director of Photography", "Original Music Composer",
        "Music", "Editor", "Production Design",
    ]

    /// Keeps the stored library small: only what Reel shows. Reviews are dropped (they are
    /// summarised first), stills are limited to 30 and logos to one.
    public func trimmed() -> TMDBMovieDetails {
        var copy = self
        if let c = credits {
            copy.credits = TMDBCredits(
                cast: Array(c.cast.sorted { ($0.order ?? 999) < ($1.order ?? 999) }.prefix(12)),
                crew: c.crew.filter { Self.keptCrewJobs.contains($0.job ?? "") }
            )
        }
        if let v = videos {
            // Only official trailers and teasers are kept: nothing else is ever played.
            copy.videos = TMDBVideoList(results: Array(v.results.filter(Trailers.isOfficial).prefix(6)))
        }
        if let k = keywords {
            copy.keywords = TMDBKeywordList(keywords: Array(k.keywords.prefix(40)))
        }
        if let set = images {
            // Frames have no text on them (language nil) and are uploaded at full resolution;
            // the most voted ones are usually real stills rather than promo art.
            let stills = (set.backdrops ?? [])
                .filter { $0.language == nil && ($0.width ?? 1920) >= 1280 }
                .sorted { ($0.voteCount ?? 0, $0.voteAverage ?? 0) > ($1.voteCount ?? 0, $1.voteAverage ?? 0) }
                .prefix(40)
                .map { TMDBImageInfo(filePath: $0.filePath) }
            let logo = (set.logos ?? []).first { $0.language == "en" } ?? set.logos?.first
            copy.images = TMDBImageSet(
                backdrops: Array(stills),
                logos: logo.map { [TMDBImageInfo(filePath: $0.filePath, language: $0.language)] }
            )
        }
        copy.reviews = nil
        return copy
    }
}

func yearFromDate(_ date: String?) -> Int? {
    guard let d = date, d.count >= 4 else { return nil }
    return Int(d.prefix(4))
}

public enum TMDBImage {
    public static func url(_ path: String?, size: String = "w342") -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(p)")
    }
}

// MARK: - Client

public protocol MovieDatabase: Sendable {
    func searchMovies(query: String, year: Int?) async throws -> [TMDBMovieSummary]
    func movieDetails(id: Int) async throws -> TMDBMovieDetails
}

public enum TMDBError: Error, LocalizedError {
    case unauthorized
    case badStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "TMDB did not accept the token."
        case .badStatus(let code): return "TMDB answered with error \(code)."
        }
    }
}

public final class TMDBClient: MovieDatabase, @unchecked Sendable {
    private let token: String
    private let session: URLSession

    /// No disk cache, no cookies: TMDB requests leave nothing behind on the Mac.
    public static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    public init(token: String, session: URLSession = TMDBClient.sharedSession) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    struct SearchResponse: Decodable {
        let results: [TMDBMovieSummary]
    }

    public func searchMovies(query: String, year: Int?) async throws -> [TMDBMovieSummary] {
        var items = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
        ]
        if let y = year { items.append(URLQueryItem(name: "year", value: String(y))) }
        let response: SearchResponse = try await get("/search/movie", items)
        return response.results
    }

    struct ListResponse: Decodable {
        let results: [TMDBMovieSummary]
    }

    /// One or more pages of a TMDB film list (trending, discover…), duplicates removed.
    public func movies(_ path: String, _ query: [URLQueryItem] = [], pages: Int = 1) async throws -> [TMDBMovieSummary] {
        var all: [TMDBMovieSummary] = []
        var seen = Set<Int>()
        for page in 1...max(pages, 1) {
            let response: ListResponse
            do {
                response = try await get(path, query + [URLQueryItem(name: "page", value: String(page))])
            } catch {
                // A later page failing keeps the pages already fetched.
                if page == 1 { throw error }
                break
            }
            for movie in response.results where seen.insert(movie.id).inserted { all.append(movie) }
            if response.results.count < 20 { break }
        }
        return all
    }

    /// A film's official videos in English, its original language and without a language
    /// (asked for when a film page opens, so original-language trailers are found too).
    public func videos(id: Int, originalLanguage: String?) async throws -> [TMDBVideo] {
        let languages = ["en", originalLanguage, "null"].compactMap { $0 }.joined(separator: ",")
        let list: TMDBVideoList = try await get("/movie/\(id)/videos", [URLQueryItem(name: "include_video_language", value: languages)])
        return list.results.filter(Trailers.isOfficial)
    }

    /// Details for a film outside the library: trailer only, kept light.
    public func previewDetails(id: Int) async throws -> TMDBMovieDetails {
        try await get("/movie/\(id)", [URLQueryItem(name: "append_to_response", value: "videos")])
    }

    /// What Picked for You compares a film by (`LikenessFeatures`): its credits and keywords.
    public func likenessDetails(id: Int) async throws -> TMDBMovieDetails {
        try await get("/movie/\(id)", [URLQueryItem(name: "append_to_response", value: "credits,keywords")])
    }

    /// What Reel keeps about a film outside the library (`FilmBrief`): with its credits, for
    /// the director.
    public func briefDetails(id: Int) async throws -> TMDBMovieDetails {
        try await get("/movie/\(id)", [URLQueryItem(name: "append_to_response", value: "credits")])
    }

    /// The TMDB film for an IMDb id ("tt0137523").
    public func find(imdbID: String) async throws -> TMDBMovieSummary? {
        struct FindResponse: Decodable {
            let movieResults: [TMDBMovieSummary]
            enum CodingKeys: String, CodingKey { case movieResults = "movie_results" }
        }
        let response: FindResponse = try await get("/find/\(imdbID)", [URLQueryItem(name: "external_source", value: "imdb_id")])
        return response.movieResults.first
    }

    /// A film's basic details (poster, year, rating), without anything appended.
    public func movieSummary(id: Int) async throws -> TMDBMovieDetails {
        try await get("/movie/\(id)", [])
    }

    /// A franchise with all its films.
    public func collection(id: Int) async throws -> TMDBCollection {
        try await get("/collection/\(id)", [])
    }

    /// A person with all their film credits.
    public func person(id: Int) async throws -> TMDBPerson {
        try await get("/person/\(id)", [URLQueryItem(name: "append_to_response", value: "movie_credits")])
    }

    /// Everything about one film in a single request, reviews included. Call `trimmed()` before storing.
    public func movieDetails(id: Int) async throws -> TMDBMovieDetails {
        try await get("/movie/\(id)", [
            URLQueryItem(name: "append_to_response", value: "videos,credits,keywords,images,reviews"),
            URLQueryItem(name: "include_image_language", value: "en,null"),
        ])
    }

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(string: "https://api.themoviedb.org/3" + path)!
        components.queryItems = query + [URLQueryItem(name: "language", value: "en-US")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var attempt = 0
        while true {
            attempt += 1
            let (data, status) = try await send(request)
            if status == 401 { throw TMDBError.unauthorized }
            if status == 429 && attempt < 4 {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                continue
            }
            guard (200..<300).contains(status) else { throw TMDBError.badStatus(status) }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: (data ?? Data(), code))
            }
            task.resume()
        }
    }
}
