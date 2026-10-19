import XCTest
@testable import ReelCore

/// Reel 1.9.2: a Shot on tag needs a sentence saying this film was shot that way. Each test is a
/// kind of mistake found by reading every Shot on sentence in a real library (the sentences are
/// shaped like the real ones), with the true sentences that look like them kept.
final class ShotOnStatementTests: XCTestCase {
    private func craft(_ sentences: [String], dp: [String] = ["Jane Doe"], directors: [String] = [], title: String? = nil,
                       otherTitles: [String] = [], colour: [String]? = nil) -> CraftIndex {
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "American Cinematographer", paragraphs: sentences)], cinematographers: dp,
                                   directors: directors, title: title, otherTitles: otherTitles)
        return CraftIndex.make(from: specs, colour: colour, keywords: [])
    }

    private func tags(_ sentence: String, dp: [String] = ["Jane Doe"], directors: [String] = [], title: String? = nil,
                      otherTitles: [String] = []) -> [ShotOn] {
        craft([sentence], dp: dp, directors: directors, title: title, otherTitles: otherTitles).shotOn
    }

    // MARK: Said, not shot

    func testAnOpinionOrARemarkIsNotATag() {
        XCTAssertEqual(tags("For me, that’s photochemical film, particularly 65mm Imax film."), [])
        XCTAssertEqual(tags("Each medium — celluloid and digital — has its own language and its pros and cons."), [])
        XCTAssertEqual(tags("Not so long ago, celluloid film was about to curl up and die."), [])
        XCTAssertEqual(tags("“Anything shot digitally can be modified, and evidence of it suppressed."), [])
        XCTAssertEqual(tags("The Alexa 65 is very clean and sharp, and has an impressive image range."), [])
        XCTAssertEqual(tags("We knew early on that the IMAX environment is, in my mind, synonymous with 65mm film."), [])
    }

    func testTheWaysPeopleSayItWasShot() {
        XCTAssertEqual(tags("He often pushed Kodak Vision3 500T 5219 to ISO 1,000."), [.film])
        XCTAssertEqual(tags("Panavision supplied two ALEXA XT cameras along with E and C series anamorphic lenses."), [.digital, .anamorphic])
        XCTAssertEqual(tags("Fraser decided to turn again to the Arri Rental Alexa 65 as his main camera."), [.digital])
        XCTAssertEqual(tags("Deakins once again employed his camera of choice, an Arriflex BL-4, outfitted with Zeiss primes."), [.film])
        XCTAssertEqual(tags("A quick call and Seale secured six ARRI Alexa Plus cameras for the shoot."), [.digital])
        XCTAssertEqual(tags("Camera operator George Richmond is handholding an Arricam Lite, framing the open bus door."), [.film])
        XCTAssertEqual(tags("We shot the film with Mitchell cameras, which were modified to accept Cooke anamorphic lenses."), [.anamorphic],
                       "a clause after a comma is still the same statement")
        XCTAssertEqual(tags("Although they considered shooting on film, the schedule made it impractical; as a result, it was shot digitally."),
                       [.digital])
    }

    // MARK: Other work

    func testOtherWorkIsNotThisFilm() {
        XCTAssertEqual(tags("\"Although I shoot a lot of commercials using digital cameras, I still believe film is more engaging,\" he says."), [])
        XCTAssertEqual(tags("I had shot another feature in New York using a Red Epic, which I liked very much."), [])
        XCTAssertEqual(tags("The director uses the large format like no one else, shooting several of his films with IMAX film cameras."), [])
        XCTAssertEqual(tags("Let’s say on movies in general, when you do a wide shot in anamorphic, maybe you’ll use a 40mm or a 35mm."), [])
        XCTAssertEqual(tags("He is behind the TV series, which is made on the ARRI Alexa digital camera, and was keen to use it again."), [])
        XCTAssertEqual(tags("I love seeing closeups of texts and books, especially when shot on film."), [])
        XCTAssertTrue(tags("Deakins used the ARRI Alexa XT for his work on Sicario.", dp: ["Roger Deakins"], title: "Sicario").contains(.digital),
                      "his work on this film counts")
    }

    func testAnotherFilmNamed() {
        XCTAssertEqual(tags("With “Alien” shooting on anamorphic lenses and “Aliens” on spherical, the mix they settled on was the right one.",
                            title: "Alien: Romulus"), [])
        XCTAssertEqual(tags("For Alien the crew shot with anamorphic lenses.", title: "Alien: Romulus", otherTitles: ["Alien", "Aliens"]), [])
        XCTAssertEqual(tags("Alien: Romulus was shot with spherical lenses on the ARRI Alexa 35.", title: "Alien: Romulus", otherTitles: ["Alien"]),
                       [.digital], "its own title holds the first film's")
        XCTAssertEqual(tags("“In Part One, we shot the inner journey with anamorphic lenses and switched to spherical lenses.",
                            title: "Dune: Part Two"), [])
        XCTAssertEqual(tags("While half of the Part One material was composed for Imax, the filmmakers shot Part Two entirely for Imax 1.43:1.",
                            title: "Dune: Part Two"), [.imax])
        XCTAssertEqual(tags("Sandgren won an Oscar for Chazelle’s La La Land, which he shot in the classic CinemaScope ratio.",
                            dp: ["Linus Sandgren"], directors: ["Emerald Fennell"]), [])
        XCTAssertEqual(tags("But Gareth Edwards is embracing 35mm on “Jurassic World Rebirth,” and “Twinless” was shot on 35mm by Greg Cotten."), [])
        XCTAssertEqual(tags("Lensed by Emmanuel “Chivo” Lubezki, the production was shot using natural light on the new Alexa 65."), [.digital],
                       "a nickname isn't a title")
        XCTAssertEqual(tags("Shot on Arri’s Alexa XT with Kodak’s help, the look stayed clean."), [.digital], "a maker's gear")
    }

    /// Found by the independent review: what's said after the words, a place and Part One of the
    /// film itself don't take a tag away.
    func testWhatDoesntTakeATagAway() {
        XCTAssertEqual(tags("The film was shot on 35 mm film at London's Shepperton Studios."), [.film])
        XCTAssertEqual(tags("We shot on Kodak Vision3 5219, which tends to hold the highlights."), [.film])
        XCTAssertEqual(tags("We shot on 35mm film, which you can push two stops."), [.film])
        XCTAssertEqual(tags("We shot on the ARRI Alexa 65 and built a LUT with our colourist."), [.digital])
        XCTAssertEqual(tags("Fraser shot the film on the ARRI Alexa LF, generally with Panavision anamorphic lenses."), [.digital, .anamorphic])
        XCTAssertEqual(tags("Fraser shot Part One on the ARRI Alexa LF.", title: "Dune", otherTitles: ["Dune: Part Two"]), [.digital])
        XCTAssertEqual(tags("Fraser shot “Dune: Part One” on the ARRI Alexa LF.", title: "Dune", otherTitles: ["Dune: Part Two"]), [.digital])
        XCTAssertEqual(tags("Fraser shot Part Two on the ARRI Alexa 65.", title: "Dune", otherTitles: ["Dune: Part Two"]), [])
        XCTAssertEqual(tags("I love shooting on 35mm film."), [], "an opinion, with a verb")
    }

    /// Found by the live check of films on record.
    func testFoundLive() {
        XCTAssertEqual(tags("The film was shot primarily in the anamorphic format on 35 mm film, with key sequences filmed on 65 mm."),
                       [.film, .anamorphic])
        XCTAssertEqual(tags("Nolan: We shot the film with a mixture of mostly the predominant bulk of the film is anamorphic 35mm, the best format by far."), [.film, .anamorphic])
        XCTAssertEqual(tags("They also talked about what kind of cameras he shot with (IMAX, anamorphic 35mm, 65mm, and VistaVision)."), [],
                       "a list of what an interview covered")
        XCTAssertFalse(tags("Though Scott initially wanted to film in anamorphic, the Super 35 format was chosen.").contains(.anamorphic))
        XCTAssertEqual(tags("A beautifully shot film on film, and a triumph."), [])
    }

    // MARK: Lenses and sensors

    func testALensOrASensorIsNotFilm() {
        let lenses = craft(["Most of the movie was shot with an Ultra Prime 28mm and a Super Speed 35mm."])
        XCTAssertEqual(lenses.shotOn, [])
        XCTAssertFalse(lenses.names.contains("35 mm"), "\(lenses.names)")
        XCTAssertEqual(tags("We used a few 16mm fisheye lenses because the director loved the look."), [])
        XCTAssertEqual(tags("The show carried two mini 16mm T2 and 15mm T4 lenses."), [])
        XCTAssertEqual(tags("He used the beautiful focus fall-off you get with the 65mm sensor."), [])
        XCTAssertEqual(tags("Using a RED Komodo, they wanted a small sensor cropped to Super 16mm."), [.digital])
        XCTAssertEqual(tags("They shot with the LF, whose sensor has twice the area of Super 35 sensors."), [])
        XCTAssertEqual(tags("He made us 35mm, 40mm, 50mm and 85mm anamorphic lenses that could open up to T1.3."), [.anamorphic])
    }

    func testAGaugeSaidAsFilm() {
        XCTAssertEqual(tags("He photographed it with Arricam LT cameras in 3-perf 35mm on Kodak Vision3 500T 5219."), [.film])
        XCTAssertEqual(tags("So Richardson decided to shoot on Kodak Vision3 35 mm with Panavision cameras."), [.film])
        XCTAssertEqual(tags("It was filmed on Super 16mm with a Red Epic."), [.film, .digital])
        XCTAssertEqual(tags("Two cameras roll, one capturing the scene in anamorphic 35mm, the other recording the action in 65mm."), [.film])
        XCTAssertEqual(tags("Van Hoytema shot it on 35 mm film in the Panavision anamorphic format and IMAX 70 mm."), [.film, .anamorphic, .imax])
    }

    // MARK: A look, a finish, a comparison, a test

    func testALookOrAFinishIsNotCapture() {
        XCTAssertEqual(tags("The third LUT we used combined the Ektachrome LUT with the ARRI look."), [])
        XCTAssertEqual(tags("Final outputs were a 4K DCP, an HD master and a 4K filmout to Fujifilm Eterna-RDI 4511."), [])
        XCTAssertEqual(tags("The palette chosen for the dream scenes was inspired by the classic three-strip Technicolor look."), [])
    }

    func testComparisonsAndTests() {
        XCTAssertEqual(tags("It’s a way of thinking better suited to CinemaScope, but we’re shooting for multiple formats."), [])
        XCTAssertFalse(tags("He prefers the anamorphic lens system to shooting Super 35mm and doing an anamorphic release print.").contains(.film))
        XCTAssertEqual(tags("One effects shot was filmed using IMAX cameras so the director could test the format for his next film."), [])
        XCTAssertEqual(tags("Tell us about the small bits of the movie that you shot digitally."), [])
        XCTAssertTrue(TechSpecs.isQuestion("Tell us about the small bits you shot digitally.", source: "American Cinematographer"))
    }

    // MARK: In part

    func testABlackAndWhiteStockIsInPart() {
        let flashbacks = craft(["We shot on Eastman Double-X black-and-white film (5222) for the flashbacks and the rest on Kodak Vision3 250D."])
        XCTAssertEqual(flashbacks.label(for: .blackAndWhite), "Black & white (in part)", "brackets don't hide the flashbacks")
        let storylines = craft(["To tell the storylines apart, he also shot using Eastman Double-X 5222 for the IMAX cameras."])
        XCTAssertEqual(storylines.label(for: .blackAndWhite), "Black & white (in part)")
        let list = craft(["2.39:1, 1.33:1 Anamorphic and Spherical 35mm Kodak Negative Stocks Vision3 5219, Double-X 5222 Panavision Millennium XL2"])
        XCTAssertEqual(list.label(for: .blackAndWhite), "Black & white (in part)", "a spec list names every stock used")
        XCTAssertTrue(list.shotOn.contains(.film))
        let whole = craft(["They shot on Eastman Double-X 5222."], colour: ["black-and-white"])
        XCTAssertEqual(whole.label(for: .blackAndWhite), "Black & white", "Wikidata says the whole film is")
        let colourFilm = craft(["The film was shot in black and white."], colour: ["color"])
        XCTAssertEqual(colourFilm.label(for: .blackAndWhite), "Black & white (in part)", "Wikidata says it's in colour")
    }

    func testAnOpeningThatFramesTheSentence() {
        let sequences = craft(["For sequences designed to be 2.39:1 in any presentation, he chose Panavision Ultra Vista anamorphic lenses."])
        XCTAssertEqual(sequences.label(for: .anamorphic), "Anamorphic (in part)")
        let brackets = craft(["They shot with Panavision anamorphic lenses (IMAX for key action sequences)."])
        XCTAssertEqual(brackets.label(for: .anamorphic), "Anamorphic", "the brackets aren't about the lenses")
        XCTAssertEqual(brackets.label(for: .imax), "IMAX (in part)")
    }

    // MARK: Spec lists

    func testASpecListIsAStatement() {
        XCTAssertEqual(tags("2.55:1 Cameras | Arri Alexa Mini LF Lenses | Panavision Super Speed, Arri Signature Prime"), [.digital])
        XCTAssertEqual(tags("Lenses: Cooke Anamorphic/i, Zeiss Master Primes."), [.anamorphic])
    }

    /// A name read for the notes and search is kept even where it isn't a Shot on tag.
    func testTheNamesStayForSearch() {
        let read = craft(["The Alexa 65 is very clean and sharp, and has an impressive image range."])
        XCTAssertEqual(read.shotOn, [])
        XCTAssertTrue(read.names.contains("Alexa 65"), "\(read.names)")
    }
}
