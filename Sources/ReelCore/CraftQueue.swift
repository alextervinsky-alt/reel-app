import Foundation

/// A reading of how a film was shot that came to nothing (nothing could be reached): when it was
/// tried, how many times in a row, and when it's tried again. Kept with the film, so a film that
/// can't be read waits its turn after a relaunch too and doesn't hold up the others.
public struct CraftAttempt: Codable, Equatable, Sendable {
    public var at: Date
    public var failures: Int
    public var retryAt: Date
    /// The rules it was tried by: newer rules try it again at once.
    public var version: Int

    public init(at: Date, failures: Int, retryAt: Date, version: Int = CraftIndex.currentVersion) {
        self.at = at
        self.failures = failures
        self.retryAt = retryAt
        self.version = version
    }

    /// Another try that came to nothing, after `previous`: six hours, a day, three days, a week, then
    /// every 30 days (see `CraftIndex.retryDelay`).
    public static func failed(after previous: CraftAttempt?, now: Date = Date()) -> CraftAttempt {
        let failures = previous.map { $0.version == CraftIndex.currentVersion ? $0.failures + 1 : 1 } ?? 1
        return CraftAttempt(at: now, failures: failures, retryAt: now.addingTimeInterval(CraftIndex.retryDelay(failures, unanswered: true)))
    }
}

/// Which films are read next for Shot on, and where each one stands: worked out from what's stored
/// with the films alone, so the queue is the same after a relaunch, and the same for the same films
/// and time.
public enum CraftQueue {
    public enum State: Equatable, Sendable {
        /// Its Wikipedia facts aren't in yet (they come with the film's info): read after them.
        case waitingForFacts
        /// Never read.
        case notRead
        /// Tried and nothing could be reached: tried again at the attempt's time.
        case failed
        /// Read by older rules: read again now.
        case olderRules
        /// Read long ago, or from little before finding improved: read again now.
        case stale
        /// Read by these rules, but a site didn't answer or a tag stands on an earlier reading's
        /// sentence: read again when planned.
        case partial
        /// Read by these rules, every site answered and nothing carried over: done (with or without
        /// tags), however many pages found couldn't be examined (see `CraftIndex.coverage`).
        case complete

        /// Still work to do for it.
        public var isOutstanding: Bool { self != .complete }
    }

    /// Where a film stands. `inCollection`: one of a collection (read again when a reading from
    /// before sequels were told apart is kept).
    public static func state(craft: CraftIndex?, attempt: CraftAttempt?, hasFacts: Bool, inCollection: Bool,
                             now: Date = Date()) -> State {
        guard hasFacts else { return .waitingForFacts }
        // A try by these rules, since the reading kept, that came to nothing waits for its time.
        if let attempt, attempt.version == CraftIndex.currentVersion, attempt.retryAt > now,
           attempt.at >= craft?.readAt ?? .distantPast {
            return .failed
        }
        guard let craft else { return .notRead }
        if craft.version < CraftIndex.currentVersion { return .olderRules }
        if craft.isPartial || craft.retryAt != nil { return .partial }
        if craft.isStale(now: now) || (craft.discovery < CraftIndex.currentDiscovery && inCollection) { return .stale }
        return .complete
    }

    /// Whether it's read now.
    public static func isDue(craft: CraftIndex?, attempt: CraftAttempt?, hasFacts: Bool, inCollection: Bool,
                             now: Date = Date()) -> Bool {
        switch state(craft: craft, attempt: attempt, hasFacts: hasFacts, inCollection: inCollection, now: now) {
        case .notRead, .olderRules, .stale: return true
        case .partial: return craft?.retryAt.map { $0 <= now } ?? true
        case .waitingForFacts, .failed, .complete: return false
        }
    }

    public static func state(of film: FilmEntry, now: Date = Date()) -> State {
        state(craft: film.craft, attempt: film.craftAttempt, hasFacts: film.funFacts != nil,
              inCollection: film.tmdb?.collection != nil, now: now)
    }

    /// The films to read now: one for each film however many copies there are, none tried already
    /// this run (`attempted`), the longest since it was last tried first (never tried before
    /// anything), the library's order among equals.
    public static func due(_ films: [FilmEntry], attempted: Set<Int> = [], now: Date = Date()) -> [FilmEntry] {
        var due: [(film: FilmEntry, last: Date, order: Int)] = []
        // Each film as its copy with the newest reading says (a copy added later has none yet).
        for (order, film) in representatives(of: films).enumerated() {
            guard let id = film.tmdb?.id, !attempted.contains(id),
                  isDue(craft: film.craft, attempt: film.craftAttempt, hasFacts: film.funFacts != nil,
                        inCollection: film.tmdb?.collection != nil, now: now) else { continue }
            let last = [film.craft?.readAt, film.craftAttempt?.at].compactMap { $0 }.max() ?? .distantPast
            due.append((film, last, order))
        }
        return due.sorted { ($0.last, $0.order) < ($1.last, $1.order) }.map(\.film)
    }

    /// One copy for each film, in the library's order of first copies: the one with the newest
    /// reading (and with its facts, when only some copies have them).
    public static func representatives(of films: [FilmEntry]) -> [FilmEntry] {
        var best: [Int: FilmEntry] = [:]
        var order: [Int] = []
        for film in films {
            guard let id = film.tmdb?.id else { continue }
            guard let known = best[id] else {
                best[id] = film
                order.append(id)
                continue
            }
            let newer = (film.craft?.readAt ?? .distantPast) > (known.craft?.readAt ?? .distantPast)
            let facts = known.funFacts == nil && film.funFacts != nil
            if newer || facts { best[id] = film }
        }
        return order.compactMap { best[$0] }
    }

    /// How much of the library Shot on covers, for Settings: live-action films, each once.
    public struct Coverage: Equatable, Sendable {
        /// Read by these rules (complete or partial), and of those with a tag (less what you removed).
        public var read = 0
        public var tagged = 0
        /// Of those read, read from one text alone.
        public var articleOnly = 0
        /// Not read by these rules yet: never read, read by older rules or long ago, tried and nothing
        /// reached, or its facts not in yet.
        public var toRead = 0
        /// Read by these rules, but not completely: read again automatically.
        public var partial = 0
        /// Read by these rules and done, but some pages found couldn't be examined (gone, not open to
        /// Reel, too little text): not counted as read in full.
        public var limited = 0
    }

    /// `removed`: the Shot on tags you said are wrong, by film.
    public static func coverage(of films: [FilmEntry], removed: [Int: Set<ShotOn>] = [:], now: Date = Date()) -> Coverage {
        var coverage = Coverage()
        for film in representatives(of: films) {
            // Animated films weren't shot on anything.
            guard let details = film.tmdb, !details.genreNames.contains("Animation") else { continue }
            let standing = state(of: film, now: now)
            // Tried again since and nothing reached (offline): still read by these rules.
            let readByTheseRules = standing == .failed && film.craft?.version == CraftIndex.currentVersion
            switch standing {
            case .waitingForFacts, .notRead, .olderRules, .stale:
                coverage.toRead += 1
            case .failed where !readByTheseRules:
                coverage.toRead += 1
            case .failed, .partial, .complete:
                guard let craft = film.craft else { continue }
                coverage.read += 1
                if !Set(craft.shotOn).subtracting(removed[details.id] ?? []).isEmpty { coverage.tagged += 1 }
                if craft.sources <= 1 { coverage.articleOnly += 1 }
                // As its reading and its log say (tried again since and nothing reached: still that reading).
                if craft.isPartial || craft.retryAt != nil || craft.coverage == .partial {
                    coverage.partial += 1
                } else if craft.coverage == .limited {
                    coverage.limited += 1
                }
            }
        }
        return coverage
    }
}
