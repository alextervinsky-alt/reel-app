import Foundation

/// When background maintenance is started again on its own: the network came back, or the Mac
/// woke from sleep. Every signal is noted (the first one too, even before the library is open, so
/// a launch while offline still sees the network come back). A start isn't more often than every
/// `minimumGap`: one asked for sooner is put off to the end of the gap, not dropped, so a wake
/// whose pass ran before the network was up still gets the network's return. After a wake the
/// pass waits `settle` for the network to come up.
public struct ResumeTrigger: Sendable {
    public static let minimumGap: TimeInterval = 120
    public static let settle: TimeInterval = 10

    public enum Event: Sendable, Equatable {
        /// The network is reachable (`reachable`) or not, as the system reports it.
        case network(reachable: Bool)
        /// The Mac woke from sleep.
        case wake
    }

    public enum Decision: Sendable, Equatable {
        case none
        /// Start a pass now.
        case now
        /// Start one at this time (`fire(at:)` then): sooner wasn't allowed, or the network is settling.
        case at(Date)
    }

    private var reachable: Bool?
    private var lastStart: Date?
    private var planned: Date?

    public init() {}

    /// Whether the network is known to be gone.
    public var isOffline: Bool { reachable == false }

    /// Notes the event and says whether, and when, it starts a pass: the network coming back after
    /// it was gone, or a wake while it isn't known to be gone. The first report is only noted.
    public mutating func handle(_ event: Event, now: Date = Date()) -> Decision {
        let wanted: Date?
        switch event {
        case .network(let up):
            wanted = up && reachable == false ? now : nil
            reachable = up
        case .wake:
            wanted = reachable != false ? now.addingTimeInterval(Self.settle) : nil
        }
        guard var when = wanted else { return .none }
        if let lastStart { when = max(when, lastStart.addingTimeInterval(Self.minimumGap)) }
        // One planned start at a time: the earliest that's allowed.
        if let planned, planned <= when, planned > now { return .none }
        if when <= now {
            lastStart = now
            planned = nil
            return .now
        }
        planned = when
        return .at(when)
    }

    /// A planned start fell due: it starts unless the network is known to be gone (its return will
    /// start one).
    public mutating func fire(now: Date = Date()) -> Bool {
        planned = nil
        guard reachable != false else { return false }
        lastStart = now
        return true
    }
}
