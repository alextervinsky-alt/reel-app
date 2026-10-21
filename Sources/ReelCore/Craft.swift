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
    /// 3: sentences about another film, tests and decisions against, finishing and prints left out;
    /// what's said of part of the film marked so.
    /// 4: a tag needs a sentence saying this film was shot that way (not an opinion, other work, a
    /// look made in the grade); a focal length or a sensor isn't film; black and white read from a
    /// film stock is in part unless Wikidata says the whole film is.
    /// 5: the names too (the specification sheet, search, a cinematographer's habits) only this
    /// film's: a camera, lens or what it was shot on said to have been used, the rest said of this
    /// film; round-ups of many films read only where they name it.
    /// 6: round-ups found by their spec sheets and list pages by their title, a sheet counted only in
    /// the film's own block; Moviecam alone is lenses; the magazine's own lines, childhood and what's
    /// said of another film in a comparison aren't this film's.
    public static let currentVersion = 6
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
        /// Every sentence behind it says part of the film only ("Black & white, in part").
        public var partial: Bool

        public init(shotOn: ShotOn, text: String, source: String, partial: Bool = false) {
            self.shotOn = shotOn
            self.text = text
            self.source = source
            self.partial = partial
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            shotOn = try c.decode(ShotOn.self, forKey: .shotOn)
            text = try c.decode(String.self, forKey: .text)
            source = try c.decode(String.self, forKey: .source)
            partial = try c.decodeIfPresent(Bool.self, forKey: .partial) ?? false
        }
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
    /// Sites that didn't answer or asked Reel to wait while it was read: read again in a few hours.
    public var unanswered: [String] = []
    /// Readings in a row that came out thinner than the one kept, or with a site unanswered (after
    /// four more, what's read then stands).
    public var retries = 0
    /// When it's read again, when that's planned (a site didn't answer, or less was read than
    /// before): until then it isn't, whatever the rules.
    public var retryAt: Date?

    public init(version: Int = CraftIndex.currentVersion, readAt: Date = Date(), shotOn: [ShotOn], names: [String],
                evidence: [Evidence] = [], sources: Int = 0, discovery: Int = CraftIndex.currentDiscovery,
                unanswered: [String] = [], retries: Int = 0, retryAt: Date? = nil) {
        self.discovery = discovery
        self.unanswered = unanswered
        self.retries = retries
        self.retryAt = retryAt
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
        unanswered = try c.decodeIfPresent([String].self, forKey: .unanswered) ?? []
        retries = try c.decodeIfPresent(Int.self, forKey: .retries) ?? 0
        retryAt = try c.decodeIfPresent(Date.self, forKey: .retryAt)
    }

    public static let maxRetries = 4

    /// How long until a reading is tried again: after a site didn't answer, six hours, then a day,
    /// three days, a week (a captcha lifts in hours, a site down for longer gets days); after
    /// fewer texts with every site answering, a week.
    static func retryDelay(_ retries: Int, unanswered: Bool) -> TimeInterval {
        guard unanswered else { return 7 * 86_400 }
        let delays: [TimeInterval] = [6 * 3600, 86_400, 3 * 86_400, 7 * 86_400]
        return delays[min(max(retries, 1), 4) - 1]
    }

    public func isStale(now: Date = Date()) -> Bool {
        // Planned: not before then (a reading kept by older rules isn't read again on every pass).
        if let retryAt { return now >= retryAt }
        return version < CraftIndex.currentVersion || readAt < now.addingTimeInterval(-CraftIndex.maxAge)
            || (discovery < CraftIndex.currentDiscovery && isThin)
    }

    /// To be read again because a site didn't answer (Settings counts these).
    public var willReadAgain: Bool { retryAt != nil && !unanswered.isEmpty }

    /// Read from the film's article alone (or nothing), or nothing found on what it was shot on:
    /// worth reading again when finding improves.
    public var isThin: Bool { sources <= 1 || shotOn.isEmpty }

    /// What's kept when a film has been read again: the new reading, unless it's thinner than the
    /// one kept (fewer texts, found the same way: a site down or asking Reel to wait, by these rules
    /// or older ones). Then the kept one stays and the film is tried again later (see `retryDelay`),
    /// four times at most; after that what's read stands. A reading found a better way always
    /// replaces it, even from fewer texts: the ones it no longer reads were about another film.
    public static func merge(old: CraftIndex?, new: CraftIndex, now: Date = Date()) -> CraftIndex {
        var new = new
        let unanswered = !new.unanswered.isEmpty
        let tries = (old?.retries ?? 0) + 1
        if var kept = old, new.sources < kept.sources, new.discovery <= kept.discovery, tries <= maxRetries {
            kept.unanswered = new.unanswered
            kept.retries = tries
            kept.retryAt = now.addingTimeInterval(retryDelay(tries, unanswered: unanswered))
            return kept
        }
        if unanswered, tries <= maxRetries {
            new.retries = tries
            new.retryAt = now.addingTimeInterval(retryDelay(tries, unanswered: true))
        } else {
            new.retries = 0
            new.retryAt = nil
        }
        return new
    }

    /// "Black & white", or "Black & white (in part)".
    public func label(for shotOn: ShotOn) -> String {
        evidence(for: shotOn)?.partial == true ? shotOn.title + " (in part)" : shotOn.title
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
        // Only what's said to have been shot with: the names alone are for the notes and search.
        for spec in specs.specs where spec.capture {
            for found in Self.shotOn(spec) {
                // Film and Digital both show when a film mixes them; "in part" is for the rest.
                var partial = spec.partial && ![.film, .digital].contains(found)
                // A black-and-white stock (Double-X) is often for some scenes: in part, unless
                // Wikidata says the whole film is black and white (below).
                if found == .blackAndWhite, spec.name != "Black and white" { partial = true }
                let said = Evidence(shotOn: found, text: spec.evidence ?? spec.name, source: spec.source ?? "Wikipedia", partial: partial)
                // One sentence about the whole film outweighs any number about part of it.
                if let known = evidence[found], !(known.partial && !said.partial) { continue }
                evidence[found] = said
            }
        }
        let colours = (colour ?? []).map { $0.lowercased() }
        let black = colours.contains(where: { $0.contains("black") })
        let colourToo = colours.contains(where: { $0.contains("colo") && !$0.contains("black") })
        if black, !colourToo {
            // Wikidata says black and white (and not colour too: partly in colour isn't): the whole film.
            if evidence[.blackAndWhite] == nil {
                evidence[.blackAndWhite] = Evidence(shotOn: .blackAndWhite, text: "Colour: " + (colour ?? []).joined(separator: ", "), source: "Wikidata")
            } else {
                evidence[.blackAndWhite]?.partial = false
            }
        } else if colourToo {
            // In colour, by Wikidata: any black and white read is part of it.
            evidence[.blackAndWhite]?.partial = true
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
    public var searchText: String { searchText(removing: []) }

    /// Without the Shot on you said is wrong.
    public func searchText(removing removed: Set<ShotOn>) -> String {
        // "16 mm" is searched as "16mm" too.
        let joined = names.filter { $0.range(of: #"\d mm\b"#, options: .regularExpression) != nil }
            .map { $0.replacingOccurrences(of: " mm", with: "mm") }
            + names.filter { $0.range(of: #"^Super \d+$"#, options: .regularExpression) != nil }
            .map { String($0.dropFirst(6)) + "mm" }
        return (names + joined + shotOn.filter { !removed.contains($0) }.flatMap(\.searchWords)).joined(separator: " , ")
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
