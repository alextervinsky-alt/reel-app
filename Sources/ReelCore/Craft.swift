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
/// Wikipedia article and the interviews and craft articles about it), and what it was shot on.
/// Read in the background for every film in the library, for searching by craft ("16mm",
/// "Steadicam", "natural light") and the Shot on filter. No sentence is kept.
public struct CraftIndex: Codable, Equatable, Sendable {
    /// Bump when the reading improves, so every film is read again.
    public static let currentVersion = 1
    /// Read again after half a year (new interviews appear).
    public static let maxAge: TimeInterval = 182 * 86_400

    public var version: Int
    public var readAt: Date
    public var shotOn: [ShotOn]
    /// The gear and techniques named ("ARRI Alexa 65", "Steadicam", "Natural light", "16 mm"), most
    /// telling kinds first, at most 30.
    public var names: [String]

    public init(version: Int = CraftIndex.currentVersion, readAt: Date = Date(), shotOn: [ShotOn], names: [String]) {
        self.version = version
        self.readAt = readAt
        self.shotOn = shotOn
        self.names = names
    }

    public func isStale(now: Date = Date()) -> Bool {
        version < CraftIndex.currentVersion || readAt < now.addingTimeInterval(-CraftIndex.maxAge)
    }

    /// From what was read, Wikidata's colour (P462) and TMDB's keywords.
    public static func make(from specs: TechSpecs, colour: [String]?, keywords: [String], now: Date = Date()) -> CraftIndex {
        let order: [TechSpecs.Kind] = [.camera, .lens, .format, .support, .light, .filter, .finish]
        var names: [String] = []
        for kind in order {
            for name in specs.names(kind) where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                names.append(name)
            }
        }
        var shotOn = Set<ShotOn>()
        for spec in specs.specs { shotOn.formUnion(Self.shotOn(spec)) }
        let colours = (colour ?? []).map { $0.lowercased() }
        // Wikidata says black and white (and not colour too: partly in colour isn't).
        if colours.contains(where: { $0.contains("black") }), !colours.contains(where: { $0.contains("colo") && !$0.contains("black") }) {
            shotOn.insert(.blackAndWhite)
        }
        if keywords.contains(where: { $0.lowercased() == "black and white" }) { shotOn.insert(.blackAndWhite) }
        if keywords.contains(where: { $0.lowercased() == "imax" }) { shotOn.insert(.imax) }
        return CraftIndex(readAt: now, shotOn: ShotOn.allCases.filter { shotOn.contains($0) }, names: Array(names.prefix(30)))
    }

    /// What one name says the film was shot on.
    static func shotOn(_ spec: TechSpecs.Spec) -> Set<ShotOn> {
        let name = spec.name.lowercased()
        var found = Set<ShotOn>()
        if name.contains("anamorphic") || name.contains("cinemascope") || name.contains("ultra panavision")
            || name.hasPrefix("hawk") || name.hasPrefix("kowa") || name.hasPrefix("lomo")
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
        return (names + joined + shotOn.flatMap(\.searchWords)).joined(separator: " , ")
    }
}
