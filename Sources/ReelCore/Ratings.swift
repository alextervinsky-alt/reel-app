import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Scores from outside TMDB, via OMDb (IMDb, Rotten Tomatoes, Metacritic).
public struct ExternalRatings: Codable, Equatable, Sendable {
    /// IMDb user rating out of 10, e.g. 8.0.
    public var imdb: Double?
    public var imdbVotes: Int?
    /// Rotten Tomatoes critics score in percent.
    public var rottenTomatoes: Int?
    /// Metacritic score out of 100.
    public var metacritic: Int?
    /// Age rating, e.g. "R".
    public var rated: String?
    /// e.g. "Won 2 Oscars. 101 wins & 352 nominations total"
    public var awards: String?

    public init(imdb: Double? = nil, imdbVotes: Int? = nil, rottenTomatoes: Int? = nil, metacritic: Int? = nil,
                rated: String? = nil, awards: String? = nil) {
        self.imdb = imdb
        self.imdbVotes = imdbVotes
        self.rottenTomatoes = rottenTomatoes
        self.metacritic = metacritic
        self.rated = rated
        self.awards = awards
    }

    public var isEmpty: Bool { imdb == nil && rottenTomatoes == nil && metacritic == nil }

    /// A fresh answer over the stored one: what the answer lacks is kept as it was (1.11.2: OMDb
    /// stopped sending Rotten Tomatoes, and the 24 Nov refresh wrote "none" over 143 stored scores).
    public static func merged(_ fresh: ExternalRatings?, over stored: ExternalRatings?) -> ExternalRatings? {
        guard let fresh else { return stored }
        guard let stored else { return fresh }
        return ExternalRatings(imdb: fresh.imdb ?? stored.imdb, imdbVotes: fresh.imdbVotes ?? stored.imdbVotes,
                               rottenTomatoes: fresh.rottenTomatoes ?? stored.rottenTomatoes,
                               metacritic: fresh.metacritic ?? stored.metacritic,
                               rated: fresh.rated ?? stored.rated, awards: fresh.awards ?? stored.awards)
    }
}

/// Rotten Tomatoes' Tomatometer from Wikidata, which OMDb no longer sends (checked on CI, 26 Nov
/// 2026: IMDb and Metacritic only). Wikidata keeps it as a review score (P444) by Rotten Tomatoes
/// (P447 = Q105584) determined as the Tomatometer (P459 = Q108403393), often several over the
/// years: the latest by its date (P585) counts. Free public data (CC0), asked in one query for many
/// films at a time.
public enum WikidataScores {
    static let endpoint = "https://query.wikidata.org/sparql"
    /// Films per query (the query lists their IMDb ids).
    public static let batch = 80

    public static func query(imdbIDs: [String]) -> String {
        let values = imdbIDs.filter { $0.range(of: #"^tt\d+$"#, options: .regularExpression) != nil }.map { "\"\($0)\"" }
        return """
        SELECT ?imdb ?score ?date WHERE {
          VALUES ?imdb { \(values.joined(separator: " ")) }
          ?film wdt:P345 ?imdb ; p:P444 ?st .
          ?st ps:P444 ?score ; pq:P447 wd:Q105584 ; pq:P459 wd:Q108403393 ; wikibase:rank ?rank .
          FILTER(?rank != wikibase:DeprecatedRank)
          OPTIONAL { ?st pq:P585 ?date }
        }
        """
    }

    struct Answer: Decodable {
        struct Results: Decodable { let bindings: [[String: Value]] }
        struct Value: Decodable { let value: String }
        let results: Results
    }

    /// IMDb id → Tomatometer percent, the latest dated score of each film ("92%" → 92).
    public static func parse(_ data: Data) -> [String: Int] {
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return [:] }
        var best: [String: (date: String, score: Int)] = [:]
        for row in answer.results.bindings {
            guard let imdb = row["imdb"]?.value, let text = row["score"]?.value,
                  let score = Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)),
                  (0...100).contains(score) else { continue }
            // ISO dates sort as text; a score without a date counts as the oldest.
            let date = row["date"]?.value ?? ""
            if let known = best[imdb], known.date >= date { continue }
            best[imdb] = (date, score)
        }
        return best.mapValues(\.score)
    }

    public static func rottenTomatoes(imdbIDs: [String], session: URLSession = TMDBClient.sharedSession) async throws -> [String: Int] {
        var found: [String: Int] = [:]
        for start in stride(from: 0, to: imdbIDs.count, by: batch) {
            let ids = Array(imdbIDs[start..<min(start + batch, imdbIDs.count)])
            var components = URLComponents(string: endpoint)!
            components.queryItems = [URLQueryItem(name: "query", value: query(imdbIDs: ids)), URLQueryItem(name: "format", value: "json")]
            var request = URLRequest(url: components.url!)
            request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
            // Wikidata asks every client to say what it is.
            request.setValue("Reel/1.11 (personal macOS film library app)", forHTTPHeaderField: "User-Agent")
            ActivityCount.request(request.url)
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            found.merge(parse(data)) { _, new in new }
        }
        return found
    }
}

public enum OMDbError: Error {
    case unauthorized
    case badStatus(Int)
}

public struct OMDbClient: Sendable {
    private let key: String
    private let session: URLSession

    public init(key: String, session: URLSession = TMDBClient.sharedSession) {
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    public func ratings(imdbID: String) async throws -> ExternalRatings? {
        var components = URLComponents(string: "https://www.omdbapi.com/")!
        components.queryItems = [URLQueryItem(name: "apikey", value: key), URLQueryItem(name: "i", value: imdbID)]
        let request = URLRequest(url: components.url!)
        let (data, status): (Data, Int) = try await withCheckedThrowingContinuation { continuation in
            ActivityCount.request(request.url)
            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
                }
            }.resume()
        }
        if status == 401 { throw OMDbError.unauthorized }
        guard (200..<300).contains(status) else { throw OMDbError.badStatus(status) }
        return Self.parse(data)
    }

    struct Answer: Decodable {
        struct Rating: Decodable {
            let source: String
            let value: String

            enum CodingKeys: String, CodingKey {
                case source = "Source"
                case value = "Value"
            }
        }

        let response: String?
        let imdbRating: String?
        let imdbVotes: String?
        let metascore: String?
        let rated: String?
        let awards: String?
        let ratings: [Rating]?

        enum CodingKeys: String, CodingKey {
            case imdbRating, imdbVotes
            case response = "Response"
            case metascore = "Metascore"
            case rated = "Rated"
            case awards = "Awards"
            case ratings = "Ratings"
        }
    }

    /// Turns an OMDb answer into ratings. "N/A" values become nil.
    public static func parse(_ data: Data) -> ExternalRatings? {
        guard let r = try? JSONDecoder().decode(Answer.self, from: data), r.response == "True" else { return nil }
        func clean(_ s: String?) -> String? {
            guard let s, !s.isEmpty, s != "N/A" else { return nil }
            return s
        }
        var ratings = ExternalRatings()
        ratings.imdb = clean(r.imdbRating).flatMap { Double($0) }
        ratings.imdbVotes = clean(r.imdbVotes).flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
        ratings.metacritic = clean(r.metascore).flatMap { Int($0) }
        ratings.rated = clean(r.rated)
        ratings.awards = clean(r.awards)
        for rating in r.ratings ?? [] {
            if rating.source == "Rotten Tomatoes" {
                ratings.rottenTomatoes = Int(rating.value.replacingOccurrences(of: "%", with: ""))
            } else if rating.source == "Metacritic", ratings.metacritic == nil {
                ratings.metacritic = Int(rating.value.split(separator: "/").first ?? "")
            }
        }
        return ratings
    }
}
