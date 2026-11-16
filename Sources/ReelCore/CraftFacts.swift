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

// MARK: - Reading the facts

/// Reads a film's facts sheet (1.11, spec §7.3) from what Reel already fetches with the film's
/// info: Wikidata's statements (ratio, colour, cinematography awards) and the film's own English
/// Wikipedia article, where only one kind of sentence counts: a plain statement, about this film,
/// that it was shot on something. Nothing is inferred from a camera's name, a year, a crew member
/// or another film; a sentence that's unsure, about plans or about another film is left out.
public enum CraftFactReader {
    /// Sections where a sentence can say how the film was shot (not its release in IMAX theatres).
    static func isProductionSection(_ path: [String]) -> Bool {
        let all = path.joined(separator: " / ").lowercased()
        let top = path.first?.lowercased() ?? ""
        let out = ["release", "reception", "box office", "accolade", "award", "home media", "legacy", "marketing", "plot", "cast",
                   "sequel", "see also", "references", "external", "notes", "soundtrack", "music", "remaster", "restoration"]
        if out.contains(where: { all.contains($0) }) { return false }
        return top == "introduction" || top.contains("production") || all.contains("filming") || all.contains("cinematograph")
            || all.contains("photography") || all.contains("visual style") || all.contains("technical") || all.contains("format")
    }

    /// Words that make a sentence about plans, tests, other films or exhibition, not the shoot.
    static let unsure = ["originally", "initially", "planned", "considered", "would have", "wanted to", "hoped", "intended", "proposed",
                         "debated", "was to be", "were to be", "discussed", "contemplated", "had been", "if ", "unlike", "like his",
                         "like her", "similar to", "previous", "earlier film", "prior film", "his film", "her film", "sequel", "prequel",
                         "the original", "remake", "inspired by", "homage", "projected", "projection", "screened", "screening",
                         "released", "converted", "conversion", "remaster", "restor", "upscal", "transfer"]
    /// Words that make a sentence true of part of the film only.
    static let partly = ["some scenes", "several scenes", "certain scenes", "select scenes", "a few scenes", "one scene", "a scene",
                         "sequences", "sequence", "portions", "portion", "parts of", "part of the film", "partially", "partly",
                         "minutes of", "the opening", "the final", "the prologue", "the epilogue", "flashback", "second unit",
                         "test", "rehearsal", "some shots", "several shots", "certain shots", "a shot", "additional", "segments",
                         "segment", "some of the", "much of the", "most of the", "except", "while the rest", "mixed", "combination",
                         "alongside", "as well as", "both"]

    static let partlyPattern = #"\b(?:"# + partly.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + #")\b"#

    static func isPartly(_ lower: String) -> Bool { lower.patternRange(partlyPattern) != nil }

    struct Rule {
        let pattern: String
        let value: String
        let shotOn: ShotOn?
    }

    /// What it was shot on, as a sentence says it (the shooting verb is required).
    static let formats: [Rule] = [
        Rule(pattern: #"\b(?:shot|filmed|photographed|lensed|captured)\b[^.;]{0,40}\b(?:digitally|on digital|in digital|with digital cameras?|on (?:high-definition|hd) video)\b"#,
             value: "Digital", shotOn: .digital),
        Rule(pattern: #"\b(?:shot|filmed|photographed|lensed)\b[^.;]{0,40}\bwith imax (?:film )?cameras?\b|\b(?:shot|filmed|photographed)\b[^.;]{0,30}\b(?:on|in) imax\b|\bimax (?:film )?cameras? (?:were|was) used\b"#,
             value: "IMAX", shotOn: .imax),
        Rule(pattern: #"\b(?:shot|filmed|photographed|lensed)\b[^.;]{0,40}\b(?:on|in|using) (?:the )?(?:5-perf |five-perf )?65 ?mm\b|\b(?:shot|filmed|photographed)\b[^.;]{0,40}\b(?:on|in) 65-millimet"#,
             value: "65 mm film", shotOn: .film),
        Rule(pattern: #"\b(?:shot|filmed|photographed|lensed)\b[^.;]{0,40}\b(?:on|in|using) (?:super ?)?16 ?mm\b|\b(?:shot|filmed|photographed)\b[^.;]{0,40}\b(?:on|in) (?:super )?16-millimet"#,
             value: "16 mm film", shotOn: .film),
        Rule(pattern: #"\b(?:shot|filmed|photographed|lensed)\b[^.;]{0,40}\b(?:on|in|using) (?:the )?(?:super ?)?35 ?mm\b|\b(?:shot|filmed|photographed)\b[^.;]{0,40}\b(?:on|in) 35-millimet"#,
             value: "35 mm film", shotOn: .film),
        Rule(pattern: #"\b(?:shot|filmed|photographed|lensed)\b[^.;]{0,30}\b(?:on (?:celluloid|film stock|kodak|eastman|fujifilm|film)\b)"#,
             value: "Film", shotOn: .film),
        Rule(pattern: #"\b(?:shot|filmed|photographed|lensed)\b[^.;]{0,30}\bin black[- ]and[- ]white\b"#,
             value: "Black and white", shotOn: .blackAndWhite),
        Rule(pattern: #"\b(?:shot|filmed|photographed|lensed)\b[^.;]{0,50}\banamorphic\b|\banamorphic lenses\b[^.;]{0,30}\b(?:were|was) used\b"#,
             value: "Anamorphic", shotOn: .anamorphic),
    ]

    /// Cameras, named as makers sell them; only from a sentence that says it was shot with them.
    static let cameraPattern = #"\b(?:Arri ?(?:Alexa|Amira|cam)[\w\- ]{0,12}|Arriflex[\w\- ]{0,12}|Panavision (?:Millennium[\w\- ]{0,6}|Panaflex[\w\- ]{0,10}|Platinum|Genesis|DXL\d?)|Sony (?:Venice ?\d?|CineAlta[\w\- ]{0,8}|F65|F55|HDW-F900|FX\d)|RED (?:Epic|Dragon|Helium|Monstro|One|Komodo|V-Raptor|Ranger|Raptor)[\w\- ]{0,10}|Canon (?:C\d{3}|EOS[\w\- ]{0,8})|Blackmagic[\w\- ]{0,16}|IMAX MSM[\w\- ]{0,6}|Phantom (?:Flex|v\d+)[\w\- ]{0,6}|Aaton[\w\- ]{0,10}|Bolex[\w\- ]{0,6})"#
    static let lensPattern = #"\b(?:Panavision [CEGT]-[Ss]eries|Panavision (?:Primo|Ultra Speed|Super Speed|Sphero|Anamorphic)[\w\- ]{0,8}|Ultra Panavision 70|Cooke (?:S\d|Panchro|Speed Panchro|Anamorphic|Xtal)[\w/\- ]{0,10}|Zeiss (?:Super Speed|Master Prime|Ultra Prime|Supreme)[\w\- ]{0,6}|Hawk[\w\- ]{0,10}anamorphic|Leica Summilux[\w\- ]{0,6}|Canon K35|Kowa[\w\- ]{0,10}|Lomo[\w\- ]{0,10}|Petzval[\w\- ]{0,6})"#

    /// The facts from Wikidata's statements and the article's text.
    /// - Parameters:
    ///   - article: the plain text of the film's own English article (sections marked "== … ==").
    ///   - title: the film's title, to tell a sentence about this film.
    public static func read(article: String?, title: String, articleTitle: String?, quick: QuickFacts?, now: Date = Date()) -> CraftFacts {
        var facts: [CraftFacts.Fact] = []
        var shotOn: [ShotOn] = []
        var inPart = Set<ShotOn>()
        let wikidata = "Wikidata"
        for ratio in quick?.aspectRatios ?? [] where !ratio.isEmpty {
            facts.append(.init(row: .aspectRatio, value: ratio, source: wikidata))
        }
        let colours = (quick?.colour ?? []).map(colourLabel)
        if !colours.isEmpty {
            facts.append(.init(row: .colour, value: colours.joined(separator: " and "), source: wikidata))
            if ShotOn.known(colour: quick?.colour) == [.blackAndWhite] { shotOn.append(.blackAndWhite) }
        }

        let link = articleTitle.flatMap { title in
            URL(string: "https://en.wikipedia.org/wiki/" + title.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)
        }
        var seenValues = Set<String>()
        for sentence in statements(in: article ?? "", title: title) {
            let lower = sentence.lowercased()
            let sentencePart = isPartly(lower)
            // "In part" is judged in the clause that says it ("shot digitally, while some scenes
            // were shot with IMAX cameras": only IMAX is in part).
            let clauses = clausesOf(lower)
            for rule in formats where lower.patternRange(rule.pattern) != nil {
                let clause = clauses.first { $0.patternRange(rule.pattern) != nil }
                let part = clause.map(isPartly) ?? sentencePart
                guard seenValues.insert(rule.value).inserted else { continue }
                facts.append(.init(row: .format, value: rule.value, source: "Wikipedia", link: link, sentence: sentence, inPart: part))
                if let kind = rule.shotOn {
                    if !shotOn.contains(kind) { shotOn.append(kind) }
                    if part { inPart.insert(kind) } else { inPart.remove(kind) }
                }
            }
            let shotWith = lower.patternRange(#"\b(?:shot|filmed|photographed|lensed)\b"#) != nil
            guard shotWith else { continue }
            for (row, pattern) in [(CraftFacts.Row.camera, cameraPattern), (.lenses, lensPattern)] {
                guard let range = sentence.patternRange(pattern) else { continue }
                let name = String(sentence[range]).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
                guard name.count >= 3, seenValues.insert(name.lowercased()).inserted else { continue }
                facts.append(.init(row: row, value: name, source: "Wikipedia", link: link, sentence: sentence, inPart: sentencePart))
            }
        }
        // A format both stated in full and in part (film and digital): kept as each sentence said.
        for honour in quick?.cinematographyHonours ?? [] {
            facts.append(.init(row: .award, value: honour.name + (honour.won ? " (won)" : " (nominated)"), source: wikidata))
        }
        let order: [CraftFacts.Row] = [.format, .aspectRatio, .colour, .camera, .lenses, .award]
        facts.sort { (order.firstIndex(of: $0.row) ?? 9) < (order.firstIndex(of: $1.row) ?? 9) }
        return CraftFacts(readAt: now, facts: facts, shotOn: shotOn, inPart: inPart)
    }

    /// A sentence's clauses, split where a new statement starts (", while", "; ", " but ").
    static func clausesOf(_ lower: String) -> [String] {
        var clauses: [String] = []
        var rest = lower
        let pattern = #",? (?:while|whereas|but|although|though|with the exception that) |; |, and "#
        while let range = rest.patternRange(pattern) {
            clauses.append(String(rest[..<range.lowerBound]))
            rest = String(rest[range.upperBound...])
        }
        clauses.append(rest)
        return clauses
    }

    /// "colour" → "Colour", "black-and-white" → "Black and white".
    static func colourLabel(_ label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("black") && lower.contains("white") { return "Black and white" }
        if lower == "color" || lower == "colour" { return "Colour" }
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    /// The sentences that can state a fact: in a section about the making, about this film (its
    /// title, "the film", "the movie", "it", "filming", "principal photography"), with nothing
    /// unsure in them; the part after "rather than" or "instead of" is dropped.
    static func statements(in article: String, title: String) -> [String] {
        let name = title.lowercased()
        var result: [String] = []
        for section in FunFactExtractor.sections(from: article) where isProductionSection(section.path) {
            for sentence in ReceptionAnalyzer.sentences(in: section.text) {
                guard sentence.count <= 400 else { continue }
                var kept = sentence
                for cut in [" rather than ", " instead of ", " as opposed to ", " but not ", " except for "] {
                    if let range = kept.range(of: cut, options: .caseInsensitive) { kept = String(kept[..<range.lowerBound]) }
                }
                let lower = kept.lowercased()
                if unsure.contains(where: { lower.contains($0) }) { continue }
                // Another film named in it: a year in brackets is how Wikipedia names one.
                if lower.patternRange(#"\((?:19|20)\d\d(?: film)?\)"#) != nil { continue }
                let aboutThis = (!name.isEmpty && lower.contains(name)) || lower.hasPrefix("it ") || lower.contains("the film")
                    || lower.contains("the movie") || lower.contains("filming") || lower.contains("principal photography")
                    || lower.contains("the production") || lower.contains("the picture")
                guard aboutThis else { continue }
                result.append(kept.hasSuffix(".") ? kept : kept + ".")
            }
        }
        return result
    }
}
