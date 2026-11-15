import Foundation

// How a film was shot, in 1.11: only facts from structured sources or one plain sentence, each with
// where it's from (spec §7). Session 2 keeps the shape the rest of Reel reads; session 4 fills it.

/// What a film was shot on, for the "Shot on" filter. The raw values are stored in Your Notes
/// ("Not right", `removedShotOn`), so they never change.
public enum ShotOn: String, Codable, CaseIterable, Sendable, Identifiable {
    case film, digital, anamorphic, imax, blackAndWhite

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .film: "Film"
        case .digital: "Digital"
        case .anamorphic: "Anamorphic"
        case .imax: "IMAX"
        case .blackAndWhite: "Black & white"
        }
    }

    /// What Wikidata's colour (P462) already says, before anything is read: black and white
    /// when it names black-and-white and no colour (a film in both is black and white in part,
    /// which the facts sheet says; the filter leaves it out).
    public static func known(colour: [String]?) -> Set<ShotOn> {
        let values = (colour ?? []).map { $0.lowercased() }
        let blackAndWhite = values.contains { $0.contains("black") && $0.contains("white") || $0.contains("monochrom") }
        let inColour = values.contains { !($0.contains("black") && $0.contains("white")) && ($0.contains("colo") || $0.contains("technicolor")) }
        return blackAndWhite && !inColour ? [.blackAndWhite] : []
    }

    /// What a search for it may say ("shot on film", "b&w").
    var searchWords: [String] {
        switch self {
        case .film: ["shot on film", "film stock", "celluloid", "analogue", "analog", "photochemical"]
        case .digital: ["digital", "shot digitally"]
        case .anamorphic: ["anamorphic", "scope"]
        case .imax: ["imax"]
        case .blackAndWhite: ["black and white", "b&w", "monochrome"]
        }
    }
}

/// The facts sheet for one film, as stored in Library.json (derived: rebuilt when its sources change).
public struct CraftFacts: Codable, Equatable, Sendable {
    /// A row of the sheet. The raw values are stored with "Not right" (`removedFacts`).
    public enum Row: String, Codable, CaseIterable, Sendable {
        case aspectRatio, colour, format, camera, lenses, award
    }

    /// One value, with where it's from.
    public struct Fact: Codable, Equatable, Sendable {
        public var row: Row
        public var value: String
        /// The source's name ("Wikidata", "American Cinematographer", "Wikipedia").
        public var source: String
        public var link: URL?
        /// The plain sentence the value is from, when it is from one (shown beside it).
        public var sentence: String?
        /// The source says it's true of part of the film.
        public var inPart: Bool

        public init(row: Row, value: String, source: String, link: URL? = nil, sentence: String? = nil, inPart: Bool = false) {
            self.row = row
            self.value = value
            self.source = source
            self.link = link
            self.sentence = sentence
            self.inPart = inPart
        }
    }

    /// Bumped when the rules change: stored text is checked again, without the network.
    public static let currentVersion = 1

    public var version: Int
    public var readAt: Date
    public var facts: [Fact]
    /// What it was shot on, from the facts (`format` rows and Wikidata's colour).
    public var shotOn: [ShotOn]
    /// The Shot on values the source gives for part of the film only.
    public var inPart: Set<ShotOn>

    public init(version: Int = CraftFacts.currentVersion, readAt: Date = Date(), facts: [Fact] = [], shotOn: [ShotOn] = [],
                inPart: Set<ShotOn> = []) {
        self.version = version
        self.readAt = readAt
        self.facts = facts
        self.shotOn = shotOn
        self.inPart = inPart
    }

    /// Camera, lens and format names, for searching by craft.
    public var names: [String] {
        facts.filter { [.camera, .lenses, .format].contains($0.row) }.map(\.value)
    }

    /// "Black & white", or "Black & white (in part)".
    public func label(for shotOn: ShotOn) -> String {
        inPart.contains(shotOn) ? shotOn.title + " (in part)" : shotOn.title
    }

    /// What a search can find it by, without the Shot on you said is wrong.
    public func searchText(removing removed: Set<ShotOn>) -> String {
        // "16 mm" is searched as "16mm" too.
        let joined = names.filter { $0.range(of: #"\d mm\b"#, options: .regularExpression) != nil }
            .map { $0.replacingOccurrences(of: " mm", with: "mm") }
        return (names + joined + shotOn.filter { !removed.contains($0) }.flatMap(\.searchWords)).joined(separator: " , ")
    }
}

/// A cinematographer's recurring formats and gear across their films in the library.
public enum CraftHabits {
    /// Each name with how many films name it, the most first. With several films only what recurs
    /// is kept; with one, that film's own (at most `limit`).
    public static func recurring(_ sheets: [CraftFacts], limit: Int = 12) -> [(name: String, films: Int)] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for sheet in sheets {
            var seen = Set<String>()
            for name in sheet.shotOn.map(\.title) + sheet.names where seen.insert(name.lowercased()).inserted {
                if counts[name] == nil { order.append(name) }
                counts[name, default: 0] += 1
            }
        }
        let minimum = sheets.count > 1 ? 2 : 1
        return order.enumerated()
            .compactMap { offset, name -> (String, Int, Int)? in (counts[name] ?? 0) >= minimum ? (name, counts[name] ?? 0, offset) : nil }
            .sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }
            .prefix(limit)
            .map { (name: $0.0, films: $0.1) }
    }
}

/// The film's camera, lighting and colour people on TMDB: which jobs are kept with its details.
public enum CraftCrew {
    /// TMDB's jobs kept for the Cinematography tab's crew.
    public static let keptJobs: Set<String> = [
        "Director of Photography", "Additional Director of Photography", "Additional Photography",
        "Aerial Director of Photography", "Underwater Director of Photography", "Second Unit Director of Photography",
        "Steadicam Operator", "Camera Operator", "\"A\" Camera Operator", "\"B\" Camera Operator", "\"C\" Camera Operator",
        "Additional Camera Operator", "Gaffer", "Chief Lighting Technician", "Key Grip", "Digital Imaging Technician",
        "Colorist", "Digital Intermediate Colorist", "Supervising Colorist", "Senior Colorist", "Visual Effects Supervisor",
        "First Assistant Camera", "\"A\" First Assistant Camera", "First Assistant \"A\" Camera",
        "\"B\" First Assistant Camera", "First Assistant \"B\" Camera",
    ]
}
