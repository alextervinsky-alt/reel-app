import Foundation

/// The chips above Recommended: any film, one mood, or something short.
public enum MoodChoice: Hashable, Sendable, Identifiable {
    case any
    case mood(Mood)
    case short

    public var id: String {
        switch self {
        case .any: "any"
        case .mood(let mood): mood.rawValue
        case .short: "short"
        }
    }

    public var title: String {
        switch self {
        case .any: "Any"
        case .mood(let mood): mood.title
        case .short: "Short"
        }
    }

    public var symbol: String {
        switch self {
        case .any: "sparkles"
        case .mood(let mood): mood.symbol
        case .short: "clock"
        }
    }
}

/// A chip and how many films it has.
public struct MoodChoiceCount: Equatable, Sendable, Identifiable {
    public let choice: MoodChoice
    public let count: Int
    public var id: String { choice.id }

    public init(choice: MoodChoice, count: Int) {
        self.choice = choice
        self.count = count
    }
}

/// What the recommender needs to know about one unwatched film.
public struct Recommendable: Sendable {
    public let id: String
    public let score: Double?
    public let onWatchlist: Bool
    public let isOnline: Bool
    public let genre: String?
    /// The film's strongest moods (up to three).
    public let moods: [Mood]
    public let runtime: Int?
    /// How well it fits the films you rated highly (see `TasteProfile`), about -2 to 3.
    public let affinity: Double

    public init(id: String, score: Double?, onWatchlist: Bool, isOnline: Bool, genre: String?, moods: [Mood], runtime: Int?,
                affinity: Double = 0) {
        self.id = id
        self.score = score
        self.onWatchlist = onWatchlist
        self.isOnline = isOnline
        self.genre = genre
        self.moods = moods
        self.runtime = runtime
        self.affinity = affinity
    }
}

/// Five films to choose from: well-rated first, a nudge for the watchlist and connected drives,
/// a dose of chance, and different genres where possible. Never the same five as last launch,
/// and films shuffled away this session come back less often.
public enum Recommender {
    public static let count = 5
    /// "Short" means under this many minutes.
    public static let shortRuntime = 100
    /// A chip needs at least this many films, so a choice never gives a thin result.
    public static let minimumForChoice = 3

    public static func fits(_ film: Recommendable, _ choice: MoodChoice) -> Bool {
        switch choice {
        case .any: true
        case .mood(let mood): film.moods.contains(mood)
        case .short: (film.runtime ?? .max) < shortRuntime
        }
    }

    /// The chips worth showing, with how many films each has: Any first, then the moods in their
    /// usual order, then Short. The chip you're on stays while it has any film at all, so marking
    /// a film watched never switches you back to Any.
    public static func choices(for pool: [Recommendable], keeping current: MoodChoice = .any) -> [MoodChoiceCount] {
        var moodCounts: [Mood: Int] = [:]
        var short = 0
        for film in pool {
            for mood in film.moods { moodCounts[mood, default: 0] += 1 }
            if fits(film, .short) { short += 1 }
        }
        var result = [MoodChoiceCount(choice: .any, count: pool.count)]
        func offered(_ choice: MoodChoice, _ n: Int) -> Bool { n >= minimumForChoice || (choice == current && n > 0) }
        for mood in Mood.allCases {
            if let n = moodCounts[mood], offered(.mood(mood), n) { result.append(MoodChoiceCount(choice: .mood(mood), count: n)) }
        }
        if offered(.short, short) { result.append(MoodChoiceCount(choice: .short, count: short)) }
        return result
    }

    /// Picks films for one choice. `keeping` are earlier picks still on show (even ones watched
    /// since): they stay in place, and only the empty places are filled.
    public static func pick<G: RandomNumberGenerator>(
        from pool: [Recommendable], choice: MoodChoice, keeping: [String] = [],
        lastLaunch: Set<String> = [], shuffledAway: Set<String> = [], using generator: inout G
    ) -> [String] {
        let candidates = pool.filter { fits($0, choice) }
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var picks: [String] = []
        for id in keeping where picks.count < count && !picks.contains(id) { picks.append(id) }
        guard picks.count < count else { return picks }

        let ranked = candidates
            .filter { !picks.contains($0.id) }
            .map { film -> (film: Recommendable, weight: Double) in
                var weight = film.score ?? 6.0
                if film.onWatchlist { weight += 1.2 }
                if film.isOnline { weight += 0.4 }
                weight += film.affinity
                if lastLaunch.contains(film.id) { weight -= 3 }
                if shuffledAway.contains(film.id) { weight -= 1.5 }
                weight += Double.random(in: 0...2, using: &generator)
                return (film, weight)
            }
            .sorted { $0.weight > $1.weight }
            .map { $0.film }

        var genres = Set(picks.compactMap { byID[$0]?.genre })
        for film in ranked where picks.count < count && genres.insert(film.genre ?? "").inserted {
            picks.append(film.id)
        }
        for film in ranked where picks.count < count && !picks.contains(film.id) {
            picks.append(film.id)
        }
        return picks
    }

    public static func pick(from pool: [Recommendable], choice: MoodChoice, keeping: [String] = [],
                            lastLaunch: Set<String> = [], shuffledAway: Set<String> = []) -> [String] {
        var generator = SystemRandomNumberGenerator()
        return pick(from: pool, choice: choice, keeping: keeping, lastLaunch: lastLaunch,
                    shuffledAway: shuffledAway, using: &generator)
    }
}
