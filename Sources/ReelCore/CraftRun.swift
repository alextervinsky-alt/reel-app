import Foundation

/// One run through the Shot on queue, as the app does it in the background (`AppModel.readCraft`):
/// which films come next, what each reading did, when the readings so far are written to the
/// library, and when the run stops because nothing can be reached. The app only fetches and writes;
/// every decision is here, so a whole library's run can be tested without the app, its network or
/// its files.
///
/// What's due is worked out from what's stored with the films alone (`CraftQueue`), so a run that's
/// interrupted (Reel quits, the Mac sleeps, the network goes) loses at most the readings not yet
/// written, and those films are simply still due next time; a reading already written isn't read
/// again until it's due again.
public struct CraftRun: Sendable {
    /// Films read side by side.
    public static let batchSize = 2
    /// Films in a row that nothing could be reached for: offline, not these films; the run stops,
    /// and they aren't marked as failed (they'd otherwise wait hours for no fault of their own).
    public static let offlineAfter = 6
    /// Readings kept before they're written (the library is rebuilt once per write, not per film).
    public static let writeEvery = 9
    /// Or after this long since the last write.
    public static let writeAfter: TimeInterval = 30

    /// Films taken this run: each film once per run, so one that keeps failing can't hold it up.
    public private(set) var attempted = Set<Int>()
    /// Readings not yet written, by TMDB id (merged with what was stored).
    public private(set) var read: [Int: CraftIndex] = [:]
    /// Tries that came to nothing, not yet written.
    public private(set) var failed: [Int: CraftAttempt] = [:]
    /// Nothing could be reached for `offlineAfter` films in a row: the run is over.
    public private(set) var offline = false
    private var failingRun: [Int] = []
    private var lastWrite: Date

    public init(now: Date = Date()) {
        lastWrite = now
    }

    /// The next films to read, taken for this run (empty: nothing left that's due). The longest
    /// since tried first, never tried before anything (see `CraftQueue.due`).
    public mutating func nextBatch(_ films: [FilmEntry], now: Date = Date()) -> [FilmEntry] {
        guard !offline else { return [] }
        let batch = Array(CraftQueue.due(films, attempted: attempted, now: now).prefix(Self.batchSize))
        for film in batch { if let id = film.tmdb?.id { attempted.insert(id) } }
        return batch
    }

    /// How many films are still due, counting the readings not yet written (for the sidebar).
    public func pending(_ films: [FilmEntry], now: Date = Date()) -> Int {
        CraftQueue.due(films, attempted: attempted, now: now).count + read.count
    }

    /// What reading a film came to: `reading` nil when nothing could be reached. Returns the
    /// reading as it will be stored (merged tag by tag with what was stored; see
    /// `CraftIndex.merging`), for its log.
    @discardableResult
    public mutating func record(_ id: Int, stored: FilmEntry?, reading: CraftIndex?, now: Date = Date()) -> CraftIndex.Merged? {
        if let reading {
            let merged = CraftIndex.merging(old: stored?.craft, new: reading, now: now)
            read[id] = merged.index
            failed[id] = nil
            failingRun = []
            return merged
        }
        failed[id] = CraftAttempt.failed(after: stored?.craftAttempt, now: now)
        failingRun.append(id)
        if failingRun.count >= Self.offlineAfter {
            for id in failingRun { failed[id] = nil }
            failingRun = []
            offline = true
        }
        return nil
    }

    /// The readings and failed tries to write now: every `writeEvery`, after `writeAfter`, or all of
    /// them when `force` (the run is ending, or Reel is quitting). Nil: nothing to write yet.
    public mutating func takeWrites(now: Date = Date(), force: Bool = false) -> (read: [Int: CraftIndex], failed: [Int: CraftAttempt])? {
        guard !read.isEmpty || !failed.isEmpty else { return nil }
        guard force || read.count + failed.count >= Self.writeEvery || now.timeIntervalSince(lastWrite) > Self.writeAfter else { return nil }
        let batch = (read, failed)
        read = [:]
        failed = [:]
        lastWrite = now
        return batch
    }

    /// Puts readings into the library, every copy of each film, and the tries that came to nothing.
    /// A reading clears the film's failed try. Returns the films whose Shot on changed, once each:
    /// (copy index, the tags before).
    @discardableResult
    public static func apply(read: [Int: CraftIndex], failed: [Int: CraftAttempt], to films: inout [FilmEntry]) -> [(index: Int, before: [ShotOn])] {
        var changes: [(index: Int, before: [ShotOn])] = []
        var noted = Set<Int>()
        for i in films.indices {
            guard let id = films[i].tmdb?.id else { continue }
            if let index = read[id] {
                let before = films[i].craft?.shotOn
                if let before, before != index.shotOn, noted.insert(id).inserted { changes.append((i, before)) }
                films[i].craft = index
                films[i].craftAttempt = nil
            } else if let attempt = failed[id] {
                films[i].craftAttempt = attempt
            }
        }
        return changes
    }
}

extension CraftQueue {
    /// When the next film becomes due on its own, after `now`: a partial reading's planned retry, a
    /// failed try's, or a reading turning half a year old. Nil when none will (or one is due now:
    /// that's for the run under way). Used to wake the queue at that time rather than at the next
    /// six-hourly refresh.
    public static func nextDue(_ films: [FilmEntry], now: Date = Date()) -> Date? {
        var next: Date?
        func consider(_ date: Date?) {
            guard let date, date > now else { return }
            if next.map({ date < $0 }) ?? true { next = date }
        }
        for film in representatives(of: films) {
            guard film.funFacts != nil else { continue }
            switch state(of: film, now: now) {
            case .failed:
                consider(film.craftAttempt?.retryAt)
            case .partial:
                consider(film.craft?.retryAt)
            case .complete:
                consider(film.craft.map { $0.readAt.addingTimeInterval(CraftIndex.maxAge) })
            case .waitingForFacts, .notRead, .olderRules, .stale:
                continue
            }
        }
        return next
    }
}

/// When background maintenance is started again on its own: the network came back, or the Mac
/// woke from sleep. Not more often than every `minimumGap`, so a flapping network or several
/// signals at once start one pass, not many (a pass already running goes round once more anyway).
public struct ResumeTrigger: Sendable {
    public static let minimumGap: TimeInterval = 120

    public enum Event: Sendable, Equatable {
        /// The network is reachable (`reachable`) or not, as the system reports it.
        case network(reachable: Bool)
        /// The Mac woke from sleep.
        case wake
    }

    private var reachable: Bool?
    private var lastStart: Date?

    public init() {}

    /// Whether this event starts a pass: the network coming back after it was gone, or a wake while
    /// it's reachable (or not known to be gone); the first report is only noted.
    public mutating func shouldStart(_ event: Event, now: Date = Date()) -> Bool {
        let start: Bool
        switch event {
        case .network(let up):
            start = up && reachable == false
            reachable = up
        case .wake:
            start = reachable != false
        }
        guard start else { return false }
        if let lastStart, now.timeIntervalSince(lastStart) < Self.minimumGap { return false }
        lastStart = now
        return true
    }
}
