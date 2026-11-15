import Foundation

// Your data's safety rules (1.11): what Reel keeps for you survives a rebuilt library, an older
// Reel and a damaged file. Everything here is plain logic over files and values, so it is tested;
// the app only calls it.

// MARK: - Any JSON value

/// A JSON value kept exactly as it was read, so a key a newer Reel wrote survives this one's save.
public enum RawJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([RawJSON])
    case object([String: RawJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Int.self) { self = .int(value) }
        else if let value = try? c.decode(Double.self) { self = .double(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([RawJSON].self) { self = .array(value) }
        else { self = .object(try c.decode([String: RawJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .int(let value): try c.encode(value)
        case .double(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }
}

/// Any key, for reading the keys a type doesn't know.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

// MARK: - Matches

/// A copy's film, remembered in Your Notes so a rebuilt Library.json never matches it again
/// (your notes, stars and history are kept by the film it was matched to).
public struct RememberedMatch: Codable, Equatable, Sendable {
    public var tmdb: Int
    /// The match was one Reel asked you to check; it comes back marked to check.
    public var check: Bool?

    public init(tmdb: Int, check: Bool = false) {
        self.tmdb = tmdb
        self.check = check ? true : nil
    }
}

public enum MatchMemory {
    /// What is remembered after looking at the library now: every copy with a film keeps it, a copy
    /// matched to another film since (you chose it) replaces its entry, and copies not in the
    /// library now (a drive away, a file renamed) keep theirs. Pending, failed and unknown copies
    /// add nothing.
    public static func remember(_ films: [FilmEntry], into matches: [String: RememberedMatch]) -> [String: RememberedMatch] {
        var result = matches
        for film in films {
            guard let id = film.tmdb?.id else { continue }
            let entry: RememberedMatch
            switch film.matchState {
            case .auto, .confirmed: entry = RememberedMatch(tmdb: id)
            case .review, .manual: entry = RememberedMatch(tmdb: id, check: true)
            case .pending, .failed: continue
            }
            result[film.fileKey] = entry
        }
        return result
    }
}

// MARK: - Frames you removed

public enum StillRemovals {
    /// More than this many for one film can't all be yours: the film's images or the check changed
    /// since, so nothing is carried over for it.
    public static let mostPerFilm = 6

    /// Today's removals, told apart from images the check turned down. A removal is an image that
    /// passed the check (it passes again now, the check being the same) but isn't among the stored
    /// stills. Nil when it can't be told for this film.
    /// - Parameters:
    ///   - stored: the stills stored for the film (`checkedStills`), at the current check version.
    ///   - passNow: the images that pass the same check now.
    public static func recover(stored: [String], passNow: [String]) -> Set<String>? {
        let kept = Set(stored)
        // An image stored as passing that fails now: the check isn't behaving as it did.
        guard kept.isSubset(of: Set(passNow)) else { return nil }
        let removed = Set(passNow).subtracting(kept)
        return removed.count <= mostPerFilm ? removed : nil
    }

    /// The stills to show: what passed the check, less what you removed.
    public static func visible(_ stills: [String], removed: Set<String>?) -> [String] {
        guard let removed, !removed.isEmpty else { return stills }
        return stills.filter { !removed.contains($0) }
    }
}

// MARK: - Opening Your Notes

/// How Your Notes was found at launch, and whether Reel may write it this session, by the same
/// rules as Library.json (`LibraryOpening`), plus one more: a damaged file offers the newest
/// readable Safety Copy, and nothing is written until you choose.
public enum NotesOpening: Equatable, Sendable {
    case missing
    case loaded(PersonalFile)
    case unopenable
    case damaged
    /// Written by a newer Reel: shown, never written by this one.
    case newer(version: Int, PersonalFile?)

    public var file: PersonalFile? {
        switch self {
        case .loaded(let file): return file
        case .newer(_, let file): return file
        case .missing, .unopenable, .damaged: return nil
        }
    }

    public var writable: Bool {
        switch self {
        case .missing, .loaded: return true
        case .unopenable, .damaged, .newer: return false
        }
    }

    public static func open(_ url: URL) -> NotesOpening {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unopenable }
        return decide(data)
    }

    public static func decide(_ data: Data) -> NotesOpening {
        if let file = try? JSONStore.decode(PersonalFile.self, from: data) {
            return file.version > PersonalFile.currentVersion ? .newer(version: file.version, file) : .loaded(file)
        }
        struct Header: Decodable { let version: Int? }
        if let version = (try? JSONStore.decode(Header.self, from: data))?.version, version > PersonalFile.currentVersion {
            return .newer(version: version, nil)
        }
        return .damaged
    }
}

/// A Safety Copy that can be read, offered when Your Notes is damaged.
public struct SafetyCopy: Equatable, Sendable {
    public let url: URL
    /// "2026-11-15"
    public let day: String
    public let file: PersonalFile
}

extension SafetyCopies {
    /// The newest copy of `stem` ("Your Notes") in `folder` that reads as Your Notes, newest day first.
    public static func newestReadableNotes(stem: String = "Your Notes", in folder: URL) -> SafetyCopy? {
        let formatter = dayFormatter()
        let items = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let dated: [(day: String, date: Date, name: String)] = items.compactMap { name in
            guard name.hasPrefix(stem + " "), name.hasSuffix(".json") else { return nil }
            let day = String(name.dropFirst(stem.count + 1).dropLast(5))
            guard let date = formatter.date(from: day) else { return nil }
            return (day, date, name)
        }
        for item in dated.sorted(by: { $0.date > $1.date }) {
            let url = folder.appendingPathComponent(item.name)
            if case .loaded(let file) = NotesOpening.open(url) { return SafetyCopy(url: url, day: item.day, file: file) }
        }
        return nil
    }
}
