import Foundation

/// What "More Like This" compares between two films in the library.
public struct LikenessFeatures: Equatable, Sendable {
    public let tmdbID: Int?
    let directors: Set<String>
    let writers: Set<String>
    let cinematographers: Set<String>
    let cast: Set<String>
    let composers: Set<String>
    /// The two top-billed actors, in billing order.
    let leads: [String]
    let genres: Set<String>
    let keywords: Set<String>
    let moods: Set<Mood>
    let year: Int?
    let isFamily: Bool
    let isAnimation: Bool
    let isDocumentary: Bool
    /// Violent, frightening or bleak: horror, war, dark or scary, or keywords of violence.
    let isIntense: Bool
    /// Gentle: a family, animated or feel-good film with none of that.
    let isGentle: Bool

    public init(tmdbID: Int?, directors: [String], writers: [String], cinematographers: [String], cast: [String],
                composers: [String] = [], genres: [String], keywords: [String], moods: [Mood], year: Int?) {
        self.tmdbID = tmdbID
        self.directors = Set(directors)
        self.writers = Set(writers).subtracting(directors)
        self.cinematographers = Set(cinematographers)
        self.cast = Set(cast)
        self.composers = Set(composers)
        self.leads = Array(cast.prefix(2))
        self.genres = Set(genres)
        self.keywords = Set(keywords)
        self.moods = Set(moods)
        self.year = year
        isFamily = genres.contains("Family")
        isAnimation = genres.contains("Animation")
        isDocumentary = genres.contains("Documentary")
        let violent = keywords.contains { Self.isViolent($0) }
        let grim = genres.contains("Horror") || genres.contains("War")
        // An animated or family film's moods come from a few keywords ("demon", "monster" make
        // Howl's Moving Castle "scary"): only its genres or real violence make it intense.
        isIntense = grim || violent || (!isAnimation && !isFamily && (moods.contains(.dark) || moods.contains(.scary)))
        isGentle = !isIntense && (isFamily || isAnimation || moods.contains(.feelGood))
    }

    /// TMDB keywords that mark a film as violent ("extreme violence", "brutality"), as whole
    /// words ("skyscraper" and "nonviolence" aren't).
    static let violent = try! NSRegularExpression(
        pattern: #"\b(?:violen(?:ce|t)|gore|gory|brutal\w*|bloody|bloodbath|tortur\w*|massacre|decapitat\w*|dismember\w*|rape|slaughter\w*|murder\w*|serial killer|beheading|revenge|war crimes?|cannibal\w*)\b"#,
        options: [.caseInsensitive])

    static func isViolent(_ keyword: String) -> Bool {
        violent.firstMatch(in: keyword, range: NSRange(keyword.startIndex..., in: keyword)) != nil
    }
}

/// How alike two films are, for "More Like This in Your Library". What people who liked a film
/// went on to like (TMDB's recommendations) counts most, then the people who made it, then
/// themes that are rare in the library (a shared "alien" means more than a shared "based on
/// novel"), tone and genre. A family film never sits next to an adult thriller because both have
/// aliens in them, and a dark film isn't offered as like a feel-good one.
/// Tone and audience come before themes: a gentle film (animated, family, feel-good) and a
/// violent or bleak one are never alike because they share a witch and a curse (Howl's Moving
/// Castle and The Northman), however rare those themes are in the library.
public enum Likeness {
    /// How many films in the library have each keyword (rare keywords count for more).
    public static func keywordCounts(_ films: [LikenessFeatures]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for film in films {
            for keyword in film.keywords { counts[keyword, default: 0] += 1 }
        }
        return counts
    }

    /// Moods that don't belong together: one of each is a poor "more like this".
    static let opposites: [(Mood, Mood)] = [(.feelGood, .dark), (.feelGood, .scary), (.funny, .scary), (.romantic, .scary)]

    /// - Parameters:
    ///   - recommended: TMDB's recommendations for `a`, film id → rank (0 is the strongest).
    ///   - keywordCounts: from `keywordCounts(_:)`; `libraryCount` is how many films that covered.
    public static func score(_ a: LikenessFeatures, _ b: LikenessFeatures, recommended: [Int: Int] = [:],
                             keywordCounts: [String: Int], libraryCount: Int) -> Double {
        var score = 0.0
        if let id = b.tmdbID, let rank = recommended[id] {
            score += 5 - 4 * Double(min(rank, 40)) / 40
        }
        score += 4 * Double(TasteProfile.shared(a.directors, b.directors))
        score += 2.5 * Double(TasteProfile.shared(a.writers, b.writers))
        score += 1.5 * Double(TasteProfile.shared(a.cinematographers, b.cinematographers))
        score += 1.2 * Double(min(TasteProfile.shared(a.cast, b.cast), 3))

        var themes = 0.0
        let total = Double(max(libraryCount, 1) + 1)
        for keyword in a.keywords where b.keywords.contains(keyword) {
            themes += log(total / Double((keywordCounts[keyword] ?? 1) + 1))
        }
        // Themes add up to a point: a few rare shared words don't make two films alike on their own.
        score += 0.5 * min(themes, 5)

        let genresBoth = Double(TasteProfile.shared(a.genres, b.genres))
        let genresEither = Double(a.genres.union(b.genres).count)
        if genresEither > 0 { score += 2.5 * genresBoth / genresEither }

        let moodsBoth = TasteProfile.shared(a.moods, b.moods)
        score += 0.8 * Double(moodsBoth)
        // Both have a feel, and it's not the same one.
        if moodsBoth == 0, !a.moods.isEmpty, !b.moods.isEmpty { score -= 0.75 }
        for (x, y) in opposites where (a.moods.contains(x) && b.moods.contains(y)) || (a.moods.contains(y) && b.moods.contains(x)) {
            score -= 1.5
        }

        // A different audience, tone or kind of film: only a strong reason keeps it.
        if (a.isGentle && b.isIntense) || (a.isIntense && b.isGentle) { score *= 0.2 }
        // Two gentle animated films are alike whether or not TMDB calls one a family film.
        if a.isFamily != b.isFamily { score *= a.isAnimation && b.isAnimation && a.isGentle && b.isGentle ? 0.8 : 0.3 }
        if a.isDocumentary != b.isDocumentary { score *= 0.3 }
        if a.isAnimation != b.isAnimation { score *= 0.45 }
        if let ya = a.year, let yb = b.year, abs(ya - yb) > 30 { score *= 0.8 }
        return score
    }

    /// Below this, two films aren't alike enough to suggest.
    public static let threshold = 2.0
}
