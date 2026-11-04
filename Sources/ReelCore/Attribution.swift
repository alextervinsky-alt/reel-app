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
            guard (1...6).contains(words.count), name.count >= 3, let first = name.first, first.isUppercase || first.isNumber,
                  !TechSpecs.namesTitle(name, title: title), !TechSpecs.namesTitle(title, title: name),
                  !found.contains(name) else { return }
            found.append(name)
        }
        let titled = #"([A-Z0-9][\w'’:&!-]*(?:\s+(?:[A-Z0-9][\w'’:&!-]*|of|the|and|a|an|in|on|to|for))*)"#
        // Two words or more, capitalised (a title, not "Tuesday" or "Location").
        let multi = #"((?:The |A |An )?[A-Z0-9][\w'’:&!-]*(?:\s+(?:of|the|and|a|an|in|on|to|for)?\s*[A-Z0-9][\w'’:&!-]*)+)"#
        let cues = [
            // "Glass Rivers (2019)".
            try! NSRegularExpression(pattern: titled + #"\s+\((?:19|20)\d\d\)"#),
            // "He shot Antlers Above the Salt Road with…", "she photographed Low Country".
            try! NSRegularExpression(pattern: #"\b(?:shot|photographed|lensed|filmed|lit)\s+"# + multi + #"(?=\s+(?:with|on|in|for|using|entirely|mostly|back)\b|[,.;])"#),
            // "Lowland Cantata, his first digital feature, …".
            try! NSRegularExpression(pattern: multi + #",\s+(?:his|her|their|the|our|my)\s+(?:\w+\s+){0,3}(?:feature|film|picture|movie|documentary|series|short)\b"#),
            // "On The Quiet Ledger, a few years earlier, …" (an opening naming a production).
            try! NSRegularExpression(pattern: #"(?:^|[.!?]\s+)(?:On|For|With|During)\s+"# + multi + #","#),
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

    /// Profile and news cues in a page's title or address: what the page is when it isn't the film's.
    static let profileCues = try! NSRegularExpression(
        pattern: #"\b(?:in memoriam|obituary|dies at|has died|remembering|tribute|welcomes?|welcomed|joins?|joined|new (?:active |associate )?members?|membership|knighted|honou?red|honou?rs?|lifetime achievement|award(?:ed|s)? |wins?\b|receives?|named|appointed|career|retrospective|profile|biography|podcast|conversations?|masterclass|interview with)\b"#,
        options: [.caseInsensitive])
    static let corporateCues = try! NSRegularExpression(
        pattern: #"\b(?:press release|appoint\w*|names? .+ (?:coo|ceo|cfo|head)|partners?(?:hip)? with|acquires?|acquisition|opens?|anniversary|turns \d+|edition|policy|careers|jobs|hiring|bio\b|announces?)\b"#,
        options: [.caseInsensitive])

    /// The page's context for `title`. `pageTitle`/`url`: the page's own; `paragraphs`: its article.
    public static func classify(pageTitle: String, url: URL, paragraphs: [String], title: String, otherTitles: [String],
                                people: [String]) -> PageContext {
        let address = url.path.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        let named = TechSpecs.namesTitle(pageTitle, title: title) || TechSpecs.namesTitle(address, title: title)
            || CameraSources.isAbout(title: title, articleTitle: pageTitle, url: url.absoluteString)
        let naming = paragraphs.map { TechSpecs.namesTitle($0, title: title) }
        let lede = naming.prefix(3).contains(true)
        let share = paragraphs.isEmpty ? 0 : Double(naming.filter { $0 }.count) / Double(paragraphs.count)
        // A page whose own title names another of the collection is that film's.
        let otherTitled = otherTitles.contains { TechSpecs.namesTitle(pageTitle, title: $0) } && !named
        let others = productions(in: paragraphs, title: title, people: people)
        if named && !otherTitled || (!otherTitled && lede && naming.filter { $0 }.count >= 2 && share >= 0.25) {
            return PageContext(kind: .targetFilm, anchored: paragraphs.reduce(0) { $0 + Digest.sentences(in: $1).count }, productions: others)
        }
        let heading = pageTitle + " " + address
        let range = NSRange(heading.startIndex..., in: heading)
        let kind: Kind = corporateCues.firstMatch(in: heading, range: range) != nil ? .newsItem
            : profileCues.firstMatch(in: heading, range: range) != nil ? .contributorProfile : .otherProduction
        let count = paragraphs.reduce(0) { total, paragraph in
            total + anchoring(paragraph, title: title, otherTitles: otherTitles + others, people: people, inherit: kind == .otherProduction)
                .filter { $0 }.count
        }
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
        var anchor = false
        return Digest.sentences(in: paragraph).map { sentence in
            let namesIt = TechSpecs.namesTitle(sentence, title: title)
            let other = TechSpecs.namesAnotherFilm(sentence, title: title, otherTitles: otherTitles, people: people)
            if namesIt, !isCreditList(sentence, title: title) {
                anchor = true
                return true
            }
            if namesIt || other {
                anchor = false
                return false
            }
            return inherit && anchor
        }
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
