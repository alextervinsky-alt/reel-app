import XCTest
@testable import ReelCore

/// Reel 1.10.4 (rules 13): what tests were shot on isn't how the film was shot, unless the sentence
/// says the tested choice was then made. The Oppenheimer sentences are short public excerpts (Kodak,
/// British Cinematographer) as Reel read them; the rest are made up.
final class TestFootageTests: XCTestCase {
    private func oppenheimer(_ texts: [(String, [String])]) -> (specs: TechSpecs, index: CraftIndex) {
        let read = texts.map { TechSpecs.Text(source: $0.0, paragraphs: $0.1) }
        let specs = TechSpecs.read(texts: read, cinematographers: ["Hoyte van Hoytema"], directors: ["Christopher Nolan"], year: 2023,
                                   title: "Oppenheimer")
        return (specs, CraftIndex.make(from: specs, colour: nil, keywords: []))
    }

    private func quiet(_ sentences: [String]) -> (specs: TechSpecs, index: CraftIndex) {
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "American Cinematographer", paragraphs: sentences)],
                                   cinematographers: ["Jane Doe"], directors: ["Carl Example"], year: 2024, title: "The Quiet Harbour")
        return (specs, CraftIndex.make(from: specs, colour: nil, keywords: []))
    }

    static let makeUpTests = "Initially, the traditional hair-and-make up tests were shot in black-and-white."
    static let doubleX = "To support the distinction between different storylines, he also shot using EASTMAN DOUBLE-X Black & White Negative Film 5222, specially manufactured for the production by Kodak for use with the IMAX and Panavision System 65mm film cameras."

    /// 1.10.3's wrong reason: the make-up tests. By themselves they say nothing of the film.
    func testMakeUpTestsShotInBlackAndWhiteAreNotTheFilm() {
        let alone = oppenheimer([("British Cinematographer", [Self.makeUpTests])])
        XCTAssertEqual(alone.index.shotOn, [])
        XCTAssertFalse(alone.specs.specs.contains { $0.name == "Black and white" }, "named, not this film's")
        XCTAssertTrue(alone.specs.mentioned.contains { $0.name == "Black and white" })
    }

    /// With the Kodak sentence (which Reel reads first), Black & white is in part and its reason is
    /// the Double-X stock the production shot, whichever page comes first.
    func testTheDoubleXStockIsTheBlackAndWhiteReason() {
        for texts in [[("Kodak", [Self.doubleX]), ("British Cinematographer", [Self.makeUpTests])],
                      [("British Cinematographer", [Self.makeUpTests]), ("Kodak", [Self.doubleX])]] {
            let reading = oppenheimer(texts)
            XCTAssertEqual(reading.index.shotOn.contains(.blackAndWhite), true)
            let reason = reading.index.evidence(for: .blackAndWhite)
            XCTAssertEqual(reason?.text, Self.doubleX)
            XCTAssertEqual(reason?.source, "Kodak")
            XCTAssertEqual(reason?.partial, true, "in part, as before")
        }
    }

    /// Tests that led to the choice: what was chosen is how the film was shot.
    func testATestThatLedToTheChoiceStillCounts() {
        XCTAssertEqual(quiet(["We shot camera tests on 16mm and 35mm film, and in the end chose 35mm for the shoot."]).index.shotOn, [.film])
        XCTAssertEqual(quiet(["After the tests, Doe shot The Quiet Harbour on Kodak 35mm film."]).index.shotOn, [.film])
        // Tests alone don't.
        XCTAssertEqual(quiet(["We shot camera tests on 16mm film and the ARRI Alexa 35."]).index.shotOn, [])
        XCTAssertEqual(quiet(["The screen tests were filmed on Kodak 16mm film."]).index.shotOn, [])
        XCTAssertEqual(quiet(["Test footage was shot on the ARRI Alexa 65."]).index.shotOn, [])
    }

    /// Camera tests next to the film's own photography: each sentence for what it says.
    func testTestsAndTheFilmsPhotographyInOneArticle() {
        let reading = quiet(["Test footage was shot on the ARRI Alexa 65.", "Principal photography used Kodak 35mm film."])
        XCTAssertEqual(reading.index.shotOn, [.film])
        XCTAssertFalse(reading.specs.specs.contains { $0.name == "ARRI Alexa 65" })
    }

    /// Another film in the same sentence, and this film's tests: neither is a tag.
    func testAnotherFilmAndThisFilmsTestsInOneSentence() {
        let both = "Glass Rivers was shot on Kodak 65mm film, while the make-up tests for The Quiet Harbour were shot on 16mm film."
        XCTAssertEqual(quiet([both]).index.shotOn, [])
    }

    /// Stored by rules 12 with the make-up tests as the reason, read again by rules 13: the tag and
    /// its scope stay, the reason becomes the Double-X sentence.
    func testReadAgainTheReasonIsReplacedTheTagKept() {
        let old = CraftIndex(version: 12, shotOn: [.film, .blackAndWhite], names: [],
                             evidence: [CraftIndex.Evidence(shotOn: .film, text: "Van Hoytema shot Oppenheimer on KODAK 65mm.", source: "Kodak"),
                                        CraftIndex.Evidence(shotOn: .blackAndWhite, text: Self.makeUpTests, source: "British Cinematographer",
                                                            partial: true)],
                             sources: 8, read: ["Kodak", "British Cinematographer"], discovery: 5)
        XCTAssertEqual(CraftQueue.state(craft: old, attempt: nil, hasFacts: true, inCollection: false), .olderRules)
        var new = oppenheimer([("Kodak", [Self.doubleX]), ("British Cinematographer", [Self.makeUpTests])]).index
        new.read = ["Kodak", "British Cinematographer"]
        let merged = CraftIndex.merging(old: old, new: new)
        XCTAssertEqual(merged.index.evidence(for: .blackAndWhite)?.text, Self.doubleX)
        XCTAssertEqual(merged.index.evidence(for: .blackAndWhite)?.partial, true)
        XCTAssertEqual(merged.carried, [])
    }

    func testRulesVersion() {
        XCTAssertEqual(CraftIndex.currentVersion, 13)
        XCTAssertEqual(CraftIndex.currentDiscovery, 5, "finding unchanged")
        XCTAssertEqual(LibraryFile.currentVersion, 3, "library format unchanged")
    }
}
