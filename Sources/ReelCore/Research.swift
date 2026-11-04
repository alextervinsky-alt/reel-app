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
    /// originally hired as the cinematographer"). Only a sentence about this film: in its own
    /// article, one that names the film or tells of a change of crew (hired, replaced, left,
    /// reshoots, second unit); anywhere else, one that names the film. "Nolan's longtime
    /// cinematographer Wally Pfister" in passing isn't this film's crew. The part of the production
    /// only when the sentence says it (`ProductionScope.said`); never guessed.
    /// A name is two or three capitalised words right by "cinematographer" or "director of photography".
    public static func named(article: [String], sources: [String], title: String, besides known: [Contributor]) -> [Contributor] {
        let patterns = [
            #"\b(?:cinematographer|director of photography|DoP|DP)\s+([A-Z][\p{L}'’.-]+(?:\s+[A-Z][\p{L}'’.-]+){1,2})"#,
            #"\b([A-Z][\p{L}'’.-]+(?:\s+[A-Z][\p{L}'’.-]+){1,2}),?\s+(?:who|was|had been|as)\s+(?:originally\s+|initially\s+|first\s+)?(?:hired\s+|brought on\s+|signed\s+)?(?:as\s+)?(?:the\s+)?(?:film's\s+)?(?:cinematographer|director of photography)\b"#,
        ]
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        let stop: Set<String> = ["The", "A", "An", "His", "Her", "Their", "Academy", "Award", "Society", "American", "British", "Best"]
        let shortTitle = title.split(separator: ":").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? title
        func namesFilm(_ sentence: String) -> Bool {
            !shortTitle.isEmpty && sentence.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: shortTitle) + #"\b"#,
                                                  options: .regularExpression) != nil
        }
        let change = #"\b(?:originally|initially|replac\w*|left the (?:film|project|production)|departed|exited|took over|stepped in|re-?shoots?|additional photography|second[- ]unit)\b"#
        var found: [Contributor] = []
        let all = article.map { ($0, true) } + sources.map { ($0, false) }
        for (paragraph, own) in all {
            for sentence in Digest.sentences(in: paragraph) {
                let titled = namesFilm(sentence)
                // In the film's own article, a change of crew said of this person: the word within a
                // few words of the name ("Pfister, who originally worked with Nolan on…" isn't one).
                let changes: [Range<String.Index>] = own && !titled ? Self.ranges(of: change, in: sentence) : []
                guard titled || !changes.isEmpty else { continue }
                for regex in regexes {
                    for match in regex.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) {
                        guard let range = Range(match.range(at: 1), in: sentence) else { continue }
                        let name = String(sentence[range]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.’'"))
                        let words = name.split(separator: " ").map(String.init)
                        guard words.count >= 2, !words.contains(where: stop.contains), name != shortTitle,
                              !shortTitle.contains(name) else { continue }
                        guard !known.contains(where: { $0.name == name }), !found.contains(where: { $0.name == name }) else { continue }
                        if !titled {
                            // At most three words between them, the role's own words aside.
                            let near = changes.contains { change in
                                let between = change.lowerBound >= range.upperBound
                                    ? String(sentence[range.upperBound..<change.lowerBound]) : String(sentence[change.upperBound..<range.lowerBound])
                                let words = between.replacingOccurrences(of: #"(?i)\b(?:cinematographer|director of photography|DoP|DP|the|as)\b"#,
                                                                         with: " ", options: .regularExpression)
                                    .split { !$0.isLetter }
                                return words.count <= 3
                            }
                            guard near else { continue }
                        }
                        let scope = ProductionScope.said(in: sentence)
                        let role: Role = scope == .secondUnit ? .secondUnitCinematographer
                            : [.additional, .reshoots].contains(scope) ? .additionalCinematographer : .cinematographer
                        found.append(Contributor(name: name, role: role, scope: scope, credited: false))
                    }
                }
            }
        }
        return Array(found.prefix(4))
    }

    static func ranges(of pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }

    /// Whose words a sentence gives: a crew member named as the speaker ("…,” Marsh says;
    /// "McConkey recalls…"; "according to Ben Seresin"), by the whole name or the surname (four
    /// letters or more, not followed by another capitalised word: "said Martin Campbell" isn't
    /// Stephanie Martin). A name only mentioned ("Forster told Seresin…") isn't the speaker.
    public static func speaker(in sentence: String, crew: [Contributor]) -> Contributor? {
        let verbs = #"(?:says|said|explains|explained|recalls|recalled|notes|noted|adds|added|remembers|remembered|tells us|told us|describes|described|admits|admitted|continues|continued|observes|observed|reflects|reflected)"#
        for person in crew {
            var names = [NSRegularExpression.escapedPattern(for: person.name)]
            if let surname = person.name.split(separator: " ").last.map(String.init), surname.count >= 4, surname != person.name {
                names.append(NSRegularExpression.escapedPattern(for: surname))
            }
            for name in names {
                let after = #"(?![\s-]+[A-Z])"#
                let patterns = [
                    #"\b"# + name + after + #",?\s+(?:\w+\s+)?"# + verbs + #"\b"#,
                    // "…,” says Marsh" (verb first only right after the quote: "Forster said Seresin
                    // brought…" is Forster speaking).
                    #"[”"’],?\s*"# + verbs + #"\s+(?:\w+\s+)?"# + name + #"\b"# + after,
                    #"\b[Aa]ccording to\s+(?:\w+\s+)?"# + name + #"\b"# + after,
                ]
                if patterns.contains(where: { sentence.range(of: $0, options: .regularExpression) != nil }) { return person }
            }
        }
        return nil
    }

    /// Whether a sentence gives someone's words: a quoted span of a sentence's length (not a title
    /// in quotes, “Mank”).
    public static func quotes(_ sentence: String) -> Bool {
        sentence.range(of: #"[“"][^”"]{20,}[”"]|[“"][^”"]{20,}$"#, options: .regularExpression) != nil
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
        Entry(host: "cinesite.com", name: "Cinesite", family: .vfxVendor, claims: [.vfx, .movement]),
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
        let ownWords = CraftCrew.quotes(text) || isInterview
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
                // Whose words isn't said: in a cinematography magazine's interview, the filmmakers';
                // otherwise (a critic, a VFX company's supervisor) reporting.
                if family == .cinematographyPublication, isInterview { return .productionStatement }
            }
            return .technicalTrade
        }
    }
}

// MARK: - Research questions (1.10.8)

/// What Reel can know about a film's research context before planning: who photographed it, what
/// was read, and whether the film involves visual effects at all (a film with no VFX credit and no
/// mention of effects has no camera-and-VFX questions: they're not applicable, not unanswered).
public struct ResearchContext: Sendable {
    public let crew: [CraftCrew.Contributor]
    public let specs: TechSpecs
    public let vfxRelevant: Bool

    public init(crew: [CraftCrew.Contributor], specs: TechSpecs, texts: [TechSpecs.Text]) {
        self.crew = crew
        self.specs = specs
        let mentions = texts.flatMap { $0.sections.flatMap(\.paragraphs) }.contains {
            $0.range(of: #"\b(?:visual effects|VFX|CGI|CG |computer[- ]generated|digital effects|green ?screen|blue ?screen)\b"#,
                     options: [.regularExpression, .caseInsensitive]) != nil
        }
        vfxRelevant = crew.contains { $0.role == .vfxSupervisor } || !specs.cameraVFX.isEmpty || mentions
    }
}

/// One reusable research question: what it asks, which part of the cinematography it belongs to,
/// who can answer it first-hand, when it applies and when it's answered. Answered by what was read
/// (never by a credit alone: a gaffer's credit says nothing of the fixtures).
public struct ResearchQuestion: Sendable {
    public let id: String
    public let dimension: ResearchDimension
    public let purpose: String
    /// The roles to search by, best first (the specialist before the cinematographer).
    public let roles: [CraftCrew.Role]
    let applies: @Sendable (ResearchContext) -> Bool
    let answered: @Sendable (TechSpecs) -> Bool

    public func isApplicable(_ context: ResearchContext) -> Bool { applies(context) }
    public func isAnswered(_ specs: TechSpecs) -> Bool { answered(specs) }
}

public enum ResearchQuestions {
    static let dp: [CraftCrew.Role] = [.cinematographer, .additionalCinematographer, .secondUnitCinematographer]
    static func notes(_ notes: [TechSpecs.Note], _ pattern: String) -> Bool {
        notes.contains { $0.text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
    }
    static let always: @Sendable (ResearchContext) -> Bool = { _ in true }
    static let vfx: @Sendable (ResearchContext) -> Bool = { $0.vfxRelevant }

    /// The catalogue, in the order questions are worth asking within a dimension.
    public static let catalogue: [ResearchQuestion] = [
        ResearchQuestion(id: "camera.capture", dimension: .camera, purpose: "film or digital capture", roles: dp + [.digitalImaging],
                         applies: always, answered: { specs in
                             specs.specs.contains { $0.capture && !CraftIndex.shotOn($0).intersection([.film, .digital, .imax]).isEmpty }
                         }),
        ResearchQuestion(id: "camera.system", dimension: .camera, purpose: "which cameras", roles: dp + [.digitalImaging, .cameraOperator],
                         applies: always, answered: { !$0.names(.camera).isEmpty }),
        ResearchQuestion(id: "lenses.family", dimension: .lenses, purpose: "which lenses", roles: dp,
                         applies: always, answered: { !$0.names(.lens).isEmpty }),
        ResearchQuestion(id: "movement.method", dimension: .movement, purpose: "how the camera moved",
                         roles: [.steadicamOperator, .cameraOperator, .keyGrip] + dp,
                         applies: always, answered: { !$0.names(.support).isEmpty || !$0.cameraLanguage.isEmpty }),
        ResearchQuestion(id: "lighting.approach", dimension: .lighting, purpose: "how it was lit", roles: [.gaffer] + dp,
                         applies: always, answered: { !$0.lighting.isEmpty || !$0.names(.light).isEmpty }),
        ResearchQuestion(id: "lighting.sources", dimension: .lighting, purpose: "which lights", roles: [.gaffer] + dp,
                         applies: always, answered: { !$0.names(.light).isEmpty }),
        ResearchQuestion(id: "colour.image", dimension: .colour, purpose: "how the image was treated", roles: [.colourist] + dp,
                         applies: always, answered: { !$0.colour.isEmpty || !$0.names(.finish).isEmpty }),
        ResearchQuestion(id: "colour.workflow", dimension: .colour, purpose: "the grade and its workflow", roles: [.colourist] + dp,
                         applies: always, answered: { !$0.names(.finish).isEmpty }),
        ResearchQuestion(id: "vfx.photography", dimension: .vfx, purpose: "how the photography served the effects",
                         roles: [.vfxSupervisor] + dp, applies: vfx, answered: { !$0.cameraVFX.isEmpty }),
        ResearchQuestion(id: "vfx.tracking", dimension: .vfx, purpose: "tracking, encoders and witness cameras",
                         roles: [.vfxSupervisor] + dp, applies: vfx, answered: {
                             notes($0.cameraVFX, #"\b(?:track\w*|encoder\w*|witness|match ?mov\w*|motion[- ]control|markers?)\b"#)
                         }),
        ResearchQuestion(id: "vfx.plates", dimension: .vfx, purpose: "plates, arrays and reference photography",
                         roles: [.vfxSupervisor] + dp, applies: vfx, answered: {
                             notes($0.cameraVFX, #"\b(?:plates?|arrays?|stitched|panoram\w*|HDRI?s?|reference photo\w*|green ?screen|blue ?screen)\b"#)
                         }),
    ]

    public static func question(_ id: String) -> ResearchQuestion? { catalogue.first { $0.id == id } }
}

// MARK: - Sources to search (1.10.8)

/// A source Reel can search for a film's research: who it is, what kind of source, how it can be
/// searched (by a person's name, by the film's title) and which parts of the cinematography it can
/// speak to. The engine plans by these capabilities; how a search is made is the transport's.
public struct ResearchProvider: Sendable, Equatable {
    public enum SearchBy: String, Sendable { case person, title }
    public let name: String
    public let host: String
    public let family: SourceRegistry.Family
    public let search: URL
    public let searchBy: Set<SearchBy>
    public let serves: Set<ResearchDimension>
    public let languages: Set<String>

    public init(name: String, host: String, family: SourceRegistry.Family, search: URL, searchBy: Set<SearchBy>,
                serves: Set<ResearchDimension>, languages: Set<String> = ["en"]) {
        self.name = name
        self.host = host
        self.family = family
        self.search = search
        self.searchBy = searchBy
        self.serves = serves
        self.languages = languages
    }

    static let camera: Set<ResearchDimension> = [.camera, .lenses, .movement, .lighting, .colour, .vfx]

    /// Every provider with a search that answers (checked live before it was added), in the order
    /// tried for a question.
    public static let all: [ResearchProvider] = [
        ResearchProvider(name: "American Cinematographer", host: "theasc.com", family: .cinematographyPublication,
                         search: URL(string: "https://theasc.com/wp-json/wp/v2/search")!, searchBy: [.person], serves: camera),
        ResearchProvider(name: "Cinesite", host: "cinesite.com", family: .vfxVendor,
                         search: URL(string: "https://cinesite.com/wp-json/wp/v2/search")!, searchBy: [.title], serves: [.vfx]),
        // Checked live on 4 Nov 2026: its search answers by person with craft interviews, and its
        // articles are told apart by its container. (Newsshooter's search answers too, but the
        // article checked read as two paragraphs; Filmmaker's search sent a challenge page and
        // Definition's redirects loop: not added.)
        ResearchProvider(name: "ProVideo Coalition", host: "provideocoalition.com", family: .cinematographyPublication,
                         search: URL(string: "https://www.provideocoalition.com/wp-json/wp/v2/search")!, searchBy: [.person], serves: camera),
    ]

    public static func named(_ name: String) -> ResearchProvider? { all.first { $0.name == name } }
}

/// How the engine reaches providers and pages: production uses `CameraSourcesClient` (paced,
/// HTTPS, its article reader); the benchmark an in-memory corpus. The engine never knows which.
public protocol ResearchTransport: Sendable {
    func researchSearch(_ provider: ResearchProvider, query: String, noting: UnansweredSites) async
        -> (hits: [(title: String, url: String)], failure: String?)
    func researchPage(_ url: URL, site: String, title: String?, noting: UnansweredSites) async
        -> (source: CameraReading.Source?, failure: SourceFailure?)
}

// MARK: - Planning

/// The bounded extra searches for a film's open research questions (discovery 7). At most
/// `maxQueries` searches and `maxPages` pages per reading, and the pages only in the slots the first
/// pass left (never more than 8 asked for and 6 read in all).
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
        /// The other dimensions the same search speaks to: one search, not three.
        public var also: [ResearchDimension] = []
        /// The research questions it was made for (1.10.8).
        public var questions: [String] = []

        public init(dimension: ResearchDimension, site: String, text: String, contributor: String? = nil,
                    also: [ResearchDimension] = [], questions: [String] = []) {
            self.dimension = dimension
            self.site = site
            self.text = text
            self.contributor = contributor
            self.also = also
            self.questions = questions
        }

        public func covers(_ dimension: ResearchDimension) -> Bool { self.dimension == dimension || also.contains(dimension) }
        public var key: String { site + "|" + text.lowercased() }
    }

    /// The questions still open for a film, the most useful first: those of dimensions with nothing
    /// found before those of dimensions found in part (a general finding never closes the rest).
    public static func open(_ context: ResearchContext) -> [ResearchQuestion] {
        let relevant = ResearchQuestions.catalogue.filter { $0.isApplicable(context) }
        let open = relevant.filter { !$0.isAnswered(context.specs) }
        let order: [ResearchDimension] = [.movement, .lighting, .camera, .lenses, .vfx, .colour]
        func untouched(_ dimension: ResearchDimension) -> Bool {
            !relevant.contains { $0.dimension == dimension && $0.isAnswered(context.specs) }
        }
        return open.sorted { a, b in
            let ua = untouched(a.dimension), ub = untouched(b.dimension)
            if ua != ub { return ua }
            return (order.firstIndex(of: a.dimension) ?? 9, ResearchQuestions.catalogue.firstIndex { $0.id == a.id } ?? 99)
                < (order.firstIndex(of: b.dimension) ?? 9, ResearchQuestions.catalogue.firstIndex { $0.id == b.id } ?? 99)
        }
    }

    /// What to search for: for each open question, each provider that can speak to it, by the
    /// person whose role answers it (specialists first) or by the title. The same search is made
    /// once for every question it serves; none repeated within a year after finding nothing.
    public static func plan(open: [ResearchQuestion], crew: [CraftCrew.Contributor], title: String,
                            providers: [ResearchProvider] = ResearchProvider.all, previous: [ResearchEntry]?,
                            discovery: Int = CraftIndex.currentDiscovery, readAt: Date? = nil, now: Date = Date()) -> [Query] {
        let quiet = Set(Self.quiet(previous, discovery: discovery, readAt: readAt, now: now).flatMap(\.queries))
        var queries: [Query] = []
        func add(_ query: Query) {
            guard !quiet.contains(query.key) else { return }
            if let same = queries.firstIndex(where: { $0.key == query.key }) {
                if !queries[same].covers(query.dimension) { queries[same].also.append(query.dimension) }
                for id in query.questions where !queries[same].questions.contains(id) { queries[same].questions.append(id) }
                return
            }
            guard queries.count < maxQueries else { return }
            queries.append(query)
        }
        // Breadth first: each question's first capable provider, then (with what's left of the
        // budget) the next ones; one that found nothing is quiet next time, so another is tried then.
        func candidates(for question: ResearchQuestion) -> [Query] {
            providers.filter { $0.serves.contains(question.dimension) }.compactMap { provider in
                if provider.searchBy.contains(.person),
                   let person = question.roles.lazy.compactMap({ role in crew.first { $0.role == role } }).first {
                    return Query(dimension: question.dimension, site: provider.name, text: person.name, contributor: person.name,
                                 questions: [question.id])
                }
                if provider.searchBy.contains(.title) {
                    return Query(dimension: question.dimension, site: provider.name, text: title, questions: [question.id])
                }
                return nil
            }.filter { !quiet.contains($0.key) }
        }
        let options = open.map(candidates)
        for round in 0..<(options.map(\.count).max() ?? 0) {
            for list in options where round < list.count { add(list[round]) }
        }
        return queries
    }

    /// The earlier entries whose searches found nothing within the last `quietPeriod` (by the same
    /// discovery): not searched again, and carried as they are (their date unchanged).
    public static func quiet(_ previous: [ResearchEntry]?, discovery: Int, readAt: Date?, now: Date = Date()) -> [ResearchEntry] {
        (previous ?? []).filter { entry in
            guard entry.state == .searchedNoSource || entry.state == .partial, entry.discovery == discovery, !entry.queries.isEmpty,
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
        /// Results asked for; none was about this film (they answered, and didn't name it).
        case nothingUsable([String])
        /// A result's page didn't answer, or asked Reel to wait (searched again at the retry).
        case pageUnavailable([String])
        /// A result's page was in a language Reel doesn't read.
        case pageLanguage([String])
        /// A result's page couldn't be read: its article couldn't be told apart, too little text,
        /// not open to Reel.
        case pageUnreadable([String])
        /// Read: these pages.
        case read([String])
    }
    public let query: ResearchPlan.Query
    public var result: Result
}

/// What was looked for, in a film's reading: the people found, the questions open, the searches
/// and what they brought. For the log and the coverage; not kept in the library itself.
public struct ResearchRun: Equatable, Sendable {
    public var contributors: [CraftCrew.Contributor] = []
    /// The dimensions with an open question after the first pass.
    public var missing: [ResearchDimension] = []
    public var outcomes: [ResearchOutcome] = []
    /// Earlier searches that found nothing, not repeated this time (see `ResearchPlan.quiet`).
    public var quiet: [ResearchEntry] = []
    /// The questions open after the first pass, the most useful first (1.10.8).
    public var open: [String] = []
    /// Candidates set aside by page context: their address and why (1.10.8).
    public var passed: [(url: String, why: String)] = []

    public init(contributors: [CraftCrew.Contributor] = [], missing: [ResearchDimension] = [], outcomes: [ResearchOutcome] = [],
                quiet: [ResearchEntry] = [], open: [String] = []) {
        self.contributors = contributors
        self.missing = missing
        self.outcomes = outcomes
        self.quiet = quiet
        self.open = open
    }

    public static func == (a: ResearchRun, b: ResearchRun) -> Bool {
        a.contributors == b.contributors && a.missing == b.missing && a.outcomes == b.outcomes && a.quiet == b.quiet && a.open == b.open
            && a.passed.map(\.url) == b.passed.map(\.url)
    }
}

/// Where a film's research stands for one dimension, kept with its reading (`CraftIndex.research`).
public struct ResearchEntry: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        /// Found in what was read: every applicable question of it answered.
        case found
        /// Found in part (1.10.8): some of its questions answered, others still open (`open`).
        case partial
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
        /// No question of it applies to this film (1.10.8): camera and VFX for a film without effects.
        case notApplicable
        /// Saved by a later Reel with a state this one doesn't know.
        case unknown

        public init(from decoder: Decoder) throws {
            self = State(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }

        /// In the order shown (found first; the unknown not shown).
        public static let shown: [State] = [.found, .partial, .readNoFindings, .searchedNoSource, .unavailable, .extractionFailed,
                                            .unsupportedLanguage, .notSearched, .notApplicable]

        public var label: String {
            switch self {
            case .found: "found"
            case .partial: "found in part, more still open"
            case .readNoFindings: "read about, nothing said"
            case .searchedNoSource: "searched for, no source found"
            case .unavailable: "a source didn't answer"
            case .extractionFailed: "a source couldn't be read"
            case .unsupportedLanguage: "a source in a language Reel doesn't read"
            case .notSearched: "not searched for yet"
            case .notApplicable: "not applicable"
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
    /// Its questions still open (1.10.8), by id (`ResearchQuestions`).
    public var open: [String] = []

    public init(dimension: ResearchDimension, state: State, queries: [String] = [], discovery: Int = CraftIndex.currentDiscovery,
                searchedAt: Date? = nil, open: [String] = []) {
        self.dimension = dimension
        self.state = state
        self.queries = queries
        self.discovery = discovery
        self.searchedAt = searchedAt
        self.open = open
    }

    enum CodingKeys: String, CodingKey { case dimension, state, queries, discovery, searchedAt, open }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A dimension a later Reel added: read as the nearest this one knows (never dropped).
        dimension = (try? c.decode(ResearchDimension.self, forKey: .dimension)) ?? .contributors
        state = try c.decodeIfPresent(State.self, forKey: .state) ?? .unknown
        queries = try c.decodeIfPresent([String].self, forKey: .queries) ?? []
        discovery = try c.decodeIfPresent(Int.self, forKey: .discovery) ?? 6
        searchedAt = try c.decodeIfPresent(Date.self, forKey: .searchedAt)
        open = try c.decodeIfPresent([String].self, forKey: .open) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dimension, forKey: .dimension)
        try c.encode(state, forKey: .state)
        try c.encode(queries, forKey: .queries)
        try c.encode(discovery, forKey: .discovery)
        try c.encodeIfPresent(searchedAt, forKey: .searchedAt)
        if !open.isEmpty { try c.encode(open, forKey: .open) }
    }
}

public enum ResearchCoverage {
    /// The dimensions with something found (any question of it answered), in a film's reading.
    public static func found(in specs: TechSpecs, crew: [CraftCrew.Contributor]) -> Set<ResearchDimension> {
        var found = Set<ResearchDimension>()
        if !crew.isEmpty { found.insert(.contributors) }
        for question in ResearchQuestions.catalogue where question.isAnswered(specs) { found.insert(question.dimension) }
        return found
    }

    /// The coverage with what the stored Shot on says (a tag carried from an earlier reading):
    /// film, digital or IMAX say the camera, anamorphic the lenses, black and white the colour.
    /// A dimension found in part stays in part (its other questions are still open).
    public static func reconciled(_ research: [ResearchEntry], shotOn: [ShotOn]) -> [ResearchEntry] {
        var found = Set<ResearchDimension>()
        if shotOn.contains(where: { [.film, .digital, .imax].contains($0) }) { found.insert(.camera) }
        if shotOn.contains(.anamorphic) { found.insert(.lenses) }
        if shotOn.contains(.blackAndWhite) { found.insert(.colour) }
        return research.map { entry in
            guard found.contains(entry.dimension), entry.state != .found, entry.state != .partial else { return entry }
            return ResearchEntry(dimension: entry.dimension, state: .partial, queries: entry.queries, discovery: entry.discovery,
                                 searchedAt: entry.searchedAt, open: entry.open)
        }
    }

    /// Where each dimension stands after a reading, decided once every source attempt of the reading
    /// is known: every applicable question answered (found), some (in part, with the rest open),
    /// none applicable, or by what this reading's searches for it came to, the carried year of
    /// quiet, then the first pass's outages and limits.
    /// `unavailable`: a site of the first pass didn't answer, or the film's article didn't come;
    /// `languageLimited`/`extractionLimited`: a first-pass page in another language, or unreadable.
    public static func entries(context: ResearchContext, run: ResearchRun?, readSomething: Bool,
                               languageLimited: Bool, extractionLimited: Bool = false, unavailable: Bool = false,
                               discovery: Int = CraftIndex.currentDiscovery, now: Date = Date()) -> [ResearchEntry] {
        ResearchDimension.allCases.map { dimension in
            let outcomes = (run?.outcomes ?? []).filter { $0.query.covers(dimension) }
            let keys = outcomes.filter {
                if case .notTried = $0.result { return false }
                return true
            }.map(\.query.key)
            let searchedAt: Date? = keys.isEmpty ? nil : now
            if dimension == .contributors {
                return ResearchEntry(dimension: dimension, state: context.crew.isEmpty ? (readSomething ? .readNoFindings : .notSearched) : .found,
                                     discovery: discovery)
            }
            let relevant = ResearchQuestions.catalogue.filter { $0.dimension == dimension && $0.isApplicable(context) }
            if relevant.isEmpty { return ResearchEntry(dimension: dimension, state: .notApplicable, discovery: discovery) }
            let open = relevant.filter { !$0.isAnswered(context.specs) }.map(\.id)
            if open.isEmpty {
                return ResearchEntry(dimension: dimension, state: .found, queries: keys, discovery: discovery, searchedAt: searchedAt)
            }
            if open.count < relevant.count {
                return ResearchEntry(dimension: dimension, state: .partial, queries: keys, discovery: discovery, searchedAt: searchedAt,
                                     open: open)
            }
            func any(_ test: (ResearchOutcome.Result) -> Bool) -> Bool { outcomes.contains { test($0.result) } }
            let state: ResearchEntry.State
            // This reading's own searches first: what they came to is said even while a site of the
            // first pass is down (and a search that found nothing keeps its year of quiet).
            if any({ if case .unavailable = $0 { true } else if case .pageUnavailable = $0 { true } else { false } }) {
                state = .unavailable
            } else if any({ if case .read = $0 { true } else { false } }) {
                state = .readNoFindings
            } else if any({ if case .pageLanguage = $0 { true } else { false } }) {
                state = .unsupportedLanguage
            } else if any({ if case .pageUnreadable = $0 { true } else { false } }) {
                state = .extractionFailed
            } else if any({ if case .noCandidate = $0 { true } else if case .nothingUsable = $0 { true } else { false } }) {
                state = .searchedNoSource
            } else if let carried = run?.quiet.first(where: { $0.dimension == dimension }) {
                // Searched within the year and nothing found: still so (not "not searched").
                return carried
            } else if unavailable {
                state = .unavailable
            } else if languageLimited {
                state = .unsupportedLanguage
            } else if extractionLimited {
                state = .extractionFailed
            } else if !outcomes.isEmpty || run?.missing.contains(dimension) == true && !readSomething {
                state = .notSearched
            } else {
                state = readSomething ? .readNoFindings : .notSearched
            }
            return ResearchEntry(dimension: dimension, state: state, queries: keys, discovery: discovery, searchedAt: searchedAt, open: open)
        }
    }
}
