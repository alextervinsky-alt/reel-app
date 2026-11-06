import XCTest
@testable import ReelCore

/// 1.10.10: every pattern behind a case the 1.10.8 and 1.10.9 audits found (`known-cases.md` in the
/// release folder), written again with invented films, people and wording, so what's tested is the
/// pattern and not the sentence. Each checks the decision and its reason (explainability, brief §9.3).
final class KnownCasesTests: XCTestCase {
    let film = "The Quiet Harbour"

    func read(_ sentence: String, title: String? = nil) -> TechSpecs {
        TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: [sentence])], cinematographers: ["Jane Doe"],
                       directors: ["Carl Example"], year: 2022, title: title ?? film)
    }

    func accepts(_ sentence: String, _ names: [String], title: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let specs = read(sentence, title: title)
        for name in names {
            XCTAssertTrue(specs.accepted.contains { $0.name.lowercased().contains(name.lowercased()) },
                          "\(name) not accepted from: \(sentence) — judged \(specs.judged.map { "\($0.name):\($0.reason)" })", file: file, line: line)
        }
    }

    func rejects(_ sentence: String, _ name: String, _ reason: ClaimReason, title: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let specs = read(sentence, title: title)
        XCTAssertFalse(specs.accepted.contains { $0.name.lowercased().contains(name.lowercased()) }, "\(name) accepted from: \(sentence)",
                       file: file, line: line)
        let judged = specs.judged.first { $0.name.lowercased().contains(name.lowercased()) }
        XCTAssertEqual(judged?.reason, reason, "\(name) in: \(sentence)", file: file, line: line)
    }

    // MARK: Clauses (brief §8.2)

    func testARelativeClauseAboutOtherWorkDoesNotSetTheSentenceAside() {
        accepts("Colourist Ada Bloom at Company 3, who has also worked on Example's last few films, once again shaped the final look in the grade.",
                ["Company 3"])
        accepts("Lensed by Jane Doe, with whom Carl Example also collaborated on Glass Rivers (2019), the production was shot using natural light and the Alexa 65.",
                ["Alexa 65", "Natural light"])
        // …and gear inside such a clause is the other production's.
        rejects("Doe, who shot Glass Rivers (2019) on an ARRI Alexa Mini, chose film for this one.", "Alexa Mini", .otherProduction)
    }

    func testARelativeClauseAboutAnotherProductionsNameIsThatProductions() {
        rejects("The night streets had a glow which recalled scenes from Stanley Vane's Glass Rivers, which was shot in candlelight with a fast lens.",
                "Candlelight", .otherProduction)
    }

    func testAnAppositiveOrADashedAsideNamingAnotherProduction() {
        accepts("The primary aspect ratio was 2:1, a tribute to Ann Vale's Univisium, with select scenes changing to a 1.43:1 aspect ratio.", ["1.43:1"])
        accepts("As on Glass Rivers and Paper Moon – two previous collaborations with Example – Doe opted for 35mm Kodak Vision3 5219 500T, capturing in 3-perf.",
                ["5219"])
    }

    func testAMakersProductIsNotAFilm() {
        accepts("The film was wholly shot using Red Digital Cinema Camera Company's RED MX digital camera.", ["Digital"])
    }

    func testATimeApartGovernsTheWholeStatement() {
        rejects("When I was in France working on Glass Rivers with Ann Vale, I was very into desaturation with a bleach-bypass process.",
                "Bleach bypass", .otherProduction)
    }

    // MARK: Physical facts and visual treatment (brief §5)

    func testATreatmentIsNotAFake() {
        // A film-emulation look is a treatment, and is what it is.
        accepts("We built three show LUTs – one of them a neutral film emulation look.", ["Film emulation"])
        // A movement's style is the movement.
        accepts("The dream sequences embraced a more dynamic, handheld style.", ["Handheld"])
        // …while light made to look like candlelight, and a process emulated, are simulations.
        rejects("We put straw gels in front of the 10Ks to give the scenes a candlelit look.", "Candlelight", .simulated)
        rejects("The film needed an emulation of the ENR silver-retention process.", "ENR", .simulated)
        rejects("That look was mostly the result of using the digital work to match a real photochemical process.", "Film", .simulated)
    }

    func testACameraCarriedAsAPayloadIsEquipment() {
        accepts("Establishing shots were made with a heavy-lift drone carrying an ARRI 235 payload on a DJI Ronin gimbal.", ["ARRI 235"])
        // A camera a character holds is a prop.
        rejects("In the epilogue a character photographs the square with a Canon C300 Mark II, a prop the art department rented.",
                "C300", .environment)
    }

    // MARK: Production time and intention (brief §6)

    func testADecisionTakenIsNotAPlan() {
        accepts("One of her decisions was to shoot on film, with Doe primarily operating an Arricam LT and working with 3-perf Fuji Vivid 500T and 250 stocks.",
                ["Arricam LT", "3-perf"])
        rejects("In my mind, I wanted to do a combination of handheld and Steadicam.", "Steadicam", .abandonedPlan)
        rejects("They intended to shoot the film in the delta in a vérité style, using 16 mm cameras, while the war was still going on.",
                "16 mm", .abandonedPlan)
    }

    func testTheOtherInAListIsPositive() {
        accepts("We shot two sequences on Kodak Ektachrome, one in 16mm and the other on Super8mm.", ["Super8"])
    }

    func testNotFamiliarWithTheStockIsNotADenial() {
        accepts("The film had been shot on new Kodak 5247 stock with which the local laboratories were not very familiar.", ["5247"])
    }

    func testAnIdeaIsNotUse() {
        rejects("When I was planning the visual strategy, I began thinking that I could convey the conflict by creating a visual conflict between artificial light and natural light.",
                "Natural light", .insufficientContext)
    }

    // MARK: Habits, capability, definitions, credits (brief §8.3, §8.4, §9.2)

    func testGeneralHabitsAreNotThisFilms() {
        rejects("The crane has become second-nature to the two of us, and to the entire crew.", "Crane", .otherPractice)
        rejects("Example usually complains about Steadicam not being really steady, like a dolly shot, so he's not a fan.", "Steadicam", .otherPractice)
        rejects("When he shoots digital, he sets a LUT at the beginning of a show.", "LUT", .otherPractice)
    }

    func testWhatAKindOfGearCanDoIsNotUse() {
        rejects("It was better because we could do a tilt, which a Steadicam doesn't do as well.", "Steadicam", .productCapability)
        // …unless the sentence goes on to say it was used.
        accepts("It can be used on a Steadicam and an Ultimate Arm, and Doe stresses that these gave him and Example flexibility in camera movement.",
                ["Steadicam"])
    }

    func testADefinitionIsNotUse() {
        rejects("ENR is a silver retention process named for its inventor, a former lab operator.", "Bleach bypass", .definition)
    }

    func testACrewJobTitleIsNotUse() {
        rejects("It made him appreciate crew collaborations, such as with his dolly grip Sam Reed.", "Dolly", .insufficientContext)
    }

    func testResearchAboutRealPlacesIsNotTheFilmsLighting() {
        rejects("The scene takes place in a manger, and his research indicated that such settings have fluorescents or big tungsten lights.",
                "Tungsten", .environment)
    }

    func testLessComputerGraphicsIsNotASimulation() {
        let specs = read("The film was shot entirely in the wilderness, minimizing the amount of CGI and using only natural lighting.")
        XCTAssertFalse(specs.judged.contains { $0.name == "Natural light" && $0.reason == .simulated }, "\(specs.judged)")
    }

    // MARK: Format stages (brief §7)

    func testARatioKeepsItsStage() {
        let extraction = read("Doe settled on the Canon 1DX, shooting full-frame 5K, but with a widescreen 2.39:1 extraction.")
        XCTAssertEqual(extraction.accepted.first { $0.name == "2.39:1" }?.stage, .extraction)
        let cropped = read("Those shots were cropped to match the 2.39:1 anamorphic aspect ratio of the rest of the movie.")
        XCTAssertEqual(cropped.accepted.first { $0.name == "2.39:1" }?.stage, .extraction)
        let sequences = read("For sequences designed to be 2.39:1 in any presentation, Doe chose anamorphic lenses.")
        XCTAssertEqual(sequences.accepted.first { $0.name == "2.39:1" }?.stage, .sequence)
        rejects("It was presented in its theatrical 2.35:1 widescreen aspect ratio and in Dolby Digital 5.1.", "2.35:1", .delivery)
        rejects("This marked the first home video release that presents the film in 2.35:1.", "2.35:1", .delivery)
    }

    // MARK: Sections and pages (brief §8.1)

    func testASectionHeadedByAnotherProductionIsThatProductions() {
        var text = TechSpecs.Text(source: "Lens Weekly", sections: [
            FilmArticle.Section(id: 0, title: "On The Quiet Harbour", paragraphs: ["Doe shot the harbour scenes on the Alexa 35."]),
            FilmArticle.Section(id: 1, title: "On Glass Rivers… and After", paragraphs: ["Doe and the lab at FotoKem built a photochemical finish for the river scenes."]),
            // A heading that names no production the page knows is no other production's.
            FilmArticle.Section(id: 2, title: "On Collaboration", paragraphs: ["Doe chose Cooke S4 lenses for the harbour scenes."]),
        ], isInterview: true)
        text.otherProductions = ["Glass Rivers"]
        let specs = TechSpecs.read(texts: [text], cinematographers: ["Jane Doe"], directors: ["Carl Example"], year: 2022, title: film)
        XCTAssertTrue(specs.accepted.contains { $0.name.contains("Alexa 35") })
        XCTAssertFalse(specs.accepted.contains { $0.name.contains("FotoKem") }, "\(specs.accepted.map(\.name))")
        XCTAssertTrue(specs.accepted.contains { $0.name.contains("Cooke") }, "\(specs.accepted.map(\.name))")
    }

    func testAPageHeadlinedByAnotherProductionHasNoPageWideSubject() {
        XCTAssertEqual(PageContext.headlineProduction("‘Glass Rivers’: Jane Doe on lighting the flood", title: film), "Glass Rivers")
        XCTAssertNil(PageContext.headlineProduction("Director's cut: Jane Doe on The Quiet Harbour", title: film))
        XCTAssertNil(PageContext.headlineProduction("‘The Quiet Harbour’: Jane Doe on the night shoot", title: film))
        let paragraphs = [
            "Doe first worked with Example on The Quiet Harbour (AC May '15).",
            "For the flood sequences the team used Creamsource Vortex8s.",
            "The grade was done at Company 3.",
            "Later the crew moved to a stage.",
        ]
        XCTAssertTrue(PageContext.isCreditList(paragraphs[0], title: film), "a back-reference names the film as earlier coverage")
        let bounded = PageContext.anchors(paragraphs, title: film, otherTitles: ["Glass Rivers"], people: ["Jane Doe"], acrossParagraphs: true, bounded: true)
        XCTAssertFalse(bounded.joined().contains(true), "\(bounded)")
    }

    // MARK: Independent review, round 1 (each a finding's own input)

    func testAnAppositiveNamingTheSubjectAsAnotherProductionSetsItAside() {
        rejects("Glass Rivers, her previous feature, was shot on 16mm.", "16 mm", .otherProduction)
        rejects("Glass Rivers (her 2019 debut) was shot on 16mm.", "16 mm", .otherProduction)
    }

    func testAPossessiveTitleIsStillAnotherFilm() {
        rejects("Christopher Nolan's Oppenheimer camera package included the IMAX MSM 9802.", "IMAX", .otherProduction)
        rejects("Christopher Nolan's IMAX epic Oppenheimer was shot on 65mm.", "65 mm", .otherProduction)
    }

    func testCaptureWordsWinOverALaterRelease() {
        accepts("The film was shot on 35mm film which Criterion later restored in 4K.", ["35 mm"])
        XCTAssertFalse(read("They used Cooke Panchro lenses that had been restored by a lens house.").judged.contains { $0.reason == .delivery })
    }

    func testASimulatedHandheldFeelIsStillSimulated() {
        rejects("A simulated handheld feel was added in post with shake plug-ins.", "Handheld", .simulated)
    }

    func testNoNewReasonRetiresARealStatement() {
        accepts("We shot on 65mm, which means the grain is finer.", ["65 mm"])
        accepts("Bleach bypass is a technique we used on the whole film.", ["Bleach bypass"])
        accepts("While he was preparing the film, Doe tested the Alexa 65 and chose it.", ["Alexa 65"])
        // ("suited to" is set against by an older rule, as in 1.10.9; what matters is no plan is read into it.)
        XCTAssertFalse(read("Ideally suited to low light, the Venice was our A-camera.").judged.contains { $0.reason == .abandonedPlan })
        accepts("We priced three Alexa 65 packages and rented two.", ["Alexa 65"])
        accepts("We kept the Technocrane rig for every shoot day.", ["Technocrane"])
        accepts("Reports that it went digital are untrue: every frame was shot on Kodak 35mm.", ["35 mm"])
    }

    func testARelativeClauseCarriesThroughItsList() {
        rejects("The look recalled Ann Vale's Glass Rivers, which was shot on 16mm, Super 8 and Hi8, and nothing like it was tried here.",
                "Super 8", .otherProduction)
    }

    func testRatiosInOneSentenceKeepTheirOwnStages() {
        let specs = read("We shot on 35mm, composed for 2.39:1 and protected for 1.78:1.")
        XCTAssertEqual(specs.accepted.first { $0.name == "2.39:1" }?.stage, .framing)
        XCTAssertFalse(specs.accepted.contains { $0.name == "1.78:1" }, "a protection ratio isn't the film's frame")
    }

    // MARK: Independent review, round 2

    func testAnAsideNeverTakesTheFilmsOwnStatement() {
        accepts("Jane Doe (Glass Rivers, 2015) shot The Quiet Harbour on 35mm.", ["35 mm"])
        accepts("The Quiet Harbour, the sequel to Glass Rivers (2015), was shot on 35mm.", ["35 mm"])
    }

    func testACollectionTitleAsAPlainWordIsNoSection() {
        let text = TechSpecs.Text(source: "Lens Weekly", sections: [
            FilmArticle.Section(id: 0, title: "Making It Real", paragraphs: ["Doe shot the whole film on the Alexa 35."]),
        ], isInterview: true)
        let specs = TechSpecs.read(texts: [text], cinematographers: ["Jane Doe"], directors: ["Carl Example"], year: 2022,
                                   title: "It Chapter Three", otherTitles: ["It", "It Chapter Two"])
        XCTAssertTrue(specs.accepted.contains { $0.name.contains("Alexa 35") }, "\(specs.judged)")
    }

    func testThisFilmAfterAnotherProductionsRelativeClauseIsThisFilms() {
        // (The list a relative clause gives ends at "this one": the clause model. The sentence as a whole is
        // still read by the trailing comparison "as she had for…", as in 1.10.9.)
        let sentence = "Doe chose Kodak for Glass Rivers, which was shot on 16mm, and this one on 35mm."
        let map = ClauseMap(sentence)
        let relative = map.clauses.first { $0.role == .relative }.map(map.text) ?? ""
        XCTAssertTrue(relative.contains("16mm") && !relative.contains("35mm"), relative)
    }

    func testRealTitlesInAHeadlineAreProductions() {
        XCTAssertEqual(PageContext.headlineProduction("‘There Will Be Blood’: lighting the oil fields", title: film), "There Will Be Blood")
        XCTAssertEqual(PageContext.headlineProduction("‘Gone with the Wind’ at 85", title: film), "Gone with the Wind")
        XCTAssertNil(PageContext.headlineProduction("Doe: ‘We Had One Shot at It’", title: film))
    }

    func testARatioAfterAReleaseIsNotAsShot() {
        let specs = read("It was shot on 35mm and released in cinemas at 1.85:1.")
        XCTAssertNotEqual(specs.accepted.first { $0.name == "1.85:1" }?.stage, .capture)
    }
}

