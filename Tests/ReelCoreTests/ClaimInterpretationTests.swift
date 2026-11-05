import XCTest
@testable import ReelCore

/// 1.10.9: what a statement asserts decides whether its gear is the film's (`ClaimFrame`), a
/// comparison is read for what it says of each production (`ComparisonFrame`), and titles are the
/// same title whatever their punctuation (`TitleMatch`). Made-up films and people; real gear names.
final class ClaimInterpretationTests: XCTestCase {
    let film = "The Quiet Harbour"

    /// What the reader accepts from these paragraphs, as an article about the film.
    func accepted(_ paragraphs: [String], title: String? = nil) -> Set<String> {
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: paragraphs)], cinematographers: ["Jane Doe"],
                                   directors: ["Carl Example"], year: 2022, title: title ?? film)
        return Set(specs.specs.map { $0.name.lowercased() })
    }

    func reasons(_ paragraphs: [String], title: String? = nil) -> [String: ClaimReason] {
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: paragraphs)], cinematographers: ["Jane Doe"],
                                   directors: ["Carl Example"], year: 2022, title: title ?? film)
        var found: [String: ClaimReason] = [:]
        for judged in specs.judged { found[judged.name.lowercased()] = judged.reason }
        return found
    }

    func has(_ set: Set<String>, _ name: String) -> Bool { set.contains { $0.contains(name.lowercased()) } }

    // MARK: Denial and negation

    func testAvoidedRejectedOrNotUsedIsNeverUsed() {
        let cases = [
            "He avoided Steadicam for the tennis action, instead deploying a Scorpio 45 crane with a Libra head.",
            "Doe decided against Steadicam for the night scenes.",
            "Steadicam was ruled out early because of the uneven floors.",
            "There was no Steadicam on this shoot at all.",
            "They never used a Steadicam, preferring a dolly.",
            "A Steadicam was considered for the stairwells but was never brought aboard.",
            "We didn't like the effect of using Steadicam.",
        ]
        for sentence in cases {
            XCTAssertFalse(has(accepted([sentence]), "steadicam"), sentence)
        }
        // The rest of the sentence still stands: what was used instead.
        XCTAssertTrue(has(accepted([cases[0]]), "crane"))
        XCTAssertTrue(has(accepted([cases[0]]), "libra"))
        XCTAssertTrue(has(accepted([cases[4]]), "dolly"))
        // Avoiding one technique doesn't take another confirmed one with it.
        let both = accepted(["The production avoided Steadicam entirely, relying on a dolly and handheld work in the kitchen."])
        XCTAssertFalse(has(both, "steadicam"))
        XCTAssertTrue(has(both, "dolly"), "\(both)")
    }

    // MARK: Counterfactuals and hypotheticals

    func testCounterfactualsAreNotProductionFacts() {
        XCTAssertTrue(accepted(["Without me, the film might have easily been shot in Super 35, or Super 16."]).isEmpty)
        XCTAssertFalse(has(accepted(["It could have been shot on an ARRI Alexa 35 if the budget had allowed."]), "alexa"))
        XCTAssertFalse(has(accepted(["Had it been photographed on 65mm film, the desert would have looked different."]), "65"))
        XCTAssertFalse(has(accepted(["It would have looked different with anamorphic lenses."]), "anamorphic"))
        XCTAssertFalse(has(accepted(["One could have used a Technocrane for the opening, but the street was too narrow."]), "technocrane"))
        // A fact next to a hypothetical is still a fact.
        let mixed = accepted(["We shot on the Sony Venice 2; an Alexa would have looked colder."])
        XCTAssertTrue(has(mixed, "venice"), "\(mixed)")
        // "would have to" is necessity, not a hypothetical.
        XCTAssertTrue(has(accepted(["Doe knew they would have to light the hall with HMIs through the windows, and they did."]), "hmi"))
    }

    // MARK: Plans, tests and adoption

    func testPlansAndTestsAreNotTheFilmUnlessAdopted() {
        XCTAssertFalse(has(accepted(["They intended to shoot the film on location, cinéma vérité style, using 16 mm cameras and real soldiers."]), "16"))
        XCTAssertFalse(has(accepted(["The original plan was to use the Panaflex Millennium XL2, but the package wasn't available."]), "millennium"))
        XCTAssertFalse(has(accepted(["We shot a day of tests on an ARRI Alexa Mini alongside the film camera, but it was never a contender."]), "alexa"))
        XCTAssertFalse(has(accepted(["During prep we experimented with Steadicam, dollies and a crane to see what would work."]), "steadicam"))
        // Adopted: the source says so.
        XCTAssertTrue(has(accepted(["She tested Hawk anamorphic lenses against two other sets in prep, and the Hawks went on to shoot the whole film."]), "hawk"))
        // A plan given up, then what was done instead.
        let turned = accepted(["Doe had originally planned to shoot on Super 16, and the production went with the Alexa 35."])
        XCTAssertTrue(has(turned, "alexa 35"))
        XCTAssertFalse(has(turned, "super 16"))
        // An intention that isn't about the gear isn't a plan for it.
        XCTAssertTrue(has(accepted(["His intention was to immerse the audience, so he shot it with IMAX cameras."]), "imax"))
    }

    // MARK: Whose practice

    func testOtherPeoplesPracticeIsNotThisFilms() {
        XCTAssertFalse(has(accepted(["And all the DPs of the period that I really admired would push the film stock or they would do handheld or whatever."]), "handheld"))
        XCTAssertFalse(has(accepted(["Beyond the things we learn from Terry, like shooting at magic hour, or with wide angle lenses, what matters is the story."]), "magic hour"))
        XCTAssertFalse(has(accepted(["A lot of my colleagues light miners' faces with a single LiteMat."]), "litemat"))
        // The speaker's own choice after another's practice is the film's.
        let own = accepted(["A lot of my colleagues light with a single LiteMat, but I used Astera tubes inside the helmets."])
        XCTAssertTrue(has(own, "astera"), "\(own)")
    }

    // MARK: Simulated, computer-generated, in the scene

    func testSimulationsPropsAndTheSceneAreNotEquipment() {
        XCTAssertFalse(has(accepted(["Guadagnino stages a faux-double split-diopter composite shot of all three players."]), "diopter"))
        XCTAssertFalse(has(accepted(["The film needed an emulation of the ENR silver-retention process."]), "enr"))
        XCTAssertFalse(has(accepted(["For nighttime events, the tracks are bathed in LED floodlights from tall towers, and the cars have rear lights and LED panels."]), "led panels"))
        XCTAssertFalse(has(accepted(["The glowing LED panels on the fridge were built by the art department as props."]), "led panels"))
        XCTAssertFalse(has(accepted(["Odile, the character, keeps an old Super 8 camera in the shed."]), "super 8"))
        // A practical said to light the scene is lighting.
        XCTAssertTrue(has(accepted(["The neon practicals built by the art department were the key light for the alley."]), "practical"))
        // An estimate qualifies the number, not the gear.
        XCTAssertTrue(has(accepted(["The practical fixtures were probably around 300 watts."]), "practical"))
    }

    // MARK: Capture and delivery; products

    func testDeliveryAndProductCapabilityAreNotCapture() {
        let apocalypse = accepted(["Despite filming Apocalypse Now in 2.35:1, the film's cinematographer Vittorio Storaro periodically approved home media releases in his preferred aspect ratio, the 2.00:1 Univisium."],
                                  title: "Apocalypse Now")
        XCTAssertTrue(has(apocalypse, "2.35:1"), "\(apocalypse)")
        XCTAssertFalse(has(apocalypse, "2.00:1"))
        XCTAssertFalse(has(accepted(["The restoration was released on Blu-ray in 1.78:1."]), "1.78"))
        // A presentation ratio alone isn't settled either way (abstained).
        let presented = reasons(["It was presented in its theatrical 2.35:1 widescreen aspect ratio."])
        XCTAssertEqual(presented["2.35:1"], .presentation)
        XCTAssertFalse(has(accepted(["Like the RED, the Alexa offers a broad spectrum of colours in even the darkest natural lighting conditions."]), "natural light"))
        XCTAssertFalse(has(accepted(["The ALEXA Mini LF has many new features like internal motorized ND filters."]), "nd filter"))
    }

    // MARK: Uncertainty

    func testReportsNobodyConfirmedAreHeldBack() {
        XCTAssertEqual(reasons(["Some reports say the finale was shot on a Technocrane, though Doe declined to confirm it."])["technocrane"], .uncertain)
        XCTAssertFalse(has(accepted(["There may be one or two drone shots in there."]), "drone"))
        XCTAssertFalse(has(accepted(["Some accounts suggest a Hawk anamorphic lens was used for the dream sequence."]), "hawk"))
    }

    // MARK: Comparisons

    func testAComparisonIsReadForWhatItSaysOfEachProduction() {
        // The film's claim in the main clause is the film's.
        XCTAssertTrue(has(accepted(["As with Top Gun: Maverick, Doe and Example spent four weeks grading with Company 3's colourist."], title: "F1"), "company 3"))
        XCTAssertTrue(has(accepted(["Just as he had on Call Me by Your Name and Suspiria, Mukdeeprom shot Challengers on Kodak Vision3 500T."], title: "Challengers"), "vision3"))
        XCTAssertTrue(has(accepted(["Natural light was also a valuable creative tool, as it was when Davis lensed Three Billboards Outside Ebbing, Missouri."]), "natural light"))
        XCTAssertTrue(has(accepted(["Company 3 colourist Yvan Lucas joined him in the LUT experimentation, continuing the journey they began on The Irishman (2019)."]), "company 3"))
        XCTAssertTrue(has(accepted(["The production used StageCraft technology that Fraser helped develop on the series The Mandalorian (2019–2023), particularly for consistent golden hour lighting inspired by the lighting from In the Mood for Love (2000)."]), "magic hour"))
        // The other production's gear, in the comparison, is never this film's.
        let other = accepted(["Unlike Glass Rivers, which was shot on the RED Monstro, The Quiet Harbour was shot on the Sony Venice."])
        XCTAssertTrue(has(other, "venice"))
        XCTAssertFalse(has(other, "monstro"), "\(other)")
        // And a sentence about the other film alone stays the other film's.
        XCTAssertFalse(has(accepted(["On Glass Rivers (2019), Doe shot everything on the RED Monstro."]), "monstro"))
    }

    // MARK: Titles

    func testTitleVariantsAreTheSameTitleAndCommonWordsAreNot() {
        let title = "Once Upon a Time... in Hollywood"
        for written in ["Once Upon a Time… in Hollywood", "Once Upon a Time in Hollywood", "Once Upon a Time...in Hollywood", "once upon a time in hollywood"] {
            XCTAssertTrue(TechSpecs.namesTitle("Making \(written) was a joy.", title: title), written)
        }
        XCTAssertFalse(TechSpecs.namesTitle("Once Upon a Time in America was an influence.", title: title))
        XCTAssertTrue(TechSpecs.namesTitle("Shooting Fast and Furious", title: "Fast & Furious"))
        XCTAssertTrue(TechSpecs.namesTitle("Odile’s Garden", title: "Odile's Garden"))
        XCTAssertTrue(TechSpecs.namesTitle("the Half–Light Ferry shoot", title: "Half-Light Ferry"))
        XCTAssertTrue(TechSpecs.namesTitle("Leon: The Professional", title: "Léon: The Professional"))
        // A short or common title only as written, and only as a whole word.
        XCTAssertFalse(PageContext.names("Their drive for realism shaped every set.", title: "Drive"))
        XCTAssertTrue(PageContext.names("On Drive, we shot at night.", title: "Drive"))
        XCTAssertFalse(PageContext.names("The kettle whistles in every scene.", title: "Kettle"))
        XCTAssertEqual(TitleMatch.key("Once Upon a Time... in Hollywood"), TitleMatch.key("Once Upon a Time in Hollywood"))
        XCTAssertNotEqual(TitleMatch.key("Once Upon a Time in Hollywood"), TitleMatch.key("Once Upon a Time in America"))
        // A page addressed by the title alone is the film's once the title is confirmed by its year or people.
        XCTAssertTrue(TitleMatch.isSlug(of: "Challengers", url: URL(string: "https://www.kodak.com/en/motion/blog-post/challengers/")!))
        XCTAssertFalse(TitleMatch.isSlug(of: "Challengers", url: URL(string: "https://example.org/the-challengers-of-video/")!))
    }

    /// A date opening a sentence ("On January 26, …") isn't another production: the sentence naming
    /// the film and its camera is the film's (the Boys State statement, traced in 1.10.9).
    func testADateIsNotAnotherProduction() {
        let sentence = "On January 26, AC joined cinematographers Jane Doe and Carl Example at the studio to discuss the making of their feature documentary The Quiet Harbour, shot with Canon EOS C300 Mark II cameras."
        XCTAssertFalse(PageContext.productions(in: [sentence], title: film).contains("January 26"))
        XCTAssertTrue(has(accepted([sentence]), "c300"), "\(accepted([sentence]))")
        XCTAssertTrue(PageContext.productions(in: ["In 2000, the film was restored."], title: film).isEmpty)
    }
}
