import Foundation

// Reel 1.10.7: who photographed a film and in which part of the production, what kind of source
// says each thing, where Reel looked for what was missing, and what it still doesn't know.
// Everything here is decided by fixed rules from what was read (no AI, no title-specific code).

/// The parts of a film's cinematography Reel researches.
public enum ResearchDimension: String, Codable, CaseIterable, Sendable {
    /// Who photographed it, and in which part of the production.
    case contributors
    /// Cameras, film or digital capture, recording format.
    case camera
    case lenses
    /// Handheld, Steadicam, cranes, how the camera moved and was operated.
    case movement
    case lighting
    /// Colour, contrast, the grade.
    case colour
    /// How the photography served visual effects: tracking, plates, witness cameras.
    case vfx

    public var title: String {
        switch self {
        case .contributors: "who shot it"
        case .camera: "camera and capture"
        case .lenses: "lenses"
        case .movement: "camera movement"
        case .lighting: "lighting"
        case .colour: "colour"
        case .vfx: "camera and visual effects"
        }
    }
}

/// The part of the production something is said of. Nil (unknown) when the source doesn't say.
public enum ProductionScope: String, Codable, CaseIterable, Sendable {
    case wholeFilm, principal, additional, reshoots, secondUnit, sequence, postProduction

    public var label: String {
        switch self {
        case .wholeFilm: "the whole film"
        case .principal: "principal photography"
        case .additional: "additional photography"
        case .reshoots: "reshoots"
        case .secondUnit: "second unit"
        case .sequence: "one sequence"
        case .postProduction: "post-production"
        }
    }

    /// What a sentence says of the part of the production it's about, in so many words. Nil when it
    /// doesn't say (most sentences): never guessed.
    public static func said(in sentence: String) -> ProductionScope? {
        let text = sentence.lowercased()
        func has(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
        if has(#"\bre-?shoots?\b|\bre-?shot\b|\bre-?filmed\b|\bpick-?ups?\b"#) { return .reshoots }
        if has(#"\badditional (?:photography|filming|shooting)\b"#) { return .additional }
        if has(#"\bsecond[- ]unit\b|\b2nd[- ]unit\b|\bsplinter unit\b|\baerial unit\b"#) { return .secondUnit }
        if has(#"\b(?:in post|post-production|postproduction|in the grade|digital intermediate|the di\b|colou?r grad\w*|colou?rist)"#) { return .postProduction }
        if has(#"\b(?:the (?:entire|whole) (?:film|movie|picture|shoot)|throughout the (?:film|movie|shoot))\b"#) { return .wholeFilm }
        if has(#"\b(?:principal photography|the main unit|main-unit)\b"#) { return .principal }
        if has(#"\b(?:the|this|that) (?:\w+[- ])?(?:sequence|scene|shot|set ?piece)\b"#) { return .sequence }
        return nil
    }
}

/// What kind of statement something is, by where it was read and how it's said.
public enum EvidenceKind: String, Codable, CaseIterable, Sendable {
    /// The cinematographer or director, in their own words.
    case productionStatement
    /// Another crew member in their own words (an operator, the VFX supervisor).
    case crewTestimony
    /// A camera, lens or film maker's account of its use on the production.
    case manufacturerCaseStudy
    /// Reported by a craft or technical publication.
    case technicalTrade
    /// Reported by general press or an encyclopedia.
    case secondaryReporting
    /// A professional's analysis of the finished film: what the images show, not what was used.
    case professionalAnalysis
    /// A credits or equipment database: a lead, not evidence.
    case databaseLead

    public var label: String {
        switch self {
        case .productionStatement: "the filmmakers' own words"
        case .crewTestimony: "a crew member's own words"
        case .manufacturerCaseStudy: "the manufacturer's account"
        case .technicalTrade: "technical reporting"
        case .secondaryReporting: "general reporting"
        case .professionalAnalysis: "a cinematographer's analysis"
        case .databaseLead: "a credits database"
        }
    }
}

// MARK: - Contributors

/// The camera, lighting, colour and VFX people of a film, with what they did and in which part.
public enum CraftCrew {
    public enum Role: String, Codable, CaseIterable, Sendable {
        case cinematographer, additionalCinematographer, secondUnitCinematographer, cameraOperator, steadicamOperator
        case gaffer, keyGrip, digitalImaging, colourist, vfxSupervisor

        public var title: String {
            switch self {
            case .cinematographer: "Director of photography"
            case .additionalCinematographer: "Additional photography"
            case .secondUnitCinematographer: "Second unit director of photography"
            case .cameraOperator: "Camera operator"
            case .steadicamOperator: "Steadicam operator"
            case .gaffer: "Gaffer"
            case .keyGrip: "Key grip"
            case .digitalImaging: "Digital imaging technician"
            case .colourist: "Colourist"
            case .vfxSupervisor: "Visual effects supervisor"
            }
        }

        /// The part of the production the role works on, when the role says it.
        public var scope: ProductionScope? {
            switch self {
            case .additionalCinematographer: .additional
            case .secondUnitCinematographer: .secondUnit
            case .colourist: .postProduction
            default: nil
            }
        }

        /// What someone in the role can speak to first-hand.
        public var dimensions: Set<ResearchDimension> {
            switch self {
            case .cinematographer, .additionalCinematographer, .secondUnitCinematographer: [.camera, .lenses, .movement, .lighting, .colour]
            case .cameraOperator, .steadicamOperator, .keyGrip: [.movement]
            case .gaffer: [.lighting]
            case .digitalImaging: [.camera, .colour]
            case .colourist: [.colour]
            case .vfxSupervisor: [.vfx]
            }
        }

        /// A director of photography of some part of the film.
        public var photographs: Bool { [.cinematographer, .additionalCinematographer, .secondUnitCinematographer].contains(self) }
    }

    public struct Contributor: Codable, Equatable, Sendable {
        public let name: String
        public let role: Role
        /// The part of the production, when the credit or the sentence says it.
        public var scope: ProductionScope?
        /// Credited on TMDB, or named only in what was read ("Robert Richardson was originally…").
        public var credited = true

        public init(name: String, role: Role, scope: ProductionScope? = nil, credited: Bool = true) {
            self.name = name
            self.role = role
            self.scope = scope
            self.credited = credited
        }

        /// "Steadicam operator Larry McConkey".
        public var described: String { role.title + " " + name + (credited ? "" : " (named in what was read)") }
    }

    /// TMDB's jobs for each role, in credit order of importance.
    public static let jobs: [(role: Role, jobs: Set<String>)] = [
        (.cinematographer, ["Director of Photography"]),
        (.additionalCinematographer, ["Additional Director of Photography", "Additional Photography", "Aerial Director of Photography",
                                      "Underwater Director of Photography"]),
        (.secondUnitCinematographer, ["Second Unit Director of Photography"]),
        (.steadicamOperator, ["Steadicam Operator"]),
        (.cameraOperator, ["Camera Operator", "\"A\" Camera Operator", "\"B\" Camera Operator", "\"C\" Camera Operator",
                           "Additional Camera Operator"]),
        (.gaffer, ["Gaffer", "Chief Lighting Technician"]),
        (.keyGrip, ["Key Grip"]),
        (.digitalImaging, ["Digital Imaging Technician"]),
        (.colourist, ["Colorist", "Digital Intermediate Colorist", "Supervising Colorist", "Senior Colorist"]),
        (.vfxSupervisor, ["Visual Effects Supervisor"]),
    ]

    /// Every job above, and the focus pullers the Cinematography tab lists: kept with the film's
    /// details (`TMDBMovieDetails.trimmed`).
    public static let keptJobs: Set<String> = jobs.reduce(into: Set<String>()) { $0.formUnion($1.jobs) }.union([
        "First Assistant Camera", "\"A\" First Assistant Camera", "First Assistant \"A\" Camera",
        "\"B\" First Assistant Camera", "First Assistant \"B\" Camera",
    ])

    /// The film's credited crew in these roles (each person once per role, at most four per role).
    public static func credited(_ details: TMDBMovieDetails?) -> [Contributor] {
        guard let details else { return [] }
        var found: [Contributor] = []
        for entry in jobs {
            for person in details.people(forJobs: entry.jobs).prefix(4)
            where !found.contains(where: { $0.name == person.name && $0.role == entry.role }) {
                found.append(Contributor(name: person.name, role: entry.role, scope: entry.role.scope))
            }
        }
        return found
    }

    /// Directors of photography named in what was read but not credited ("Robert Richardson was
    /// originally hired as the cinematographer"), with the part the sentence says when it says one.
    /// A name is two or three capitalised words right by "cinematographer" or "director of photography".
    public static func named(in paragraphs: [String], besides known: [Contributor]) -> [Contributor] {
        let patterns = [
            #"\b(?:cinematographer|director of photography|DoP|DP)\s+([A-Z][\p{L}'’.-]+(?:\s+[A-Z][\p{L}'’.-]+){1,2})"#,
            #"\b([A-Z][\p{L}'’.-]+(?:\s+[A-Z][\p{L}'’.-]+){1,2}),?\s+(?:who|was|had been|as)\s+(?:originally\s+|initially\s+|first\s+)?(?:hired\s+|brought on\s+|signed\s+)?(?:as\s+)?(?:the\s+)?(?:film's\s+)?(?:cinematographer|director of photography)\b"#,
        ]
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        let stop: Set<String> = ["The", "A", "An", "His", "Her", "Their", "Academy", "Award", "Society", "American", "British", "Best"]
        var found: [Contributor] = []
        for paragraph in paragraphs {
            for sentence in Digest.sentences(in: paragraph) {
                for regex in regexes {
                    for match in regex.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) {
                        guard let range = Range(match.range(at: 1), in: sentence) else { continue }
                        let name = String(sentence[range]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.’'"))
                        let words = name.split(separator: " ").map(String.init)
                        guard words.count >= 2, !words.contains(where: stop.contains) else { continue }
                        guard !known.contains(where: { $0.name == name }), !found.contains(where: { $0.name == name }) else { continue }
                        let scope = ProductionScope.said(in: sentence)
                            ?? (sentence.range(of: #"\b(?:originally|initially|first|replaced|left the (?:film|project|production)|departed|exited)\b"#,
                                                options: .regularExpression) != nil ? .principal : nil)
                        let role: Role = scope == .secondUnit ? .secondUnitCinematographer
                            : [.additional, .reshoots].contains(scope) ? .additionalCinematographer : .cinematographer
                        found.append(Contributor(name: name, role: role, scope: scope, credited: false))
                    }
                }
            }
        }
        return Array(found.prefix(4))
    }

    /// Who in `crew` a sentence names: the whole name, or the surname (four letters or more) of
    /// someone whose role it is. The first named.
    public static func named(in sentence: String, crew: [Contributor]) -> Contributor? {
        let folded = CameraSources.fold(sentence)
        for person in crew {
            let whole = CameraSources.fold(person.name)
            if folded.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: whole) + #"\b"#, options: .regularExpression) != nil {
                return person
            }
        }
        for person in crew {
            guard let surname = person.name.split(separator: " ").last.map(String.init), surname.count >= 4 else { continue }
            if sentence.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: surname) + #"\b"#, options: .regularExpression) != nil {
                return person
            }
        }
        return nil
    }
}

// MARK: - Sources

/// The sites Reel reads, what kind of source each is, and what kind of claim it's good for. Not a
/// trust score: a VFX publication is a strong source for camera tracking and plates and says
/// nothing authoritative about the whole camera package.
public enum SourceRegistry {
    public enum Family: String, Codable, Sendable {
        /// American Cinematographer, British Cinematographer…: interviews and production pieces.
        case cinematographyPublication
        /// ARRI, Kodak, Panavision…: the maker's account of its gear on a production.
        case manufacturer
        /// fxguide, Animation World Network, Post Magazine…: VFX and post-production reporting.
        case productionTechnology
        /// A visual-effects company's own pages about its work on a film.
        case vfxVendor
        /// General press: only its pieces about the shooting are read.
        case news
        /// Credits and equipment databases: leads, not evidence.
        case creditDatabase
        /// The film's and the cinematographer's Wikipedia articles.
        case encyclopedia
    }

    public struct Entry: Sendable {
        public let host: String
        public let name: String
        public let family: Family
        /// What it's good for.
        public let claims: Set<ResearchDimension>
        /// Its own WordPress search (`/wp-json/wp/v2/search`), when it has a working one: searched by
        /// a film's title for what's missing.
        public var search: URL? = nil
    }

    static let all: Set<ResearchDimension> = Set(ResearchDimension.allCases)

    /// The research sites added in 1.10.7, besides those `CameraSources` has read since 1.9
    /// (`craftSites`, `newsSites`, whose families are below). Each was checked to publish
    /// production-specific pieces; only those with a search that answers are searched.
    public static let added: [Entry] = [
        Entry(host: "fxguide.com", name: "fxguide", family: .productionTechnology, claims: [.vfx, .movement, .camera]),
        Entry(host: "awn.com", name: "Animation World Network", family: .productionTechnology, claims: [.vfx]),
        Entry(host: "postmag.com", name: "Post Magazine", family: .productionTechnology, claims: [.vfx, .colour]),
        Entry(host: "cgw.com", name: "Computer Graphics World", family: .productionTechnology, claims: [.vfx]),
        Entry(host: "beforesandafters.com", name: "befores & afters", family: .productionTechnology, claims: [.vfx, .movement]),
        Entry(host: "vfxvoice.com", name: "VFX Voice", family: .productionTechnology, claims: [.vfx]),
        Entry(host: "cinesite.com", name: "Cinesite", family: .vfxVendor, claims: [.vfx, .movement],
              search: URL(string: "https://cinesite.com/wp-json/wp/v2/search")),
        Entry(host: "dneg.com", name: "DNEG", family: .vfxVendor, claims: [.vfx]),
        Entry(host: "catalog.afi.com", name: "AFI Catalog", family: .creditDatabase, claims: [.contributors]),
        Entry(host: "shotonwhat.com", name: "ShotOnWhat", family: .creditDatabase, claims: [.camera, .lenses]),
        Entry(host: "imdb.com", name: "IMDb", family: .creditDatabase, claims: [.contributors]),
    ]

    static let manufacturers: Set<String> = ["Kodak", "ARRI", "Panavision", "Cooke Optics", "ZEISS"]

    /// The family of a source as `TechSpecs.Text.source` names it (nil: the film's Wikipedia article).
    public static func family(ofSource source: String?) -> Family {
        guard let source else { return .encyclopedia }
        if source.hasPrefix("Wikipedia") { return .encyclopedia }
        if let entry = added.first(where: { $0.name == source }) { return entry.family }
        if manufacturers.contains(source) { return .manufacturer }
        if CameraSources.newsSites.contains(where: { $0.name == source }) { return .news }
        return .cinematographyPublication
    }

    /// The entry for a host ("www.fxguide.com", "cinesite.com").
    public static func entry(host: String) -> Entry? {
        let host = host.lowercased()
        return added.first { host == $0.host || host.hasSuffix("." + $0.host) }
    }

    /// Whether what a source of this family says can make a Shot on tag or a camera, lens or
    /// format of the sheet. A VFX publication or vendor reports what it needed (every camera fitted
    /// with an encoder), not the production's camera package; a database is only a lead.
    public static func establishesCapture(_ family: Family) -> Bool {
        ![.productionTechnology, .vfxVendor, .creditDatabase].contains(family)
    }

    /// What kind of statement a note is: where it was read, and whether it's someone's own words.
    /// `speaker`: the crew member the sentence names, when it names one.
    public static func evidence(source: String?, text: String, isInterview: Bool, speaker: CraftCrew.Contributor?) -> EvidenceKind {
        let family = family(ofSource: source)
        let ownWords = text.contains("“") || text.contains("\"") || isInterview
            && text.range(of: #"\b(?:I|we|my|our)\b"#, options: .regularExpression) != nil
        // Someone looking at the finished film (no one of its crew speaking, in a piece that isn't
        // an interview): an analysis, however expert, not testimony.
        if speaker == nil, !isInterview, family != .encyclopedia, family != .creditDatabase,
           text.range(of: #"\b(?:we (?:can )?see|notice how|in my (?:opinion|view)|I (?:think|believe|suspect)|it (?:seems|looks like)|appears to (?:have|be)|one can see|the viewer)\b"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return .professionalAnalysis
        }
        switch family {
        case .creditDatabase: return .databaseLead
        case .manufacturer: return .manufacturerCaseStudy
        case .encyclopedia, .news:
            if ownWords, let speaker { return speaker.role.photographs ? .productionStatement : .crewTestimony }
            return .secondaryReporting
        case .productionTechnology, .vfxVendor, .cinematographyPublication:
            if ownWords {
                if let speaker { return speaker.role.photographs ? .productionStatement : .crewTestimony }
                // A quote from someone not of the film's crew (a VFX company's supervisor): reporting.
                if family == .cinematographyPublication { return .productionStatement }
            }
            return .technicalTrade
        }
    }
}

// MARK: - What's missing, and where to look

/// The bounded extra searches for what a film's reading is missing (discovery 6). Old budget, per
/// film: two magazine searches, Wikipedia's links, three guessed story pages and the
/// cinematographer's article; at most 8 pages asked for and 6 read. New: at most `maxQueries`
/// more searches, and their pages only in the slots the first pass left (never more than 8 asked
/// for and 6 read in all), at most `maxPages` of them.
public enum ResearchPlan {
    public static let maxQueries = 4
    public static let maxPages = 3
    /// A search that found nothing usable isn't repeated for this long (same discovery).
    public static let quietPeriod: TimeInterval = 365 * 86_400

    public struct Query: Codable, Equatable, Sendable {
        public let dimension: ResearchDimension
        /// The site searched ("American Cinematographer", "Cinesite").
        public let site: String
        /// What was searched for: a person's name, or the film's title.
        public let text: String
        /// The person searched for, when it's a person.
        public var contributor: String?
        /// The other missing dimensions the same search speaks to (a cinematographer searched for
        /// the light is searched for the lenses and colour too): one search, not three.
        public var also: [ResearchDimension] = []

        /// Whether the search was made for `dimension`.
        public func covers(_ dimension: ResearchDimension) -> Bool { self.dimension == dimension || also.contains(dimension) }

        public var key: String { site + "|" + text.lowercased() }
    }

    /// Searches that need no planning: a site searched by the film's title (American and British
    /// Cinematographer always are, in the first pass).
    static let byTitleFirstPass: Set<String> = ["American Cinematographer", "British Cinematographer"]

    /// What to search for, most useful first: for each dimension nothing was found for, the people
    /// whose role speaks to it (searched by name on American Cinematographer, whose interviews are
    /// titled by subject rather than film), and for camera and VFX work, the VFX sites that have a
    /// search (by the film's title). None for what's already known, a search repeated within a year
    /// that found nothing, or the same query twice.
    public static func plan(missing: [ResearchDimension], crew: [CraftCrew.Contributor], title: String,
                            previous: [ResearchEntry]?, discovery: Int = CraftIndex.currentDiscovery,
                            readAt: Date? = nil, now: Date = Date()) -> [Query] {
        let quiet = Set(Self.quiet(previous, discovery: discovery, readAt: readAt, now: now).flatMap(\.queries))
        var queries: [Query] = []
        func add(_ query: Query) {
            guard !quiet.contains(query.key) else { return }
            if let same = queries.firstIndex(where: { $0.key == query.key }) {
                if !queries[same].covers(query.dimension) { queries[same].also.append(query.dimension) }
                return
            }
            guard queries.count < maxQueries else { return }
            queries.append(query)
        }
        let order: [ResearchDimension] = [.movement, .lighting, .camera, .lenses, .vfx, .colour]
        for dimension in order where missing.contains(dimension) {
            if dimension == .vfx {
                for entry in SourceRegistry.added where entry.search != nil && entry.claims.contains(.vfx) {
                    add(Query(dimension: .vfx, site: entry.name, text: title))
                }
                continue
            }
            // The specialists first (an operator for movement, a gaffer for light), then whoever
            // photographed it.
            let people = crew.filter { $0.role.dimensions.contains(dimension) && !$0.role.photographs }
                + crew.filter { $0.role.dimensions.contains(dimension) && $0.role.photographs }
            for person in people.prefix(1) {
                add(Query(dimension: dimension, site: "American Cinematographer", text: person.name, contributor: person.name))
            }
        }
        return queries
    }

    /// The earlier entries whose searches found nothing within the last `quietPeriod` (by the same
    /// discovery): not searched again, and carried as they are (their date unchanged) so the year
    /// is counted from the search, not from the latest reading.
    public static func quiet(_ previous: [ResearchEntry]?, discovery: Int, readAt: Date?, now: Date = Date()) -> [ResearchEntry] {
        (previous ?? []).filter { entry in
            guard entry.state == .searchedNoSource, entry.discovery == discovery, !entry.queries.isEmpty,
                  let searched = entry.searchedAt ?? readAt else { return false }
            return now.timeIntervalSince(searched) < quietPeriod
        }
    }
}

/// What became of one planned search (for the log and coverage).
public struct ResearchOutcome: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        /// Not asked: no slot left among the pages to ask for or read.
        case notTried(String)
        /// The site didn't answer (the failure's own words).
        case unavailable(String)
        /// Answered; no result named the film or the person.
        case noCandidate(Int)
        /// Results asked for; none was about this film (or none could be read).
        case nothingUsable([String])
        /// Read: these pages.
        case read([String])
    }
    public let query: ResearchPlan.Query
    public var result: Result
}

/// What was looked for, in a film's reading: the people found, the searches planned for what was
/// missing and what they brought. For the log and the coverage; not kept in the library.
public struct ResearchRun: Equatable, Sendable {
    public var contributors: [CraftCrew.Contributor] = []
    public var missing: [ResearchDimension] = []
    public var outcomes: [ResearchOutcome] = []
    /// Earlier searches that found nothing, not repeated this time (see `ResearchPlan.quiet`).
    public var quiet: [ResearchEntry] = []

    public init(contributors: [CraftCrew.Contributor] = [], missing: [ResearchDimension] = [], outcomes: [ResearchOutcome] = [],
                quiet: [ResearchEntry] = []) {
        self.contributors = contributors
        self.missing = missing
        self.outcomes = outcomes
        self.quiet = quiet
    }
}

/// Where a film's research stands for one dimension, kept with its reading (`CraftIndex.research`).
public struct ResearchEntry: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        /// Found in what was read.
        case found
        /// Pages were read; none said anything of it.
        case readNoFindings
        /// Searched for; no suitable page was found.
        case searchedNoSource
        /// A page for it was found but couldn't be reached (read again later).
        case unavailable
        /// A page for it was found but its article couldn't be told apart, or it was too thin.
        case extractionFailed
        /// A page for it was found in a language Reel doesn't read.
        case unsupportedLanguage
        /// Not looked for beyond the first pass (no slot left, or nothing to search by).
        case notSearched
        /// Saved by a later Reel with a state this one doesn't know.
        case unknown

        public init(from decoder: Decoder) throws {
            self = State(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }

        /// In the order shown (found first; the unknown not shown).
        public static let shown: [State] = [.found, .readNoFindings, .searchedNoSource, .unavailable, .extractionFailed,
                                            .unsupportedLanguage, .notSearched]

        public var label: String {
            switch self {
            case .found: "found"
            case .readNoFindings: "read about, nothing said"
            case .searchedNoSource: "searched for, no source found"
            case .unavailable: "a source didn't answer"
            case .extractionFailed: "a source couldn't be read"
            case .unsupportedLanguage: "a source in a language Reel doesn't read"
            case .notSearched: "not searched for yet"
            case .unknown: "unknown"
            }
        }
    }

    public let dimension: ResearchDimension
    public let state: State
    /// The planned searches made for it (`ResearchPlan.Query.key`), so one that found nothing
    /// isn't repeated within a year.
    public var queries: [String] = []
    /// The discovery that made it.
    public var discovery: Int = CraftIndex.currentDiscovery
    /// When its searches were made (none: nothing was searched for it).
    public var searchedAt: Date?

    public init(dimension: ResearchDimension, state: State, queries: [String] = [], discovery: Int = CraftIndex.currentDiscovery,
                searchedAt: Date? = nil) {
        self.dimension = dimension
        self.state = state
        self.queries = queries
        self.discovery = discovery
        self.searchedAt = searchedAt
    }

    enum CodingKeys: String, CodingKey { case dimension, state, queries, discovery, searchedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A dimension a later Reel added: read as the nearest this one knows (never dropped).
        dimension = (try? c.decode(ResearchDimension.self, forKey: .dimension)) ?? .contributors
        state = try c.decodeIfPresent(State.self, forKey: .state) ?? .unknown
        queries = try c.decodeIfPresent([String].self, forKey: .queries) ?? []
        discovery = try c.decodeIfPresent(Int.self, forKey: .discovery) ?? 6
        searchedAt = try c.decodeIfPresent(Date.self, forKey: .searchedAt)
    }
}

public enum ResearchCoverage {
    /// What was found, by dimension, in a film's reading.
    public static func found(in specs: TechSpecs, crew: [CraftCrew.Contributor]) -> Set<ResearchDimension> {
        var found = Set<ResearchDimension>()
        if !crew.isEmpty { found.insert(.contributors) }
        if !specs.names(.camera).isEmpty || specs.specs.contains(where: { $0.kind == .format && !$0.name.contains(":1") }) { found.insert(.camera) }
        if !specs.names(.lens).isEmpty { found.insert(.lenses) }
        if !specs.names(.support).isEmpty || !specs.cameraLanguage.isEmpty { found.insert(.movement) }
        if !specs.names(.light).isEmpty || !specs.lighting.isEmpty { found.insert(.lighting) }
        if !specs.colour.isEmpty || !specs.names(.finish).isEmpty { found.insert(.colour) }
        if !specs.cameraVFX.isEmpty { found.insert(.vfx) }
        return found
    }

    /// Where each dimension stands after a reading: found; else, by what the planned searches for it
    /// brought; else, pages were read (`readSomething`) and said nothing of it, or nothing was.
    public static func entries(found: Set<ResearchDimension>, run: ResearchRun?, readSomething: Bool,
                               languageLimited: Bool, extractionLimited: Bool = false,
                               discovery: Int = CraftIndex.currentDiscovery, now: Date = Date()) -> [ResearchEntry] {
        ResearchDimension.allCases.map { dimension in
            let outcomes = (run?.outcomes ?? []).filter { $0.query.covers(dimension) }
            let keys = outcomes.filter {
                if case .notTried = $0.result { return false }
                return true
            }.map(\.query.key)
            let searchedAt: Date? = keys.isEmpty ? nil : now
            if found.contains(dimension) {
                return ResearchEntry(dimension: dimension, state: .found, queries: keys, discovery: discovery, searchedAt: searchedAt)
            }
            // Searched within the year and nothing found: still so (not "not searched").
            if keys.isEmpty, let carried = run?.quiet.first(where: { $0.dimension == dimension }) { return carried }
            let state: ResearchEntry.State
            if outcomes.contains(where: { if case .unavailable = $0.result { return true } else { return false } }) {
                state = .unavailable
            } else if outcomes.contains(where: { if case .read = $0.result { return true } else { return false } }) {
                state = .readNoFindings
            } else if !keys.isEmpty {
                state = .searchedNoSource
            } else if languageLimited {
                state = .unsupportedLanguage
            } else if extractionLimited, !readSomething {
                state = .extractionFailed
            } else {
                state = readSomething ? .readNoFindings : .notSearched
            }
            return ResearchEntry(dimension: dimension, state: state, queries: keys, discovery: discovery, searchedAt: searchedAt)
        }
    }
}
