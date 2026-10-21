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

    func testAReadingASiteDidntAnswerIsReadAgainLater() {
        let now = Date()
        // A first reading with a site asking to wait: kept, read again in six hours, then a day…
        var reading = CraftIndex.merge(old: nil, new: CraftIndex(readAt: now, shotOn: [], names: [], sources: 1,
                                                                 unanswered: ["American Cinematographer"]), now: now)
        XCTAssertEqual(reading.retries, 1)
        XCTAssertTrue(reading.willReadAgain)
        XCTAssertFalse(reading.isStale(now: now.addingTimeInterval(3600)))
        XCTAssertTrue(reading.isStale(now: now.addingTimeInterval(7 * 3600)))
        for _ in 0..<3 {
            reading = CraftIndex.merge(old: reading, new: CraftIndex(shotOn: [], names: [], sources: 1, unanswered: ["American Cinematographer"]), now: now)
        }
        XCTAssertEqual(reading.retries, 4)
        XCTAssertEqual(reading.retryAt, now.addingTimeInterval(7 * 86_400), "six hours, a day, three days, a week")
        reading = CraftIndex.merge(old: reading, new: CraftIndex(shotOn: [], names: [], sources: 1, unanswered: ["American Cinematographer"]), now: now)
        XCTAssertNil(reading.retryAt, "after that what was read stands")
        XCTAssertFalse(reading.willReadAgain)
        // A complete reading clears it.
        let complete = CraftIndex.merge(old: reading, new: CraftIndex(shotOn: [.film], names: [], sources: 3), now: now)
        XCTAssertEqual(complete.retries, 0)
        XCTAssertNil(complete.retryAt)
    }

    /// The 1.9.3 re-read of a whole library, while a magazine asks Reel to wait: a fuller reading by
    /// 1.9.2's rules isn't lost, and isn't read again on every pass.
    func testAFullerOlderReadingWaitsForTheSite() {
        let now = Date()
        let old = CraftIndex(version: 4, readAt: now.addingTimeInterval(-86_400), shotOn: [.film, .anamorphic], names: ["Panaflex"], sources: 5)
        var kept = CraftIndex.merge(old: old, new: CraftIndex(readAt: now, shotOn: [], names: [], sources: 1,
                                                              unanswered: ["American Cinematographer"]), now: now)
        XCTAssertEqual(kept.version, 4)
        XCTAssertEqual(kept.shotOn, [.film, .anamorphic])
        XCTAssertFalse(kept.isStale(now: now.addingTimeInterval(60)), "not on the next pass, though its rules are older")
        XCTAssertTrue(kept.isStale(now: now.addingTimeInterval(7 * 3600)))
        for _ in 0..<3 {
            kept = CraftIndex.merge(old: kept, new: CraftIndex(shotOn: [], names: [], sources: 1, unanswered: ["American Cinematographer"]), now: now)
        }
        XCTAssertEqual(kept.version, 4, "four tries in all")
        let full = CraftIndex.merge(old: kept, new: CraftIndex(shotOn: [.film, .anamorphic], names: [], sources: 5), now: now)
        XCTAssertEqual(full.version, CraftIndex.currentVersion)
        XCTAssertNil(full.retryAt)
    }

    func testOlderReadingsOpenWithoutTheNewFields() throws {
        let saved = #"{"version":4,"readAt":"2026-10-01T00:00:00Z","shotOn":["film"],"names":["Steadicam"],"sources":3,"discovery":2}"#
        let craft = try JSONStore.decode(CraftIndex.self, from: Data(saved.utf8))
        XCTAssertTrue(craft.unanswered.isEmpty)
        XCTAssertEqual(craft.retries, 0)
        XCTAssertTrue(craft.isStale(), "read again by the 1.9.3 rules")
        let data = try JSONEncoder().encode(CraftIndex(shotOn: [.film], names: [], unanswered: ["Kodak"], retries: 2, retryAt: Date()))
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
            "“Twinless” was shot on the ARRI Alexa 35, “Sorry, Baby” on the Sony Venice 2 and “Hal and Harper” on the RED V-Raptor, the Canon C300 and the Blackmagic Pocket Cinema Camera 4K.",
            "“Rebirth” shot on the Arricam LT, the Arriflex 416, the Panaflex Millennium XL2 and the Aaton XTR Prod.",
            "Megalopolis was shot on the ARRI Alexa 65 with Cooke lenses.",
        ])
        let specs = TechSpecs.read(texts: [roundup], cinematographers: ["Mihai Mălaimare Jr."], title: "Megalopolis")
        XCTAssertEqual(specs.names(.camera), ["ARRI Alexa 65"], "\(specs.names(.camera))")
        // One film's long article naming many cameras, but no other titles, is read in full.
        let feature = TechSpecs.Text(source: "American Cinematographer", paragraphs: [
            "We shot on the Sony Venice, the Venice Rialto, the Red Komodo, the ARRI Alexa Mini, the Alexa LF, the Alexa 65, a GoPro Hero 7 and a Blackmagic Pocket Cinema Camera 4K.",
        ])
        XCTAssertEqual(TechSpecs.read(texts: [feature], cinematographers: ["Jane Doe"], title: "Top Gun").names(.camera).count >= 6, true)
    }
}
