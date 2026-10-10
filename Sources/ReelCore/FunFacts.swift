import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct FunFact: Codable, Equatable, Sendable {
    public var category: String
    public var text: String

    public init(category: String, text: String) {
        self.category = category
        self.text = text
    }
}

/// Structured facts from Wikidata.
public struct QuickFacts: Codable, Equatable, Sendable {
    public var basedOn: [String] = []
    public var filmedIn: [String] = []
    public var setIn: [String] = []
    /// The most notable awards won (Oscars, Golden Globes, BAFTAs, festival prizes first).
    public var notableAwards: [String] = []
    public var awardsWon = 0
    public var nominations = 0
    public var follows: String?
    public var followedBy: String?
    /// How the picture is framed ("2.39:1") and whether it's in colour, for the Cinematography tab
    /// (missing in facts fetched before Reel 1.7).
    public var aspectRatios: [String]?
    public var colour: [String]?
    /// Where it was filmed, each with Wikidata's short description ("greenhouse area in Almería,
    /// Spain"); missing in facts fetched before Reel 1.8.1 (`filmedIn` has the names).
    public var filmingPlaces: [FilmingPlace]?
    /// Awards and nominations for the cinematography (missing in facts fetched before Reel 1.8.2).
    public var cinematographyHonours: [Honour]?

    public init() {}

    public var isEmpty: Bool {
        basedOn.isEmpty && filmedIn.isEmpty && setIn.isEmpty && awardsWon == 0 && nominations == 0
            && follows == nil && followedBy == nil
    }
}

/// An award for the film, won or a nomination.
public struct Honour: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var won: Bool
    public var id: String { name }

    public init(name: String, won: Bool) {
        self.name = name
        self.won = won
    }
}

/// A place a film was shot, and what it is.
public struct FilmingPlace: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var about: String?
    public var id: String { name }

    public init(name: String, about: String?) {
        self.name = name
        self.about = about
    }
}

/// Behind-the-scenes facts and critics' notes from the film's Wikipedia article and Wikidata.
/// Stored with the film, so they are available offline.
public struct FunFacts: Codable, Equatable, Sendable {
    public var facts: [FunFact]
    public var quick: QuickFacts?
    /// Rotten Tomatoes' critics consensus, as quoted on Wikipedia.
    public var consensus: String?
    /// Opening-night audience grade from CinemaScore, e.g. "A−".
    public var cinemaScore: String?
    public var articleTitle: String?
    public var fetchedAt: Date

    public init(facts: [FunFact], quick: QuickFacts? = nil, consensus: String? = nil,
                cinemaScore: String? = nil, articleTitle: String?, fetchedAt: Date) {
        self.facts = facts
        self.quick = quick
        self.consensus = consensus
        self.cinemaScore = cinemaScore
        self.articleTitle = articleTitle
        self.fetchedAt = fetchedAt
    }

    public var isEmpty: Bool { facts.isEmpty && (quick?.isEmpty ?? true) }

    public var articleURL: URL? {
        guard let title = articleTitle,
              let encoded = title.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://en.wikipedia.org/wiki/\(encoded)")
    }
}

/// What one Wikipedia article gives Reel.
public struct ArticleFindings: Sendable {
    public var funFacts: FunFacts
    /// Sentences from the critical-response section, for the reception summary.
    public var criticSentences: [String]
}

public enum FunFactExtractor {
    /// Display order of the categories.
    public static let categoryOrder = [
        "At a glance", "Story & script", "Casting", "Making of", "On set", "Effects", "Music", "Release", "Awards", "Legacy",
    ]

    struct Section {
        let path: [String]
        var text: String
    }

    /// Splits a plain-text Wikipedia extract ("== Production ==", "=== Casting ===") into sections.
    static func sections(from extract: String) -> [Section] {
        var result: [Section] = []
        var path: [String] = ["Introduction"]
        var current = Section(path: path, text: "")
        for rawLine in extract.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("=="), line.hasSuffix("=="), line.count > 4 {
                result.append(current)
                let level = line.prefix { $0 == "=" }.count
                let title = line.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
                path = Array(path.prefix(max(level - 2, 0))) + [title]
                current = Section(path: path, text: "")
            } else if !line.isEmpty {
                current.text += line + "\n"
            }
        }
        result.append(current)
        return result.filter { !$0.text.isEmpty }
    }

    /// Which group a section belongs to, or nil for sections that aren't trivia (plot, cast list, critics…).
    static func category(for path: [String]) -> String? {
        let all = path.joined(separator: " / ").lowercased()
        let top = path.first?.lowercased() ?? ""
        func has(_ words: [String]) -> Bool { words.contains { all.contains($0) } }

        if top == "introduction" { return "At a glance" }
        if has(["casting"]) { return "Casting" }
        if has(["visual effect", "special effect", "effects"]) { return "Effects" }
        if has(["music", "soundtrack", "score"]) { return "Music" }
        if has(["development", "writing", "pre-production", "screenplay", "concept", "script"]) { return "Story & script" }
        if has(["filming", "principal photography", "cinematography", "design", "location", "costume", "makeup", "make-up", "stunt", "post-production", "editing"]) { return "On set" }
        if has(["box office", "release", "marketing", "home media", "distribution", "premiere"]) { return "Release" }
        if has(["accolade", "award", "honor", "honour"]) { return "Awards" }
        if has(["legacy", "sequel", "influence", "cultural impact", "future", "in popular culture"]) { return "Legacy" }
        if top.contains("production") { return "Making of" }
        return nil
    }

    /// Sections with what critics wrote.
    static func isCriticSection(_ path: [String]) -> Bool {
        let all = path.joined(separator: " / ").lowercased()
        return all.contains("critical") || (path.first?.lowercased() == "reception" && !all.contains("box office"))
    }

    static let cues: [(String, Double)] = [
        ("originally", 1.5), ("initially", 1), ("improvis", 2), ("turned down", 2), ("auditioned", 1.5),
        ("rewrote", 1), ("practical", 1.5), ("shot on", 1), ("shot in", 1), ("filmed in", 1), ("filmed on", 1),
        ("inspired by", 1.5), ("cameo", 2), ("homage", 1.5), ("easter egg", 2), ("uncredited", 1.5),
        ("budget", 1), ("million", 1), ("record", 1.5), ("largest", 1), ("longest", 1), ("youngest", 1),
        ("oldest", 1), ("scrapped", 1.5), ("cut from", 1.5), ("deleted", 1), ("almost", 1), ("declined", 1.5),
        ("insisted", 1), ("refused", 1), ("secret", 1), ("accident", 1.5), ("injur", 1.5), ("weight", 1),
        ("trained", 1), ("learned", 1), ("built", 1), ("constructed", 1), ("oscar", 1), ("academy award", 1),
        ("first", 1), ("only", 0.5), ("real ", 0.5), ("actual", 0.5), ("hours", 0.5), ("days", 0.5),
        ("weeks", 0.5), ("months", 0.5), ("years", 0.5), ("replaced", 1), ("wanted", 0.5), ("idea", 0.5),
        ("nominated", 0.5), ("won", 0.5), ("working title", 2), ("originally titled", 2),
        ("reshoot", 1.5), ("recast", 2), ("body double", 1.5), ("own stunts", 2), ("stunt", 1),
        ("true story", 1), ("real-life", 1), ("in-camera", 1.5), ("anamorphic", 1), ("imax", 1),
        ("65 mm", 1.5), ("70 mm", 1.5), ("35 mm", 1), ("film stock", 1.5), ("tribute", 1), ("reportedly", 0.5),
        ("the most", 1), ("highest", 1), ("for the role", 1), ("method", 0.5), ("ad-lib", 2), ("unscripted", 2),
    ]

    static let dullCues = ["was released on", "premiered at", "was released in", "is a ", "distributed by", "produced by"]
    /// The business around a film (dates, screenings, rights, takings): rarely what's worth knowing.
    static let logistics = ["screened", "screening", "scheduled", "festival", "premiere", "released", "distribut", "rights to",
                            "acquired the rights", "box office", "grossed", "opening weekend", "filmgoers", "admissions",
                            "home media", "blu-ray", "dvd", "streaming", "cancelled", "postponed", "trailer", "teaser",
                            "poster", "rated r", "rating of", "theaters", "theatres", "ticket", "revenue", "showings",
                            "earned", "million in"]

    static let weakStarts = ["he ", "she ", "they ", "it ", "this ", "these ", "his ", "her ", "their ", "its ", "however", "also", "in addition", "for example", "for instance", "in particular"]

    /// Whether a sentence makes sense on its own ("For example, he…" doesn't).
    public static func standsAlone(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return !weakStarts.contains { lower.hasPrefix($0) }
    }

    /// How worth knowing a sentence is: what surprises (originally, turned down, improvised,
    /// the first…), specifics (numbers, someone's own words), less for the business around it.
    public static func score(_ sentence: String) -> Double {
        let lower = sentence.lowercased()
        var score = cues.reduce(0.0) { lower.contains($1.0) ? $0 + $1.1 : $0 }
        if sentence.contains(where: { $0.isNumber }) { score += 0.5 }
        if sentence.contains(where: { "\"“”".contains($0) }) { score += 0.75 }
        if weakStarts.contains(where: { lower.hasPrefix($0) }) { score -= 1.5 }
        if dullCues.contains(where: { lower.contains($0) }) { score -= 0.75 }
        score -= 1.25 * Double(min(2, logistics.filter { lower.contains($0) }.count))
        return score
    }

    /// Picks the most interesting sentences: up to `limit`, at most four per group (two from the
    /// introduction), in reading order within a group. Also returns the best one.
    public static func facts(fromExtract extract: String, limit: Int = 16) -> [FunFact] {
        struct Candidate {
            let category: String
            let text: String
            let score: Double
            let position: Int
        }
        var candidates: [Candidate] = []
        var position = 0
        for section in sections(from: extract) {
            guard let category = category(for: section.path) else { continue }
            for sentence in ReceptionAnalyzer.sentences(in: section.text) {
                position += 1
                guard sentence.count >= 60, sentence.count <= 320, !sentence.contains("[") else { continue }
                let s = score(sentence)
                if s >= 1.5 { candidates.append(Candidate(category: category, text: sentence, score: s, position: position)) }
            }
        }

        var perCategory: [String: Int] = [:]
        var chosen: [Candidate] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            if chosen.count >= limit { break }
            let cap = candidate.category == "At a glance" ? 2 : 4
            if perCategory[candidate.category, default: 0] >= cap { continue }
            perCategory[candidate.category, default: 0] += 1
            chosen.append(candidate)
        }
        func rank(_ category: String) -> Int { categoryOrder.firstIndex(of: category) ?? categoryOrder.count }
        let ordered = chosen
            .sorted { rank($0.category) != rank($1.category) ? rank($0.category) < rank($1.category) : $0.position < $1.position }
            .map { FunFact(category: $0.category, text: $0.text) }
        return ordered
    }

    /// Sentences critics wrote about the film (for likes and dislikes), at most 40.
    public static func criticSentences(fromExtract extract: String) -> [String] {
        var result: [String] = []
        for section in sections(from: extract) where isCriticSection(section.path) {
            for sentence in ReceptionAnalyzer.sentences(in: section.text) where !sentence.contains("[") {
                result.append(sentence)
                if result.count >= 40 { return result }
            }
        }
        return result
    }

    /// Rotten Tomatoes' consensus, which Wikipedia quotes as: …consensus reads, "…".
    public static func consensus(fromExtract extract: String) -> String? {
        guard let marker = extract.range(of: "consensus reads") ?? extract.range(of: "consensus states") else { return nil }
        return quoted(after: marker.upperBound, in: extract)
    }

    /// CinemaScore grade: …gave the film an average grade of "A−"…
    public static func cinemaScore(fromExtract extract: String) -> String? {
        guard let cinema = extract.range(of: "CinemaScore") else { return nil }
        let window = extract[cinema.upperBound...].prefix(160)
        guard let grade = window.range(of: "grade of ") else { return nil }
        let text = String(window[grade.upperBound...])
        guard let value = quoted(after: text.startIndex, in: text), value.count <= 3 else { return nil }
        return value
    }

    private static func quoted(after index: String.Index, in text: String) -> String? {
        let opening: Set<Character> = ["\"", "“"]
        let closing: Set<Character> = ["\"", "”"]
        guard let start = text[index...].prefix(40).firstIndex(where: { opening.contains($0) }) else { return nil }
        let afterStart = text.index(after: start)
        guard let end = text[afterStart...].firstIndex(where: { closing.contains($0) }) else { return nil }
        let value = text[afterStart..<end].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

/// Finds a film's English Wikipedia article (via its IMDb id on Wikidata), reads its text, and
/// collects structured facts from Wikidata.
public struct WikipediaClient: Sendable {
    let session: URLSession

    public init(session: URLSession = TMDBClient.sharedSession) {
        self.session = session
    }

    public func findings(imdbID: String?, title: String, year: Int?, now: Date = Date()) async throws -> ArticleFindings {
        var article: String?
        var knownWithoutEnglishArticle = false
        var quick: QuickFacts?
        if let imdbID, !imdbID.isEmpty, let item = try await wikidataItem(imdbID: imdbID) {
            let entity = try await entity(item)
            article = entity.sitelinks?["enwiki"]?.title
            knownWithoutEnglishArticle = article == nil
            quick = try? await quickFacts(from: entity)
        }
        // A search is only a fallback for films Wikidata doesn't know; a film it knows without an
        // English article would otherwise risk another work's article.
        var needsFilmCheck = false
        if article == nil && !knownWithoutEnglishArticle,
           let found = try await searchArticle(title: title, year: year) {
            article = found.title
            needsFilmCheck = found.isBareTitle
        }
        var text: String?
        if let article { text = try await extract(title: article) }
        // "Frankenstein" could be the novel: a bare title only counts if the article is about a film.
        if needsFilmCheck, let t = text, !t.prefix(400).lowercased().contains(" film") {
            text = nil
            article = nil
        }
        guard let text else {
            return ArticleFindings(
                funFacts: FunFacts(facts: [], quick: quick, articleTitle: nil, fetchedAt: now),
                criticSentences: [])
        }
        let facts = FunFacts(
            facts: FunFactExtractor.facts(fromExtract: text), quick: quick,
            consensus: FunFactExtractor.consensus(fromExtract: text),
            cinemaScore: FunFactExtractor.cinemaScore(fromExtract: text),
            articleTitle: article, fetchedAt: now)
        return ArticleFindings(funFacts: facts, criticSentences: FunFactExtractor.criticSentences(fromExtract: text))
    }

    // MARK: Wikidata

    struct WikidataSearch: Decodable {
        struct Query: Decodable {
            struct Hit: Decodable { let title: String }
            let search: [Hit]
        }
        let query: Query?
    }

    struct Entity: Decodable {
        struct Link: Decodable { let title: String }
        struct Label: Decodable { let value: String }
        struct Claim: Decodable {
            struct Snak: Decodable {
                struct DataValue: Decodable {
                    struct ItemRef: Decodable { let id: String }
                    let itemID: String?
                    enum CodingKeys: String, CodingKey { case value }
                    init(from decoder: Decoder) throws {
                        let c = try decoder.container(keyedBy: CodingKeys.self)
                        itemID = (try? c.decode(ItemRef.self, forKey: .value))?.id
                    }
                }
                let datavalue: DataValue?
            }
            let mainsnak: Snak
        }
        let sitelinks: [String: Link]?
        let claims: [String: [Claim]]?
        let labels: [String: Label]?
        let descriptions: [String: Label]?

        func items(_ property: String) -> [String] {
            (claims?[property] ?? []).compactMap { $0.mainsnak.datavalue?.itemID }
        }
    }

    struct Entities: Decodable {
        let entities: [String: Entity]?
    }

    func wikidataItem(imdbID: String) async throws -> String? {
        let search: WikidataSearch = try await get("https://www.wikidata.org/w/api.php", [
            "action": "query", "list": "search", "srsearch": "haswbstatement:P345=\(imdbID)", "format": "json",
        ])
        return search.query?.search.first?.title
    }

    func entity(_ item: String) async throws -> Entity {
        let result: Entities = try await get("https://www.wikidata.org/w/api.php", [
            "action": "wbgetentities", "ids": item, "props": "sitelinks|claims", "sitefilter": "enwiki", "format": "json",
        ])
        guard let entity = result.entities?[item] else { throw TMDBError.badStatus(404) }
        return entity
    }

    /// Based on, filming locations, setting, awards, sequels — names looked up in one request.
    func quickFacts(from entity: Entity) async throws -> QuickFacts {
        let basedOn = Array(entity.items("P144").prefix(3))
        let filmedIn = Array(entity.items("P915").prefix(12))
        let setIn = Array(entity.items("P840").prefix(4))
        let awards = entity.items("P166")
        let follows = entity.items("P155").first
        let followedBy = entity.items("P156").first

        let ratios = Array(entity.items("P2061").prefix(3))
        let colour = Array(entity.items("P462").prefix(2))
        var ids: [String] = basedOn + filmedIn + setIn + ratios + colour + [follows, followedBy].compactMap { $0 }
        ids += awards.prefix(max(0, 50 - ids.count))
        var labels: [String: String] = [:]
        var descriptions: [String: String] = [:]
        var seen = Set<String>()
        let unique = ids.filter { seen.insert($0).inserted }
        if !unique.isEmpty {
            let result: Entities = try await get("https://www.wikidata.org/w/api.php", [
                "action": "wbgetentities", "ids": unique.joined(separator: "|"), "props": "labels|descriptions",
                "languages": "en", "format": "json",
            ])
            for (id, item) in result.entities ?? [:] {
                if let label = item.labels?["en"]?.value { labels[id] = label }
                if let about = item.descriptions?["en"]?.value { descriptions[id] = about }
            }
        }

        // The rest of the awards and the nominations (up to 100 more names), for the ones given
        // for the cinematography.
        let nominations = entity.items("P1411")
        // Best-effort: when it fails the rest stands, and the honours are asked for again next time.
        let more = Array((awards + nominations).filter { labels[$0] == nil && seen.insert($0).inserted }.prefix(100))
        var allNamed = true
        for start in stride(from: 0, to: more.count, by: 50) {
            let batch = more[start..<min(start + 50, more.count)]
            guard let result: Entities = try? await get("https://www.wikidata.org/w/api.php", [
                "action": "wbgetentities", "ids": batch.joined(separator: "|"), "props": "labels", "languages": "en", "format": "json",
            ]) else {
                allNamed = false
                continue
            }
            for (id, item) in result.entities ?? [:] {
                if let label = item.labels?["en"]?.value { labels[id] = label }
            }
        }

        var quick = QuickFacts()
        if allNamed {
            quick.cinematographyHonours = Self.cinematographyHonours(won: awards.compactMap { labels[$0] },
                                                                     nominated: nominations.compactMap { labels[$0] })
        }
        quick.basedOn = basedOn.compactMap { labels[$0] }
        quick.filmedIn = filmedIn.compactMap { labels[$0] }
        quick.filmingPlaces = filmedIn.compactMap { id in labels[id].map { FilmingPlace(name: $0, about: descriptions[id]) } }
        quick.setIn = setIn.compactMap { labels[$0] }
        quick.awardsWon = awards.count
        quick.nominations = entity.items("P1411").count
        quick.follows = follows.flatMap { labels[$0] }
        quick.followedBy = followedBy.flatMap { labels[$0] }
        quick.aspectRatios = ratios.compactMap { labels[$0] }
        quick.colour = colour.compactMap { labels[$0] }
        quick.notableAwards = Self.notable(awards.compactMap { labels[$0] })
        return quick
    }

    /// The awards for the cinematography, won first, each once (a nomination that was won is a win).
    static func cinematographyHonours(won: [String], nominated: [String]) -> [Honour] {
        func forTheCamera(_ name: String) -> Bool {
            let lowered = name.lowercased()
            // Not "Virtual Cinematography" (the effects team's).
            return ["cinematograph", "photography", "camerimage", "golden frog"].contains { lowered.contains($0) }
                && !lowered.contains("virtual")
        }
        var seen = Set<String>()
        let wins = won.filter(forTheCamera).filter { seen.insert($0).inserted }.map { Honour(name: $0, won: true) }
        let nods = nominated.filter(forTheCamera).filter { seen.insert($0).inserted }.map { Honour(name: $0, won: false) }
        return wins + nods
    }

    static let prestige = ["Academy Award", "Palme d'Or", "Golden Lion", "Golden Bear", "Golden Globe", "BAFTA", "British Academy", "Grand Prix", "Saturn Award"]

    /// The most prestigious awards first, at most five.
    static func notable(_ awards: [String]) -> [String] {
        func rank(_ name: String) -> Int { prestige.firstIndex { name.contains($0) } ?? prestige.count }
        var seen = Set<String>()
        return awards
            .filter { seen.insert($0).inserted }
            .enumerated()
            .sorted { rank($0.element) != rank($1.element) ? rank($0.element) < rank($1.element) : $0.offset < $1.offset }
            .prefix(5)
            .map { $0.element }
    }

    // MARK: Wikipedia

    struct Extracts: Decodable {
        struct Query: Decodable {
            struct Page: Decodable {
                let title: String?
                let extract: String?
            }
            let pages: [String: Page]?
        }
        let query: Query?
    }

    struct Search: Decodable {
        struct Query: Decodable {
            struct Hit: Decodable { let title: String }
            let search: [Hit]
        }
        let query: Query?
    }

    /// Fallback when Wikidata doesn't know the film: "Title (film)" or "Title (2021 film)"; a bare
    /// "Title" only with a check that the article is about a film.
    func searchArticle(title: String, year: Int?) async throws -> (title: String, isBareTitle: Bool)? {
        let query = "\(title) \(year.map { String($0) } ?? "") film"
        let search: Search = try await get("https://en.wikipedia.org/w/api.php", [
            "action": "query", "list": "search", "srsearch": query, "srlimit": "5", "format": "json",
        ])
        let hits = search.query?.search ?? []
        let accepted = Self.acceptedTitles(title: title, year: year)
        if let film = hits.first(where: { accepted.contains(TitleSimilarity.normalize($0.title)) }) {
            return (film.title, false)
        }
        let bare = TitleSimilarity.normalize(title)
        if let plain = hits.first(where: { TitleSimilarity.normalize($0.title) == bare }) {
            return (plain.title, true)
        }
        return nil
    }

    static func acceptedTitles(title: String, year: Int?) -> Set<String> {
        let wanted = TitleSimilarity.normalize(title)
        var accepted: Set<String> = [wanted + " film"]
        if let year { accepted.insert("\(wanted) \(year) film") }
        return accepted
    }

    func extract(title: String) async throws -> String? {
        let result: Extracts = try await get("https://en.wikipedia.org/w/api.php", [
            "action": "query", "prop": "extracts", "explaintext": "1", "exsectionformat": "wiki",
            "redirects": "1", "titles": title, "format": "json",
        ])
        return result.query?.pages?.values.first?.extract
    }

    private func get<T: Decodable>(_ base: String, _ parameters: [String: String]) async throws -> T {
        try await Wikimedia.get(base, parameters, session: session)
    }
}

/// Requests to Wikipedia and Wikidata: identified as Reel, two at a time, retried when busy.
enum Wikimedia {
    /// Who's asking: Wikimedia (and the craft sites the Cinematography tab reads) ask for a way to reach the maker.
    static let userAgent = "Reel/1.8 (personal macOS film library; https://github.com/alextervinsky-alt/reel-app)"

    /// At most two Wikimedia requests at a time, app-wide, as their API etiquette asks.
    static let gate = RequestGate(limit: 2)

    static func get<T: Decodable>(_ base: String, _ parameters: [String: String], session: URLSession,
                                  accept: String = "application/json") async throws -> T {
        var components = URLComponents(string: base)!
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        // Wikimedia asks for an identifying User-Agent with a way to reach the maker.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.timeoutInterval = 45

        await gate.acquire()
        var attempt = 0
        var result: (Data, Int) = (Data(), 0)
        do {
            repeat {
                attempt += 1
                result = try await send(request, session: session)
                if result.1 == 429 { try await Task.sleep(nanoseconds: 2_000_000_000) }
            } while result.1 == 429 && attempt < 3
        } catch {
            await gate.release()
            throw error
        }
        await gate.release()
        guard (200..<300).contains(result.1) else { throw TMDBError.badStatus(result.1) }
        return try JSONDecoder().decode(T.self, from: result.0)
    }

    private static func send(_ request: URLRequest, session: URLSession) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
                }
            }.resume()
        }
    }
}

/// Lets a limited number of tasks through at a time; the rest wait their turn.
public actor RequestGate {
    private var available: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int) {
        available = limit
    }

    public func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    public func release() {
        if waiting.isEmpty {
            available += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
