import XCTest
@testable import ReelCore

/// A Shot on tag needs a sentence that says this film was shot that way, from an article that is
/// about this film; and the tab, the filter and search read the same texts the same way.
final class CraftEvidenceTests: XCTestCase {
    private func shotOn(_ sentences: [String], colour: [String]? = nil, keywords: [String] = []) -> [ShotOn] {
        CraftIndex.make(from: TechSpecs.read(sentences), colour: colour, keywords: keywords).shotOn
    }

    // MARK: Said not to have been used

    func testRatherThanAndInsteadOf() {
        XCTAssertEqual(shotOn(["The film was shot digitally rather than on 35 mm film, using the ARRI Alexa 65."]), [.digital])
        XCTAssertEqual(shotOn(["Instead of anamorphic lenses, they shot with spherical Cooke S4 lenses on the ARRI Alexa Mini."]), [.digital])
    }

    func testNotAndNever() {
        XCTAssertFalse(shotOn(["The production did not use IMAX cameras for any sequence, shooting on the Sony Venice."]).contains(.imax))
        XCTAssertFalse(shotOn(["The film was never shot on 35 mm film, though the look was meant to resemble it."]).contains(.film))
        XCTAssertFalse(shotOn(["IMAX cameras were not used for the night scenes because of their noise."]).contains(.imax))
    }

    func testOtherFilmsAndPlans() {
        XCTAssertFalse(shotOn(["Unlike his IMAX films, the director shot this one on the ARRI Alexa Mini LF."]).contains(.imax))
        XCTAssertFalse(shotOn(["They considered shooting on 65 mm film but chose the Alexa 65 for its sensitivity."]).contains(.film))
        XCTAssertFalse(shotOn(["The look was designed as if shot on Super 8 film, but everything was captured on the RED Komodo."]).contains(.film))
    }

    func testAClauseOfItsOwnStillCounts() {
        XCTAssertTrue(shotOn(["After testing several lenses, they chose Panavision C-Series anamorphic lenses and shot on 35 mm film."])
            .contains(.anamorphic))
        XCTAssertTrue(shotOn(["Not only was it shot on 65 mm film, but some sequences used IMAX cameras."]).contains(.film))
        // The camera names in the clause after "while" are this film's.
        XCTAssertEqual(shotOn(["Nolan filmed the battle scenes with IMAX 65 mm film cameras, while the rest was shot digitally on the RED Monstro."]),
                       [.film, .digital, .imax])
    }

    func testTheGuardItself() {
        let sentence = "They shot digitally rather than on film."
        let film = sentence.range(of: "film")!
        let digitally = sentence.range(of: "digitally")!
        XCTAssertTrue(TechSpecs.denied(sentence, at: film))
        XCTAssertFalse(TechSpecs.denied(sentence, at: digitally))
    }

    // MARK: Evidence

    func testEachTagHasItsSentenceAndSource() {
        let texts = [
            TechSpecs.Text(source: "American Cinematographer",
                           paragraphs: ["Deakins shot the picture with ARRI Alexa Mini LF cameras and Signature Prime lenses for a seamless look across every take."]),
        ]
        let specs = TechSpecs.read(texts: texts, cinematographers: ["Roger Deakins"])
        let craft = CraftIndex.make(from: specs, colour: nil, keywords: [], sources: texts.count)
        XCTAssertEqual(craft.shotOn, [.digital])
        XCTAssertEqual(craft.evidence(for: .digital)?.source, "American Cinematographer")
        XCTAssertTrue(craft.evidence(for: .digital)?.text.contains("Alexa Mini LF") ?? false)
        XCTAssertEqual(craft.sources, 1)
    }

    func testTheFilmsArticleIsNamedWikipedia() {
        let craft = CraftIndex.make(from: TechSpecs.read(["The film was shot on 35 mm film with Panavision cameras."]), colour: nil, keywords: [])
        XCTAssertEqual(craft.evidence(for: .film)?.source, "Wikipedia")
    }

    func testBlackAndWhiteKeywordOnlyWhenWikidataIsSilent() {
        XCTAssertEqual(shotOn([], colour: ["black-and-white", "color"], keywords: ["black and white"]), [],
                       "partly in colour (Oppenheimer): the keyword doesn't override Wikidata")
        XCTAssertEqual(shotOn([], colour: nil, keywords: ["black and white"]), [.blackAndWhite])
        XCTAssertEqual(CraftIndex.make(from: TechSpecs.read([]), colour: ["black-and-white"], keywords: []).evidence.first?.source, "Wikidata")
    }

    func testIMAXKeywordIsNotEvidence() {
        XCTAssertEqual(shotOn([], keywords: ["imax"]), [], "TMDB marks IMAX releases too")
    }

    func testOldSummariesStillOpen() throws {
        let saved = #"{"version":1,"readAt":"2026-01-01T00:00:00Z","shotOn":["film"],"names":["Steadicam"]}"#
        let craft = try JSONStore.decode(CraftIndex.self, from: Data(saved.utf8))
        XCTAssertEqual(craft.shotOn, [.film])
        XCTAssertTrue(craft.evidence.isEmpty)
        XCTAssertTrue(craft.isStale(), "read again by the new rules")
    }

    // MARK: Refreshing never makes it worse

    func testAThinnerReadingDoesNotReplaceAFullerOne() {
        let full = CraftIndex(shotOn: [.film, .anamorphic], names: [], sources: 4)
        XCTAssertTrue(full.keeps(over: CraftIndex(shotOn: [.film], names: [], sources: 1)), "a site was down")
        XCTAssertFalse(full.keeps(over: CraftIndex(shotOn: [.film], names: [], sources: 4)))
        XCTAssertFalse(CraftIndex(version: 1, shotOn: [.film], names: [], sources: 9).keeps(over: CraftIndex(shotOn: [], names: [], sources: 1)),
                       "new rules always replace the old reading")
    }

    // MARK: The right article

    func testAMagazineArticleMustBeAboutThisFilm() {
        let heatWave = ["Our cover story follows a summer heat wave shot by Jane Doe on the Sony Venice in 2019."]
        XCTAssertFalse(CameraSources.namesFilm(heatWave, people: ["Dante Spinotti", "Michael Mann"], year: 1995))
        let heat = ["Spinotti lit the downtown shootout with practicals and shot on 35 mm."]
        XCTAssertTrue(CameraSources.namesFilm(heat, people: ["Dante Spinotti", "Michael Mann"], year: 1995))
        XCTAssertTrue(CameraSources.namesFilm(["The 2024 release was shot on 35 mm film."], people: [], year: 2024))
        XCTAssertTrue(CameraSources.namesFilm(["It premiered in 2023 at Venice."], people: [], year: 2024), "a festival the year before")
        XCTAssertFalse(CameraSources.namesFilm(["The 1922 silent classic was shot on orthochromatic film."], people: ["Jarin Blaschke"], year: 2024),
                       "a remake isn't the original")
    }

    // MARK: One reading

    func testTheTabAndTheSummaryReadTheSameOrder() {
        let article = FilmArticle(title: "Film", extract: "== Production ==\nThe film was shot on 35 mm film.")
        let reading = CameraReading(sources: [CameraReading.Source(title: "The look", site: "American Cinematographer",
                                                                   url: URL(string: "https://theasc.com/a")!, paragraphs: ["We shot on film."])],
                                    more: [], cinematographer: nil)
        let texts = CraftReader.texts(article: article, reading: reading, hiding: false)
        XCTAssertEqual(texts.map(\.source), ["American Cinematographer", nil], "the filmmakers' own words first, then the article")
        XCTAssertEqual(CraftReader.texts(article: article, reading: nil, hiding: true).count, 1)
    }
}
