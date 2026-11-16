import XCTest
@testable import ReelCore

/// The facts sheet's one text rule (spec §7.3): a plain sentence in the film's own article, about
/// this film, saying it was shot on something. Sentences written for these tests, in the way
/// Wikipedia's articles put it.
final class CraftFactReaderTests: XCTestCase {
    private func article(_ production: String, intro: String = "Harbour Lights is a 2019 drama film.") -> String {
        "\(intro)\n== Plot ==\nA keeper shot a flare in black and white.\n== Production ==\n=== Filming ===\n\(production)\n"
            + "== Release ==\nThe film was released in IMAX theatres and shot to the top of the box office.\n"
    }

    private func read(_ text: String, quick: QuickFacts? = nil) -> CraftFacts {
        CraftFactReader.read(article: text, title: "Harbour Lights", articleTitle: "Harbour Lights", quick: quick)
    }

    func testAPlainSentenceGivesTheFormat() {
        let facts = read(article("Principal photography took place in Maine. The film was shot on 35 mm film using Panavision Millennium XL2 cameras."))
        XCTAssertEqual(facts.facts.filter { $0.row == .format }.map(\.value), ["35 mm film"])
        XCTAssertEqual(facts.shotOn, [.film])
        XCTAssertEqual(facts.facts.first { $0.row == .camera }?.value, "Panavision Millennium XL2")
        XCTAssertNotNil(facts.facts.first?.sentence, "the sentence is shown beside the value")
        XCTAssertEqual(facts.facts.first?.source, "Wikipedia")
    }

    func testDigitalAndCamera() {
        let facts = read(article("Harbour Lights was shot digitally on the Arri Alexa Mini LF."))
        XCTAssertEqual(facts.shotOn, [.digital])
        XCTAssertTrue(facts.facts.contains { $0.row == .camera && $0.value.hasPrefix("Arri Alexa Mini LF") })
    }

    func testPartOfTheFilmIsMarked() {
        let facts = read(article("The film was shot digitally, while some scenes were shot with IMAX cameras."))
        XCTAssertEqual(Set(facts.shotOn), [.digital, .imax])
        XCTAssertEqual(facts.inPart, [.imax], "digital is the whole film; IMAX only some scenes")
        XCTAssertEqual(facts.label(for: .imax), "IMAX (in part)")
    }

    func testWhatIsNotAboutTheShootIsLeftOut() {
        // Plans, other films, exhibition, the plot, a camera without a sentence saying it was used.
        let text = article("""
            The film was originally to be shot on 65 mm film. Like his previous film, it was shot in black and white. \
            Nolan used IMAX cameras on Dunkirk (2017). The film was projected in 70 mm in select cinemas. \
            The Arri Alexa is a popular camera.
            """)
        let facts = read(text)
        XCTAssertTrue(facts.facts.isEmpty, "\(facts.facts.map(\.value))")
        XCTAssertTrue(facts.shotOn.isEmpty)
    }

    func testRatherThanKeepsOnlyWhatWasDone() {
        let facts = read(article("The film was shot on film rather than digitally."))
        XCTAssertEqual(facts.shotOn, [.film])
    }

    func testANewWordInTheTitleCounts() {
        let facts = read(article("Harbour Lights was filmed in black-and-white."))
        XCTAssertEqual(facts.shotOn, [.blackAndWhite])
    }

    func testWikidataGivesRatioColourAndAwards() {
        var quick = QuickFacts()
        quick.aspectRatios = ["2.39:1"]
        quick.colour = ["black-and-white"]
        quick.cinematographyHonours = [Honour(name: "Academy Award for Best Cinematography", won: true)]
        let facts = read("Harbour Lights is a film.", quick: quick)
        XCTAssertEqual(facts.facts.map(\.row), [.aspectRatio, .colour, .award])
        XCTAssertEqual(facts.facts.map(\.value), ["2.39:1", "Black and white", "Academy Award for Best Cinematography (won)"])
        XCTAssertEqual(facts.shotOn, [.blackAndWhite])
    }

    func testANonEnglishArticleOrNoneGivesWikidataOnly() {
        let facts = CraftFactReader.read(article: nil, title: "Harbour Lights", articleTitle: nil, quick: nil)
        XCTAssertTrue(facts.facts.isEmpty)
    }
}
