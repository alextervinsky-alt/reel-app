import XCTest
@testable import ReelCore

/// Reel 1.9.3: a site that didn't answer, or asked Reel to wait, isn't taken for "nothing written".
final class ReadingAgainTests: XCTestCase {
    func testACaptchaPageIsNotThePage() {
        let siteGround = #"<html><head><link rel="icon" href="data:;"><meta http-equiv="refresh" content="0;/.well-known/sgcaptcha/?r=%2Fwp-json%2F"></head></html>"#
        XCTAssertTrue(CameraSources.isChallenge(Data(siteGround.utf8)))
        XCTAssertTrue(CameraSources.isChallenge(Data("<html><head><title>Just a moment...</title>".utf8)))
        XCTAssertFalse(CameraSources.isChallenge(Data(#"[{"title":"Barbie","url":"https://theasc.com/articles/barbie"}]"#.utf8)))
        XCTAssertFalse(CameraSources.isChallenge(Data("<html><body><p>Prieto shot Barbie on film.</p></body></html>".utf8)))
    }

    func testAReadingASiteDidntAnswerIsReadAgainSoon() {
        let now = Date()
        var reading = CraftIndex(readAt: now.addingTimeInterval(-7 * 3600), shotOn: [], names: [], sources: 1)
        XCTAssertFalse(reading.isStale(now: now))
        reading.unanswered = ["American Cinematographer"]
        reading.retries = 1
        XCTAssertTrue(reading.isStale(now: now), "a few hours later")
        reading.readAt = now.addingTimeInterval(-3600)
        XCTAssertFalse(reading.isStale(now: now), "not straight away")
        reading.readAt = now.addingTimeInterval(-7 * 3600)
        reading.retries = CraftIndex.maxRetries
        XCTAssertFalse(reading.isStale(now: now), "after a few tries, what was read stands")
    }

    func testOlderReadingsOpenWithoutTheNewFields() throws {
        let saved = #"{"version":4,"readAt":"2026-10-01T00:00:00Z","shotOn":["film"],"names":["Steadicam"],"sources":3,"discovery":2}"#
        let craft = try JSONStore.decode(CraftIndex.self, from: Data(saved.utf8))
        XCTAssertTrue(craft.unanswered.isEmpty)
        XCTAssertEqual(craft.retries, 0)
        XCTAssertTrue(craft.isStale(), "read again by the 1.9.3 rules")
        let data = try JSONEncoder().encode(CraftIndex(shotOn: [.film], names: [], unanswered: ["Kodak"], retries: 2))
        XCTAssertEqual(try JSONDecoder().decode(CraftIndex.self, from: data).unanswered, ["Kodak"])
    }

    func testTheSheetHoldsOnlyThisFilmsGear() {
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "British Cinematographer", paragraphs: [
            "I had shot another feature in New York using a Red Epic, which I liked very much.",
            "For this film we shot on the Sony F65 with Xtal Express anamorphic lenses.",
            "The Alexa 65 is very clean and sharp, and has an impressive image range.",
            "In general, I love natural light for interiors.",
            "We lit the house with practicals and a few Kino Flos.",
        ])], cinematographers: ["Jane Doe"])
        XCTAssertEqual(specs.names(.camera), ["Sony F65"], "another film's camera and a remark aren't this film's")
        XCTAssertTrue(specs.mentioned.contains { $0.name == "Red Epic" })
        XCTAssertEqual(Set(specs.names(.light)), ["Practicals", "Kino Flos"], "a remark in general isn't this film's light")
    }

    func testARoundUpIsReadWhereItNamesTheFilm() {
        let roundup = TechSpecs.Text(source: "IndieWire", paragraphs: [
            "Cameras this year: the ARRI Alexa 35, the Sony Venice 2, the RED V-Raptor, the Canon C300 and the Blackmagic Pocket Cinema Camera 4K.",
            "Others shot on the Arricam LT, the Arriflex 416, the Panaflex Millennium XL2 and the Aaton XTR Prod.",
            "Megalopolis was shot on the ARRI Alexa 65 with Cooke lenses.",
        ])
        let specs = TechSpecs.read(texts: [roundup], cinematographers: ["Mihai Mălaimare Jr."], title: "Megalopolis")
        XCTAssertEqual(specs.names(.camera), ["ARRI Alexa 65"], "\(specs.names(.camera))")
    }
}
