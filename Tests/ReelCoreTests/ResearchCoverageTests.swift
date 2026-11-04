import XCTest
@testable import ReelCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reel 1.10.7: research coverage, source discovery and craft observations. Made-up films, people
/// and pages (no real film's title is in the extraction rules); the response shapes are the sites' own.
extension DiscoveryFixtures {
    // MARK: The Long Quarantine (2013): a big VFX-led production, sparse after the first pass.
    // Credited: Tom Ashby (director of photography), Lena Marsh (Steadicam), Ravi Holt (VFX).
    // Its article names Paul Rowe as originally hired. American and British Cinematographer find
    // nothing by its title; Wikipedia cites a VFX trade piece and a credits database.

    static let quarantineVFX = page("Inside the VFX of The Long Quarantine", [
        "The Long Quarantine needed crowds of thousands, and the camera team fitted zoom encoders on every lens so the matchmove artists could follow every change of focal length.",
        "For the motorway chase, four static cameras were mounted on a truck and their plates were stitched into one moving background.",
        "The production shot on ARRI ALEXA M cameras, the visual effects supervisor Ravi Holt told the magazine.",
        "Most of the crowd shots were extended digitally, with witness cameras recording every take from the side.",
    ])

    static let quarantineSteadicam = page("Moving Through Panic: Lena Marsh on Steadicam", [
        "Lena Marsh spent four months on The Long Quarantine as its Steadicam operator, running backwards through crowds of extras.",
        "“We wanted the camera to feel like one of the people fleeing,” Marsh says. “So the Steadicam never settles; it is always catching up.”",
        "Marsh carried a lightweight rig for the stairwell sequence, where the Steadicam followed the family up twelve floors in one take.",
        "The second unit shot the aerial plates of the city while Marsh worked with the main unit on the street.",
    ])

    static func longQuarantine(vfxSearch: Bool = false) {
        StandInSite.reset()
        // The bounded searches by person, before the title search they share an address with.
        StandInSite.route("theasc.com", "search=Lena", body: ascHits([
            ("Moving Through Panic: Lena Marsh on Steadicam", "https://theasc.com/article/lena-marsh-steadicam/", "article"),
            ("Lena Marsh Joins the Society", "https://theasc.com/news/lena-marsh-joins/", "post"),
        ]))
        StandInSite.route("theasc.com", "search=Tom", body: "[]")
        StandInSite.route("theasc.com", "search=Paul", body: "[]")
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: "[]")
        StandInSite.route("theasc.com", "lena-marsh-steadicam", body: quarantineSteadicam)
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: "[]")
        StandInSite.route("en.wikipedia.org", "prop=extlinks", body: extlinks([
            "https://www.awn.com/vfxworld/inside-vfx-long-quarantine",
            "https://www.imdb.com/title/tt0000001/fullcredits",
            "https://web.archive.org/web/20130701000000/https://www.awn.com/vfxworld/inside-vfx-long-quarantine",
        ]))
        StandInSite.route("en.wikipedia.org", "prop=extracts", body: missingArticle)
        StandInSite.route("www.awn.com", "inside-vfx-long-quarantine", body: quarantineVFX)
        StandInSite.route("www.kodak.com", "long-quarantine", status: 404, body: "<p>Not here</p>")
        StandInSite.route("nofilmschool.com", "long-quarantine", status: 404, body: "<p>Not here</p>")
        if vfxSearch {
            StandInSite.route("cinesite.com", "wp-json/wp/v2/search", body: "[]")
        }
    }

    static let quarantineArticle = FilmArticle(title: "The Long Quarantine", extract: """
    == Production ==
    Paul Rowe was originally hired as the cinematographer, and left the production before filming began; Tom Ashby replaced him.
    Principal photography began in Glasgow in June 2012, with reshoots in Budapest the following year.
    """)
}

final class ResearchCoverageTests: XCTestCase {
    override func tearDown() {
        StandInSite.reset()
        super.tearDown()
    }

    private func client() -> CameraSourcesClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StandInSite.self]
        return CameraSourcesClient(session: URLSession(configuration: config))
    }

    private func quarantine() -> TMDBMovieDetails {
        var details = TMDBMovieDetails(id: 900_001, title: "The Long Quarantine", releaseDate: "2013-06-21")
        details.credits = TMDBCredits(cast: [], crew: [
            TMDBCrewMember(name: "Tom Ashby", job: "Director of Photography"),
            TMDBCrewMember(name: "Lena Marsh", job: "Steadicam Operator"),
            TMDBCrewMember(name: "Ravi Holt", job: "Visual Effects Supervisor"),
            TMDBCrewMember(name: "Ann Writer", job: "Screenplay"),
        ])
        return details
    }

    private func person(_ name: String, _ role: CraftCrew.Role, credited: Bool = true) -> CraftCrew.Contributor {
        CraftCrew.Contributor(name: name, role: role, scope: role.scope, credited: credited)
    }

    // MARK: A. Contributors and their part of the production

    func testTheCreditedCrewByRoleAndTheirPart() {
        let crew = CraftCrew.credited(quarantine())
        XCTAssertEqual(crew.map(\.name), ["Tom Ashby", "Lena Marsh", "Ravi Holt"])
        XCTAssertEqual(crew.map(\.role), [.cinematographer, .steadicamOperator, .vfxSupervisor])
        XCTAssertTrue(crew.allSatisfy(\.credited))
        // The writer isn't camera crew.
        XCTAssertFalse(crew.contains { $0.name == "Ann Writer" })
        // Kept in the library (not trimmed away with the rest of the crew).
        XCTAssertTrue(CraftCrew.keptJobs.contains("Steadicam Operator"))
        XCTAssertTrue(CraftCrew.keptJobs.contains("Visual Effects Supervisor"))
        XCTAssertEqual(quarantine().trimmed().credits?.crew.map(\.name).sorted(),
                       ["Ann Writer", "Lena Marsh", "Ravi Holt", "Tom Ashby"])
    }

    func testAnUncreditedCinematographerIsNamedOnlyWhenTheSentenceIsAboutThisFilm() {
        let credited = CraftCrew.credited(quarantine())
        let named = CraftCrew.named(article: [
            "Paul Rowe was originally hired as the cinematographer, and left the production before filming began.",
            "The second unit director of photography Kim Vale shot the aerial plates over the city.",
            "Additional photography during reshoots was handled by cinematographer Sara Lund.",
            "Tom Ashby was the cinematographer.",
            // In passing, about other work: not this film's crew.
            "The director's longtime cinematographer Roberto Vane shot his earlier films.",
            "The film was originally set in Seattle, where cinematographer Ola Strand had shot the director's debut.",
        ], sources: [
            "Like cinematographer Wally Pfister on his last thriller, Ashby kept the camera moving.",
            "For The Long Quarantine, cinematographer Ann Vey photographed the Budapest pick-ups.",
        ], title: "The Long Quarantine", besides: credited)
        XCTAssertEqual(named.map(\.name), ["Paul Rowe", "Kim Vale", "Sara Lund", "Ann Vey"])
        // The part of the production only when the sentence says it: "originally hired" isn't a part.
        XCTAssertEqual(named.map(\.scope), [nil, .secondUnit, .reshoots, .reshoots])
        XCTAssertEqual(named.map(\.role), [.cinematographer, .secondUnitCinematographer, .additionalCinematographer, .additionalCinematographer])
        XCTAssertTrue(named.allSatisfy { !$0.credited })
        XCTAssertEqual(named[0].described, "Director of photography Paul Rowe (named in what was read)")
    }

    func testWhoseWordsTheyAreIsWhoIsSpeaking() {
        let crew = CraftCrew.credited(quarantine()) + [person("Stephanie Martin", .cameraOperator)]
        XCTAssertEqual(CraftCrew.speaker(in: "“We wanted the camera to feel like one of the people fleeing,” Marsh says.", crew: crew)?.name,
                       "Lena Marsh")
        XCTAssertEqual(CraftCrew.speaker(in: "According to Tom Ashby, “the light had to come from the street.”", crew: crew)?.name, "Tom Ashby")
        // Named, not speaking.
        XCTAssertNil(CraftCrew.speaker(in: "The director told Tom Ashby: “shoot every scene handheld and close to them.”", crew: crew))
        // Another person of the same name.
        XCTAssertNil(CraftCrew.speaker(in: "“It never settles,” said Martin Campbell of his own films.", crew: crew))
        // The speaker named first: "Forster said Ashby brought…" is Forster's words.
        XCTAssertNil(CraftCrew.speaker(in: "The director said Ashby brought “a documentary approach to every single setup.”", crew: crew))
        XCTAssertEqual(CraftCrew.speaker(in: "“The camera never settles in the chase,” says Lena Marsh.", crew: crew)?.name, "Lena Marsh")
        // A title in quotes isn't someone's words.
        XCTAssertFalse(CraftCrew.quotes("Ashby shot “Mank” and this film back to back."))
        XCTAssertTrue(CraftCrew.quotes("“We kept the camera low for the whole of the chase,” he says."))
    }

    func testAPartOfTheProductionIsSaidNotGuessed() {
        XCTAssertEqual(ProductionScope.said(in: "During the reshoots, the camera was mostly handheld."), .reshoots)
        XCTAssertEqual(ProductionScope.said(in: "The second unit shot the aerial plates."), .secondUnit)
        XCTAssertNil(ProductionScope.said(in: "The camera was mostly handheld."))
    }

    // MARK: B. Sources: families and kinds of evidence

    func testSourcesByFamilyAndWhatTheyCanEstablish() {
        XCTAssertEqual(SourceRegistry.family(ofSource: "fxguide"), .productionTechnology)
        XCTAssertEqual(SourceRegistry.family(ofSource: "Cinesite"), .vfxVendor)
        XCTAssertEqual(SourceRegistry.family(ofSource: "IMDb"), .creditDatabase)
        XCTAssertEqual(SourceRegistry.family(ofSource: "ARRI"), .manufacturer)
        XCTAssertEqual(SourceRegistry.family(ofSource: nil), .encyclopedia)
        XCTAssertEqual(SourceRegistry.family(ofSource: "American Cinematographer"), .cinematographyPublication)
        XCTAssertFalse(SourceRegistry.establishesCapture(.productionTechnology))
        XCTAssertFalse(SourceRegistry.establishesCapture(.vfxVendor))
        XCTAssertFalse(SourceRegistry.establishesCapture(.creditDatabase))
        XCTAssertTrue(SourceRegistry.establishesCapture(.cinematographyPublication))
        XCTAssertTrue(SourceRegistry.establishesCapture(.manufacturer))
        XCTAssertEqual(SourceRegistry.entry(host: "www.fxguide.com")?.name, "fxguide")
        // A VFX piece is what a VFX publication is read for; on a cinematography magazine it's still another craft.
        XCTAssertFalse(CameraSources.isOtherCraft(title: "Inside the VFX of The Long Quarantine", cinematographers: ["Tom Ashby"],
                                                  site: "Animation World Network"))
        XCTAssertTrue(CameraSources.isOtherCraft(title: "Inside the VFX of The Long Quarantine", cinematographers: ["Tom Ashby"],
                                                 site: "American Cinematographer"))
        XCTAssertTrue(CameraSources.isOtherCraft(title: "The Editor of The Long Quarantine", cinematographers: ["Tom Ashby"], site: "fxguide"))
        XCTAssertNil(SourceRegistry.entry(host: "notfxguide.com"))
    }

    func testEvidenceKinds() {
        let dp = person("Tom Ashby", .cinematographer)
        let operatorMarsh = person("Lena Marsh", .steadicamOperator)
        func kind(_ source: String?, _ text: String, interview: Bool = false, speaker: CraftCrew.Contributor? = nil) -> EvidenceKind {
            SourceRegistry.evidence(source: source, text: text, isInterview: interview, speaker: speaker)
        }
        XCTAssertEqual(kind("American Cinematographer", "“We lit it with streetlights,” Ashby says.", speaker: dp), .productionStatement)
        XCTAssertEqual(kind("American Cinematographer", "“The Steadicam never settles,” Marsh says.", speaker: operatorMarsh), .crewTestimony)
        XCTAssertEqual(kind("fxguide", "Zoom encoders were fitted on every lens."), .technicalTrade)
        XCTAssertEqual(kind("ARRI", "The production chose the ALEXA M for its small head."), .manufacturerCaseStudy)
        XCTAssertEqual(kind("IMDb", "Camera: ARRI ALEXA M"), .databaseLead)
        XCTAssertEqual(kind(nil, "The film was shot digitally."), .secondaryReporting)
        // Someone looking at the finished film: analysis, not testimony, however expert.
        XCTAssertEqual(kind("American Cinematographer", "In the opening we can see the camera searching for the family in the crowd."),
                       .professionalAnalysis)
        XCTAssertNotEqual(kind("American Cinematographer", "I think we pushed the zoom too far.", interview: true, speaker: dp),
                          .professionalAnalysis)
    }

    func testAWaybackCopyIsJudgedAsThePageItKeeps() throws {
        let url = try XCTUnwrap(URL(string: "https://web.archive.org/web/20130701000000/https://www.awn.com/vfxworld/inside"))
        XCTAssertEqual(CameraSources.archived(url)?.host, "www.awn.com")
        XCTAssertEqual(CameraSources.archived(url)?.path, "/vfxworld/inside")
        XCTAssertNil(CameraSources.archived(try XCTUnwrap(URL(string: "https://www.awn.com/vfxworld/inside"))))
        // Found by a search and cited from the archive: one article, read at its own address.
        let live = try XCTUnwrap(URL(string: "https://theasc.com/article/inside/"))
        let copy = try XCTUnwrap(URL(string: "https://web.archive.org/web/20260606003457/https://theasc.com/article/inside/"))
        XCTAssertEqual(CameraSources.identity(copy), CameraSources.identity(live))
        let merged = CameraSources.merge([(url: copy, site: "American Cinematographer", title: nil, cited: nil)],
                                         adding: [(url: live, site: "American Cinematographer", title: "Inside", cited: nil)])
        XCTAssertEqual(merged.links.map(\.url), [live])
        XCTAssertEqual(merged.aliases.map(\.url), [copy])
    }

    func testAPageInAnotherLanguageIsSaidSo() async throws {
        XCTAssertEqual(CameraSources.otherLanguage(#"<html lang="es-ES"><head>"#), "Spanish")
        XCTAssertNil(CameraSources.otherLanguage(#"<html lang="en-GB"><head>"#))
        XCTAssertNil(CameraSources.otherLanguage("<html><head>"))
        StandInSite.reset()
        StandInSite.route("www.fxguide.com", "analisis", body: #"<html lang="es"><head><title>Análisis</title></head><body>"#
            + (1...5).map { "<p>La cámara en mano y el zoom dominan la película, párrafo \($0).</p>" }.joined() + "</body></html>")
        let url = try XCTUnwrap(URL(string: "https://www.fxguide.com/analisis-long-quarantine/"))
        let got = await client().page(url, site: "fxguide", title: nil)
        XCTAssertNil(got.source)
        XCTAssertEqual(got.failure?.limit, .language)
        XCTAssertEqual(got.failure?.reason, "not read: written in Spanish, a language Reel doesn't read yet")
    }

    // MARK: C. Technical facts and craft observations

    func testAVFXTradePieceIsObservationNotTheCameraPackage() {
        let text = TechSpecs.Text(source: "fxguide", sections: [FilmArticle.Section(id: 0, title: "", paragraphs: [
            "For The Long Quarantine, the camera team fitted zoom encoders on every lens so the matchmove artists could follow the handheld footage.",
            "The production shot digitally on ARRI ALEXA M cameras.",
        ])], isInterview: false)
        let specs = TechSpecs.read(texts: [text], cinematographers: ["Tom Ashby"], directors: [], year: 2013, title: "The Long Quarantine",
                                   crew: CraftCrew.credited(quarantine()))
        XCTAssertFalse(specs.cameraVFX.isEmpty, "the encoder sentence is a camera and VFX observation")
        XCTAssertEqual(specs.cameraVFX.first?.evidence, .technicalTrade)
        // Not a Shot on tag from a VFX publication.
        let index = CraftIndex.make(from: specs, colour: nil, keywords: [], sources: 1)
        XCTAssertFalse(index.shotOn.contains(.digital))
        // The same words in a cinematography magazine do make it.
        let ac = TechSpecs.Text(source: "American Cinematographer", sections: text.sections, isInterview: false)
        let fromAC = TechSpecs.read(texts: [ac], cinematographers: ["Tom Ashby"], directors: [], year: 2013, title: "The Long Quarantine")
        XCTAssertTrue(CraftIndex.make(from: fromAC, colour: nil, keywords: [], sources: 1).shotOn.contains(.digital))
    }

    func testAVFXCompanysLightAndCameraAreTheEffectsNotTheCinematography() {
        let text = TechSpecs.Text(source: "Cinesite", sections: [FilmArticle.Section(id: 0, title: "", paragraphs: [
            "The work on The Long Quarantine led to significant developments in the studio's raytracing, lighting and shading pipelines.",
            "Beyond the bridge are tower-blocks, and furthest from the camera is the harbour, all of it built for The Long Quarantine.",
            "“We’re very proud of the response to our stereo conversion of The Long Quarantine,” said the company's head of visual effects.",
            "The whole sequence was filmed in Glasgow against greenscreen, with reference photographs taken with HDRI cameras.",
        ])], isInterview: true)
        let specs = TechSpecs.read(texts: [text], cinematographers: ["Tom Ashby"], directors: [], year: 2013, title: "The Long Quarantine",
                                   crew: CraftCrew.credited(quarantine()))
        XCTAssertTrue(specs.lighting.isEmpty, "CG shading isn't how the film was lit: \(specs.lighting.map(\.text))")
        XCTAssertTrue(specs.cameraLanguage.isEmpty, "a virtual camera isn't the film's camera work: \(specs.cameraLanguage.map(\.text))")
        XCTAssertTrue(specs.approach.isEmpty, "a VFX company's own words aren't the filmmakers': \(specs.approach.map(\.text))")
        XCTAssertEqual(specs.cameraVFX.count, 1)
        XCTAssertEqual(specs.cameraVFX.first?.evidence, .technicalTrade)
        let found = ResearchCoverage.found(in: specs, crew: [])
        XCTAssertEqual(found, [.vfx])
        // A quote with no one of the film's crew named, on a VFX site: reporting, not crew testimony.
        XCTAssertEqual(SourceRegistry.evidence(source: "Cinesite", text: "“We’re proud of it,” said the company.", isInterview: true, speaker: nil),
                       .technicalTrade)
    }

    func testAGuessIsNotGear() {
        func filters(_ sentence: String) -> [String] {
            let text = TechSpecs.Text(source: "American Cinematographer", sections: [FilmArticle.Section(id: 0, title: "", paragraphs: [sentence])],
                                      isInterview: false)
            return TechSpecs.read(texts: [text], cinematographers: ["Tom Ashby"], directors: [], year: 2013, title: "The Long Quarantine")
                .names(.filter)
        }
        XCTAssertFalse(filters("For The Long Quarantine, Ashby used Black Satin filters on every lens.").isEmpty)
        XCTAssertTrue(filters("For The Long Quarantine, they may have used Black Satin filters to soften the highlights.").isEmpty)
        XCTAssertTrue(filters("The halation suggests Ashby probably used Black Satin filters on The Long Quarantine.").isEmpty)
    }

    func testAnObservationKeepsWhoseWordsAndWhichPart() {
        let crew = CraftCrew.credited(quarantine())
        let text = TechSpecs.Text(source: "American Cinematographer", sections: [FilmArticle.Section(id: 0, title: "", paragraphs: [
            "“We wanted the camera to feel like one of the people fleeing,” Marsh says of the Steadicam work on The Long Quarantine.",
        ])], isInterview: true)
        let specs = TechSpecs.read(texts: [text], cinematographers: ["Tom Ashby"], directors: [], year: 2013, title: "The Long Quarantine",
                                   crew: crew)
        let notes = specs.approach + specs.cameraLanguage + specs.intent + specs.sentences
        let note = notes.first { $0.text.contains("Marsh") }
        XCTAssertEqual(note?.speaker?.name, "Lena Marsh")
        XCTAssertEqual(note?.evidence, .crewTestimony)
        XCTAssertNil(note?.scope, "the sentence names no part of the production: not said to be the whole film either")
    }

    // MARK: D. Planning: open questions, by whom, where, within the bounds

    /// What's known of a synthetic film, as the engine sees it: these sentences read from a
    /// cinematography magazine, and its crew.
    private func knowing(_ sentences: [String], crew: [CraftCrew.Contributor], title: String = "The Long Quarantine") -> ResearchContext {
        let texts = sentences.isEmpty ? [] : [TechSpecs.Text(source: "American Cinematographer", paragraphs: sentences, isInterview: false)]
        let specs = TechSpecs.read(texts: texts, cinematographers: crew.filter { $0.role == .cinematographer }.map(\.name), directors: [],
                                   year: 2013, title: title, crew: crew)
        return ResearchContext(crew: crew, specs: specs, texts: texts)
    }

    func testThePlanSearchesTheRightPeopleOnceEach() {
        let crew = CraftCrew.credited(quarantine()) + [person("Ivy Lamp", .gaffer)]
        let context = knowing([], crew: crew)
        let open = ResearchPlan.open(context)
        XCTAssertEqual(open.first?.id, "movement.method")
        let plan = ResearchPlan.plan(open: open, crew: crew, title: "The Long Quarantine", previous: nil)
        XCTAssertLessThanOrEqual(plan.count, ResearchPlan.maxQueries)
        XCTAssertEqual(plan.map(\.text), ["Lena Marsh", "Ivy Lamp", "Tom Ashby", "Ravi Holt"])
        XCTAssertEqual(plan.map(\.dimension), [.movement, .lighting, .camera, .vfx])
        // The cinematographer's search speaks to the lenses and colour too: one search, not three.
        XCTAssertEqual(plan[2].also, [.lenses, .colour])
        XCTAssertTrue(plan[1].questions.contains("lighting.sources"))
        // Nothing open, nothing searched.
        XCTAssertTrue(ResearchPlan.plan(open: [], crew: crew, title: "The Long Quarantine", previous: nil).isEmpty)
        // No one to search by: only a provider searched by title.
        XCTAssertEqual(ResearchPlan.plan(open: open, crew: [], title: "X", previous: nil).map(\.site), ["Cinesite"])
    }

    func testAGeneralFindingLeavesItsMoreSpecificQuestionsOpen() {
        let crew = CraftCrew.credited(quarantine())
        let context = knowing(["For The Long Quarantine, the background plates were shot from a camera array on a truck in Glasgow."], crew: crew)
        XCTAssertFalse(context.specs.cameraVFX.isEmpty)
        let open = ResearchPlan.open(context).map(\.id)
        XCTAssertTrue(open.contains("vfx.tracking"), "plates found; tracking still open: \(open)")
        XCTAssertFalse(open.contains("vfx.plates"))
        XCTAssertFalse(open.contains("vfx.photography"))
        let entries = ResearchCoverage.entries(context: context, run: nil, readSomething: true, languageLimited: false)
        let vfx = entries.first { $0.dimension == .vfx }
        XCTAssertEqual(vfx?.state, .partial)
        XCTAssertEqual(vfx?.open, ["vfx.tracking"])
        // And it's still searched for, after the dimensions with nothing found.
        let plan = ResearchPlan.plan(open: ResearchPlan.open(context), crew: crew, title: "The Long Quarantine", previous: nil)
        XCTAssertTrue(plan.contains { $0.questions.contains("vfx.tracking") } || plan.count == ResearchPlan.maxQueries)
    }

    func testAQuestionThatDoesntApplyIsNotSearchedOrMissing() {
        // No VFX credit and nothing read about effects: camera and VFX doesn't apply.
        var details = quarantine()
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Tom Ashby", job: "Director of Photography")])
        let crew = CraftCrew.credited(details)
        let context = knowing(["For The Long Quarantine, Ashby shot on ARRI ALEXA Mini cameras with Cooke S4 lenses."], crew: crew)
        XCTAssertFalse(context.vfxRelevant)
        XCTAssertFalse(ResearchPlan.open(context).contains { $0.dimension == .vfx })
        XCTAssertEqual(ResearchCoverage.entries(context: context, run: nil, readSomething: true, languageLimited: false)
            .first { $0.dimension == .vfx }?.state, .notApplicable)
        XCTAssertFalse(ResearchPlan.plan(open: ResearchPlan.open(context), crew: crew, title: "The Long Quarantine", previous: nil)
            .contains { $0.site == "Cinesite" })
    }

    func testASearchThatFoundNothingWaitsAYearAndStaysSaid() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let crew = CraftCrew.credited(quarantine())
        let open = ResearchPlan.open(knowing([], crew: crew)).filter { $0.dimension == .movement }
        let key = "American Cinematographer|lena marsh"
        let earlier = [ResearchEntry(dimension: .movement, state: .searchedNoSource, queries: [key], discovery: CraftIndex.currentDiscovery,
                                     searchedAt: now.addingTimeInterval(-30 * 86_400))]
        let plan = ResearchPlan.plan(open: open, crew: crew, title: "T", previous: earlier, now: now)
        // Not on the provider that found nothing a month ago; the next provider that can answer it instead.
        XCTAssertEqual(plan.map(\.key), ["ProVideo Coalition|lena marsh"], "searched a month ago with nothing found")
        let quiet = ResearchPlan.quiet(earlier, discovery: CraftIndex.currentDiscovery, readAt: nil, now: now)
        // Carried as it was (its date too), not "not searched".
        let entries = ResearchCoverage.entries(context: knowing([], crew: crew),
                                               run: ResearchRun(contributors: crew, missing: [.movement], quiet: quiet),
                                               readSomething: true, languageLimited: false, now: now)
        let movement = entries.first { $0.dimension == .movement }
        XCTAssertEqual(movement?.state, .searchedNoSource)
        XCTAssertEqual(movement?.searchedAt, earlier[0].searchedAt)
        // A year on, or by a new discovery: searched again.
        XCTAssertEqual(ResearchPlan.plan(open: open, crew: crew, title: "T", previous: earlier,
                                         now: now.addingTimeInterval(400 * 86_400)).map(\.key).first, key)
        XCTAssertEqual(ResearchPlan.plan(open: open, crew: crew, title: "T", previous: earlier,
                                         discovery: CraftIndex.currentDiscovery + 1, now: now).map(\.key).first, key)
    }

    // MARK: E. Coverage states

    func testEveryStateIsSaidForWhatItIs() {
        let query = { (dimension: ResearchDimension, text: String) in
            ResearchPlan.Query(dimension: dimension, site: "American Cinematographer", text: text)
        }
        let crew = CraftCrew.credited(quarantine())
        let camera = knowing(["For The Long Quarantine, Ashby shot digitally on ARRI ALEXA Mini cameras."], crew: crew)
        let nothing = knowing([], crew: crew)
        let run = ResearchRun(missing: [.movement, .lighting, .lenses, .vfx, .colour], outcomes: [
            ResearchOutcome(query: query(.movement, "a"), result: .unavailable("didn't answer")),
            ResearchOutcome(query: query(.lighting, "b"), result: .noCandidate(3)),
            ResearchOutcome(query: query(.lenses, "c"), result: .read(["https://theasc.com/x"])),
            ResearchOutcome(query: query(.vfx, "d"), result: .notTried("no page left to ask for or read")),
        ])
        let entries = ResearchCoverage.entries(context: camera, run: run, readSomething: false, languageLimited: false)
        func state(_ dimension: ResearchDimension) -> ResearchEntry.State? { entries.first { $0.dimension == dimension }?.state }
        XCTAssertEqual(state(.contributors), .found)
        XCTAssertEqual(state(.camera), .found)
        XCTAssertEqual(state(.movement), .unavailable)
        XCTAssertEqual(state(.lighting), .searchedNoSource)
        XCTAssertEqual(state(.lenses), .readNoFindings)
        XCTAssertEqual(state(.vfx), .notSearched, "planned but no slot left: not searched, not 'nothing found'")
        XCTAssertEqual(state(.colour), .notSearched)
        func first(_ entries: [ResearchEntry]) -> ResearchEntry.State? { entries.first { $0.dimension == .lighting }?.state }
        // A page in another language, and a page that couldn't be told apart.
        XCTAssertEqual(first(ResearchCoverage.entries(context: nothing, run: nil, readSomething: true, languageLimited: true)), .unsupportedLanguage)
        XCTAssertEqual(first(ResearchCoverage.entries(context: nothing, run: nil, readSomething: false, languageLimited: false,
                                                      extractionLimited: true)), .extractionFailed)
        XCTAssertEqual(first(ResearchCoverage.entries(context: nothing, run: nil, readSomething: true, languageLimited: false)), .readNoFindings)
        // A site of the first pass that didn't answer (the film's article included): not a verdict on
        // anything not found; what was found stays found.
        let down = ResearchCoverage.entries(context: camera, run: nil, readSomething: true, languageLimited: false, unavailable: true)
        XCTAssertEqual(down.first { $0.dimension == .camera }?.state, .found)
        XCTAssertEqual(down.first { $0.dimension == .lighting }?.state, .unavailable)
        // A search this reading made still says what it came to while a site of the first pass is down.
        let searched = ResearchRun(missing: [.lighting], outcomes: [ResearchOutcome(query: query(.lighting, "b"), result: .noCandidate(2))])
        XCTAssertEqual(first(ResearchCoverage.entries(context: nothing, run: searched, readSomething: true, languageLimited: false,
                                                      unavailable: true)), .searchedNoSource)
    }

    func testAPageThatDidntAnswerIsNotKeptQuiet() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nothing = knowing([], crew: CraftCrew.credited(quarantine()))
        let query = ResearchPlan.Query(dimension: .movement, site: "American Cinematographer", text: "Lena Marsh", contributor: "Lena Marsh")
        func entry(_ result: ResearchOutcome.Result) -> ResearchEntry? {
            ResearchCoverage.entries(context: nothing, run: ResearchRun(missing: [.movement], outcomes: [ResearchOutcome(query: query, result: result)]),
                                     readSomething: true, languageLimited: false, now: now).first { $0.dimension == .movement }
        }
        XCTAssertEqual(entry(.pageUnavailable(["https://theasc.com/a"]))?.state, .unavailable)
        XCTAssertEqual(entry(.pageLanguage(["https://theasc.com/a"]))?.state, .unsupportedLanguage)
        XCTAssertEqual(entry(.pageUnreadable(["https://theasc.com/a"]))?.state, .extractionFailed)
        XCTAssertEqual(entry(.nothingUsable(["https://theasc.com/a"]))?.state, .searchedNoSource)
        // Only "searched, nothing about the film" waits a year.
        for result: ResearchOutcome.Result in [.pageUnavailable([]), .pageLanguage([]), .pageUnreadable([])] {
            let earlier = entry(result).map { [$0] }
            XCTAssertTrue(ResearchPlan.quiet(earlier, discovery: CraftIndex.currentDiscovery, readAt: now, now: now.addingTimeInterval(86_400)).isEmpty)
        }
        XCTAssertFalse(ResearchPlan.quiet(entry(.nothingUsable([])).map { [$0] }, discovery: CraftIndex.currentDiscovery, readAt: now,
                                          now: now.addingTimeInterval(86_400)).isEmpty)
    }

    func testAPartlyFoundDimensionWhoseSearchFailedIsSearchedAgain() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let crew = CraftCrew.credited(quarantine()) + [person("Ivy Lamp", .gaffer)]
        // How it was lit is known; which lights is open; the gaffer's search didn't answer.
        let context = knowing(["For The Long Quarantine, Ashby lit the corridors from above so the actors could move freely."], crew: crew)
        let lighting = ResearchPlan.open(context).filter { $0.dimension == .lighting }
        XCTAssertEqual(lighting.map(\.id), ["lighting.sources"])
        let query = ResearchPlan.Query(dimension: .lighting, site: "American Cinematographer", text: "Ivy Lamp", contributor: "Ivy Lamp",
                                       questions: ["lighting.sources"])
        let entries = ResearchCoverage.entries(context: context, run: ResearchRun(missing: [.lighting],
                                               outcomes: [ResearchOutcome(query: query, result: .unavailable("didn't answer: timed out"))]),
                                               readSomething: true, languageLimited: false, now: now)
        let entry = entries.first { $0.dimension == .lighting }
        XCTAssertEqual(entry?.state, .partial)
        XCTAssertEqual(entry?.queries, [], "a search that didn't answer isn't kept, so it can't be kept quiet")
        XCTAssertEqual(ResearchPlan.plan(open: lighting, crew: crew, title: "The Long Quarantine", previous: entries,
                                         now: now.addingTimeInterval(6 * 3600)).first?.key, query.key)
    }

    func testATagCarriedWhileItsSiteIsDownCountsAsFoundInPart() {
        let research = [ResearchEntry(dimension: .camera, state: .unavailable), ResearchEntry(dimension: .lenses, state: .unavailable)]
        let reconciled = ResearchCoverage.reconciled(research, shotOn: [.digital])
        XCTAssertEqual(reconciled.map(\.state), [.partial, .unavailable])
    }

    // MARK: F. Persistence

    func testResearchIsKeptWithTheReadingAndOldFilesStillRead() throws {
        var index = CraftIndex.make(from: TechSpecs.read([]), colour: nil, keywords: [], sources: 0)
        index.research = [ResearchEntry(dimension: .movement, state: .searchedNoSource, queries: ["American Cinematographer|lena marsh"],
                                        searchedAt: Date(timeIntervalSince1970: 1_800_000_000))]
        let data = try JSONEncoder().encode(index)
        let back = try JSONDecoder().decode(CraftIndex.self, from: data)
        XCTAssertEqual(back.research, index.research)
        // Saved by 1.10.6 (no research), and by a later Reel with a state this one doesn't know.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "research")
        XCTAssertNil(try JSONDecoder().decode(CraftIndex.self, from: JSONSerialization.data(withJSONObject: object)).research)
        object["research"] = [["dimension": "sound", "state": "askedTwice"]]
        let later = try JSONDecoder().decode(CraftIndex.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(later.research?.first?.state, .unknown)
    }

    func testALibraryFileOfVersionThreeIsReadAsIs() throws {
        XCTAssertEqual(LibraryFile.currentVersion, 4)
        let film = FilmEntry(driveID: "Main", relativePath: "Q.mkv", fileName: "Q.mkv", size: 1, modified: nil, addedAt: Date())
        let encoded = try JSONEncoder().encode(LibraryFile(films: [film]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 4)
        object["version"] = 3
        let decoded = try JSONDecoder().decode(LibraryFile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.films.map(\.fileName), ["Q.mkv"])
    }

    // MARK: G. A sparse VFX-led film, end to end (the World War Z shape, made up)

    func testASparseFilmIsResearchedWithinItsBounds() async throws {
        DiscoveryFixtures.longQuarantine(vfxSearch: true)
        let details = quarantine()
        let article = DiscoveryFixtures.quarantineArticle
        let first = await client().read(articleTitle: "The Long Quarantine", filmTitle: details.title, cinematographers: details.cinematographers,
                                        directors: details.directors, year: details.year, otherTitles: [])
        // The VFX trade piece Wikipedia cites is read (a registered site; its archive copy is the same page).
        XCTAssertTrue(first.sources.contains { $0.site == "Animation World Network" }, "\(first.sources.map(\.site)) \(first.skipped.map(\.reason))")
        XCTAssertFalse(first.sources.contains { $0.url.host?.contains("archive.org") ?? false })
        // A credits database is a lead, not read.
        XCTAssertFalse(StandInSite.allAsked().contains { $0.host == "www.imdb.com" })
        XCTAssertTrue(first.discovery?.cited?.links.contains { $0.rejected == .creditDatabase } ?? false)

        let crew = CraftReader.crew(of: details, article: article, reading: first)
        XCTAssertTrue(crew.contains { $0.name == "Paul Rowe" && !$0.credited && $0.scope == nil })
        let researched = await client().researched(first, article: article, filmTitle: details.title, cinematographers: details.cinematographers,
                                                   directors: details.directors, year: details.year, otherTitles: [], crew: crew,
                                                   previous: nil)
        let run = try XCTUnwrap(researched.research)
        XCTAssertFalse(run.missing.contains(.vfx), "the encoders and plates are camera and VFX work")
        XCTAssertTrue(run.missing.contains(.movement))
        // The Steadicam operator, searched by name, on American Cinematographer: read.
        let searched = run.outcomes.map(\.query.text)
        XCTAssertEqual(searched.first, "Lena Marsh")
        XCTAssertTrue(researched.sources.contains { $0.url.absoluteString.contains("lena-marsh-steadicam") })
        // Within the bounds: never more than 8 pages asked for and 6 read in all, at most 4 searches.
        XCTAssertLessThanOrEqual(run.outcomes.count, ResearchPlan.maxQueries)
        XCTAssertLessThanOrEqual(researched.sources.count, CameraSources.readLimit)
        let pages = StandInSite.allAsked().filter { !$0.absoluteString.contains("wp-json") && $0.host != "en.wikipedia.org" }
        XCTAssertLessThanOrEqual(Set(pages).count, CameraSources.askLimit)
        XCTAssertEqual(Set(pages).count, pages.count, "nothing asked for twice")

        let reading = CraftReader.reading(of: details, articleTitle: "The Long Quarantine", article: article, reading: researched, colour: nil)
        let research = try XCTUnwrap(reading.index.research)
        func state(_ dimension: ResearchDimension) -> ResearchEntry.State? { research.first { $0.dimension == dimension }?.state }
        XCTAssertEqual(state(.contributors), .found)
        XCTAssertEqual(state(.vfx), .found)
        XCTAssertEqual(state(.movement), .found)
        XCTAssertNotEqual(state(.lighting), .found)
        XCTAssertNotEqual(state(.lighting), .unknown)
        // The log says who, what was missing, where Reel looked, and the observations with their source.
        XCTAssertTrue(reading.log.contains("RESEARCH (who photographed it"))
        XCTAssertTrue(reading.log.contains("Director of photography Paul Rowe (named in what was read)"))
        XCTAssertTrue(reading.log.contains("Searched American Cinematographer for “Lena Marsh”"))
        XCTAssertTrue(reading.log.contains("Camera and VFX — Animation World Network; technical reporting"))
        XCTAssertTrue(reading.log.contains("Steadicam operator Lena Marsh"))
        // The VFX trade piece makes no Shot on tag.
        XCTAssertFalse(reading.index.evidence.contains { $0.source == "Animation World Network" })
    }

    func testAShortTitleAloneDoesntMakeAPageTheFilms() async {
        func run(_ paragraphs: [String]) async -> CameraReading {
            StandInSite.reset()
            StandInSite.route("cinesite.com", "wp-json/wp/v2/search", body: DiscoveryFixtures.ascHits([("Ash", "https://cinesite.com/ash/", "page")]))
            StandInSite.route("cinesite.com", "/ash/", body: DiscoveryFixtures.page("Ash", paragraphs))
            return await client().researched(CameraReading(sources: [], more: [], cinematographer: nil), article: nil, filmTitle: "Ash",
                                              cinematographers: ["Ida Holm"], directors: ["Ola Berg"], year: 2019, otherTitles: [],
                                              crew: [person("Ole Vik", .vfxSupervisor)], previous: nil)
        }
        let generic = await run([
            "Ash from the fires drifted over the plates we shot for the commercial, and the greenscreen work took a week.",
            "The studio's reel this year includes car spots, a music video and a game trailer, each with its own camera arrays.",
            "Ash and smoke simulations were rendered on the new farm, with HDRI captured on every set.",
        ])
        XCTAssertTrue(generic.sources.isEmpty, "\(generic.sources.map(\.title))")
        XCTAssertEqual(generic.research?.outcomes.first { $0.query.site == "Cinesite" }?.result, .nothingUsable(["https://cinesite.com/ash/"]))
        let film = await run([
            "For Ash (2019), directed by Ola Berg, the studio built the burning forest around the plates shot on location.",
            "Ida Holm's camera team fitted witness cameras on every set so the matchmove artists could track the handheld shots.",
            "The forest was extended digitally from HDRI captured at dusk, with greenscreen used for the cabin interiors.",
        ])
        XCTAssertEqual(film.sources.map(\.url.absoluteString), ["https://cinesite.com/ash/"])
    }

    func testAFilmWithNothingMissingIsNotSearchedFurther() async {
        DiscoveryFixtures.quietHarbour()
        let first = await client().read(articleTitle: "The Quiet Harbour", filmTitle: "The Quiet Harbour", cinematographers: ["Jane Doe"],
                                        directors: ["Carl Example"], year: 2015, otherTitles: [])
        let before = StandInSite.allAsked().count
        let crew = [person("Jane Doe", .cinematographer)]
        let researched = await client().researched(first, article: nil, filmTitle: "The Quiet Harbour", cinematographers: ["Jane Doe"],
                                                   directors: ["Carl Example"], year: 2015, otherTitles: [], crew: crew, previous: nil)
        // Whatever was missing, at most the bounded searches; the first pass's reading is kept whole.
        XCTAssertLessThanOrEqual(StandInSite.allAsked().count - before, ResearchPlan.maxQueries + ResearchPlan.maxPages)
        XCTAssertTrue(Set(first.sources.map(\.url)).isSubset(of: Set(researched.sources.map(\.url))))
        XCTAssertEqual(researched.discovery, first.discovery)
    }
}
