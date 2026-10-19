import Foundation

/// What a film was shot on, for the "Shot on" filter.
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

/// How a film was shot, in names only: the gear and techniques read about it (the film's
/// Wikipedia article and the interviews and craft articles about it), and what it was shot on,
/// each with the sentence that says so. Read in the background for every film in the library, for
/// searching by craft ("16mm", "Steadicam", "natural light") and the Shot on filter.
public struct CraftIndex: Codable, Equatable, Sendable {
    /// Bump when the reading improves, so every film is read again.
    /// 2: the sentence behind each Shot on, "not / instead of / unlike" in a clause, magazine
    /// articles only when they're about this film, TMDB keywords only where Wikidata is silent.
    public static let currentVersion = 2
    /// Bump when finding what to read improves: films read from too little (their article alone,
    /// or nothing on what they were shot on) are read again; the rest keep their reading.
    /// 2: the magazines' searches sorted by relevance, and American Cinematographer's posts too.
    public static let currentDiscovery = 2
    /// Read again after half a year (new interviews appear).
    public static let maxAge: TimeInterval = 182 * 86_400

    /// Why a film is tagged Film, Anamorphic, IMAX…: the sentence and where it was read.
    public struct Evidence: Codable, Equatable, Sendable {
        public let shotOn: ShotOn
        /// The sentence, or what says it ("Wikidata: black-and-white").
        public let text: String
        /// "American Cinematographer", "Wikipedia" (the film's article), "Wikidata", "TMDB".
        public let source: String
    }

    public var version: Int
    public var readAt: Date
    public var shotOn: [ShotOn]
    /// The gear and techniques named ("ARRI Alexa 65", "Steadicam", "Natural light", "16 mm"), most
    /// telling kinds first, at most 30.
    public var names: [String]
    /// One for each of `shotOn`.
    public var evidence: [Evidence]
    /// How many texts it was read from (the article, interviews, the cinematographer's article):
    /// a later reading from fewer, while a site is down, doesn't replace it (see `keeps`).
    public var sources: Int
    /// How it was found (see `currentDiscovery`); 1 for readings before 1.9.0.
    public var discovery: Int

    public init(version: Int = CraftIndex.currentVersion, readAt: Date = Date(), shotOn: [ShotOn], names: [String],
                evidence: [Evidence] = [], sources: Int = 0, discovery: Int = CraftIndex.currentDiscovery) {
        self.discovery = discovery
        self.version = version
        self.readAt = readAt
        self.shotOn = shotOn
        self.names = names
        self.evidence = evidence
        self.sources = sources
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        readAt = try c.decode(Date.self, forKey: .readAt)
        shotOn = try c.decode([ShotOn].self, forKey: .shotOn)
        names = try c.decode([String].self, forKey: .names)
        evidence = try c.decodeIfPresent([Evidence].self, forKey: .evidence) ?? []
        sources = try c.decodeIfPresent(Int.self, forKey: .sources) ?? 0
        discovery = try c.decodeIfPresent(Int.self, forKey: .discovery) ?? 1
    }

    public func isStale(now: Date = Date()) -> Bool {
        version < CraftIndex.currentVersion || readAt < now.addingTimeInterval(-CraftIndex.maxAge)
            || (discovery < CraftIndex.currentDiscovery && isThin)
    }

    /// Read from the film's article alone (or nothing), or nothing found on what it was shot on:
    /// worth reading again when finding improves.
    public var isThin: Bool { sources <= 1 || shotOn.isEmpty }

    /// Whether this reading stays instead of a `newer` one: when they're read by the same rules and
    /// found the same way, and the newer one read fewer texts (a site down, offline for part of it).
    /// It's tried again later. A reading found a better way always replaces it, even from fewer
    /// texts: the ones it no longer reads were about another film.
    public func keeps(over newer: CraftIndex) -> Bool {
        version == newer.version && discovery >= newer.discovery && newer.sources < sources
    }

    /// The sentence behind one Shot on, for "why".
    public func evidence(for shotOn: ShotOn) -> Evidence? {
        evidence.first { $0.shotOn == shotOn }
    }

    /// From what was read, Wikidata's colour (P462) and TMDB's keywords. `sources`: how many texts.
    public static func make(from specs: TechSpecs, colour: [String]?, keywords: [String], sources: Int = 0,
                            now: Date = Date()) -> CraftIndex {
        let order: [TechSpecs.Kind] = [.camera, .lens, .format, .support, .light, .filter, .finish]
        var names: [String] = []
        for kind in order {
            for name in specs.names(kind) where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                names.append(name)
            }
        }
        var evidence: [ShotOn: Evidence] = [:]
        for spec in specs.specs {
            for found in Self.shotOn(spec) where evidence[found] == nil {
                evidence[found] = Evidence(shotOn: found, text: spec.evidence ?? spec.name, source: spec.source ?? "Wikipedia")
            }
        }
        let colours = (colour ?? []).map { $0.lowercased() }
        // Wikidata says black and white (and not colour too: partly in colour isn't).
        if evidence[.blackAndWhite] == nil, colours.contains(where: { $0.contains("black") }),
           !colours.contains(where: { $0.contains("colo") && !$0.contains("black") }) {
            evidence[.blackAndWhite] = Evidence(shotOn: .blackAndWhite, text: "Colour: " + (colour ?? []).joined(separator: ", "), source: "Wikidata")
        }
        // TMDB's keyword only where Wikidata says nothing about colour (a film partly in black and
        // white has the keyword too). Its "imax" keyword isn't used: it marks IMAX releases as well.
        if evidence[.blackAndWhite] == nil, colours.isEmpty, keywords.contains(where: { $0.lowercased() == "black and white" }) {
            evidence[.blackAndWhite] = Evidence(shotOn: .blackAndWhite, text: "Keyword: black and white", source: "TMDB")
        }
        let shotOn = ShotOn.allCases.filter { evidence[$0] != nil }
        return CraftIndex(readAt: now, shotOn: shotOn, names: Array(names.prefix(30)),
                          evidence: shotOn.compactMap { evidence[$0] }, sources: sources)
    }

    /// What one name says the film was shot on.
    static func shotOn(_ spec: TechSpecs.Spec) -> Set<ShotOn> {
        let name = spec.name.lowercased()
        var found = Set<ShotOn>()
        if name.contains("anamorphic") || name.contains("cinemascope") || name.contains("ultra panavision")
            || name.hasPrefix("hawk")
            || name.range(of: #"\b[cegt]-series\b"#, options: .regularExpression) != nil {
            found.insert(.anamorphic)
        }
        if name.contains("imax") || name == "15/70" { found.insert(.imax) }
        if name == "black and white" || name.contains("double-x") || name.contains("tri-x") { found.insert(.blackAndWhite) }
        switch spec.kind {
        case .format:
            if name == "digital" || ["arriraw", "redcode", "prores", "x-ocn", "blackmagic raw"].contains(where: name.hasPrefix) {
                found.insert(.digital)
            } else if name == "film" || name.hasPrefix("kodak") || name.hasPrefix("eastman") || name.hasPrefix("fuji")
                        || ["double-x", "tri-x", "ektachrome", "vistavision", "techniscope", "todd-ao", "three-strip"].contains(where: name.contains)
                        || name.range(of: #"^(?:super ?(?:8|16|35)(?: mm)?|(?:8|16|35|65|70) mm)$"#, options: .regularExpression) != nil
                        || name.contains("panavision 70") {
                found.insert(.film)
            }
        case .camera:
            if ["arricam", "arriflex", "panaflex", "aaton", "bolex", "moviecam", "mitchell", "imax msm", "imax mk",
                "imax mark", "imax 65", "imax film", "panavision millennium xl", "panavision film", "panavision 35", "panavision 65",
                "panastar", "system 65", "technicolor", "vistavision"]
                .contains(where: name.contains) {
                found.insert(.film)
            } else if ["alexa", "red ", "venice", "f65", "f55", "cinealta", "blackmagic", "canon", "phantom", "iphone", "gopro",
                       "varicam", "viper", "genesis", "dxl", "imax digital", "komodo", "raptor", "monstro", "burano", "ronin 4d"]
                .contains(where: name.contains) || name == "red" {
                found.insert(.digital)
            }
        default:
            break
        }
        return found
    }

    /// What a search can find it by: the names, and the words for what it was shot on.
    public var searchText: String {
        // "16 mm" is searched as "16mm" too.
        let joined = names.filter { $0.range(of: #"\d mm\b"#, options: .regularExpression) != nil }
            .map { $0.replacingOccurrences(of: " mm", with: "mm") }
            + names.filter { $0.range(of: #"^Super \d+$"#, options: .regularExpression) != nil }
            .map { String($0.dropFirst(6)) + "mm" }
        return (names + joined + shotOn.flatMap(\.searchWords)).joined(separator: " , ")
    }
}

/// A cinematographer's recurring gear and looks, across their films in the library.
public enum CraftHabits {
    /// What they shot on and the gear and techniques read about their films, each with how many
    /// films name it, the most films first. With several films only what recurs is kept; with
    /// one, that film's own (at most `limit`).
    public static func recurring(_ indexes: [CraftIndex], limit: Int = 12) -> [(name: String, films: Int)] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for index in indexes {
            let names = index.shotOn.map(\.title) + index.names
            var seen = Set<String>()
            for name in names where seen.insert(name.lowercased()).inserted {
                if counts[name] == nil { order.append(name) }
                counts[name, default: 0] += 1
            }
        }
        let minimum = indexes.count > 1 ? 2 : 1
        return order.enumerated()
            .compactMap { offset, name -> (String, Int, Int)? in (counts[name] ?? 0) >= minimum ? (name, counts[name] ?? 0, offset) : nil }
            .sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }
            .prefix(limit)
            .map { (name: $0.0, films: $0.1) }
    }
}
