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
