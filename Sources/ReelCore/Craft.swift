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
    /// 7: a plan given up, what footage was transferred onto, an award speech and an interviewer's
    /// line aren't how it was shot; a stated share ("about 28 minutes of IMAX") is in part.
    /// 8: the rest of an award speech's quote, and films counted in general ("four out of five
    /// nominated films"), aren't how it was shot either.
    public static let currentVersion = 8
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
        /// Carried from an earlier reading because its source couldn't be read again (a site didn't
        /// answer): when that reading was made, and by which rules. Nil: found by the reading it's in.
        public var carriedFrom: Date?
        public var carriedRules: Int?
        /// Readings in a row, every site answering, that didn't find its page again (it's dropped
        /// after `CraftIndex.maxRetries`).
        public var misses: Int?

        public init(shotOn: ShotOn, text: String, source: String, partial: Bool = false, carriedFrom: Date? = nil,
                    carriedRules: Int? = nil, misses: Int? = nil) {
            self.shotOn = shotOn
            self.text = text
            self.source = source
            self.partial = partial
            self.carriedFrom = carriedFrom
            self.carriedRules = carriedRules
            self.misses = misses
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            shotOn = try c.decode(ShotOn.self, forKey: .shotOn)
            text = try c.decode(String.self, forKey: .text)
            source = try c.decode(String.self, forKey: .source)
            partial = try c.decodeIfPresent(Bool.self, forKey: .partial) ?? false
            carriedFrom = try c.decodeIfPresent(Date.self, forKey: .carriedFrom)
            carriedRules = try c.decodeIfPresent(Int.self, forKey: .carriedRules)
            misses = try c.decodeIfPresent(Int.self, forKey: .misses)
        }

        public var isCarried: Bool { carriedFrom != nil }

        /// The site it was read on: "Wikipedia" for "Wikipedia: Roger Deakins" too.
        public var site: String { CraftIndex.site(of: source) }
    }

    public var version: Int
    public var readAt: Date
    public var shotOn: [ShotOn]
    /// The gear and techniques named ("ARRI Alexa 65", "Steadicam", "Natural light", "16 mm"), most
    /// telling kinds first, at most 30.
    public var names: [String]
    /// One for each of `shotOn`.
    public var evidence: [Evidence]
    /// How many texts it was read from (the article, interviews, the cinematographer's article).
    public var sources: Int
    /// Where those texts were read, as their sentences' sources say it ("American Cinematographer",
    /// "Wikipedia", "Wikipedia: Roger Deakins"): what was read again, for `merge`.
    public var read: [String] = []
    /// How it was found (see `currentDiscovery`); 1 for readings before 1.9.0.
    public var discovery: Int
    /// Sites that didn't answer or asked Reel to wait while it was read: read again later.
    public var unanswered: [String] = []
    /// Readings in a row that were incomplete: a site unanswered, or a tag carried over.
    public var retries = 0
    /// When it's read again, when that's planned (a site didn't answer, a tag was carried over):
    /// until then it isn't, unless the rules change.
    public var retryAt: Date?

    public init(version: Int = CraftIndex.currentVersion, readAt: Date = Date(), shotOn: [ShotOn], names: [String],
                evidence: [Evidence] = [], sources: Int = 0, read: [String] = [], discovery: Int = CraftIndex.currentDiscovery,
                unanswered: [String] = [], retries: Int = 0, retryAt: Date? = nil) {
        self.read = read
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
        read = try c.decodeIfPresent([String].self, forKey: .read) ?? []
        discovery = try c.decodeIfPresent(Int.self, forKey: .discovery) ?? 1
        unanswered = try c.decodeIfPresent([String].self, forKey: .unanswered) ?? []
        retries = try c.decodeIfPresent(Int.self, forKey: .retries) ?? 0
        retryAt = try c.decodeIfPresent(Date.self, forKey: .retryAt)
    }

    /// Tries in a row while a tag is carried over because its page wasn't found again (every site
    /// answering): after that the reading made then stands.
    public static let maxRetries = 4

    /// How long until an incomplete reading is tried again: after a site didn't answer, six hours,
    /// then a day, three days, a week, and then every 30 days for as long as it doesn't (a captcha
    /// lifts in hours, a site down for longer gets days, one gone for good isn't asked every week);
    /// when a tag was carried over with every site answering, a week.
    public static func retryDelay(_ retries: Int, unanswered: Bool) -> TimeInterval {
        guard unanswered else { return 7 * 86_400 }
        let delays: [TimeInterval] = [6 * 3600, 86_400, 3 * 86_400, 7 * 86_400, 30 * 86_400]
        return delays[min(max(retries, 1), delays.count) - 1]
    }

    /// To be read again: by newer rules at once; otherwise when planned, after half a year, or when
    /// finding has improved and it was read from little.
    public func isStale(now: Date = Date()) -> Bool {
        if version < CraftIndex.currentVersion { return true }
        if let retryAt { return now >= retryAt }
        return readAt < now.addingTimeInterval(-CraftIndex.maxAge) || (discovery < CraftIndex.currentDiscovery && isThin)
    }

    /// Not everything could be read again: a site didn't answer, or a tag stands on an earlier
    /// reading's sentence. Read again automatically (`retryAt`); Settings counts these.
    public var isPartial: Bool { !unanswered.isEmpty || evidence.contains(where: \.isCarried) }

    /// To be read again because it's partial (Settings counts these).
    public var willReadAgain: Bool { retryAt != nil && isPartial }

    /// Read from the film's article alone (or nothing), or nothing found on what it was shot on:
    /// worth reading again when finding improves.
    public var isThin: Bool { sources <= 1 || shotOn.isEmpty }

    /// "Wikipedia" for "Wikipedia: Roger Deakins": the site a source is on, as `unanswered` names it.
    public static func site(of source: String) -> String {
        source.components(separatedBy: ": ").first ?? source
    }

    /// A tag the new reading no longer has, and why it wasn't kept.
    public struct Dropped: Equatable, Sendable {
        public let shotOn: ShotOn
        public let reason: String
    }

    /// What `merge` kept: the reading stored, the tags carried over from the one before (marked so),
    /// and the ones dropped.
    public struct Merged: Equatable, Sendable {
        public let index: CraftIndex
        public let carried: [Evidence]
        public let dropped: [Dropped]
    }

    /// What's stored when a film has been read again: the new reading, tag by tag. A tag it no longer
    /// has is dropped when its sentence's source was read again (by these rules it doesn't say so), or
    /// its source answered but its page wasn't found again for four readings, or it was found by
    /// older rules. It's carried over, marked with the reading it came from, only while its source
    /// couldn't be read again: its site didn't answer (for as long as it doesn't, with the reading
    /// tried again later), or, by the same rules, its page wasn't found this time. A reading found a
    /// better way (discovery) replaces the old one whole: the texts it no longer reads were about
    /// another film.
    public static func merge(old: CraftIndex?, new: CraftIndex, now: Date = Date()) -> CraftIndex {
        merging(old: old, new: new, now: now).index
    }

    public static func merging(old: CraftIndex?, new: CraftIndex, now: Date = Date()) -> Merged {
        var merged = new
        let tries = (old?.retries ?? 0) + 1
        var carried: [Evidence] = [], dropped: [Dropped] = []
        if let old {
            for kind in old.shotOn where !new.shotOn.contains(kind) {
                guard let evidence = old.evidence(for: kind) else {
                    dropped.append(Dropped(shotOn: kind, reason: "the earlier reading kept no sentence for it"))
                    continue
                }
                let site = evidence.site
                // Worked out from Wikidata and TMDB each time, not read from a page.
                let fromPage = site != "Wikidata" && site != "TMDB"
                let readAgain = new.read.contains(evidence.source)
                // Its site didn't answer, unless its own page was read all the same (the
                // cinematographer's article, "Wikipedia: …", while the film's didn't come).
                let siteDown = fromPage && new.unanswered.contains(site) && !(readAgain && evidence.source != site)
                let sameRules = (evidence.carriedRules ?? old.version) == new.version
                let misses = (evidence.misses ?? 0) + 1
                let carry: Bool
                let reason: String
                if new.discovery > old.discovery {
                    carry = false
                    reason = "found again a better way, which no longer reads its source"
                } else if !fromPage {
                    carry = false
                    reason = "\(site) no longer says so"
                } else if siteDown {
                    carry = true
                    reason = ""
                } else if readAgain {
                    carry = false
                    reason = "\(evidence.source) was read again and, by rules \(new.version), doesn't say so"
                } else if !sameRules {
                    carry = false
                    reason = "found by rules \(evidence.carriedRules ?? old.version); \(evidence.source) wasn't found again to read by rules \(new.version)"
                } else if misses <= maxRetries {
                    carry = true
                    reason = ""
                } else {
                    carry = false
                    reason = "\(evidence.source) wasn't found again in \(maxRetries) readings"
                }
                if carry {
                    var kept = evidence
                    kept.carriedFrom = evidence.carriedFrom ?? old.readAt
                    kept.carriedRules = evidence.carriedRules ?? old.version
                    // Counted only while every site answers and its page isn't found.
                    kept.misses = siteDown ? evidence.misses : misses
                    carried.append(kept)
                } else {
                    dropped.append(Dropped(shotOn: kind, reason: reason))
                }
            }
            if !carried.isEmpty {
                let kinds = Set(merged.shotOn).union(carried.map(\.shotOn))
                merged.shotOn = ShotOn.allCases.filter { kinds.contains($0) }
                let byKind = Dictionary((merged.evidence + carried).map { ($0.shotOn, $0) }, uniquingKeysWith: { first, _ in first })
                merged.evidence = merged.shotOn.compactMap { byKind[$0] }
                // Its names too, when read by these rules: search still finds what that page named.
                if old.version == new.version {
                    var names = merged.names
                    for name in old.names where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { names.append(name) }
                    merged.names = Array(names.prefix(30))
                }
            }
        }
        if !new.unanswered.isEmpty {
            merged.retries = tries
            merged.retryAt = now.addingTimeInterval(retryDelay(tries, unanswered: true))
        } else if !carried.isEmpty {
            merged.retries = tries
            merged.retryAt = now.addingTimeInterval(retryDelay(tries, unanswered: false))
        } else {
            merged.retries = 0
            merged.retryAt = nil
        }
        return Merged(index: merged, carried: carried, dropped: dropped)
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
        var scope: [ShotOn: Int] = [:]
        // Only what's said to have been shot with: the names alone are for the notes and search.
        for spec in specs.specs where spec.capture {
            for found in Self.shotOn(spec) {
                // Film and Digital both show when a film mixes them; "in part" is for the rest.
                let mixed = [.film, .digital].contains(found)
                var partial = spec.partial && !mixed
                var rank = mixed ? 1 : spec.scopeRank
                // A black-and-white stock (Double-X) is often for some scenes: in part, unless
                // Wikidata says the whole film is black and white (below).
                if found == .blackAndWhite, spec.name != "Black and white", !partial {
                    partial = true
                    rank = 0
                }
                let said = Evidence(shotOn: found, text: spec.evidence ?? spec.name, source: spec.source ?? "Wikipedia", partial: partial)
                // The whole film in so many words outweighs a stated share ("about 28 minutes"), which
                // outweighs a sentence that only says it was filmed that way, which outweighs any
                // number about part of it. Among equals, the first read.
                if let known = scope[found], known >= rank { continue }
                evidence[found] = said
                scope[found] = rank
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
