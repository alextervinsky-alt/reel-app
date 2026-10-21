import Foundation

/// A film from IMDb's own ratings files, kept compact (short keys keep the saved file small).
public struct IMDbFilm: Codable, Equatable, Sendable, Identifiable {
    /// "tt0137523"
    public let id: String
    public let title: String
    public let year: Int
    public let rating: Double
    public let votes: Int
    /// IMDb's genres ("Drama", "Sci-Fi"), at most three (empty in copies saved before Reel 1.9.4).
    public let genres: [String]

    enum CodingKeys: String, CodingKey {
        case id = "i", title = "t", year = "y", rating = "r", votes = "v", genres = "g"
    }

    public init(id: String, title: String, year: Int, rating: Double, votes: Int, genres: [String] = []) {
        self.id = id
        self.title = title
        self.year = year
        self.rating = rating
        self.votes = votes
        self.genres = genres
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        year = try c.decode(Int.self, forKey: .year)
        rating = try c.decode(Double.self, forKey: .rating)
        votes = try c.decode(Int.self, forKey: .votes)
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
    }
}

/// The saved compact copy: "IMDb Ratings.json" in List Data.
public struct IMDbRatingsFile: Codable, Equatable, Sendable {
    /// 2: with each film's genres (Reel 1.9.4). An older copy is built again in the background.
    public static let currentVersion = 2

    public var version: Int
    public var builtAt: Date
    public var films: [IMDbFilm]

    public init(version: Int = IMDbRatingsFile.currentVersion, builtAt: Date, films: [IMDbFilm]) {
        self.version = version
        self.builtAt = builtAt
        self.films = films
    }

    enum CodingKeys: String, CodingKey {
        case version, builtAt, films
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        builtAt = try c.decode(Date.self, forKey: .builtAt)
        films = try c.decode([IMDbFilm].self, forKey: .films)
    }
}

/// IMDb publishes its ratings as free files for personal, non-commercial use
/// (https://developer.imdb.com/non-commercial-datasets/). Reel downloads them once, keeps only
/// feature films with at least a thousand votes, and ranks from that.
public enum IMDbDataset {
    public static let ratingsURL = URL(string: "https://datasets.imdbws.com/title.ratings.tsv.gz")!
    public static let basicsURL = URL(string: "https://datasets.imdbws.com/title.basics.tsv.gz")!
    public static let attribution = "Information courtesy of IMDb (imdb.com). Used with permission."

    /// Films with fewer votes are left out of the saved copy.
    public static let minimumVotes = 1_000

    // MARK: Building the compact copy

    /// Reads both downloaded files (gzip) and returns the feature films worth keeping.
    public static func build(ratingsFile: URL, basicsFile: URL) throws -> [IMDbFilm] {
        var ratings: [Int: (rating: Double, votes: Int)] = [:]
        try forEachLine(ofGzip: ratingsFile) { line in
            guard let id = numericID(line) else { return }
            let fields = String(decoding: line, as: UTF8.self).split(separator: "\t")
            guard fields.count >= 3, let votes = Int(fields[2]), votes >= minimumVotes,
                  let rating = Double(fields[1]) else { return }
            ratings[id] = (rating, votes)
        }

        var films: [IMDbFilm] = []
        films.reserveCapacity(60_000)
        try forEachLine(ofGzip: basicsFile) { line in
            // Most of the 11 million lines are episodes and shorts: only the id is read for those.
            guard let id = numericID(line), let score = ratings[id] else { return }
            if let film = film(fromBasics: String(decoding: line, as: UTF8.self), rating: score.rating, votes: score.votes) {
                films.append(film)
            }
        }
        return films
    }

    /// One line of title.basics.tsv: tconst, titleType, primaryTitle, originalTitle, isAdult,
    /// startYear, endYear, runtimeMinutes, genres.
    static func film(fromBasics line: String, rating: Double, votes: Int) -> IMDbFilm? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count >= 6, fields[1] == "movie", fields[4] == "0", let year = Int(fields[5]) else { return nil }
        // "\N" when it has none.
        let genres = fields.count >= 9 && fields[8] != "\\N" ? fields[8].split(separator: ",").map(String.init) : []
        return IMDbFilm(id: String(fields[0]), title: String(fields[2]), year: year, rating: rating, votes: votes, genres: genres)
    }

    /// "tt0137523…" → 137523, read straight from the bytes.
    static func numericID(_ line: UnsafeBufferPointer<UInt8>) -> Int? {
        guard line.count > 3, line[0] == UInt8(ascii: "t"), line[1] == UInt8(ascii: "t") else { return nil }
        var value = 0
        var index = 2
        while index < line.count, line[index] >= 48, line[index] <= 57 {
            value = value * 10 + Int(line[index] - 48)
            index += 1
        }
        return index > 2 ? value : nil
    }

    /// Streams a .gz file line by line through the system's gzip, so the 1 GB of text is never
    /// held in memory.
    static func forEachLine(ofGzip url: URL, _ body: (UnsafeBufferPointer<UInt8>) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        let handle = pipe.fileHandleForReading
        var carry: [UInt8] = []
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let bytes = raw.bindMemory(to: UInt8.self)
                guard let base = raw.baseAddress else { return }
                var start = 0
                while start < bytes.count {
                    // memchr finds the line end far faster than a Swift loop over a gigabyte.
                    guard let hit = memchr(base + start, 10, bytes.count - start) else {
                        carry.append(contentsOf: bytes[start...])
                        break
                    }
                    let end = base.distance(to: UnsafeRawPointer(hit))
                    if carry.isEmpty {
                        body(UnsafeBufferPointer(rebasing: bytes[start..<end]))
                    } else {
                        carry.append(contentsOf: bytes[start..<end])
                        carry.withUnsafeBufferPointer { body($0) }
                        carry.removeAll(keepingCapacity: true)
                    }
                    start = end + 1
                }
            }
        }
        if !carry.isEmpty { carry.withUnsafeBufferPointer { body($0) } }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
    }

    // MARK: Rankings

    /// The year's top films by rating, weighed by how many people voted (a Bayesian average, as
    /// IMDb's own charts use), so a film rated 8.9 by 1,200 people doesn't outrank one rated 8.6
    /// by 900,000. Only films with plenty of votes for their year qualify.
    public static func top(_ films: [IMDbFilm], year: Int, count: Int = 100) -> [IMDbFilm] {
        // The bar: the votes of the year's 300th most-voted film.
        top(of: films.filter { $0.year == year }, depth: 300, count: count)
    }

    /// The highest-rated films of all time (25,000 votes or more).
    public static func topAllTime(_ films: [IMDbFilm], count: Int = 250) -> [IMDbFilm] {
        ranked(films.filter { $0.votes >= 25_000 }, bar: 25_000, count: count)
    }

    /// A decade's best ("the 1970s": 1970–1979), of one genre or all. The vote bar follows how many
    /// people rate the films of that time and genre, so the 1920s or documentaries aren't held to
    /// the bar of today's blockbusters.
    public static func top(_ films: [IMDbFilm], decade: Int, genre: String? = nil, count: Int = 100) -> [IMDbFilm] {
        let pool = films.filter { $0.year >= decade && $0.year < decade + 10 && (genre.map($0.genres.contains) ?? true) }
        return top(of: pool, depth: genre == nil ? 500 : 300, count: count)
    }

    /// A genre's best of all time.
    public static func top(_ films: [IMDbFilm], genre: String, count: Int = 100) -> [IMDbFilm] {
        top(of: films.filter { $0.genres.contains(genre) }, depth: 1_000, count: count)
    }

    /// The films the most people have rated.
    public static func mostVoted(_ films: [IMDbFilm], count: Int = 100) -> [IMDbFilm] {
        Array(films.sorted { $0.votes != $1.votes ? $0.votes > $1.votes : $0.id < $1.id }.prefix(count))
    }

    /// IMDb's genres for feature films, in the order the menu shows them.
    public static let genres = ["Action", "Adventure", "Animation", "Biography", "Comedy", "Crime", "Documentary", "Drama", "Family",
                                "Fantasy", "Film-Noir", "History", "Horror", "Music", "Musical", "Mystery", "Romance", "Sci-Fi", "Sport",
                                "Thriller", "War", "Western"]

    /// Ranks the films with enough votes: at least the votes of the `depth`-th most voted of them,
    /// between 1,000 and 25,000.
    static func top(of pool: [IMDbFilm], depth: Int, count: Int) -> [IMDbFilm] {
        guard !pool.isEmpty else { return [] }
        let votes = pool.map { $0.votes }.sorted(by: >)
        let bar = min(25_000, max(minimumVotes, votes[min(votes.count - 1, depth - 1)]))
        return ranked(pool.filter { $0.votes >= bar }, bar: bar, count: count)
    }

    static func ranked(_ eligible: [IMDbFilm], bar: Int, count: Int) -> [IMDbFilm] {
        guard !eligible.isEmpty else { return [] }
        let mean = eligible.reduce(0) { $0 + $1.rating } / Double(eligible.count)
        let m = Double(bar)
        func weighted(_ film: IMDbFilm) -> Double {
            let v = Double(film.votes)
            return (v / (v + m)) * film.rating + (m / (v + m)) * mean
        }
        return Array(eligible
            .map { (film: $0, score: weighted($0)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.film.votes > $1.film.votes }
            .prefix(count)
            .map { $0.film })
    }
}
