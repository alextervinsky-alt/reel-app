import XCTest
@testable import ReelCore

final class TechSpecsTests: XCTestCase {
    func testCamerasLensesAndStockAreFound() {
        let specs = TechSpecs.read([
            "Principal photography began in March 2019. Cinematographer Roger Deakins shot the film with the ARRI Alexa Mini LF and Signature Primes, framing it at 1.90:1.",
            "Some scenes used vintage Cooke Panchro lenses. The night exteriors were lit with a single source.",
        ])
        XCTAssertEqual(specs.names(.camera), ["ARRI Alexa Mini LF"])
        XCTAssertEqual(specs.names(.lens), ["Signature Primes", "Vintage Cooke Panchro"])
        XCTAssertEqual(specs.names(.format), ["1.90:1"])
        XCTAssertEqual(specs.sentences.map(\.text), [
            "Cinematographer Roger Deakins shot the film with the ARRI Alexa Mini LF and Signature Primes, framing it at 1.90:1.",
            "Some scenes used vintage Cooke Panchro lenses.",
        ], "gear, the sentence that says most first")
        XCTAssertTrue(specs.approach.isEmpty, "the article telling of a choice is not their own words")
        XCTAssertEqual(specs.lighting.map(\.text), ["The night exteriors were lit with a single source."])
    }

    func testFilmStockAndGauge() {
        let specs = TechSpecs.read([
            "The film was shot on 35mm film using Kodak Vision3 500T 5219 stock and Panavision C-Series anamorphic lenses on a Panaflex Millennium XL2.",
        ])
        XCTAssertEqual(specs.names(.camera), ["Panaflex Millennium XL2"])
        XCTAssertEqual(specs.names(.lens), ["Panavision C-Series anamorphic"])
        XCTAssertEqual(Set(specs.names(.format)), ["Kodak Vision3 500T 5219", "35 mm", "Film"])
    }

    func testAReleaseFormatIsNotHowItWasShot() {
        let specs = TechSpecs.read([
            "The film was released in IMAX and 70 mm prints in selected theaters.",
            "Alexa Demie and Jacob Elordi joined the cast in May.",
            "The red one stood out among the costumes.",
        ])
        XCTAssertTrue(specs.isEmpty, "\(specs.specs)")
    }

    func testShotInIMAXAndDigitally() {
        let specs = TechSpecs.read([
            "Nolan filmed the battle scenes with IMAX 65 mm film cameras, while the rest was shot digitally on the RED Monstro.",
        ])
        XCTAssertEqual(Set(specs.names(.camera)), ["IMAX 65 mm film", "RED Monstro"])
        XCTAssertTrue(specs.names(.format).contains("Digital"))
        XCTAssertTrue(specs.names(.format).contains("IMAX"))
    }

    func testBlackAndWhiteAndAcademyRatio() {
        let specs = TechSpecs.read([
            "It was photographed in black-and-white on Eastman Double-X 5222 in the Academy ratio.",
        ])
        XCTAssertEqual(Set(specs.names(.format)), ["Black and white", "Eastman Double-X 5222", "1.33:1 (Academy)"])
    }

    func testWikipediaSpellingsAndReleaseVersions() {
        let specs = TechSpecs.read([
            "It was filmed on Super 16mm with a Red Epic and Panavision lenses.",
            "The film was shot digitally and released in IMAX theaters.",
            "The IMAX release expanded the aspect ratio to 1.90:1 for some scenes.",
            "It premiered at Venice 2022 alongside the restored version.",
        ])
        XCTAssertEqual(specs.names(.camera), ["Red Epic"])
        XCTAssertEqual(specs.names(.lens), ["Panavision"])
        XCTAssertEqual(Set(specs.names(.format)), ["Super 16 mm", "Digital"])
    }

    func testLightsAndTheApproach() {
        let sections = [
            FilmArticle.Section(id: 1, title: "Production · Filming", paragraphs: [
                "Filming took place in Seoul over 77 days.",
                "Hong wanted the rich family's house to feel open, and lit it mostly with natural light through its large windows, adding ARRI SkyPanels and a 12K HMI outside.",
                "The basement scenes were shot handheld with long takes, so the camera stays close to the family.",
                "The night scenes used sodium vapour lights and practicals to give the streets an orange glow.",
            ]),
            FilmArticle.Section(id: 2, title: "Reception", paragraphs: [
                "Critics praised the lighting and the camera work, and the film won the Palme d'Or.",
            ]),
            FilmArticle.Section(id: 3, title: "Music", paragraphs: [
                "The score's compositions use the camera as a motif.",
            ]),
        ]
        let specs = TechSpecs.read(sections: sections, cinematographers: ["Hong Kyung-pyo"])
        XCTAssertEqual(Set(specs.names(.light)), ["Natural light", "ARRI SkyPanels", "12K HMI", "Sodium vapour", "Practicals"])
        XCTAssertEqual(specs.intent.map(\.text), [
            "Hong wanted the rich family's house to feel open, and lit it mostly with natural light through its large windows, adding ARRI SkyPanels and a 12K HMI outside.",
        ], "the visual idea, with what it was lit with")
        XCTAssertEqual(specs.lighting.count, 1, "\(specs.lighting)")
        XCTAssertEqual(specs.cameraLanguage.map(\.text), ["The basement scenes were shot handheld with long takes, so the camera stays close to the family."])
        XCTAssertTrue(specs.sentences.isEmpty)
    }

    func testTheCinematographersFollowingSentenceIsTheirsToo() {
        let specs = TechSpecs.read(sections: [FilmArticle.Section(id: 1, title: "Production · Cinematography", paragraphs: [
            "In terms of practical lighting, the DP had specific requests regarding the color. He wanted sophisticated indirect lighting and the warmth from tungsten light sources.",
            "Bong chose to shoot the film without traditional coverage.",
        ])], cinematographers: ["Hong Kyung-pyo"])
        XCTAssertEqual(specs.lighting.count, 2, "\(specs.lighting)")
        XCTAssertEqual(specs.cameraLanguage.map(\.text), ["Bong chose to shoot the film without traditional coverage."])
        XCTAssertEqual(Set(specs.names(.light)), ["Practicals", "Tungsten"])
    }

    func testAnInterviewGivesTheirOwnWordsAndTheGear() {
        let interview = TechSpecs.Text(source: "American Cinematographer", paragraphs: [
            "“We shot on the ARRI Alexa 65 with Panavision Sphero 65 lenses because we wanted the landscapes to feel enormous.” It gave us room in the frame.",
            "Deakins and Villeneuve first met in Montreal for dinner.",
            "AC: How did you light the casino and the dust storm sequences?",
            "AC: You don't seem to be a huge fan of traditional camera coverage.",
            "I lit the casino with a single big source, bounced off the ceiling, so the faces fell into shadow.",
            "The production was based in Budapest, where the crew built several stages.",
            "We graded with a show LUT designed with our colorist to keep the orange of the dust.",
            "The camera was mostly on a dolly or a Technocrane, and we used a Black Pro-Mist 1/8 on every lens.",
        ])
        let specs = TechSpecs.read(texts: [interview], cinematographers: ["Roger Deakins"])
        XCTAssertEqual(Set(specs.approach.map(\.text)), [
            "“We shot on the ARRI Alexa 65 with Panavision Sphero 65 lenses because we wanted the landscapes to feel enormous.” It gave us room in the frame.",
            "I lit the casino with a single big source, bounced off the ceiling, so the faces fell into shadow.",
            "We graded with a show LUT designed with our colorist to keep the orange of the dust.",
            "The camera was mostly on a dolly or a Technocrane, and we used a Black Pro-Mist 1/8 on every lens.",
        ], "only what's about the look, the next sentence kept with the one it finishes, never the interviewer's lines")
        XCTAssertTrue(specs.approach.first?.text.contains("Technocrane") == true, "the most telling first")
        XCTAssertTrue(specs.approach.allSatisfy { $0.source == "American Cinematographer" })
        XCTAssertEqual(specs.names(.camera), ["ARRI Alexa 65"])
        XCTAssertEqual(specs.names(.lens), ["Panavision Sphero 65"])
        XCTAssertEqual(Set(specs.names(.support)), ["Dolly", "Technocrane"])
        XCTAssertEqual(specs.names(.filter), ["Black Pro-Mist 1/8"])
        XCTAssertEqual(specs.names(.finish), ["A show LUT"])
        XCTAssertEqual(specs.brief(by: ["Roger Deakins"], ratio: "1.43:1"),
                       "Shot by Roger Deakins on ARRI Alexa 65 with Panavision Sphero 65 lenses. Framed at 1.43:1.")
    }

    func testReasonsColourAndTheBrief() {
        let specs = TechSpecs.read([
            "The film was shot on 35 mm film with anamorphic lenses, and lit largely with natural light.",
            "Anamorphic lenses were chosen because the director wanted the background to fall apart into soft ovals.",
            "The colour palette was drained of greens, leaving the city in browns and greys.",
            "The camera rarely moves, framing the characters in wide shots.",
        ])
        XCTAssertEqual(specs.intent.map(\.text), ["Anamorphic lenses were chosen because the director wanted the background to fall apart into soft ovals."])
        XCTAssertEqual(specs.colour.map(\.text), ["The colour palette was drained of greens, leaving the city in browns and greys."])
        XCTAssertEqual(specs.cameraLanguage.map(\.text), ["The camera rarely moves, framing the characters in wide shots."])
        XCTAssertEqual(specs.brief(by: ["Bradford Young"]),
                       "Shot by Bradford Young with anamorphic lenses. Photographed on 35 mm. Lit with natural light.")
    }

    func testTheSameThingSaidTwiceIsShownOnce() {
        let interview = TechSpecs.Text(source: "No Film School", paragraphs: [
            "“We lit the whole house with tungsten practicals and one big soft source outside,” Hong said.",
            "Hong said they lit the whole house with tungsten practicals and one big soft source outside the windows.",
            "\"I knew that Korean audiences would react well to this film.\"",
        ])
        let specs = TechSpecs.read(texts: [interview], cinematographers: ["Hong Kyung-pyo"])
        XCTAssertEqual(specs.approach.count, 1, "\(specs.approach.map(\.text))")
    }

    func testAnEditorsInterviewIsNotReadForTheCamera() {
        XCTAssertTrue(CameraSources.isOtherCraft(title: "'Parasite' Editor Jinmo Yang Teaches Us How to Edit Without Coverage",
                                                 cinematographers: ["Hong Kyung-pyo"]))
        XCTAssertFalse(CameraSources.isOtherCraft(title: "How the Cinematographer and Editor of 'Parasite' Built Its Rhythm",
                                                  cinematographers: ["Hong Kyung-pyo"]))
        XCTAssertFalse(CameraSources.isOtherCraft(title: "Universal Translator: Arrival", cinematographers: ["Bradford Young"]))
        XCTAssertTrue(TechSpecs.isQuestion("NFS: Bong doesn't seem to be a huge fan of coverage.", source: "No Film School"))
        XCTAssertTrue(TechSpecs.isQuestion("Q: Tell us about the lighting.", source: nil))
        XCTAssertFalse(TechSpecs.isQuestion("DP: We lit it with one big source.", source: "No Film School"))
        XCTAssertFalse(TechSpecs.isQuestion("We lit it with one big source.", source: "No Film School"))
    }

    func testAPieceAboutTheCinematographyIsToldInItsParts() {
        let sections = [FilmArticle.Section(id: 1, title: "Production · Cinematography", paragraphs: [
            "The director of photography was Bradford Young, a well-known cinematographer.",
            "Young had previously worked with Villeneuve's producers, and Villeneuve hired him after seeing Selma.",
            "The look was inspired by the photographs of Martina Hoogland Ivanow, whose pictures feel haunted yet hopeful.",
            "Villeneuve wanted the alien ship to feel ordinary, so the interiors were lit by a single screen of light.",
            "The helicopter scene at night was lit with searchlights and strobes from a crane.",
            "Lighting the mist inside the ship was the hardest problem, and the crew built a custom LED sled for it.",
        ])]
        let specs = TechSpecs.read(sections: sections, cinematographers: ["Bradford Young"], directors: ["Denis Villeneuve"])
        XCTAssertEqual(specs.references.count, 1, "\(specs.references)")
        XCTAssertEqual(specs.intent.count, 1, "\(specs.intent)")
        XCTAssertEqual(specs.scenes.map(\.text), ["The helicopter scene at night was lit with searchlights and strobes from a crane."])
        XCTAssertEqual(specs.challenges.count, 1, "\(specs.challenges)")
        XCTAssertEqual(specs.collaboration.map(\.text), ["Young had previously worked with Villeneuve's producers, and Villeneuve hired him after seeing Selma."])
        let all = specs.intent + specs.references + specs.lighting + specs.cameraLanguage + specs.sentences + specs.approach
        XCTAssertFalse(all.contains { $0.text.hasPrefix("The director of photography was") }, "who shot it says nothing on its own")
    }

    func testTheCinematographysOwnAwards() {
        let honours = WikipediaClient.cinematographyHonours(
            won: ["Academy Award for Best Picture", "BAFTA Award for Best Cinematography", "Camerimage Golden Frog"],
            nominated: ["Academy Award for Best Cinematography", "BAFTA Award for Best Cinematography", "Academy Award for Best Director"])
        XCTAssertEqual(honours, [
            Honour(name: "BAFTA Award for Best Cinematography", won: true),
            Honour(name: "Camerimage Golden Frog", won: true),
            Honour(name: "Academy Award for Best Cinematography", won: false),
        ])
    }
}
