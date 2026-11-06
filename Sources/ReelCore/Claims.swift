import Foundation

// MARK: - Titles (1.10.9)

/// A film's title as every part of the pipeline compares it: its words in order, whatever the
/// punctuation between them ("Once Upon a Time... in Hollywood", "Once Upon a Time… in Hollywood",
/// "Once Upon a Time in Hollywood"), its apostrophes ("Don't", "Don’t", "Dont") and "&" or "and".
/// Only punctuation and spacing may differ: every word must be there, in order, with nothing else
/// between (no fuzzy match), so "Once Upon a Time in America" is never "…in Hollywood". Accents are
/// compared without regard to marks ("Leon" is "Léon"). Whether case counts is the caller's: a short
/// or common title ("Drive", "Heat", "F1") is matched as written (`PageContext.names`).
public enum TitleMatch {
    /// The title's words as written: letters and digits, an apostrophe inside a word kept ("Don't"),
    /// "&" a word of its own.
    public static func words(_ title: String) -> [String] {
        var words: [String] = []
        var current = ""
        func flush() {
            while current.hasSuffix("'") { current.removeLast() }
            if !current.isEmpty { words.append(current) }
            current = ""
        }
        for character in title {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if character == "'" || character == "’" || character == "‘" || character == "ʼ" {
                if !current.isEmpty { current.append("'") }
            } else if character == "&" || character == "＆" {
                flush()
                words.append("&")
            } else {
                flush()
            }
        }
        flush()
        return words
    }

    /// The canonical form: lowercase, no accents or apostrophes, "&" as "and", words single-spaced.
    /// Two titles written differently are the same title when their keys are equal.
    public static func key(_ title: String) -> String {
        words(title).map { word -> String in
            if word == "&" { return "and" }
            return fold(word).replacingOccurrences(of: "'", with: "")
        }.joined(separator: " ")
    }

    static func fold(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
    }

    /// The pattern for the title's words (folded, see `ranges`), between letter-or-digit boundaries.
    public static func pattern(for title: String) -> String? {
        // Accents folded (as the text is, in `ranges`); case left to the caller's option.
        let words = words(title.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US")))
        guard !words.isEmpty else { return nil }
        var pattern = #"(?<![\p{L}\p{N}])"#
        let gap = separator(for: title)
        for (index, word) in words.enumerated() {
            if index > 0 {
                // "&" may be written against its neighbours ("Fast&Furious"); words otherwise need a break.
                pattern += (word == "&" || words[index - 1] == "&") ? gap + "*" : gap + "+"
            }
            if word == "&" || word.lowercased() == "and" {
                pattern += "(?i:and|&|＆)"
            } else {
                pattern += word.split(separator: "'", omittingEmptySubsequences: false)
                    .map { NSRegularExpression.escapedPattern(for: String($0)) }
                    .joined(separator: "['’‘ʼ]?")
            }
        }
        return pattern + #"(?![\p{L}\p{N}])"#
    }

    /// What may stand between two of the title's words: spaces, punctuation and symbols, but not a
    /// sentence's end (". ", "! ", "? ") unless the title has one itself ("Dr. Strangelove"); an
    /// ellipsis always may ("Once Upon a Time... in Hollywood").
    static func separator(for title: String) -> String {
        if title.range(of: #"[.!?]"#, options: .regularExpression) != nil { return #"[\s\p{P}\p{S}]"# }
        return #"(?:[[\s\p{P}\p{S}]--[.!?]]|\.\.\.)"#
    }

    /// The title's pattern to embed in a larger one, without its boundaries (the caller adds its
    /// own) and unfolded (it runs on the text as written): a short title (three characters or
    /// fewer, "Her", "F1") is matched as written, case and all.
    public static func embeddable(_ title: String) -> String {
        let words = words(title)
        guard !words.isEmpty else { return NSRegularExpression.escapedPattern(for: title) }
        let gap = separator(for: title)
        var pattern = ""
        for (index, word) in words.enumerated() {
            if index > 0 { pattern += (word == "&" || words[index - 1] == "&") ? gap + "*" : gap + "+" }
            if word == "&" || word.lowercased() == "and" {
                pattern += "(?i:and|&|＆)"
            } else {
                pattern += word.split(separator: "'", omittingEmptySubsequences: false)
                    .map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "['’‘ʼ]?")
            }
        }
        return title.count <= 3 ? "(?-i:" + pattern + ")" : "(?:" + pattern + ")"
    }

    final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var regexes: [String: NSRegularExpression?] = [:]
    }
    static let cache = Cache()

    static func regex(_ title: String, caseSensitive: Bool) -> NSRegularExpression? {
        let key = (caseSensitive ? "c|" : "i|") + title
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let known = cache.regexes[key] { return known }
        let made = pattern(for: title).flatMap { try? NSRegularExpression(pattern: $0, options: caseSensitive ? [] : [.caseInsensitive]) }
        if cache.regexes.count > 4000 { cache.regexes.removeAll() }
        cache.regexes[key] = made
        return made
    }

    /// Where the title is written in `text`. Matched on the folded text (accents and case aside);
    /// the ranges are the text's own.
    public static func ranges(of title: String, in text: String, caseSensitive: Bool = false) -> [Range<String.Index>] {
        guard let regex = regex(title, caseSensitive: caseSensitive) else { return [] }
        // Case is the regex's to ignore or keep; accents are folded here, character for character.
        let folded = text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
        let same = folded.count == text.count
        let haystack = same ? folded : text
        let found = regex.matches(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)).compactMap { Range($0.range, in: haystack) }
        guard same else { return found }
        // Character offsets carry over: folding changed no character count.
        return found.map { range in
            let lower = text.index(text.startIndex, offsetBy: folded.distance(from: folded.startIndex, to: range.lowerBound))
            let upper = text.index(lower, offsetBy: folded.distance(from: range.lowerBound, to: range.upperBound))
            return lower..<upper
        }
    }

    public static func names(_ text: String, title: String, caseSensitive: Bool = false) -> Bool {
        !ranges(of: title, in: text, caseSensitive: caseSensitive).isEmpty
    }

    /// Whether a page's address is the title itself: its last path segment is the title's words and
    /// nothing else ("/blog-post/challengers/" for Challengers), not merely contains them.
    public static func isSlug(of title: String, url: URL) -> Bool {
        guard let last = url.path.split(separator: "/").last(where: { !$0.isEmpty }) else { return false }
        let slug = last.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        let own = key(title)
        return !own.isEmpty && key(slug) == own
    }
}

// MARK: - Which production a part of a sentence is about (1.10.9)

/// The parts of a sentence that compare this film with another production or say where something
/// came from, as against what the sentence asserts: "Just as he had on <Other>, Doe shot <Film> on
/// 500T", "As with <Other>, they graded at Company 3", "Natural light was a tool, as it was when he
/// lensed <Other>", "…, continuing the journey they began on <Other> (2019)", "…technology that he
/// helped develop on <Other>, particularly for golden hour lighting inspired by <Other>". A part is
/// set aside (`ranges`) only when it names another production; the rest is the sentence's own
/// statement, read for whichever production it names (or the page's film). Gear inside a set-aside
/// part is that production's, never this film's.
public struct ComparisonFrame: Sendable {
    /// The parts that compare or refer to another production.
    public let spans: [Range<String.Index>]
    /// The sentence as written.
    public let original: String
    /// The sentence with those parts blanked, character for character (positions carry over).
    public let main: String

    static let leading = try! NSRegularExpression(
        pattern: #"^\W*(?:and\s+|but\s+)?(?:just\s+|much\s+|exactly\s+|very\s+much\s+)?(?:(?:as|like)\s+(?:with|on|in|for|during|he|she|they|we|i|it|was|did|had|has|before|previously|earlier)\b|unlike\b|compared\s+(?:to|with)\b|in contrast\s+(?:to|with)\b|similar\s+to\b|following\b)[^;]{0,160}?,\s*"#,
        options: [.caseInsensitive])
    static let leadingWithClause = try! NSRegularExpression(
        pattern: #"^\W*(?:unlike|like|as with|as on|compared (?:to|with))\s+[^,;]{1,80},\s*(?:which|who|where)\s+[^,;]{1,120},\s*"#,
        options: [.caseInsensitive])
    static let trailing = try! NSRegularExpression(
        pattern: #"(?:,\s*|\s+)(?:just\s+|much\s+|exactly\s+)?(?:as\s+(?:it|they|he|she|we|i)\s+(?:had|did|was|were|has|does|is)\b|as\s+(?:on|in|with|for|when)\b|like\s+(?:on|in|with|for|when)\b)[^;]*$"#,
        options: [.caseInsensitive])
    static let continuing = try! NSRegularExpression(
        pattern: #",\s*(?:continuing|following|extending|reprising|repeating|building on|carrying over|picking up|resuming)\b[^;]*$"#,
        options: [.caseInsensitive])
    static let relative = try! NSRegularExpression(
        pattern: #"\b(?:that|which|who)\s+[^,;]{0,120}?\b(?:on|for|in|from|during)\s+[^,;]{1,100}"#,
        options: [.caseInsensitive])
    static let referencePhrase = try! NSRegularExpression(
        pattern: #"\b(?:inspired by|influenced by|model(?:l)?ed (?:on|after)|borrowed from|reminiscent of|evocative of|in the (?:vein|style|tradition|spirit) of|a nod to|an? homage to|homage to|harking back to|recalling)\b[^,;]*"#,
        options: [.caseInsensitive])
    /// Brackets with words in them ("(as on The Irishman)"), not a title's year alone ("(2007)", which
    /// stays: it's what says the title before it is another production).
    static let parenthesis = try! NSRegularExpression(pattern: #"\((?![\s\d–-]*\))[^()]{2,120}\)"#)

    /// A title-like name: capitalised words after "on/in/for/with/from/of" ("on The Irishman",
    /// "for Industrial Light & Magic", "from In the Mood for Love"), or a year in brackets.
    static let titleAfterPreposition = try! NSRegularExpression(
        pattern: #"\b(?:on|for|with|lensed|shot|photographed|filmed)\s+(?:the\s+)?(?:[A-Z][\w'’:&!.-]*|[A-Z0-9]{2,})(?:\s+(?:of|the|and|a|an|in|on|to|for|by|&)?\s*[A-Z0-9][\w'’:&!.-]*){0,7}"#)
    /// "the series The Mandalorian", "his earlier film Kiln", "the 2019 feature …".
    static let productionNoun = try! NSRegularExpression(
        pattern: #"\b(?:the|a|his|her|their|our|my|an earlier|a previous|the previous|earlier|last|next)\s+(?:[\w+-]+\s+){0,3}?(?:mini-?series|series|show|feature|film|documentary|commercial|short|movie|pilot|sequel|remake|production)\s+(?:[A-Z][\w'’:&!.-]*)"#)
    static let bracketYear = try! NSRegularExpression(pattern: #"\((?:19|20)\d{2}(?:[–-](?:19|20)?\d{2,4})?\)"#)

    /// The words every part set aside starts with: a sentence with none of them has none.
    static let cue = try! NSRegularExpression(
        pattern: #"\b(?:as|like|unlike|compared|contrast|similar|following|continuing|extending|reprising|repeating|building|carrying|picking|resuming|that|which|who|inspired|influenced|model(?:l)?ed|borrowed|reminiscent|evocative|vein|style|tradition|spirit|nod|homage|harking|recalling)\b"#,
        options: [.caseInsensitive])

    final class Memo: @unchecked Sendable {
        let lock = NSLock()
        var frames: [String: ComparisonFrame] = [:]
    }
    static let memo = Memo()

    /// The frame of a sentence, worked out once per sentence and context (pages read the same
    /// sentence for anchors, classification and gear).
    public init(_ sentence: String, title: String?, otherTitles: [String], people: [String] = []) {
        let key = sentence + "\u{1}" + (title ?? "") + "\u{1}" + otherTitles.joined(separator: "\u{2}") + "\u{1}" + people.joined(separator: "\u{2}")
        Self.memo.lock.lock()
        let known = Self.memo.frames[key]
        Self.memo.lock.unlock()
        if let known, known.original.count == sentence.count {
            // Positions carried over by offset into this copy of the sentence.
            let spans = known.spans.map { span in
                let lower = known.original.distance(from: known.original.startIndex, to: span.lowerBound)
                let upper = known.original.distance(from: known.original.startIndex, to: span.upperBound)
                return sentence.index(sentence.startIndex, offsetBy: lower)..<sentence.index(sentence.startIndex, offsetBy: upper)
            }
            self.init(spans: spans, original: sentence, main: known.main)
            return
        }
        self.init(computing: sentence, title: title, otherTitles: otherTitles, people: people)
        Self.memo.lock.lock()
        if Self.memo.frames.count > 4000 { Self.memo.frames.removeAll(keepingCapacity: true) }
        Self.memo.frames[key] = self
        Self.memo.lock.unlock()
    }

    init(spans: [Range<String.Index>], original: String, main: String) {
        self.spans = spans
        self.original = original
        self.main = main
    }

    init(computing sentence: String, title: String?, otherTitles: [String], people: [String]) {
        if Self.cue.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) == nil {
            spans = []
            original = sentence
            main = sentence
            return
        }
        var spans: [Range<String.Index>] = []
        let ns = NSRange(sentence.startIndex..., in: sentence)
        // A comparison ("Just as he had on <Other>,") names a production by a capitalised name after
        // its preposition; any other part (a relative clause, a reference, brackets) only by what
        // plainly names one: another title known to the page, a title with its year, a quoted title,
        // "the series <Other>" (a place or a company after "in" or "for" is not a production).
        func namesOther(_ range: Range<String.Index>, loose: Bool) -> Bool {
            let part = String(sentence[range])
            if TechSpecs.namesAnotherFilm(part, title: title, otherTitles: otherTitles, people: people) { return true }
            if otherTitles.contains(where: { TechSpecs.namesTitle(part, title: $0) && !(title.map { TechSpecs.namesTitle(part, title: $0) } ?? false) }) {
                return true
            }
            let pns = NSRange(part.startIndex..., in: part)
            if Self.bracketYear.firstMatch(in: part, range: pns) != nil { return true }
            if Self.productionNoun.firstMatch(in: part, range: pns) != nil { return true }
            guard loose else { return false }
            // A capitalised name after a preposition that isn't this film, a person of the film, or gear.
            for match in Self.titleAfterPreposition.matches(in: part, range: pns) {
                guard let found = Range(match.range, in: part) else { continue }
                let words = part[found].split(separator: " ").dropFirst().joined(separator: " ")
                if let title, TechSpecs.namesTitle(words, title: title) { continue }
                if people.contains(where: { person in person.split(separator: " ").contains { words.contains($0) } }) { continue }
                if !TechSpecs.isOtherTitle(words, title: title) { continue }
                // Gear ("on the Alexa 65", "with Cooke S4s"): what the gear rules find in the words.
                if TechSpecs.rules.contains(where: { !$0.found(in: words).isEmpty }) { continue }
                // A single short word ("In", "The") isn't a name.
                if words.filter(\.isLetter).count >= 3 { return true }
            }
            return false
        }
        func add(_ regex: NSRegularExpression, loose: Bool, apart: Bool = false) {
            for match in regex.matches(in: sentence, range: ns) {
                guard let range = Range(match.range, in: sentence) else { continue }
                // A trailing comparison starts after an opening one, never inside it: "Just as he had on
                // <Other>, <Film> was shot…" is an opening comparison, not "as he had…" to the end.
                if apart, let opening = spans.first(where: { $0.overlaps(range) }) {
                    // …and a real trailing comparison after the opening one is still found: search again
                    // from where the opening one ends.
                    let rest = NSRange(opening.upperBound..., in: sentence)
                    if let again = regex.firstMatch(in: sentence, range: rest), let later = Range(again.range, in: sentence),
                       !spans.contains(where: { $0.overlaps(later) }), namesOther(later, loose: loose) {
                        spans.append(later)
                    }
                    continue
                }
                guard namesOther(range, loose: loose) else { continue }
                // The film itself named only inside the part is no reason to set it aside, but a part
                // naming both is still a comparison: the main clause must say something on its own.
                spans.append(range)
            }
        }
        // "Unlike Odile's Garden, which she lit with HMIs, …": the clause that follows the comparison's
        // title is part of it.
        for match in Self.leadingWithClause.matches(in: sentence, range: ns) {
            if let range = Range(match.range, in: sentence), namesOther(range, loose: true) { spans.append(range) }
        }
        add(Self.leading, loose: true)
        add(Self.trailing, loose: true, apart: true)
        add(Self.continuing, loose: true, apart: true)
        add(Self.relative, loose: false)
        add(Self.referencePhrase, loose: false)
        // Brackets aren't blanked: "Robert Elswit (“There Will Be Blood”)" is often all a sentence says of
        // whose film it is about (the 1.10.9 live check).
        // Nothing left to assert: the whole sentence is the comparison, so nothing is set aside.
        var chars = Array(sentence)
        var offsets: [Range<Int>] = []
        for span in spans {
            let lower = sentence.distance(from: sentence.startIndex, to: span.lowerBound)
            let upper = sentence.distance(from: sentence.startIndex, to: span.upperBound)
            offsets.append(lower..<upper)
        }
        for range in offsets { for i in range where i < chars.count { chars[i] = " " } }
        let main = String(chars)
        original = sentence
        if main.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isLetter).count < 12 {
            self.spans = []
            self.main = sentence
        } else {
            self.spans = spans
            self.main = main
        }
    }

    /// Whether the words at `range` are inside a part set aside (another production's).
    public func contains(_ range: Range<String.Index>) -> Bool {
        spans.contains { $0.overlaps(range) }
    }
}

// MARK: - What a statement asserts (1.10.9)

/// Why a statement naming gear doesn't make it this film's: what the sentence asserts about it, read
/// from its own words around the gear. Deterministic and small: a statement is read for its
/// polarity (used or not), its modality (fact, or a hypothetical), its status (final production, a
/// plan, a test, delivery, a product's capability, an object in the story, a simulation) and whose
/// practice it describes. Each reason applies to the gear it governs, never to the whole sentence:
/// "He avoided Steadicam, instead deploying a crane" rejects Steadicam and keeps the crane.
public enum ClaimReason: String, Codable, Sendable, CaseIterable {
    case otherProduction, denied, hypothetical, abandonedPlan, testOnly, otherPractice, simulated, environment, delivery,
         productCapability, presentation, uncertain,
         /// 1.10.10: a definition or general information about the gear ("ENR is a silver retention process
         /// named for its inventor…"), and a statement that names it without saying it was used here (a crew
         /// member's job title, "his dolly grip").
         definition, insufficientContext

    /// Rejected outright, or left undecided (abstained): a presentation ratio or a statement too
    /// uncertain to settle is neither confirmed nor ruled out.
    public var abstains: Bool { self == .presentation || self == .uncertain || self == .insufficientContext }

    public var label: String {
        switch self {
        case .otherProduction: "about another production"
        case .denied: "said not to have been used"
        case .hypothetical: "a hypothetical or counterfactual"
        case .abandonedPlan: "a plan, not what was done"
        case .testOnly: "used in tests only"
        case .otherPractice: "someone else's or general practice"
        case .simulated: "simulated or computer-generated, not the physical equipment"
        case .environment: "an object in the scene, not the production's equipment"
        case .delivery: "a release or delivery format, not how it was shot"
        case .productCapability: "what a product can do, not what this film used"
        case .presentation: "how it was presented, not necessarily how it was shot"
        case .uncertain: "too uncertain to settle"
        case .definition: "a definition or general information, not a statement of use"
        case .insufficientContext: "named without saying it was used on this film"
        }
    }
}

public enum ClaimFrame {
    /// Breaks that end what a word governs: a new clause or a turn. A comma doesn't when what follows
    /// it is only more of a list ("Super 35, or Super 16"; "Steadicam, dollies and a crane").
    static let strongBreaks = ["; ", " but ", " however", ". ", " instead", " while ", " whereas ", " although ", " though ", " yet ",
                               " in the end", " ultimately", " eventually", " so we ", " so they ", " so he ", " so she ", " – ", " — ", ": ",
                               " then ", " and went ", " and chose ", " and opted ", " and settled ", " and switched ", " and ended up ",
                               " and shot ", " and used ", " and lit ", " and filmed ", " and photographed ", " and pulled ", " and got "]

    /// The text before the gear that governs it: back to the last strong break, and across commas
    /// only while what lies between is a list or an example ("like…", "such as…").
    static func governing(_ sentence: String, before range: Range<String.Index>, acrossCommas: Bool) -> String {
        let lead = String(sentence[..<range.lowerBound])
        var start = lead.startIndex
        for mark in strongBreaks {
            if let found = lead.range(of: mark, options: [.backwards, .caseInsensitive]), found.upperBound > start { start = found.upperBound }
        }
        var text = String(lead[start...])
        guard acrossCommas else {
            if let comma = text.range(of: ",", options: .backwards) { text = String(text[comma.upperBound...]) }
            return text
        }
        // Walk back over commas while the part after each is a list item or an example.
        var parts = text.components(separatedBy: ",")
        var kept: [String] = []
        while let last = parts.popLast() {
            kept.insert(last, at: 0)
            if !isContinuation(last) { break }
        }
        return kept.joined(separator: ",")
    }

    static let finiteVerb = try! NSRegularExpression(
        pattern: #"\b(?:was|were|is|are|had|has|have|did|does|do|shot|used|lit|chose|went|decided|opted|deployed|captured|filmed|photographed|graded|rigged|built|made|took|kept|ran|operated|mounted|turned|switched|settled|ended|needed|wanted|tested|tried|preferred|favou?red|carried|paired|rented|bought|got|gave|found|created|added|placed|hung|put|set|relies|rely|relied|uses|employs|brings|brought|takes|gives|makes|lights|shoots|needs|wants|keeps|goes|went|came|comes|arrived|pulled|helped|let|lets|allowed|meant|said|says|felt|feels|thought|knew|saw|became|stayed|worked|works)\b"#,
        options: [.caseInsensitive])

    /// A part after a comma that continues what came before rather than starting a clause.
    static func isContinuation(_ part: String) -> Bool {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        let lowered = trimmed.lowercased()
        if lowered.range(of: #"^(?:like|such as|including|e\.g\.|for example|for instance|say)\b"#, options: .regularExpression) != nil { return true }
        let item = lowered.replacingOccurrences(of: #"^(?:and|or|nor|as well as|plus|even)\s+"#, with: "", options: .regularExpression)
        let words = item.split(separator: " ")
        if words.count > 7 { return false }
        // "…, relying on a dolly", "…, instead using…": a new action, not more of a list.
        if let first = words.first, first.hasSuffix("ing"), !["including", "something", "nothing", "anything", "everything", "lighting", "string", "ceiling", "building", "evening", "morning", "opening", "ending", "spring"].contains(String(first)) {
            return false
        }
        // "…, relied on a dolly", "…, pulled it off": a past verb leading the part, followed by what
        // it governs ("a modified dolly" is still a list item).
        if words.count >= 2, words[0].count >= 5, words[0].hasSuffix("ed"),
           ["on", "with", "the", "a", "an", "it", "them", "to", "in", "for", "up", "out", "down", "off", "that", "his", "her", "their", "our", "by", "back"].contains(String(words[1])) {
            return false
        }
        return finiteVerb.firstMatch(in: item, range: NSRange(item.startIndex..., in: item)) == nil
            && item.range(of: #"\b(?:we|i|he|she|they)\b"#, options: .regularExpression) == nil
    }

    /// The text after the gear in its clause (up to the next strong break or a comma that starts a
    /// clause).
    static func following(_ sentence: String, after range: Range<String.Index>) -> String {
        var tail = String(sentence[range.upperBound...])
        let lower = tail.lowercased()
        var end = lower.endIndex
        for mark in strongBreaks + [", "] {
            if let found = lower.range(of: mark), found.lowerBound < end { end = found.lowerBound }
        }
        tail = String(tail[..<tail.index(tail.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: end))])
        return tail
    }

    /// What follows the gear, as far as it still says something of the gear (1.10.10): a relative clause
    /// with a subject of its own ("…5247 stock with which Soviet laboratories were not very familiar",
    /// "…the stock that the lab had never seen") is about that subject, not the gear.
    static func ownPredicate(_ after: String) -> String {
        if let cut = after.range(of: #"\b(?:(?:with|of|for|to|in|on|by|about|from)\s+(?:which|whom)|whose)\b|\b(?:which|that|who|whom)\s+(?!(?:was|were|is|are|had|has|have|would|could|never|wasn|weren|isn|aren|did|didn)\b)(?:the\s+|a\s+|an\s+|his\s+|her\s+|their\s+|our\s+)?[a-z]+\s+(?:[a-z]+\s+)?(?:was|were|is|are|had|have|has|did|didn|would|could|knew|know|found|saw)\b"#,
                                options: [.regularExpression, .caseInsensitive]) {
            return String(after[..<cut.lowerBound])
        }
        return after
    }

    static func has(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: Reasons

    /// Avoided, rejected, ruled out, done without: the verb governs the gear.
    static let avoidance = try! NSRegularExpression(
        pattern: #"\b(?:avoid(?:ed|ing|s)?|eschew(?:ed|ing|s)?|shun(?:ned|ning|s)?|reject(?:ed|ing|s)?|ruled out|rule out|ruling out|ditch(?:ed|ing)?|scrap(?:ped|ping)?|abandon(?:ed|ing)?|passed on|pass on|steer(?:ed|ing)? clear of|stay(?:ed)? away from|kept away from|gave up(?: on)?|giving up(?: on)?|(?:decided|decision|opted|chose|choosing|argued|ruled|went) against|resist(?:ed|ing)? (?:using|the temptation to use|the urge to use)|refus(?:ed|ing) to use|forwent|forgo(?:ing|ne)?|forego(?:ing|ne)?|dispens(?:ed|ing) with|did away with|do away with|without (?:using |any |a |an )?|no need for|banned|ban(?:ning)?|instead of|rather than|in place of|as opposed to|never (?:once )?(?:used?|using|touched|considered|needed|wanted)|not (?:using|use|used)|nothing like|not (?:a|an|any)\s|no (?:room|space|budget|time|place) for|(?:didn'?t|did not|don'?t|do not|doesn'?t|does not|couldn'?t|could not|wouldn'?t|would not|won'?t|will not) (?:\w+ ){0,2}?(?:use|using|need|want|bring|employ|rely on|shoot (?:on|with)|go with|choose|pick|like (?:the (?:look|effect|feel) of|using)|have (?:a|an|any|the)|carry|rent|touch)\b)"#,
        options: [.caseInsensitive])
    /// "couldn't have done it without", "wouldn't work without", "impossible without": the gear was needed.
    static let necessity = try! NSRegularExpression(
        pattern: #"\b(?:couldn'?t|could not|wouldn'?t|would not|can'?t|cannot|never could|impossible|unthinkable)\b[^.;]{0,80}\bwithout\s+(?:[\w'-]+\s+){0,3}$"#,
        options: [.caseInsensitive])
    /// "no Steadicam", "zero practicals": a determiner right before the gear.
    static let noneBefore = try! NSRegularExpression(pattern: #"\b(?:no|zero|nor|neither)\s+(?:[\w-]+\s+){0,2}$"#, options: [.caseInsensitive])
    /// After the gear: "…Steadicam was out of the question", "…cranes were never an option".
    /// "A Steadicam was considered for the stairwells but was never brought aboard": weighed, then not used.
    static let consideredNot = try! NSRegularExpression(
        pattern: #"^\W*(?:[\w'’-]+\s+){0,4}?(?:was|were|had been|got)\s+(?:briefly\s+|also\s+)?(?:considered|discussed|proposed|suggested|floated|explored|looked at|tested|tried)\b[^.;]*\bbut\b[^.;]*\b(?:never|not|n['’]t|dropped|abandoned|rejected|ruled out|scrapped|cut|shelved)\b"#,
        options: [.caseInsensitive])
    static let deniedAfter = try! NSRegularExpression(
        pattern: #"^\W*(?:[\w'’-]+\s+){0,5}?(?:was|were|is|are|would be|had been)\s+(?:never(?! the only)|not(?! the only| only| just| alone| enough)|n['’]t(?! the only| only| just| alone| enough)|out of the question|ruled out|abandoned|rejected|dropped|scrapped|off the table|unnecessary|too (?:big|heavy|expensive|slow)|impossible)\b(?!\s+(?:the only|only|just|alone|enough))|^\W*(?:[\w'’-]+\s+){0,3}?(?:wasn['’]t|weren['’]t|isn['’]t|aren['’]t)\s+(?:used|an option|available|possible|allowed|chosen|needed|on set|brought|considered|wanted|part of)\b"#,
        options: [.caseInsensitive])

    /// A counterfactual or hypothetical, governing to the end of its part of the sentence.
    static let hypothetical = try! NSRegularExpression(
        pattern: #"\bwhether\s+(?:we|i|you|they|he|she|it|one)\b[^.;,]{0,40}$|\b(?:might|could|would|should|may|must)(?:\s+not|n['’]t)?\s+(?:\w+\s+){0,2}?have\b(?!\s+to\b)|\bhad\s+(?:it|we|they|he|she|i|the (?:film|movie|production))\s+(?:been|shot|used|gone|chosen)\b|\bif\s+(?:we|it|they|he|she|i|you|the (?:film|movie|production))\s+(?:had|were|was|could|would)\b|\bwere\s+(?:it|we|they)\s+to\b|\b(?:one|you)\s+could\b|(?:^|[,;:]\s*|\bthat\s+|\bif\s+)had\s+(?!(?:already|just|previously|originally|all|not|never|long)\b)(?:[\w'’:-]+\s+){1,5}?been\s+(?:shot|filmed|photographed|made|lit|lensed)\b|\b(?:might|may|could)\s+(?:well\s+)?be\s+(?:shot|filmed|photographed)\b|\bif it happens\b|\bwhat if\b|\b(?:dream(?:ed|t|s)? of|fantasi[sz]ed about)\b|\bwish(?:ed|es)?\s+(?:we|they|he|she|i)\s+(?:had|could)\b|\bwould\s+(?:have\s+)?(?:look(?:ed)?|feel|felt)\b|\bin an? (?:ideal|perfect|alternate|different) world\b|\b(?:hypothetical(?:ly)?|in theory|theoretically)\b"#,
        options: [.caseInsensitive])

    /// A plan or intention, unless the sentence says it was carried out.
    static let plan = try! NSRegularExpression(
        pattern: #"\b(?:had\s+)?(?:originally|initially|first|once)\s+(?:intended|planned|meant|hoped|wanted|set out|proposed|considered|thought)\b|\b(?:had\s+)?(?:intended|planned|meant|proposed|envisioned|envisaged)\s+(?:to|on)\s+(?:"# + planVerbs + #")\b|\b(?:the|our|my|his|her|their|an?)\s+(?:original\s+|initial\s+|early\s+|first\s+)?(?:plan|intention|proposal)\s+(?:was|had been|is)\s+(?:always\s+|originally\s+|initially\s+)?to\s+(?:"# + planVerbs + #")\b|\b(?:was|were)\s+(?:going|supposed|meant|slated)\s+to\s+(?:be\s+)?(?:"# + planVerbs + #")\b|\bat (?:first|one point)\b[^.;]{0,50}\b(?:wanted|planned|considered|thought|hoped)\b|\bwas to have\b|\b(?:was|were)\s+to\s+(?:be\s+)?(?:"# + planVerbs + #")\b|\b(?:had\s+)?planned\s+(?:a|an|the|on a|on an)\b|\b(?:early|first|initial)\s+(?:draft|version|plan|idea)\b|\b(?:the\s+)?(?:financiers|producers|studio|network|distributor|executives|investors)\s+(?:wanted|asked for|pushed for|suggested|preferred|first suggested)\b"#,
        options: [.caseInsensitive])
    static let planVerbs = "shoot|shooting|shot|film|filming|filmed|use|using|used|capture|capturing|captured|photograph|photographing|photographed|go with|lens|lensed|light|lighting|lit|rent|rely on|employ|work with|frame|grade"
    static let planKept = try! NSRegularExpression(
        pattern: #"\b(?:as (?:planned|intended)|and (?:that'?s what )?(?:we|they|he|she|i) did|which (?:we|they|he|she|i) did|stuck (?:to|with) (?:it|that|the plan)|stayed with|in the end (?:we|they|he|she|i) (?:did|used|shot)|ended up (?:using|shooting|doing)|and did|so (?:we|they|he|she) did|pulled it off|and got (?:it|them|its way|their way)|got (?:its|their|his|her) way|and it worked|it happened|went ahead)\b"#,
        options: [.caseInsensitive])

    /// Tried out, not necessarily used.
    static let tried = try! NSRegularExpression(
        pattern: #"\b(?:tests?|test days?|test shoots?|a day of tests|camera tests)\s+(?:on|with|using)\b|\b(?:experiment(?:ed|ing)?\s+with|tri(?:ed|al(?:l)?ed)\s+(?:out\s+)?(?!to\b)|test(?:ed|ing)\s+(?:out\s+)?(?!to\b)|auditioned|screen[- ]tested)\b[^.;]*$"#,
        options: [.caseInsensitive])
    static let adopted = try! NSRegularExpression(
        pattern: #"\b(?:went on to (?:shoot|be used|photograph|cover|do)|made it (?:into|onto) (?:the|our) (?:film|final|movie|picture|cut)|stayed (?:on|for) the (?:whole |entire )?(?:shoot|film|production)|chose|chosen|choose|went with|settled on|ended up|adopted|became (?:the|our)|carried (?:through|over) (?:into|to) (?:the|principal)|for the (?:film|shoot|production|movie|whole)|used (?:it|them) (?:for|on|throughout)|and (?:it|they) (?:stayed|stuck)|kept (?:it|them) for)\b"#,
        options: [.caseInsensitive])

    /// What other people do or did: other cinematographers, the period, a mentor's lessons, a habit.
    static let practice = try! NSRegularExpression(
        pattern: #"\b(?:a lot of|lots of|many of|most of|some of|all of)?\s*(?:my|our|his|her|their)\s+(?:colleagues|peers|contemporaries|fellow (?:dps|cinematographers|operators|gaffers))\b|\b(?:all|many|most|some|other|lots of|plenty of|a lot of)\s+(?:of\s+)?(?:the\s+)?(?:[\w'’-]+\s+){0,3}?(?:colleagues|peers|dps|dops|cinematographers|directors|filmmakers|photographers|camera\s?(?:men|people|operators)|crews|productions)\b|\b(?:dps|dops|cinematographers|filmmakers|directors)\s+(?:of|from|in)\s+(?:the|that|this)\s+(?:period|era|time|day|decade|generation)\b|\bthings\s+(?:that\s+)?(?:we|i|you|he|she|they)\s+(?:learn|learned|learnt|picked up|took)\s+from\b|\b(?:taught|teaches|teach)\s+(?:me|us|him|her|them)\b|\b(?:his|her|their)\s+(?:usual|typical|signature|habitual|trademark)\s+(?:approach|way|practice|habit|method|choice)\b|\b(?:his|her|their|my|\w+'s)\s+(?:usual|typical|habitual|go-to|favou?rite|regular|default)\s+(?:[\w-]+\s+){0,2}?(?:is|are)\s+(?:the\s+|a\s+|an\s+)?$|\b(?:my|his|her|their|our)\s+(?:mentor|teacher|professor|old boss|hero|idol|predecessors?)\b|\b(?:the\s+)?(?:old|older|classic|old-school|traditional|studio-era|golden-age)\s+(?:\w+\s+)?(?:cameramen|cinematographers|dps|gaffers|crews|hands)\b|\b(?:tends|tend) to (?:use|shoot|rely on|prefer|work with|reach for)\b|\b(?:usually|typically|generally|normally|always|traditionally|historically|conventionally|routinely)\s+(?:uses|shoots|relies|prefers|favou?rs|reaches for|works with)\b|\bused to\s+(?:use|shoot|light|work)\b|\bin (?:those|these) days\b|\b(?:everyone|everybody|people)\s+(?:used to|uses|would|shoots)\b"#,
        options: [.caseInsensitive])

    /// The practice of a period: "In the seventies everyone shot anamorphic", "Everyone shot on film
    /// back then".
    static let era = try! NSRegularExpression(
        pattern: #"\b(?:everyone|everybody|people|most (?:dps|cinematographers|films|productions|filmmakers))\s+(?:shot|used|lit)\b[^.;]*\b(?:back then|in those days|in the (?:\w+ )?(?:forties|fifties|sixties|seventies|eighties|nineties|(?:19)?\d0s))\b|\b(?:back then|in those days|in the (?:\w+ )?(?:forties|fifties|sixties|seventies|eighties|nineties|(?:19)?\d0s)),?\s+(?:everyone|everybody|people|most (?:dps|cinematographers|films|productions|filmmakers))\s+(?:shot|used|lit)\b"#,
        options: [.caseInsensitive])

    /// A simulation or a look, right by the gear.
    static let simulatedBefore = try! NSRegularExpression(
        pattern: #"\b(?:faux|fake|mock|pseudo|simulat\w*|emulat\w*|imitat\w*|mimic\w*|digital(?:ly)?\s+(?:added|created|recreated|simulated|generated|applied|replicated|emulated)|cgi?|computer[- ]generated|synthetic|artificial|recreat\w*\s+in\s+post|added\s+in\s+post|look\s+of|style\s+of|in the manner of|look-alike)\b[^.;,]{0,30}$"#,
        options: [.caseInsensitive])
    static let simulatedAfter = try! NSRegularExpression(
        pattern: #"^[\s-]{0,2}(?:look|style|effect|emulation|simulation|plug-?in|-like|like effect|feel)\b|^[^.;,]{0,25}\b(?:added|created|simulated|recreated|emulated|faked)\s+(?:digitally|in post|in the grade|in comp(?:ositing)?|by the vfx)\b"#,
        options: [.caseInsensitive])
    /// Computer-generated light or cameras: CG shading, a render, a virtual camera.
    static let computerGenerated = try! NSRegularExpression(
        pattern: #"\b(?:cg|cgi|rendered|render(?:ing)?|virtual|digital (?:lighting|light|lights|camera)|shading|shaders?|in the computer|in houdini|in maya|in nuke|in unreal|game engine)\b"#,
        options: [.caseInsensitive])

    /// An object in the story or the location, not equipment of the production.
    static let environmentSubject = try! NSRegularExpression(
        pattern: #"\b(?:buses|bus|ceilings?|interiors?|cars?|vehicles?|trucks?|bikes?|motorbikes?|trains?|ships?|boats?|planes?|aircraft|jets?|tracks?|circuits?|stadiums?|arenas?|streets?|buildings?|rooms?|bars?|clubs?|houses?|apartments?|hospitals?|offices?|stores?|shops?|restaurants?|diners?|casinos?|robots?|spaceships?|props?|scoreboards?|billboards?|signs?|towers?|city|town|venues?|set dressing|set decoration|lamps?)\s+(?:[\w'’-]+\s+){0,3}?(?:have|has|had|feature\w*|carr(?:y|ies)|contain\w*|sports?|display\w*|(?:is|are|was|were)\s+(?:commonly|usually|typically|often|normally|already|all)?\s*(?:bathed|lined|dotted|decorated|equipped|fitted|strung))\b"#,
        options: [.caseInsensitive])
    /// Made or placed by the art department as part of the scene: set dressing, props.
    static let setDressing = try! NSRegularExpression(
        pattern: #"\b(?:decorative|ornamental|art department|production design(?:er)?|set dress\w*|set decorat\w*|as (?:a |the )?props?|prop (?:master|department)|part of the (?:set|decor|scenery)|on the (?:dashboard|fridge|console|sign)s?|the character(?:'s|’s)?\s+(?:own\s+)?(?:keeps|owns|has|carries|holds|uses|treasures)|,\s+the character,\s+(?:keeps|owns|has|carries|holds|uses))\b"#,
        options: [.caseInsensitive])
    /// …unless it's said to light the scene: "the neon practicals were the key light".
    static let lightsTheScene = try! NSRegularExpression(
        pattern: #"\b(?:key(?: light)?|main source|only source|lit (?:the|her|him|them|it|every|each|most)|to light|as (?:a |the )?(?:light )?source|lighting the|did the lighting)\b"#,
        options: [.caseInsensitive])
    static let productionAgent = try! NSRegularExpression(
        pattern: #"\b(?:we|i|our|us|crew|grips?|gaffers?|dp|dop|cinematographer|camera team|production|filmmakers|rigged|rig|placed|mounted|hung|added|used|lit (?:the|them|it|her|him)|for the (?:shot|scene|camera))\b"#,
        options: [.caseInsensitive])
    static let prop = try! NSRegularExpression(
        pattern: #"\b(?:prop|props|in-?story|on[- ]screen|diegetic|character(?:s|'s|’s)?|holds?|holding|carries|carrying)\b"#,
        options: [.caseInsensitive])

    /// A release, delivery or presentation: home media, restoration, streaming, cropping.
    static let deliveryCue = try! NSRegularExpression(
        pattern: #"\b(?:home (?:media|video|entertainment|release)s?|blu-?rays?|dvds?|uhd|ultra hd|4k (?:disc|release|remaster)|streaming|streamers?|vod|broadcasts?|(?:television|tv) (?:broadcast|airing|version|release)s?|vhs|laserdiscs?|releases?|re-?released?|re-?issues?|restor\w*|remaster\w*|cropp?(?:ed|ing)|open matte|pan and scan|letterbox\w*|transfers?)\b"#,
        options: [.caseInsensitive])
    static let presentationCue = try! NSRegularExpression(
        pattern: #"\b(?:presented|presentation|projected|projection|screen(?:ed|ings?)|exhibit\w*|theatrical(?:ly)?|widescreen)\b"#,
        options: [.caseInsensitive])
    static let captureVerb = try! NSRegularExpression(
        pattern: #"\b(?:shot|shoot|shooting|filmed|filming|photographed|captured|capturing|lensed|composed|framed|recorded|acquired|originated)\b|\b(?:original|camera)\s+(?:camera\s+)?negative\b"#,
        options: [.caseInsensitive])

    /// A product and what it can do: "the Alexa offers…", "the light features…".
    static let capability = try! NSRegularExpression(
        pattern: #"\b(?:offers|offer|(?:many |several |new |other )?features (?:like|such as|include|including|a|an|the)|provides|provide|boasts|delivers|allows|enables|lets\s+(?:you|users|filmmakers|operators)|can|is able to|are able to|is capable of|are capable of|comes with|come with|ships with|supports|promises|(?:is|are) designed (?:for|to)|records up to|shoots up to)\b"#,
        options: [.caseInsensitive])
    static let productSubject = try! NSRegularExpression(
        pattern: #"\b(?:the|this|its|a|an|each|every)?\s*(?:camera|cameras|sensor|lens|lenses|fixture|fixtures|system|unit|model|body|bodies|series|range|product|line|panel|it)\b|\b(?:arri|alexa|red|sony|venice|canon|blackmagic|panavision|cooke|zeiss|leica|aputure|astera|creamsource|kino flo|skypanel|dji|ronin|fujinon|angenieux|angénieux)\b"#,
        options: [.caseInsensitive])
    /// A rental house, a vendor or a department as the subject: supplying the production, not a
    /// product's capability ("Keslow Camera provides…", "the camera department delivers…").
    static let supplier = try! NSRegularExpression(
        pattern: #"\b(?:department|rental|rentals|house|vendor|supplier|supplied|provided|camera\s+(?:company|team)|crew|production|we|i)\b"#,
        options: [.caseInsensitive])
    static let personalAgent = try! NSRegularExpression(
        pattern: #"\b(?:we|i|our|us|he|she|they|the (?:production|crew|film|movie|filmmakers|dp|cinematographer|director))\b"#,
        options: [.caseInsensitive])

    /// Reports and rumours, and things nobody would confirm: "Some reports say…", "reportedly",
    /// "there may be one or two drone shots", "declined to confirm it". Not settled either way.
    static let rumour = try! NSRegularExpression(
        pattern: #"\b(?:some|several|unconfirmed|anecdotal|other)\s+(?:reports?|accounts?|sources?|stories|people)\s+(?:say|said|suggest|suggested|claim|claimed|have it)\b|\breportedly\b|\ballegedly\b|\brumou?r\w*|\b(?:is|was|were|are)\s+(?:said|rumou?red|reported|thought|believed|supposed)\s+to\b|\bthere\s+(?:may|might|could)\s+(?:be|have been)\b|\b(?:declined|refused)\s+to\s+confirm\b|\b(?:couldn['’]?t|could not|can['’]?t|cannot|nobody\s+(?:we\s+spoke\s+to\s+)?could)\s+confirm\b|\bunconfirmed\b|\bnot sure (?:if|whether)\b|\bi (?:think|believe) (?:there|we|they) (?:may|might)\b"#,
        options: [.caseInsensitive])

    // MARK: 1.10.10

    /// "named for its inventor", "invented by", "developed by…": the gear's history, not its use.
    static let definitionAfter = try! NSRegularExpression(
        pattern: #"^\W*(?:[\w-]+\s+){0,2}?(?:named (?:for|after)|invented by|patented by|pioneered by|coined by|so called because|refers to)\b"#,
        options: [.caseInsensitive])
    /// "<term> is a …", "<term> are …": the gear as what something is.
    static let definitionBefore = try! NSRegularExpression(pattern: #"^\W*[\w\s'’-]{1,30}\s(?:is|are)\s+(?:a|an)\s+(?:[\w-]+\s+){0,2}$"#,
                                                       options: [.caseInsensitive])
    static let definitionNoun = try! NSRegularExpression(pattern: #"^\W*(?:[\w-]+\s+){0,1}?(?:process|technique|method|type|kind|term|system)\b(?!\s+(?:we|i|they|he|she)\b)"#,
                                                     options: [.caseInsensitive])
    static let definitionCopula = try! NSRegularExpression(
        pattern: #"^\s*(?:is|are)\s+(?:a|an)\s+(?:[\w-]+\s+){0,3}?(?:process|technique|method|type|kind|term)\b"#, options: [.caseInsensitive])
    static let crewRoleAfter = try! NSRegularExpression(pattern: #"^\s*(?:grips?|key grip|dolly grips?)\b"#, options: [.caseInsensitive])
    static let genericBefore = try! NSRegularExpression(pattern: #"\b(?:a|an|any)\s+$"#, options: [.caseInsensitive])
    static let genericCapabilityAfter = try! NSRegularExpression(
        pattern: #"^\s*(?:doesn'?t|does not|can'?t|cannot|can|could|won'?t|will not|is (?:not |n't )?(?:able|good|great|better|worse|ideal|limited)|isn'?t (?:able|good|great|ideal))\b"#,
        options: [.caseInsensitive])
    /// "One of her decisions was to shoot…": decided.
    static let decided = try! NSRegularExpression(pattern: #"\b(?:decisions?|choices?|solutions?)\s+(?:was|were|had been)\s+to\b"#,
                                                  options: [.caseInsensitive])
    /// "In my mind, I wanted…", "Ideally, …": an intention.
    static let intention = try! NSRegularExpression(
        pattern: #"\bin (?:my|his|her|our|their) (?:mind|head)\b[^.;]{0,30}\b(?:wanted|want|intended|imagined|pictured|saw)\b|\bideally\b"#,
        options: [.caseInsensitive])
    static let idea = try! NSRegularExpression(pattern: #"\b(?:began|started|start)\s+(?:thinking|to think)\b|\b(?:i|we|he|she|they)\s+(?:could|might)\s+convey\b"#,
                                               options: [.caseInsensitive])
    /// Someone's habit, in the present: "Scorsese usually complains about…".
    static let habitual = try! NSRegularExpression(
        pattern: #"\b(?:usually|typically|generally|normally|routinely|habitually|often|always)\s+(?:complains?|says|insists|hates|loves|dislikes|avoids|asks|likes|prefers|favou?rs|refuses|objects)\b"#,
        options: [.caseInsensitive])
    /// "When he shoots digital, he sets a LUT at the beginning of a show": what someone does on any job.
    static let habitWhen = try! NSRegularExpression(pattern: #"\bwhen(?:ever)?\s+(?:he|she|they)\s+(?:shoots|works|lights|uses|does)\b"#,
                                                    options: [.caseInsensitive])
    static let genericJob = try! NSRegularExpression(pattern: #"\b(?:a|every|each|any)\s+(?:show|film|project|job|picture|production|movie)\b"#,
                                                     options: [.caseInsensitive])
    /// "The crane has become second-nature to the two of us".
    static let secondNature = try! NSRegularExpression(
        pattern: #"^\W*(?:[\w-]+\s+){0,2}?(?:has|have)\s+(?:long\s+)?become\s+(?:second[- ]nature|a habit|routine|standard|(?:our|his|her|their)\s+(?:go-to|default|habit|signature))\b"#,
        options: [.caseInsensitive])
    static let movementStyleAfter = try! NSRegularExpression(pattern: #"^[\s-]{0,2}(?:style|feel|approach|aesthetic)\b"#, options: [.caseInsensitive])
    /// "…using the digital work to match a real photochemical process".
    static let matchedDigitally = try! NSRegularExpression(
        pattern: #"\b(?:digital(?:ly)?|digital work|in post|in the grade|grading|the grade|vfx|plug-?ins?)\b[^.;]{0,40}\b(?:match|matching|matched|replicate|reproduce|recreate)\s+(?:a |an |the )?(?:real |true |genuine |actual |traditional )?(?:[\w-]+\s+){0,1}$"#,
        options: [.caseInsensitive])
    static let lessCG = try! NSRegularExpression(
        pattern: #"\b(?:minimi[sz]\w*|reduc\w*|avoid\w*|without|no|less|fewer|instead of|rather than)\s+(?:the\s+)?(?:amount of\s+|use of\s+|need for\s+)?(?:any\s+)?(?:cgi?|vfx|computer[- ]generated (?:imagery|effects)|digital effects)\b"#,
        options: [.caseInsensitive])
    /// "his research indicated that such settings have…": what real places are like.
    static let researchFound = try! NSRegularExpression(
        pattern: #"\b(?:research|references?|reference photos|photos|photographs|archives?)\s+(?:\w+\s+)?(?:indicated|showed|shows|suggested|revealed|found)\b"#,
        options: [.caseInsensitive])
    static let carriedByRig = try! NSRegularExpression(
        pattern: #"\b(?:drones?|gimbals?|cranes?|rigs?|arms?|heads?|mounts?|helicopters?|copters?|cars?|vehicles?|bikes?|steadicams?|technocranes?|ronins?|movis?|cable ?cams?|spidercams?)\s+(?:[\w-]+\s+){0,3}?(?:carrying|carries|carried|holding|holds)\s+(?:an?\s+|the\s+|two\s+|its\s+)?(?:[\w-]+\s+){0,2}$"#,
        options: [.caseInsensitive])
    static let payloadAfter = try! NSRegularExpression(pattern: #"^\W*(?:[\w-]+\s+){0,2}?payloads?\b"#, options: [.caseInsensitive])

    /// The reason the gear at `range` isn't this film's, if the sentence's own words give one.
    /// `kind`: the gear's kind (a ratio's presentation matters, a light in a scene matters).
    public static func reason(_ sentence: String, at range: Range<String.Index>, kind: TechSpecs.Kind, name: String,
                              context: String = "") -> ClaimReason? {
        let folded = sentence.replacingOccurrences(of: "’", with: "'")
        guard folded.count == sentence.count else { return nil }
        let gear = folded.index(folded.startIndex, offsetBy: sentence.distance(from: sentence.startIndex, to: range.lowerBound))
            ..< folded.index(folded.startIndex, offsetBy: sentence.distance(from: sentence.startIndex, to: range.upperBound))
        let clause = governing(folded, before: gear, acrossCommas: true)
        let near = governing(folded, before: gear, acrossCommas: false)
        let after = ownPredicate(following(folded, after: gear))
        let lowered = name.lowercased()
        // The gear's own name is a visual treatment ("Film emulation", "a show LUT", "Kodachrome look"):
        // words of simulation describe what it is, not that it was faked (1.10.10).
        let isLook = ["lut", "look", "emulation", "simulation", "style"].contains { lowered.contains($0) }

        // Necessity, not denial or a hypothetical: "we couldn't have done it without the Steadicam".
        let needed = has(necessity, clause)
        // Denied: the verb of avoidance or a negation governs it ("avoided Steadicam", "no
        // practicals", "decided against anamorphic"), or the clause after says so.
        if !needed, let match = avoidance.matches(in: clause, range: NSRange(clause.startIndex..., in: clause)).last,
           let found = Range(match.range, in: clause) {
            // What lies between the verb and the gear must not start a new statement of use ("instead
            // deploying", "and went with").
            let between = String(clause[found.upperBound...])
            let verb = String(clause[found]).lowercased()
            // A negation's exception ("didn't use any lights except a SkyPanel", "nothing other than
            // 35mm", "no more than two"), or a negated object that isn't the gear, the gear only in an
            // adjunct after it ("didn't have a big crew on the Technocrane days", "without a permit on
            // the Alexa Mini"), or a new clause ("…, so a single Steadicam did…").
            let negation = verb.range(of: #"^(?:didn|did not|don|do not|doesn|does not|couldn|could not|wouldn|would not|won|will not|never|not|without|no need)"#,
                                      options: .regularExpression) != nil
            var excepted = between.range(of: #"\b(?:except|excepting|other than|more than|besides|apart from|aside from|beyond|but for|save for)\b|,\s*(?:so|and so|which|and then)\b"#,
                                         options: [.regularExpression, .caseInsensitive]) != nil
            // ", and …" starts a new clause only when what follows isn't more of the list ("avoided
            // zooms, Steadicam, and drones" is still one list).
            // (The last ", and": a regular-expression search doesn't go backwards, so the matches are listed.)
            let ands = try! NSRegularExpression(pattern: #",\s*and\s+"#).matches(in: between, range: NSRange(between.startIndex..., in: between))
            if !excepted, let last = ands.last, let and = Range(last.range, in: between),
               !isContinuation(String(between[and.upperBound...])) {
                excepted = true
            }
            // The gear in a phrase after the negated object ("didn't have a big crew on the
            // Technocrane days"), unless that object is what the gear needed: budget, time, room…
            var adjunct = false
            if negation, let tail = between.range(of: #"(\w+)\s+(?:on|in|at|for|during|from|inside|aboard)\s+(?:the|a|an|his|her|their|our|my|this|that)?\s*$"#,
                                                   options: [.regularExpression, .caseInsensitive]) {
                let words = between[tail].split(separator: " ").map { $0.lowercased() }
                let noun = words.first ?? "", preposition = words.count > 1 ? words[1] : ""
                // "the budget for", "the crew for", "clearance for": what the gear needed, so still a denial.
                let needed = ["budget", "time", "room", "space", "money", "need", "permission", "chance", "opportunity", "reason",
                              "patience", "appetite", "call", "use", "place", "funds", "means", "access", "manpower", "power",
                              "crew", "resources", "clearance", "clearances", "insurance", "license", "licence", "rigging", "power"]
                // Only "didn't have the budget for": "didn't need any rigging for the Technocrane" says it was used.
                adjunct = !(needed.contains(noun) && preposition == "for" && verb.contains("have"))
            }
            if !excepted, !adjunct,
               between.range(of: #"\b(?:instead|went with|switched to|opted for|chose|settled on|turned to|replaced (?:it|them) with|in favou?r of)\b"#,
                             options: [.regularExpression, .caseInsensitive]) == nil {
                return .denied
            }
        }
        if has(noneBefore, String(near.suffix(30))) { return .denied }
        if has(deniedAfter, after) { return .denied }
        if has(consideredNot, String(folded[gear.upperBound...])) { return .denied }

        // A definition or the history of the gear (1.10.10): "ENR is a silver retention process named for
        // its inventor…".
        let rest = String(folded[gear.upperBound...].prefix(100))
        if has(definitionAfter, rest) || has(definitionCopula, rest) || (has(definitionBefore, near) && has(definitionNoun, rest)) { return .definition }
        // A crew member's job ("his dolly grip Lowell Richardson"): every production has one; it says
        // nothing of how this film was shot.
        if kind == .support, has(crewRoleAfter, rest) { return .insufficientContext }
        // What a kind of gear can or can't do, said of any one of it ("a tilt, which a Steadicam doesn't do
        // as well"): a product's capability, not this film's use.
        if has(genericBefore, near), has(genericCapabilityAfter, rest) { return .productCapability }

        // A hypothetical: from its modal to the end of its part of the sentence, commas included.
        let part = governing(folded, before: gear, acrossCommas: true)
        let wholePart = String(folded[segmentStart(folded, before: gear)..<gear.upperBound])
        if !needed, has(hypothetical, wholePart) || has(hypothetical, part) { return .hypothetical }

        // A plan, unless it's said to have been carried out.
        // ("One of her decisions was to shoot on film": a decision taken, not a plan, 1.10.10.)
        let planned = decided.stringByReplacingMatches(in: wholePart, range: NSRange(wholePart.startIndex..., in: wholePart), withTemplate: "decided to")
        if has(plan, planned) || has(intention, wholePart), !has(planKept, String(folded[gear.upperBound...])) { return .abandonedPlan }
        // An idea being thought through, not something done ("I began thinking that I could convey the
        // conflict… between artificial light and natural light").
        if has(idea, wholePart) { return .insufficientContext }

        // Reported, rumoured, unconfirmed: neither confirmed nor ruled out.
        if has(rumour, wholePart) || has(rumour, String(folded[gear.upperBound...])) { return .uncertain }

        // Tried out only (unless the sentence says it was then chosen).
        // Not when the film itself comes between ("We shot tests on 35mm and the film on 65mm").
        if let match = tried.firstMatch(in: clause, range: NSRange(clause.startIndex..., in: clause)),
           let found = Range(match.range, in: clause),
           String(clause[found.lowerBound...]).range(of: #"\b(?:the (?:film|movie|feature|shoot|production|picture)|principal|main unit)\b"#,
                                                    options: [.regularExpression, .caseInsensitive]) == nil,
           !has(adopted, String(folded[gear.upperBound...])), !has(adopted, clause) {
            return .testOnly
        }

        // Other people's practice, a mentor's lesson, a habit.
        if has(practice, clause) || has(habitual, clause) { return .otherPractice }
        if has(habitWhen, wholePart), has(genericJob, wholePart + " " + after) { return .otherPractice }
        if has(secondNature, rest) { return .otherPractice }
        if has(era, wholePart + " " + following(folded, after: gear)) { return .otherPractice }

        // A simulation or a look made, right by the gear.
        // (A movement's "style" is the movement itself: "a more dynamic, handheld style".)
        let styleOfMovement = kind == .support && has(movementStyleAfter, String(folded[gear.upperBound...].prefix(30)))
        if !isLook, !styleOfMovement, has(simulatedBefore, String(near.suffix(60))) || has(simulatedAfter, String(folded[gear.upperBound...].prefix(60)))
            || has(matchedDigitally, String(clause.suffix(90))) {
            return .simulated
        }
        // ("minimizing the amount of CGI and using only natural lighting": less CG, not CG.)
        let cgScope = lessCG.stringByReplacingMatches(in: near.isEmpty ? clause : near + " " + after,
                                                      range: NSRange((near.isEmpty ? clause : near + " " + after).startIndex..., in: near.isEmpty ? clause : near + " " + after),
                                                      withTemplate: " ")
        if kind == .light || kind == .camera, has(computerGenerated, cgScope), !has(productionAgent, near) {
            return .simulated
        }

        // Set dressing or a prop, not equipment lighting or photographing the film (unless it's said to
        // light the scene): "LED panels built by the art department as props", "the character keeps
        // an old Super 8 camera".
        let dressingScope = wholePart + " " + following(folded, after: gear)
        if [.light, .camera, .format, .support].contains(kind), has(setDressing, dressingScope),
           !has(lightsTheScene, dressingScope), !has(productionAgent, near) {
            return .environment
        }
        // An object in the scene or the location (lights and grip; a prop camera).
        if kind == .light || kind == .support, has(environmentSubject, clause), !has(productionAgent, clause) { return .environment }
        if kind == .light, has(researchFound, wholePart) { return .environment }
        // (A camera carried by a drone, a gimbal or a crane is the payload, equipment: 1.10.10.)
        let payload = has(carriedByRig, near) || has(payloadAfter, rest)
        if kind == .camera, !payload, has(prop, near) || has(prop, after), !has(productionAgent, near) { return .environment }

        // Delivery or presentation of a format or ratio, with no word of shooting in its clause.
        if kind == .format || kind == .lens {
            let scope = clause + " " + after
            let stage = FormatStage.of(folded, at: gear, name: name, context: context)
            if stage == .homeMedia || stage == .restoration || stage == .streaming { return .delivery }
            // A ratio framed, extracted, designed or projected for the film (1.10.10): the film's image,
            // kept with its stage. A ratio said only of a presentation that may be any release stays
            // undecided.
            if !(stage?.isFilmImage ?? false), !has(captureVerb, scope) {
                if has(deliveryCue, scope) { return .delivery }
                if has(presentationCue, scope) { return .presentation }
            }
        }

        // A product's capability, with no one using it.
        // The product is the subject, the capability verb follows it, and the gear is what it offers.
        if let verb = capability.firstMatch(in: clause, range: NSRange(clause.startIndex..., in: clause)),
           let verbRange = Range(verb.range, in: clause) {
            let subject = String(clause[..<verbRange.lowerBound])
            // …and the sentence doesn't go on to say the production used it ("…, and Doe used that", "…,
            // and Pfister stresses that these gave him and Nolan flexibility").
            let usedAfter = String(folded[gear.upperBound...]).range(of: #"\b(?:used|shot|recorded|chose|went with|relied on|picked)\b|\b(?:these|they|it|this|that|those)\s+(?:gave|allowed|let|helped|enabled|offered)\s+(?:him|her|them|us|me|the (?:production|crew|filmmakers))\b"#,
                                       options: [.regularExpression, .caseInsensitive]) != nil
            if has(productSubject, subject), !has(personalAgent, clause), !has(supplier, subject), !usedAfter { return .productCapability }
        }
        return nil
    }

    /// Where the gear's part of the sentence starts: the last strong break before it (commas don't
    /// end a hypothetical or a plan: "might have been shot in Super 35, or Super 16").
    static func segmentStart(_ sentence: String, before range: Range<String.Index>) -> String.Index {
        let lead = sentence[..<range.lowerBound]
        var start = 0
        for mark in strongBreaks where mark != ": " {
            if let found = lead.range(of: mark, options: [.backwards, .caseInsensitive]) {
                start = max(start, lead.distance(from: lead.startIndex, to: found.upperBound))
            }
        }
        // ", and the production went with…", ", so he shot…": a new clause, unless it's only more of a list.
        for mark in [", and ", ", so ", ", which ", ", who ", " and the ", " and then ", " so he ", " so she ", " so they ", " so we ", " so i "] {
            if let found = lead.range(of: mark, options: [.backwards, .caseInsensitive]) {
                let offset = lead.distance(from: lead.startIndex, to: found.upperBound)
                guard offset > start else { continue }
                let rest = String(lead[found.upperBound...])
                if !isContinuation(rest) || mark.contains("so ") { start = offset }
            }
        }
        return sentence.index(sentence.startIndex, offsetBy: start)
    }
}
