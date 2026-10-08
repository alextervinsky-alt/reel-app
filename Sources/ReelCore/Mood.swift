import Foundation

/// How a film feels, separate from its genre. Worked out from TMDB genres, keywords and length.
public enum Mood: String, CaseIterable, Codable, Sendable, Identifiable {
    case feelGood, funny, romantic, gripping, dark, mindBending, moving, epic, scary, inspiring

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .feelGood: "Feel-good"
        case .funny: "Funny"
        case .romantic: "Romantic"
        case .gripping: "Gripping"
        case .dark: "Dark"
        case .mindBending: "Mind-bending"
        case .moving: "Moving"
        case .epic: "Epic"
        case .scary: "Scary"
        case .inspiring: "Inspiring"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .feelGood: "sun.max"
        case .funny: "face.smiling"
        case .romantic: "heart"
        case .gripping: "bolt"
        case .dark: "moon.stars"
        case .mindBending: "infinity"
        case .moving: "drop"
        case .epic: "mountain.2"
        case .scary: "eye"
        case .inspiring: "sparkles"
        }
    }
}

public enum MoodClassifier {
    struct Rule {
        let genres: [String: Double]
        let keywords: [String]
    }

    static let rules: [Mood: Rule] = [
        .feelGood: Rule(
            genres: ["Family": 2, "Animation": 1.5, "Comedy": 1, "Music": 1, "Romance": 0.5,
                     "Horror": -3, "Thriller": -1.5, "Crime": -1.5, "War": -2],
            keywords: ["feel good", "feel-good", "heartwarming", "friendship", "uplifting", "christmas", "found family", "best friend"]),
        .funny: Rule(
            genres: ["Comedy": 3],
            keywords: ["parody", "satire", "spoof", "dark comedy", "absurd", "slapstick", "buddy comedy"]),
        .romantic: Rule(
            genres: ["Romance": 3],
            keywords: ["love", "romance", "romantic", "wedding", "relationship"]),
        .gripping: Rule(
            genres: ["Thriller": 2, "Action": 1.5, "Crime": 1],
            keywords: ["heist", "chase", "suspense", "assassin", "hostage", "survival", "conspiracy", "escape", "manhunt", "cat and mouse", "race against time"]),
        .dark: Rule(
            genres: ["Horror": 1.5, "Crime": 1, "Thriller": 1, "War": 1],
            keywords: ["dystopia", "violence", "murder", "serial killer", "revenge", "drug", "gore", "brutal", "nihilism", "despair", "noir", "corruption", "psychopath", "addiction", "abuse"]),
        .mindBending: Rule(
            genres: ["Science Fiction": 1, "Mystery": 1.5],
            keywords: ["twist", "time travel", "dream", "nonlinear", "reality", "simulation", "artificial intelligence", "parallel", "memory", "philosophy", "existential", "psychological", "identity", "paradox", "alternate", "surreal", "cyberpunk"]),
        .moving: Rule(
            genres: ["Drama": 2],
            keywords: ["grief", "loss", "death", "coming of age", "tragedy", "family", "illness", "sacrifice", "father son", "mother daughter", "loneliness", "friendship"]),
        .epic: Rule(
            genres: ["Adventure": 1.5, "Fantasy": 1.5, "War": 1.5, "History": 1.5, "Science Fiction": 1],
            keywords: ["epic", "battle", "kingdom", "empire", "space", "saga", "sword", "viking", "quest", "army", "desert", "galaxy"]),
        .scary: Rule(
            genres: ["Horror": 3],
            keywords: ["supernatural", "ghost", "haunted", "monster", "demon", "slasher", "zombie", "creature", "possession"]),
        .inspiring: Rule(
            genres: ["History": 0.5],
            keywords: ["sports", "underdog", "biography", "perseverance", "inspirational", "overcoming", "based on true story", "true story"]),
    ]

    /// Up to three moods, strongest first.
    public static func moods(genres: [String], keywords: [String], runtime: Int?) -> [Mood] {
        let lowered = keywords.map { $0.lowercased() }
        var scored: [(mood: Mood, score: Double)] = []
        for mood in Mood.allCases {
            guard let rule = rules[mood] else { continue }
            var score = genres.reduce(0.0) { $0 + (rule.genres[$1] ?? 0) }
            let hits = rule.keywords.filter { key in lowered.contains { keyword in keyword.contains(key) } }.count
            score += min(Double(hits) * 1.5, 4.5)
            if mood == .epic, let runtime, runtime >= 150 { score += 1.5 }
            if score >= 2.5 { scored.append((mood, score)) }
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.mood.rawValue < $1.mood.rawValue }
            .prefix(3)
            .map { $0.mood }
    }
}

/// A mood for films known only by their genres (Explore's lists from TMDB): genres that bring
/// it (any one) and genres that rule it out. Also what TMDB is asked for, for a mood's own row.
public struct MoodGenres: Sendable {
    public let any: Set<String>
    public let none: Set<String>
    /// Long films only (epics).
    public let minimumRuntime: Int?

    public static func of(_ mood: Mood) -> MoodGenres {
        switch mood {
        case .feelGood: MoodGenres(any: ["Comedy", "Family", "Animation", "Music"], none: ["Horror", "Thriller", "Crime", "War"])
        case .funny: MoodGenres(any: ["Comedy"], none: ["Horror", "War"])
        case .romantic: MoodGenres(any: ["Romance"], none: ["Horror"])
        case .gripping: MoodGenres(any: ["Thriller", "Action", "Crime"], none: ["Animation", "Family", "Comedy"])
        case .dark: MoodGenres(any: ["Crime", "Horror", "Thriller", "War"], none: ["Animation", "Family", "Comedy"])
        case .mindBending: MoodGenres(any: ["Science Fiction", "Mystery"], none: ["Animation", "Family", "Comedy"])
        case .moving: MoodGenres(any: ["Drama"], none: ["Comedy", "Horror", "Action"])
        case .epic: MoodGenres(any: ["Adventure", "Fantasy", "War", "History"], none: ["Comedy", "Horror"], minimumRuntime: 140)
        case .scary: MoodGenres(any: ["Horror"], none: ["Comedy", "Family"])
        case .inspiring: MoodGenres(any: ["History", "Music", "Documentary"], none: ["Horror", "Thriller"])
        }
    }

    init(any: Set<String>, none: Set<String>, minimumRuntime: Int? = nil) {
        self.any = any
        self.none = none
        self.minimumRuntime = minimumRuntime
    }

    /// Whether a film with these genres has the mood.
    public func fits(_ genres: [String]) -> Bool {
        genres.contains { any.contains($0) } && !genres.contains { none.contains($0) }
    }

    /// TMDB's discover filters: any of the genres ("|"), none of the others (",").
    public var query: [URLQueryItem] {
        let ids = Dictionary(TMDBGenreNames.byID.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func list(_ names: Set<String>, _ separator: String) -> String {
            names.compactMap { ids[$0] }.sorted().map(String.init).joined(separator: separator)
        }
        var items = [URLQueryItem(name: "with_genres", value: list(any, "|"))]
        if !none.isEmpty { items.append(URLQueryItem(name: "without_genres", value: list(none, ","))) }
        if let minimumRuntime { items.append(URLQueryItem(name: "with_runtime.gte", value: String(minimumRuntime))) }
        return items
    }
}

/// Running-time bands for the length filter.
public enum LengthBand: String, CaseIterable, Sendable, Identifiable {
    case any, short, standard, long, epic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: "Any length"
        case .short: "Under 1½ h"
        case .standard: "1½–2 h"
        case .long: "2–2½ h"
        case .epic: "Over 2½ h"
        }
    }

    public func contains(_ runtime: Int?) -> Bool {
        guard self != .any else { return true }
        guard let runtime, runtime > 0 else { return false }
        switch self {
        case .any: return true
        case .short: return runtime < 90
        case .standard: return runtime >= 90 && runtime <= 120
        case .long: return runtime > 120 && runtime <= 150
        case .epic: return runtime > 150
        }
    }
}
