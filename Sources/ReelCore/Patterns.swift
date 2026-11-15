import Foundation

/// Regular expressions compiled once and kept (1.11): reading a file name used to compile each
/// pattern again for every name, which on a Mac made opening a 300-film library take about a
/// second (spec §9.2).
final class Patterns: @unchecked Sendable {
    static let shared = Patterns()
    private let lock = NSLock()
    private var compiled: [String: NSRegularExpression] = [:]

    func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let regex = compiled[pattern] { return regex }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        compiled[pattern] = regex
        return regex
    }
}

extension String {
    /// The first match of `pattern` (case as written), like `range(of:options: .regularExpression)`.
    func patternRange(_ pattern: String) -> Range<String.Index>? {
        guard let regex = Patterns.shared.regex(pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return Range(match.range, in: self)
    }
}

/// File names already read (see `FilenameParser.parse`).
final class ParseCache: @unchecked Sendable {
    static let shared = ParseCache()
    private let lock = NSLock()
    private var parsed: [String: ParsedFilename] = [:]

    func get(_ path: String) -> ParsedFilename? {
        lock.lock()
        defer { lock.unlock() }
        return parsed[path]
    }

    func set(_ path: String, _ value: ParsedFilename) {
        lock.lock()
        defer { lock.unlock() }
        if parsed.count > 20_000 { parsed.removeAll(keepingCapacity: true) }
        parsed[path] = value
    }
}
