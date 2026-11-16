import Foundation

/// What Reel did on its own, counted for the idle gate (spec §11): web requests by host and
/// saves by file. Only counts; nothing is logged or kept.
public enum ActivityCount {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [String: Int] = [:]
    nonisolated(unsafe) private static var saves: [String: Int] = [:]

    public static func request(_ url: URL?) {
        let host = url?.host ?? "?"
        lock.lock(); requests[host, default: 0] += 1; lock.unlock()
    }

    public static func save(_ url: URL) {
        let name = url.lastPathComponent
        lock.lock(); saves[name, default: 0] += 1; lock.unlock()
    }

    public static func snapshot() -> (requests: [String: Int], saves: [String: Int]) {
        lock.lock(); defer { lock.unlock() }
        return (requests, saves)
    }

    public static func reset() {
        lock.lock(); requests = [:]; saves = [:]; lock.unlock()
    }
}
