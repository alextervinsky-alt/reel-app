import Foundation

// MARK: - Page context and claim attribution (1.10.8)

/// What a page is, for the film being researched, and which of its statements can be about that
/// film. Three separate decisions (`ResearchEngine` makes the first, whether to fetch a candidate):
/// - the page's context: an article about the film, or a page about something else that mentions
///   it (a contributor's profile, an interview about another production, a news item, a vendor's
///   corporate page);
/// - each statement's relevance: on a page about the film every statement is read by the usual
///   rules; on any other page only a statement anchored to the film (it names the film, outside a
///   list of credits, or follows such a statement in the same paragraph with no other production
///   named in between);
/// - the statement's suitability as evidence, by its source family (`SourceRegistry`).
/// Nothing here knows any film, person or site: it works from the film's title, its collection's
/// other titles and the names on the page.
public struct PageContext: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// About the film: its title or address names it, or its opening and much of its text do.
        case targetFilm
        /// About the people: a profile, an obituary, an honour, a membership announcement.
        case contributorProfile
        /// News or a company's corporate page (appointments, anniversaries, partnerships).
        case newsItem
        /// About another production, or several, that mentions the film.
        case otherProduction

        public var label: String {
            switch self {
            case .targetFilm: "about the film"
            case .contributorProfile: "a page about the people, not the film"
            case .newsItem: "a news or company page"
            case .otherProduction: "a page about other productions"
            }
        }
    }

    public let kind: Kind
    /// Statements anchored to the film (on a page that isn't about it); all of them on one that is.
    public let anchored: Int
    /// Other productions the page itself identifies as such: the other titles of its credit lists,
    /// and titles given with their year ("Glass Rivers (2019)"). A statement naming one is about that
    /// production, on any page.
    public var productions: [String] = []

    public var aboutFilm: Bool { kind == .targetFilm }

    public init(kind: Kind, anchored: Int, productions: [String] = []) {
        self.kind = kind
        self.anchored = anchored
        self.productions = productions
    }

    /// The other productions a page names as productions (see `productions`), never the film itself.
    public static func productions(in paragraphs: [String], title: String, people: [String] = []) -> [String] {
        var found: [String] = []
        func add(_ raw: String) {
            let name = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:“”\"'‘’()"))
                .replacingOccurrences(of: #"^(?:and|or|the films?|including|include|includes)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            let words = name.split(separator: " ")
            // A date, a time or an attribution isn't a production (1.10.9): "On January 26, AC joined…",
            // "In 2000, …", "According to Coppola, …".
            if name.range(of: Self.notATitle, options: .regularExpression) != nil { return }
            guard (1...6).contains(words.count), name.count >= 3, let first = name.first, first.isUppercase || first.isNumber,
                  !TechSpecs.namesTitle(name, title: title), !TechSpecs.namesTitle(title, title: name),
                  !found.contains(name) else { return }
            found.append(name)
        }
        let titled = #"([A-Z0-9][\w'’:&!-]*(?:\s+(?:[A-Z0-9][\w'’:&!-]*|of|the|and|a|an|in|on|to|for|by))*)"#
        // Two words or more, capitalised (a title, not "Tuesday" or "Location").
        let multi = #"((?:The |A |An )?[A-Z0-9][\w'’:&!-]*(?:\s+(?:of|the|and|a|an|in|on|to|for|by)?\s*[A-Z0-9][\w'’:&!-]*)+)"#
        let cues = [
            // "Glass Rivers (2019)".
            try! NSRegularExpression(pattern: titled + #"\s+\((?:19|20)\d\d\)"#),
            // "He shot Antlers Above the Salt Road with…", "she photographed Low Country".
            try! NSRegularExpression(pattern: #"\b(?:shot|photographed|lensed|filmed|lit)\s+"# + multi + #"(?=\s+(?:with|on|in|for|using|entirely|mostly|back)\b|[,.;])"#),
            // "Lowland Cantata, his first digital feature, …".
            try! NSRegularExpression(pattern: multi + #",\s+(?:his|her|their|the|our|my)\s+(?:\w+\s+){0,3}(?:feature|film|picture|movie|documentary|series|short)\b"#),
            // "On The Quiet Ledger, a few years earlier, …", "On Overpass she worked…" (an opening naming a production).
            try! NSRegularExpression(pattern: #"(?:^|[.!?:]\s+)(?:On|For|With|During)\s+"# + multi + #"(?:,|(?=\s+(?:he|she|they|we|I|I'd|we'd)\b))"#),
            try! NSRegularExpression(pattern: #"(?:^|[.!?:]\s+)(?:On|For|With|During)\s+"# + titled + #"(?=\s+(?:he|she|they|we|I|I'd|we'd)\b)"#),
            // "Her follow-up, Static Bloom,", "another feature, Fieldnote,", "coming off The Copper Season,".
            try! NSRegularExpression(pattern: #"\b(?:[Hh]is|[Hh]er|[Tt]heir)\s+(?:follow-up|next(?:\s+(?:film|feature|project))?|previous\s+(?:film|feature)|newest|latest|debut|first\s+feature),?\s+"# + titled),
            try! NSRegularExpression(pattern: #"\banother\s+(?:feature|film|movie|production|picture|project),?\s+"# + titled),
            try! NSRegularExpression(pattern: #"\b(?:coming|fresh|straight)\s+(?:off|from)\s+"# + titled),
            // "the miniseries Dust", "the feature Low Country", "on the set of Kiln" (one word or more).
            try! NSRegularExpression(pattern: #"\b(?:the|a|his|her|their|our|my)\s+(?:mini-?series|series|show|feature|film|documentary|commercial|short|movie|pilot|sequel|remake)\s+"#
                                     + titled + #"(?=[\s,.;:!?)]|$)"#),
            try! NSRegularExpression(pattern: #"\bon the set of\s+"# + titled),
        ]
        for paragraph in paragraphs {
            let range = NSRange(paragraph.startIndex..., in: paragraph)
            for cue in cues {
                for match in cue.matches(in: paragraph, range: range) {
                    guard let r = Range(match.range(at: 1), in: paragraph) else { continue }
                    let name = String(paragraph[r])
                    // Gear, a company or a person isn't a production ("shot Sony Venice", "On Kodak Vision3").
                    let read = TechSpecs.read([name + " was used."])
                    if !read.specs.isEmpty || !read.mentioned.isEmpty || people.contains(where: { name.contains($0) || $0.contains(name) }) { continue }
                    // A part of the film itself ("shot Part One on…") is the collection's rules' to judge.
                    if name.range(of: #"^(?:Part|Chapter|Volume|Book|Episode|Act)\b"#, options: .regularExpression) != nil { continue }
                    // The shoot's own vocabulary isn't a title ("During Principal Photography,", "On Set Day").
                    let lowered = name.lowercased()
                    if ["photography", "production", "filming", "shoot", "location", "season", "week", "scene", "sequence", "night",
                        "morning", "evening", "stage", "set ", "day", "unit", "studio", "camera", "lens", "light"].contains(where: lowered.contains) { continue }
                    add(name)
                }
            }
            for sentence in Digest.sentences(in: paragraph) where namesCredits(sentence) || isCreditList(sentence, title: title) {
                // The list: after its cue ("…include", "known for", a colon), split at commas and "and".
                var list = sentence
                if let cue = list.range(of: #"\b(?:include|includes|included|including|such as|like|known for|range from|span|for|on)\b|:"#,
                                        options: [.regularExpression, .caseInsensitive]) {
                    list = String(list[cue.upperBound...])
                }
                for item in list.components(separatedBy: CharacterSet(charactersIn: ",;")).flatMap({ $0.components(separatedBy: " and ") }) {
                    add(item.replacingOccurrences(of: #"\s+\((?:19|20)\d\d\)"#, with: "", options: .regularExpression))
                }
            }
        }
        return found
    }

    /// Dates, times and attributions that open a sentence like a title would ("On January 26,",
    /// "In 2000,", "According to Coppola,", "By the 1970s,").
    static let notATitle = #"^(?:(?:January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept?|Oct|Nov|Dec)\.?(?:\s+\d{1,2}(?:st|nd|rd|th)?)?(?:,?\s+\d{4})?|(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b.*|(?:In|By|Since|From|Until|Around|After|Before|During|Through|Throughout)\s+(?:the\s+)?(?:\d{1,4}(?:s|st|nd|rd|th)?|early|late|mid|summer|winter|spring|autumn|fall)\b.*|According\s+to\b.*|\d+(?:st|nd|rd|th)?|(?:Day|Week|Night|Episode|Season|Year)\s+\d+)$"#

    /// Profile and news cues in a page's title or address: what the page is when it isn't the film's.
    static let profileCues = try! NSRegularExpression(
        pattern: #"\b(?:in memoriam|obituary|dies at|has died|remembering|tribute to|welcomes?|welcomed|joins?|joined|new (?:active |associate )?members?|members|membership|knighted|honou?red|lifetime achievement|appointed|career|retrospective|biography)\b"#,
        options: [.caseInsensitive])
    static let corporateCues = try! NSRegularExpression(
        pattern: #"\b(?:press release|appoint\w*|names? .+ (?:coo|ceo|cfo|head)|partners?(?:hip)? with|acquires?|acquisition|opens?|anniversary|turns \d+|edition|policy|careers|jobs|hiring|bio\b|announces?)\b"#,
        options: [.caseInsensitive])

    /// The page's context for `title`. `pageTitle`/`url`: the page's own; `paragraphs`: its article.
    /// A title of two words or more and eight letters or more ("World War Z") names the film by
    /// itself; a short or common one ("Drive", "Heat", "Her") only as written, with a capital.
    public static func isDistinctive(_ title: String) -> Bool {
        let short = (title.split(separator: ":").first.map(String.init) ?? title).trimmingCharacters(in: .whitespaces)
        return short.split(separator: " ").count >= 2 && short.filter(\.isLetter).count >= 8
    }

    /// Whether `text` names the film: any case for a distinctive title, as written for another
    /// ("the drive for realism" isn't Drive).
    public static func names(_ text: String, title: String) -> Bool {
        if isDistinctive(title) { return TechSpecs.namesTitle(text, title: title) }
        let short = (title.split(separator: ":").first.map(String.init) ?? title).trimmingCharacters(in: .whitespaces)
        guard !short.isEmpty else { return false }
        // As written (case and all), whatever the punctuation between its words (1.10.9).
        return TitleMatch.names(text.replacingOccurrences(of: "’", with: "'"), title: short, caseSensitive: true)
    }

    public static func classify(pageTitle: String, url: URL, paragraphs: [String], title: String, otherTitles: [String],
                                people: [String], year: Int? = nil) -> PageContext {
        let address = url.path.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        // A short or common title in a page's title or address is the film's only when the page
        // also gives its year or one of its people.
        let body = paragraphs.joined(separator: " ")
        // In a paragraph that names it as written: the year or a credited surname beside the title.
        let surnames = people.compactMap { $0.split(separator: " ").last.map(String.init) }.filter { $0.count >= 4 }
        let confirmed = isDistinctive(title) || paragraphs.contains { paragraph in
            names(paragraph, title: title) && (year.map { paragraph.contains(String($0)) } ?? false || surnames.contains { paragraph.contains($0) })
        }
        // An address that is the title itself ("/blog-post/challengers/") names it too, once the title
        // is confirmed (1.10.9): a short title's address otherwise says nothing.
        let named = confirmed && (names(pageTitle, title: title) || isDistinctive(title) && TechSpecs.namesTitle(address, title: title)
            || TitleMatch.isSlug(of: title, url: url)
            || CameraSources.isAbout(title: title, articleTitle: pageTitle, url: url.absoluteString) && names(pageTitle + " " + body, title: title))
        // Named outside a list of credits: "her credits include…" says nothing about the film.
        let naming = paragraphs.map { paragraph in
            Digest.sentences(in: paragraph).contains { names($0, title: title) && !isCreditList($0, title: title) }
        }
        let lede = naming.prefix(3).contains(true)
        let share = paragraphs.isEmpty ? 0 : Double(naming.filter { $0 }.count) / Double(paragraphs.count)
        // A page whose own title names another of the collection is that film's.
        let otherTitled = otherTitles.contains { TechSpecs.namesTitle(pageTitle, title: $0) } && !named
        let others = productions(in: paragraphs, title: title, people: people)
        let heading = pageTitle + " " + address
        let range = NSRange(heading.startIndex..., in: heading)
        // A profile, an obituary or a news page is about its person or company, whatever it says of the
        // film after (an interview titled with its subject's name isn't: it can be about the film).
        let personal = profileCues.firstMatch(in: heading, range: range) != nil || corporateCues.firstMatch(in: heading, range: range) != nil
        if named && !otherTitled || (!otherTitled && !personal && lede && naming.filter { $0 }.count >= 2 && share >= 0.25) {
            return PageContext(kind: .targetFilm, anchored: paragraphs.reduce(0) { $0 + Digest.sentences(in: $1).count }, productions: others)
        }
        let kind: Kind = corporateCues.firstMatch(in: heading, range: range) != nil ? .newsItem
            : profileCues.firstMatch(in: heading, range: range) != nil ? .contributorProfile : .otherProduction
        let count = anchors(paragraphs, title: title, otherTitles: otherTitles + others, people: people, inherit: kind == .otherProduction,
                            acrossParagraphs: true)
            .joined().filter { $0 }.count
        return PageContext(kind: kind, anchored: count, productions: others)
    }

    /// For each statement of a paragraph on a page that isn't about the film: whether it's anchored
    /// to the film. A statement naming the film anchors itself and the statements after it in its
    /// paragraph, until one names another production; a list of credits ("his films include…",
    /// three titles or more) names the film without saying anything about it.
    /// On a profile, an obituary or a news page (`inherit` false) the subject is the person or the
    /// company: only a statement naming the film is about it ("In his last years he taught…" after a
    /// sentence on the film is about him, not the film).
    public static func anchoring(_ paragraph: String, title: String, otherTitles: [String], people: [String],
                                 inherit: Bool = true) -> [Bool] {
        anchors([paragraph], title: title, otherTitles: otherTitles, people: people, inherit: inherit, acrossParagraphs: false).first ?? []
    }

    /// `anchoring` for a page's paragraphs in order. The film stays the subject within a paragraph
    /// on an interview (`inherit`), not across paragraphs: a round-table or an interview moving to
    /// another production often names it in a way no rule can tell from a name ("looks back further,
    /// to Saints of the Low Meridian"), and the holdout showed carrying it over leaks that film's gear.
    ///
    /// 1.10.9: the film stays the subject across paragraphs only in a bounded context that says so
    /// (`continues`): an interview's question naming the film holds for its answers until the next
    /// question; a paragraph continues the one before only when the film was still the subject at its
    /// end, it names no other production, it doesn't turn to a career, a biography or another time
    /// ("Her first feature…", "Years earlier…"), and at most two paragraphs have passed since the film
    /// was named. A comparison inside a sentence ("Just as on <Other>, …") doesn't end the subject:
    /// what the sentence asserts is read apart from what it compares (`ComparisonFrame`).
    public static func anchors(_ paragraphs: [String], title: String, otherTitles: [String], people: [String],
                               inherit: Bool = true, acrossParagraphs: Bool = false) -> [[Bool]] {
        var anchor = false
        var sinceNamed = Int.max
        var question: Bool? = nil
        return paragraphs.map { paragraph in
            let isQuestion = Self.isQuestion(paragraph)
            let sentences = Digest.sentences(in: paragraph)
            let othersHere = sentences.contains { sentence in
                let main = ComparisonFrame(sentence, title: title, otherTitles: otherTitles, people: people).main
                return !names(main, title: title) && TechSpecs.namesAnotherFilm(main, title: title, otherTitles: otherTitles, people: people)
            }
            if isQuestion {
                // The question sets what its answers are about: the film, another production, or (a
                // follow-up naming neither) whatever the answers were about.
                if sentences.contains(where: { names($0, title: title) }) { question = true } else if othersHere { question = false }
                anchor = false
                return sentences.map { _ in false }
            }
            if sinceNamed != Int.max { sinceNamed += 1 }
            let carried = inherit && acrossParagraphs && anchor && sinceNamed <= 2 && !othersHere && !Self.turnsAway(paragraph)
            anchor = (inherit && question == true && !othersHere) || carried
            return sentences.map { sentence in
                let frame = ComparisonFrame(sentence, title: title, otherTitles: otherTitles, people: people)
                let namesIt = names(sentence, title: title)
                let other = TechSpecs.namesAnotherFilm(frame.main, title: title, otherTitles: otherTitles, people: people)
                    && !names(frame.main, title: title)
                if namesIt, !isCreditList(sentence, title: title), names(frame.main, title: title) || !other {
                    anchor = true
                    sinceNamed = 0
                    return true
                }
                if namesIt || other {
                    anchor = false
                    return false
                }
                return inherit && anchor
            }
        }
    }

    /// An interviewer's question: it ends with "?", or opens with the interviewer's tag ("Q:", "AC:").
    static func isQuestion(_ paragraph: String) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^(?:Q|Question|Interviewer|[A-Z]{2,4})\s*[:.]"#, options: .regularExpression) != nil,
           trimmed.hasSuffix("?") || trimmed.hasPrefix("Q") { return true }
        return trimmed.hasSuffix("?") && trimmed.count < 400 && !trimmed.contains("\"")
    }

    /// A paragraph turning to a career, a biography or another time: where a subject carried over
    /// from the paragraph before would leak.
    static func turnsAway(_ paragraph: String) -> Bool {
        // A production named by an opening ("Five years later, on The Lantern Keepers of Hollow Bay, …"):
        // capitalised words after "on", "for" or "with" up to a comma.
        if paragraph.range(of: #"(?:^|[,.;]\s+|\s)(?i:on|for|with|during)\s+(?:The\s+|A\s+|An\s+)?[A-Z][\w'’-]+(?:\s+(?:of|the|and|a|an|in|on|for|to)?\s*[A-Z][\w'’-]+){0,6}(?:,|\s+(?i:he|she|they|we|i)\b)"#,
                           options: .regularExpression) != nil { return true }
        return paragraph.range(of: #"\b(?:was born|grew up|began (?:his|her|their) career|started (?:out|his career|her career)|credits include|filmography|(?:his|her|their) (?:first|debut|previous|earlier|last|next|latest|newest|new) (?:feature|film|movie|project|picture|documentary)|debut|years (?:earlier|before|later)|a decade (?:earlier|before|later)|before that|after that,? (?:he|she|they)|looks back|went on to|is (?:now|currently) (?:prepping|shooting|working)|(?:next|current|new|latest|upcoming) (?:project|feature|film)|(?:his|her|their) (?:newest|latest|next|new|follow-up|current)\b|\b(?:now|these days|nowadays|today)\s+(?:teaches|runs|works|lives|flies|shoots|lectures|owns|uses|prefers)|\bteaches\b|in (?:19|20)\d{2},)"#,
                        options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "Her credits include A, B and C", "known for A, B and C", "(A, B, C)": a list of work.
    /// A list of work said as one: "her credits include…", "known for…", "whose films…".
    static func namesCredits(_ sentence: String) -> Bool {
        sentence.range(of: #"\b(?:credits?|films|features|filmography|work|projects|titles|movies)\s+(?:include|includes|included|including|such as|like|range from|span)\b|\b(?:best |also )?known for\b|\bwhose (?:credits|films|work)\b|\b(?:other|previous|recent) (?:credits|films|work)\b"#,
                       options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func isCreditList(_ sentence: String, title: String? = nil) -> Bool {
        if namesCredits(sentence) { return true }
        // Three titles or more in quotes.
        if TechSpecs.quotedTitle.numberOfMatches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) >= 3 { return true }
        // The film as one item of a run of capitalised names ("…Glass Rivers, The Long Quarantine, Moth
        // and Kiln"): a list, not a statement about it.
        guard let title else { return false }
        let items = sentence.components(separatedBy: ",").flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .;:")) }
        guard items.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) else { return false }
        let names = items.filter { item in
            let words = item.split(separator: " ")
            return !words.isEmpty && words.count <= 6 && words.allSatisfy { $0.first?.isUppercase == true || $0.first?.isNumber == true
                || ["of", "the", "a", "an", "in", "on", "to", "for"].contains($0.lowercased()) }
        }
        return names.count >= 3
    }
}
