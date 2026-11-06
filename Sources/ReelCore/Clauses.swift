import Foundation

// MARK: - The clauses of a statement (1.10.10)

/// A sentence split into the clauses it is made of, and how they hang together. Deterministic and
/// small: the parts that never assert anything about the sentence's own subject on their own — a
/// relative clause ("…, who has also worked on <Other>,"), an appositive ("…, a tribute to <Person>'s
/// <Format>,"), words between dashes or brackets, an opening comparison ("As on <Other> – … –") — are
/// told apart from the clauses that do.
///
/// Why a clause model and not another rule (1.10.10): up to 1.10.9 whether a sentence was about
/// another production was decided once, for the whole sentence. A sentence about this film that
/// mentioned another production in a side clause lost all its gear ("Colourist Greg Fisher at
/// Company 3, who has also worked on <Other>'s last few films, …"), and gear inside a side clause
/// about another production was read as this film's ("…recalled <Other>, which was shot in
/// candlelight"). Both are the same question asked at the wrong level: whose statement is the
/// gear in. A clause answers it; no list of phrases can.
public struct ClauseMap: Sendable {
    public enum Role: String, Sendable {
        /// The sentence's own statement.
        case main
        /// A further statement joined to it ("…; the lenses were…", "…, but we…").
        case coordinate
        /// About the words before it ("…, which was shot in…", "…, who has also worked on…").
        case relative
        /// Renames the words before it (", a tribute to…,").
        case appositive
        /// Between brackets or dashes.
        case parenthetical
        /// An opening comparison ("As on <Other>, …", "Unlike <Other>, …"). (Not "When I was working on
        /// <Other>, I…": a time apart governs the whole statement after it.)
        case comparison
    }

    public struct Clause: Sendable, Equatable {
        /// Character offsets in the sentence.
        public let lower: Int
        public let upper: Int
        public let role: Role
        /// For a relative clause or an appositive: the offsets of the words it is about (up to eight
        /// words before it, in the clause it hangs on).
        public let antecedent: Range<Int>?

        /// A clause that doesn't assert anything of the sentence's subject on its own.
        public var isDependent: Bool { role != .main && role != .coordinate }
    }

    public let sentence: String
    public let clauses: [Clause]

    static let parenthesis = try! NSRegularExpression(pattern: #"\((?![\s\d–-]*\))[^()]{1,160}\)"#)
    static let dashPair = try! NSRegularExpression(pattern: #"\s[–—]\s[^–—;.]{2,160}?\s[–—]\s|\s-\s[^;.]{2,120}?\s-\s"#)
    /// "…, which …", "…, with whom …", "… which recalled …" (no "that": too often a conjunction).
    static let relativeStart = try! NSRegularExpression(
        pattern: #",\s*(?:(?:with|for|on|in|of|by|from|to|through)\s+)?(?:which|who|whom|whose)\b|(?<=[a-z])\s+(?:which|who|whom)\s+(?=(?:was|were|is|are|had|has|have|recalled|recalls|used|uses|also|later|previously|once|famously)\b)"#,
        options: [.caseInsensitive])
    /// ", a tribute to …", ", an homage to …", ", a nod to …", ", the director's previous film…".
    /// (A production noun only with a word that makes it another one: ", the production was shot…" is the
    /// sentence's own subject, not an appositive.)
    static let appositiveStart = try! NSRegularExpression(
        pattern: #",\s*(?:itself\s+)?(?:a|an|the)\s+(?:[\w'’-]+\s+){0,3}?(?:tribute|homage|nod|reference|callback|throwback|salute|allusion|riff|send-up|technique|trick|habit|idea)\b|,\s*(?:a|an|the|his|her|their|its)\s+(?:[\w'’-]+\s+){0,2}?(?:previous|earlier|last|next|first|debut|other|prior|later|recent)\s+(?:[\w'’-]+\s+){0,2}?(?:films?|features?|movies?|series|productions?|pictures?|documentar(?:y|ies)|projects?|collaborations?)\b|,\s*(?:a|an|the)\s+(?:follow-up|sequel|remake|prequel)\b"#,
        options: [.caseInsensitive])
    static let leadingComparison = try! NSRegularExpression(
        pattern: #"^\W*(?:and\s+|but\s+)?(?:just\s+|much\s+|exactly\s+)?(?:(?:as|like)\s+(?:with|on|in|for|during|before|previously|earlier|he|she|they|we|i)\b|unlike\b|compared\s+(?:to|with)\b|in contrast\s+(?:to|with)\b|similar\s+to\b)"#,
        options: [.caseInsensitive])
    static let coordinateBreak = try! NSRegularExpression(
        pattern: #";\s+|,?\s+but\s+|,?\s+whereas\s+|,\s+while\s+|,\s+and\s+(?=(?:i|we|he|she|they|it|the|his|her|their|our)\s+\w+)"#,
        options: [.caseInsensitive])

    public init(_ sentence: String) {
        self.sentence = sentence
        let chars = Array(sentence)
        let count = chars.count
        let ns = NSRange(sentence.startIndex..., in: sentence)
        func offsets(_ range: NSRange) -> Range<Int>? {
            guard let found = Range(range, in: sentence) else { return nil }
            return sentence.distance(from: sentence.startIndex, to: found.lowerBound)..<sentence.distance(from: sentence.startIndex, to: found.upperBound)
        }
        var found: [Clause] = []
        func taken(_ offset: Int) -> Bool { found.contains { $0.lower <= offset && offset < $0.upper } }

        // Brackets and words between a pair of dashes.
        var parentheticals: [Range<Int>] = []
        for regex in [Self.parenthesis, Self.dashPair] {
            for match in regex.matches(in: sentence, range: ns) {
                guard let range = offsets(match.range), !parentheticals.contains(where: { $0.overlaps(range) }) else { continue }
                parentheticals.append(range)
            }
        }
        // An opening comparison: to its first comma outside brackets, or to the end of the dashes or
        // brackets that come right after its words.
        if let match = Self.leadingComparison.firstMatch(in: sentence, range: ns), let start = offsets(match.range) {
            var end: Int? = nil
            var i = start.upperBound
            while i < count {
                if let inside = parentheticals.first(where: { $0.lowerBound == i || ($0.lowerBound < i && i < $0.upperBound) }) {
                    // Words between dashes right after the comparison close it ("As on <Other> – two
                    // previous collaborations – <Film> was…").
                    let rest = String(chars[inside.upperBound..<min(count, inside.upperBound + 2)])
                    if !(rest.first.map { $0 == "," } ?? false), String(chars[inside.lowerBound..<min(count, inside.lowerBound + 3)]).contains(where: { "–—-".contains($0) }) {
                        end = inside.upperBound
                        break
                    }
                    i = inside.upperBound
                    continue
                }
                if chars[i] == "," || chars[i] == ";" { end = i + 1; break }
                i += 1
            }
            if let end, end < count, end - start.lowerBound < 220 {
                found.append(Clause(lower: 0, upper: end, role: .comparison, antecedent: nil))
            }
        }
        for range in parentheticals where !taken(range.lowerBound) {
            found.append(Clause(lower: range.lowerBound, upper: range.upperBound, role: .parenthetical, antecedent: nil))
        }
        // Relative clauses and appositives: to the next comma, semicolon or dash outside brackets.
        func end(from start: Int) -> Int {
            var i = start
            while i < count {
                if let inside = parentheticals.first(where: { $0.lowerBound <= i && i < $0.upperBound }), chars[inside.lowerBound] == "(" {
                    i = inside.upperBound
                    continue
                }
                if chars[i] == "," || chars[i] == ";" || ((chars[i] == "–" || chars[i] == "—") && i > start) { return i }
                i += 1
            }
            return count
        }
        func antecedent(before start: Int) -> Range<Int> {
            // Up to eight words back, not past a clause already found or a break.
            var i = start
            var words = 0
            var inWord = false
            while i > 0 {
                let c = chars[i - 1]
                if c == ";" || c == "–" || c == "—" { break }
                if c == ",", words > 0 { break }
                if c.isWhitespace { if inWord { words += 1; inWord = false; if words >= 8 { break } } } else { inWord = true }
                i -= 1
            }
            return i..<start
        }
        for regex in [Self.relativeStart, Self.appositiveStart] {
            for match in regex.matches(in: sentence, range: ns) {
                guard let range = offsets(match.range), !taken(range.lowerBound + 1) else { continue }
                let stop = end(from: range.upperBound)
                guard stop > range.upperBound else { continue }
                found.append(Clause(lower: range.lowerBound, upper: stop, role: regex === Self.relativeStart ? .relative : .appositive,
                                    antecedent: antecedent(before: range.lowerBound)))
            }
        }
        // The rest: the main clause, and coordinate clauses after a break.
        var dependent = [Bool](repeating: false, count: count)
        for clause in found { for i in clause.lower..<min(clause.upper, count) { dependent[i] = true } }
        var breaks = Set<Int>()
        for match in Self.coordinateBreak.matches(in: sentence, range: ns) {
            if let range = offsets(match.range), !dependent[range.lowerBound] { breaks.insert(range.lowerBound) }
        }
        var role = Role.main
        var start: Int? = nil
        var independent: [Clause] = []
        func close(_ upper: Int) {
            if let lower = start, upper > lower { independent.append(Clause(lower: lower, upper: upper, role: role, antecedent: nil)) }
            start = nil
        }
        for i in 0..<count {
            if breaks.contains(i) {
                close(i)
                role = .coordinate
            }
            if dependent[i] {
                close(i)
            } else if start == nil {
                start = i
            }
        }
        close(count)
        // A run of only spaces and punctuation between two dependent clauses is no clause.
        found += independent.filter { clause in
            chars[clause.lower..<clause.upper].contains { $0.isLetter || $0.isNumber }
        }
        clauses = found.sorted { $0.lower < $1.lower }
    }

    /// The clause the offset is in (the innermost: a relative clause inside a main one).
    public func clause(at offset: Int) -> Clause? {
        clauses.filter { $0.lower <= offset && offset < $0.upper }.min { ($0.upper - $0.lower) < ($1.upper - $1.lower) }
    }

    public func text(_ clause: Clause) -> String {
        let chars = Array(sentence)
        return String(chars[clause.lower..<min(clause.upper, chars.count)])
    }

    public func antecedentText(_ clause: Clause) -> String? {
        guard let range = clause.antecedent else { return nil }
        let chars = Array(sentence)
        return String(chars[range.lowerBound..<min(range.upperBound, chars.count)])
    }

    /// The sentence with the given clauses blanked, character for character.
    public func blanking(_ blanked: [Clause], in text: String) -> String {
        var chars = Array(text)
        for clause in blanked { for i in clause.lower..<min(clause.upper, chars.count) { chars[i] = " " } }
        return String(chars)
    }
}

/// Whose production each clause of a statement is about (1.10.10): the decision that up to 1.10.9
/// was made once per sentence, made per clause. A dependent clause (relative, appositive, brackets,
/// dashes, an opening comparison) naming another production is that production's and nothing in it is
/// read for this film, but it doesn't make the clause it hangs on another production's. A relative
/// clause or an appositive about another production's name is that production's even when it names
/// no title itself ("…<Person>'s <Other>, which was shot in candlelight").
public struct ClauseProduction: Sendable {
    public let map: ClauseMap
    /// Dependent clauses about another production.
    public let other: [ClauseMap.Clause]
    /// Whether every mention of another production in the sentence is in a dependent clause, and
    /// something is left: the sentence's own statement is free of it.
    public let confined: Bool

    /// `signal`: whether a piece of text is about another production (the sentence-level test, applied
    /// to a clause).
    /// `main`: the sentence with the parts already set aside as comparisons blanked (`ComparisonFrame`),
    /// what the sentence's own statement is read from; dependent clauses and what they're about are
    /// read as written.
    /// A relative clause about a person, naming their other work ("…Okafor, who shot Lantern Season on
    /// the Alexa Mini, …"): a capitalised title as what they shot, not this film's.
    static let personWork = try! NSRegularExpression(
        pattern: #"^\W*(?:who|whom|whose)\b[^,;]{0,40}?\b(?:shot|lensed|photographed|lit|filmed|directed|made|graded|cut)\s+((?:[A-Z][\w'’-]*)(?:\s+(?:[A-Z][\w'’-]*|of|the|and|a|in|on|to)){0,6})"#)

    public init(_ sentence: String, main: String? = nil, title: String? = nil, signal: (String) -> Bool) {
        let map = ClauseMap(sentence)
        let mainChars = Array(main ?? sentence)
        let comparisons = map.clauses.filter { $0.role == .comparison }
        func namesOtherWork(_ text: String) -> Bool {
            guard let match = Self.personWork.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let found = Range(match.range(at: 1), in: text) else { return false }
            var named = String(text[found])
            while let last = named.split(separator: " ").last, ["of", "the", "and", "a", "in", "on", "to"].contains(String(last)) {
                named = named.split(separator: " ").dropLast().joined(separator: " ")
            }
            guard named.count >= 3 else { return false }
            guard let title else { return true }
            return !TitleMatch.names(named, title: title) && !TitleMatch.names(title, title: named)
        }
        self.map = map
        var other: [ClauseMap.Clause] = []
        var independentSignal = false
        var independentText = ""
        for clause in map.clauses {
            let text = map.text(clause)
            if clause.isDependent {
                let antecedentOther = (clause.role == .relative || clause.role == .appositive)
                    && (map.antecedentText(clause).map(signal) == true
                        // Hanging on what an opening comparison compares with ("Unlike Glass Rivers, which
                        // was shot on 35mm, …", "Unlike her previous film, Paper Moon, which…").
                        || comparisons.contains { comparison in
                            comparison.upper <= clause.lower + 1
                                && (comparison.upper >= clause.lower ? "" : map.text(ClauseMap.Clause(lower: comparison.upper, upper: clause.lower,
                                                                                                       role: .main, antecedent: nil)))
                                    .split(whereSeparator: { $0.isWhitespace }).count <= 4
                        })
                    || (clause.role == .relative && namesOtherWork(text))
                    // A relative clause naming this film's people as its subject is about them, not
                    // the production before it ("…Lubezki, with whom Iñárritu also collaborated on…"):
                    // that one is caught by its own words.
                if signal(text) || antecedentOther { other.append(clause) }
            } else {
                let own = mainChars.count == map.sentence.count ? String(mainChars[clause.lower..<min(clause.upper, mainChars.count)]) : text
                independentText += " " + own
                if signal(own) { independentSignal = true }
            }
        }
        self.other = other
        confined = !independentSignal && independentText.filter(\.isLetter).count >= 12
    }

    /// Whether the words at these offsets are in a clause about another production.
    public func isOther(_ offsets: Range<Int>) -> Bool {
        other.contains { $0.lower <= offsets.lowerBound && offsets.lowerBound < $0.upper }
    }
}

// MARK: - The stage an image format is said of (1.10.10)

/// Which stage of the image a ratio or a format is said of. A ratio can describe the camera's
/// capture, the framing the film was composed for, an extraction from a larger frame, a sequence,
/// the theatrical presentation, or a later home release, restoration or stream; only the last three
/// say nothing of how the film was made. A ratio whose stage can't be told keeps no stage (nil): it
/// is not given one by guessing.
public enum FormatStage: String, Codable, Sendable, CaseIterable {
    case capture, framing, extraction, sequence, theatrical, homeMedia, restoration, streaming

    /// The film's own image: how it was shot, framed or shown when it came out.
    public var isFilmImage: Bool { ![.homeMedia, .restoration, .streaming].contains(self) }

    public var label: String {
        switch self {
        case .capture: "as shot"
        case .framing: "framing"
        case .extraction: "extraction"
        case .sequence: "for some sequences"
        case .theatrical: "theatrical"
        case .homeMedia: "home release"
        case .restoration: "restoration"
        case .streaming: "streaming"
        }
    }

    static let homeMediaCue = try! NSRegularExpression(
        pattern: #"\b(?:home (?:media|video|entertainment|release)s?|blu-?rays?|dvds?|uhd|ultra hd|4k (?:disc|release|blu-?ray)|vhs|laserdiscs?|dolby digital|dts\b|5\.1\b|7\.1\b|subtitles?|audio tracks?|bonus features?|special features?|criterion|box set|disc|television (?:broadcast|airing|version)|tv (?:broadcast|airing|version))\b"#,
        options: [.caseInsensitive])
    static let restorationCue = try! NSRegularExpression(pattern: #"\b(?:restor\w*|remaster\w*|re-?release[sd]?|re-?issue[sd]?|rescan\w*|new scan|new transfer)\b"#,
                                                          options: [.caseInsensitive])
    static let streamingCue = try! NSRegularExpression(pattern: #"\b(?:streaming|streamers?|netflix version|vod|on demand|imax enhanced)\b"#,
                                                        options: [.caseInsensitive])
    static let extractionCue = try! NSRegularExpression(
        pattern: #"\b(?:extract(?:ion|ions|ed|ing)?|cropp?(?:ed|ing)? (?:to|for|in)|crop (?:to|for)|protect(?:ed|ing)? for|center[- ]extract\w*|common top)\b"#,
        options: [.caseInsensitive])
    static let framingCue = try! NSRegularExpression(
        pattern: #"\b(?:designed (?:to be|for|in)|composed (?:for|in)|framed (?:for|in|to)|framing (?:for|in|of)|to match the\b[^.;]{0,60}\bof the (?:rest of the )?(?:film|movie|picture)|(?:aspect )?ratio of the (?:rest of the )?(?:film|movie|picture)|(?:the )?(?:film|movie|picture)(?:'s)? (?:primary |main |native |original )?(?:aspect )?ratio (?:was|is)|primary (?:aspect )?ratio|native (?:aspect )?ratio)\b"#,
        options: [.caseInsensitive])
    static let sequenceCue = try! NSRegularExpression(
        pattern: #"\b(?:for|in) (?:the |some |select |certain |several )?(?:sequences?|scenes?|shots?|segments?)\b|\b(?:select|certain|some) (?:sequences?|scenes?|shots?)\b"#,
        options: [.caseInsensitive])
    static let theatricalCue = try! NSRegularExpression(
        // (Not "presented in its theatrical 2.35:1": a presentation that may be any release stays undecided.)
        pattern: #"\b(?:theatrical(?:ly)? (?:release|run|projection|prints?|exhibition)|released theatrically|in (?:cinemas|theaters|theatres)|projected|projection)\b"#,
        options: [.caseInsensitive])
    static let captureCue = try! NSRegularExpression(
        pattern: #"\b(?:shot|shoot|shooting|filmed|filming|photographed|captured|capturing|lensed|recorded|acquired|originated|sensor|gate|negative)\b"#,
        options: [.caseInsensitive])

    /// The stage the ratio or format at `range` is said of, from its own clause (and the section it's in:
    /// `context`, a heading such as "Home media"). nil when its words don't say.
    public static func of(_ sentence: String, at range: Range<String.Index>, name: String, context: String = "") -> FormatStage? {
        let isRatio = name.contains(":1") || name.range(of: #"^\d(?:\.\d+)?:\d"#, options: .regularExpression) != nil
        let lead = ClaimFrame.governing(sentence, before: range, acrossCommas: true)
        let after = ClaimFrame.following(sentence, after: range)
        let scope = lead + " " + String(sentence[range]) + " " + after
        let wide = String(sentence[ClaimFrame.segmentStart(sentence, before: range)...])
        func has(_ regex: NSRegularExpression, _ text: String) -> Bool { ClaimFrame.has(regex, text) }
        // A later release, by its own words or its section's.
        if has(homeMediaCue, scope) || has(homeMediaCue, context) { return .homeMedia }
        if has(streamingCue, scope) || has(streamingCue, context) { return .streaming }
        if has(restorationCue, scope) || has(restorationCue, context) { return .restoration }
        guard isRatio else { return has(captureCue, scope) ? .capture : nil }
        if has(extractionCue, scope) { return .extraction }
        if has(sequenceCue, lead) || has(sequenceCue, after) { return .sequence }
        if has(framingCue, wide) { return .framing }
        if has(captureCue, scope) { return .capture }
        if has(theatricalCue, scope) || has(theatricalCue, wide) { return .theatrical }
        return nil
    }
}
