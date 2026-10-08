import Foundation

/// What a film shares with others, for learning from your ratings.
public struct TasteFeatures: Sendable {
    public let id: String
    public let title: String
    let directors: Set<String>
    let cinematographers: Set<String>
    let moods: Set<Mood>
    let keywords: Set<String>
    let genres: Set<String>

    public init(id: String, title: String, directors: [String], cinematographers: [String], moods: [Mood],
                keywords: [String], genres: [String]) {
        self.id = id
        self.title = title
        self.directors = Set(directors)
        self.cinematographers = Set(cinematographers)
        self.moods = Set(moods)
        self.keywords = Set(keywords)
        self.genres = Set(genres)
    }
}

/// How well an unwatched film fits what you've rated, and why.
public struct TasteMatch: Equatable, Sendable {
    public let score: Double
    /// "From the director of Stalker", "Shot by Roger Deakins, like Sicario", "Because you loved Her".
    public let reason: PickReason?
}

/// Learnt from your shared star ratings: films you gave 4–5 stars pull similar films up, films
/// you gave 1–2 stars push similar ones down a little.
public struct TasteProfile: Sendable {
    let loved: [TasteFeatures]
    let disliked: [TasteFeatures]
    /// Per genre: the share of loved films in it, less half the share of disliked ones.
    private let genreLean: [String: Double]

    public init(rated: [(features: TasteFeatures, stars: Int)]) {
        loved = rated.filter { $0.stars >= 4 }.map { $0.features }
        disliked = rated.filter { $0.stars <= 2 }.map { $0.features }
        var lean: [String: Double] = [:]
        if !loved.isEmpty {
            for film in loved { for genre in film.genres { lean[genre, default: 0] += 1 / Double(loved.count) } }
            for film in disliked { for genre in film.genres { lean[genre, default: 0] -= 0.5 / Double(disliked.count) } }
        }
        genreLean = lean
    }

    public var isEmpty: Bool { loved.isEmpty && disliked.isEmpty }

    /// How well a film you know little about (from a list: its directors and genres) fits what
    /// you've rated: a director of a film you loved counts most, then how often you loved its
    /// genres. Up to about 3, with the loved film it shares a director with.
    public func fit(directors: [String], genres: [String]) -> (score: Double, sameDirectorAs: String?) {
        guard !loved.isEmpty else { return (0, nil) }
        let lovedFilm = directors.isEmpty ? nil : loved.first { film in directors.contains { film.directors.contains($0) } }
        let genreFit = genres.isEmpty ? 0 : genres.reduce(0.0) { $0 + (genreLean[$1] ?? 0) } / Double(genres.count)
        return ((lovedFilm == nil ? 0 : 2) + genreFit, lovedFilm?.title)
    }

    public func match(_ film: TasteFeatures) -> TasteMatch {
        var total = 0.0
        var best: (score: Double, film: TasteFeatures, why: Why)?
        for other in loved where other.id != film.id {
            let (score, why) = Self.likeness(film, other)
            total += score
            if score >= 1, best == nil || score > best!.score { best = (score, other, why) }
        }
        for other in disliked where other.id != film.id {
            total -= Self.likeness(film, other).score * 0.5
        }
        let reason = best.map { best -> PickReason in
            switch best.why {
            case .director: .director(film: best.film.title)
            case .cinematographer(let name): .cinematographer(name: name, film: best.film.title)
            case .alike: .alike(film: best.film.title)
            }
        }
        return TasteMatch(score: min(max(total, -2), 3), reason: reason)
    }

    enum Why {
        case director
        case cinematographer(String)
        case alike
    }

    /// How many things two sets share, without building a new set (this runs for every pair).
    static func shared<T: Hashable>(_ a: Set<T>, _ b: Set<T>) -> Int {
        let (small, large) = a.count <= b.count ? (a, b) : (b, a)
        var n = 0
        for x in small where large.contains(x) { n += 1 }
        return n
    }

    /// How much two films share, and what stands out most.
    static func likeness(_ a: TasteFeatures, _ b: TasteFeatures) -> (score: Double, why: Why) {
        let sameDirector = a.directors.contains { b.directors.contains($0) }
        let cinematographer = a.cinematographers.first { b.cinematographers.contains($0) }
        var score = 0.0
        if sameDirector { score += 2 }
        if cinematographer != nil { score += 1 }
        score += Double(shared(a.moods, b.moods)) * 0.3
        score += min(Double(shared(a.keywords, b.keywords)) * 0.25, 1)
        score += Double(shared(a.genres, b.genres)) * 0.2
        if sameDirector { return (score, .director) }
        if let cinematographer { return (score, .cinematographer(cinematographer)) }
        return (score, .alike)
    }
}

// MARK: - What matters on the sofa

extension FilmEntry {
    /// Languages of the subtitle files that come with the film ("English", "Estonian").
    public var subtitleLanguages: [String] {
        var seen = Set<String>()
        return extras.filter { $0.kind == .subtitle }.compactMap { $0.language }.filter { seen.insert($0).inserted }
    }

    /// Has subtitle files, even ones without a language in their name.
    public var hasSubtitles: Bool { extras.contains { $0.kind == .subtitle } }

    /// "4K · HDR", "1080p", from the file name.
    public var qualityLabel: String? {
        let resolution = parsed.resolution.map { $0 == "2160p" ? "4K" : $0 }
        let parts = [resolution, parsed.hdr].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
