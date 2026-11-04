import XCTest
@testable import ReelCore

/// Reel 1.10.8: page context, claim anchoring, property-specific uncertainty, source-aware support
/// and unfinished downloads. Synthetic films and pages only; no rule here knows a title.
final class AttributionTests: XCTestCase {
    let film = "The Copper Lantern"

    private func page(_ title: String, _ url: String, _ paragraphs: [String]) -> PageContext {
        PageContext.classify(pageTitle: title, url: URL(string: url)!, paragraphs: paragraphs, title: film, otherTitles: [], people: ["Ada Brisk"])
    }

    // MARK: Page context

    func testAPageAboutTheFilmByItsTitleAddressOrOpening() {
        XCTAssertTrue(page("Lighting The Copper Lantern", "https://example.org/a/", ["Ada Brisk lit it with care."]).aboutFilm)
        XCTAssertTrue(page("Interview", "https://example.org/the-copper-lantern-interview/", ["Ada Brisk talks."]).aboutFilm)
        // An ambiguous title, the film throughout from its opening.
        XCTAssertTrue(page("A Conversation About Night", "https://example.org/night/", [
            "The Copper Lantern opens on a night drive.", "On The Copper Lantern, Ada Brisk chose the Sony Venice.", "It took nine weeks.",
        ]).aboutFilm)
    }

    func testAProfileOrNewsPageIsNotAboutTheFilm() {
        let profile = page("Ada Brisk Joins the Society", "https://example.org/news/ada-brisk-joins/", [
            "The Society has welcomed Ada Brisk into its membership.",
            "Her credits include Glass Rivers, The Copper Lantern, Saltmarsh and Night Ferry.",
            "On Glass Rivers, she shot with the RED Monstro.",
        ])
        XCTAssertFalse(profile.aboutFilm)
        XCTAssertEqual(profile.kind, .contributorProfile)
        XCTAssertEqual(profile.anchored, 0, "a credits list names the film without saying anything about it")
        XCTAssertEqual(Set(profile.productions), ["Glass Rivers", "Saltmarsh", "Night Ferry"])
        XCTAssertEqual(page("Studio Names New Head of Production", "https://example.org/press-release/", ["We worked on The Copper Lantern."]).kind,
                       .newsItem)
    }

    func testAStatementIsAnchoredToTheFilmUntilAnotherProductionIsNamed() {
        let anchors = PageContext.anchoring(
            "On The Copper Lantern, we lit the interiors with Kino Flos. We wanted the rooms to breathe. “Glass Rivers” was different: we shot it handheld.",
            title: film, otherTitles: [], people: [])
        XCTAssertEqual(anchors, [true, true, false])
        // A new paragraph starts unanchored.
        XCTAssertEqual(PageContext.anchoring("We used a Technocrane throughout.", title: film, otherTitles: [], people: []), [false])
        // A list naming the film anchors nothing.
        XCTAssertEqual(PageContext.anchoring("This year we delivered shots for Glass Rivers, The Copper Lantern, Saltmarsh and Night Ferry.",
                                             title: film, otherTitles: [], people: []), [false])
        // A gear list naming the film is a statement about it, not a list of credits.
        XCTAssertTrue(PageContext.anchoring("On The Copper Lantern, we used the ARRI Alexa Mini, Cooke S4s, SkyPanels and a Technocrane.",
                                            title: film, otherTitles: [], people: []).first ?? false)
    }

    func testOnAPageNotAboutTheFilmOnlyAnchoredStatementsAreRead() {
        var text = TechSpecs.Text(source: "American Cinematographer", paragraphs: [
            "Her credits include Glass Rivers, The Copper Lantern, Saltmarsh and Night Ferry.",
            "On Glass Rivers, she shot with the RED Monstro and Leica Summilux-C lenses.",
            "She began as a Steadicam operator on commercials.",
            "On The Copper Lantern, she chose the Sony Venice. We lit the interiors with Kino Flos.",
        ], isInterview: true)
        text.aboutFilm = false
        text.otherProductions = ["Glass Rivers", "Saltmarsh", "Night Ferry"]
        let specs = TechSpecs.read(texts: [text], cinematographers: ["Ada Brisk"], directors: [], year: 2020, title: film)
        let names = Set(specs.specs.map(\.name))
        XCTAssertTrue(names.contains("Sony Venice"), "\(names)")
        XCTAssertTrue(names.contains { $0.contains("Kino") }, "follows a statement about the film in its paragraph: \(names)")
        XCTAssertFalse(names.contains { $0.contains("RED") || $0.contains("Summilux") || $0 == "Steadicam" }, "\(names)")
        // The same page read the old way (about the film) takes the other production's gear.
        text.aboutFilm = true
        text.otherProductions = []
        let old = Set(TechSpecs.read(texts: [text], cinematographers: ["Ada Brisk"], directors: [], year: 2020, title: film).specs.map(\.name))
        XCTAssertTrue(old.contains("Steadicam") || old.contains { $0.contains("RED") }, "the baseline this replaces: \(old)")
    }

    // MARK: Uncertainty on the property it qualifies

    func testAGuessQualifiesOnlyWhatItIsAbout() {
        func gear(_ sentence: String) -> Set<String> {
            Set(TechSpecs.read(texts: [TechSpecs.Text(source: "American Cinematographer", paragraphs: [sentence], isInterview: false)],
                               cinematographers: ["Ada Brisk"], directors: [], year: 2020, title: film).specs.map(\.name))
        }
        XCTAssertFalse(gear("On The Copper Lantern, above all of the practicals we had little tungsten Fresnels that were probably 300 watts.").isEmpty)
        XCTAssertTrue(gear("On The Copper Lantern, they may have used Black Satin filters on the close-ups.").isEmpty)
        XCTAssertTrue(gear("Without her, The Copper Lantern might have easily been shot in Super 35.").isEmpty)
        // An estimate of how much doesn't make the format a guess.
        XCTAssertTrue(gear("The Copper Lantern was shot on 35mm film, perhaps 90 percent of it.").contains { $0.contains("35") })
    }

    // MARK: Support from more than one source

    func testAnEstablishingSourceIsKeptOverAnIncidentalMention() {
        let vfx = TechSpecs.Text(source: "befores & afters", paragraphs: ["For The Copper Lantern, the colorist out at FotoKem did an early test."],
                                 isInterview: true)
        let magazine = TechSpecs.Text(source: "American Cinematographer",
                                      paragraphs: ["On The Copper Lantern, Ada Brisk and FotoKem senior colorist Dee Cole set a LUT early in preproduction."],
                                      isInterview: false)
        let specs = TechSpecs.read(texts: [vfx, magazine], cinematographers: ["Ada Brisk"], directors: [], year: 2020, title: film)
        let lab = specs.specs.first { $0.name == "FotoKem" }
        XCTAssertNotNil(lab, "\(specs.specs.map(\.name)) / \(specs.mentioned.map(\.name))")
        XCTAssertEqual(lab?.source, "American Cinematographer")
        XCTAssertEqual(lab?.support, ["American Cinematographer"])
    }

    // MARK: Coverage when the film's own article doesn't come

    func testTheFilmsArticleNotAnsweringIsSaid() {
        var details = TMDBMovieDetails(id: 1, title: film, releaseDate: "2020-01-01")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Ada Brisk", job: "Director of Photography")])
        let reading = CameraReading(sources: [CameraReading.Source(title: "Lighting The Copper Lantern", site: "American Cinematographer",
                                                                   url: URL(string: "https://theasc.com/article/copper/")!,
                                                                   paragraphs: ["The Copper Lantern was shot on the Sony Venice.", "It took nine weeks.", "It was cold."])],
                                    more: [], cinematographer: nil)
        let index = CraftReader.reading(of: details, articleTitle: film, article: nil, reading: reading, colour: nil, articleFailed: true).index
        let states = Dictionary(uniqueKeysWithValues: (index.research ?? []).map { ($0.dimension, $0.state) })
        XCTAssertEqual(states[.lighting], .unavailable)
        XCTAssertNotEqual(states[.camera], .unavailable, "what was found stays found")
        XCTAssertTrue(index.unanswered.contains("Wikipedia"))
    }

    // MARK: Unfinished downloads

    func testADownloadInProgressIsNotAFilm() {
        func grouped(_ names: [String]) -> [String] {
            let files = names.map { name in
                FilmGrouping.File(relativePath: name, size: 2_000_000_000, modified: nil)
            }
            return FilmGrouping.group(files, minimumSize: 100_000_000).map(\.relativePath)
        }
        for suffix in ["crdownload", "part", "download", "!qb", "partial", "aria2", "opdownload", "tmp"] {
            XCTAssertEqual(grouped(["Copper Lantern (2020)/Copper Lantern (2020) 1080p.mkv.\(suffix)"]), [], suffix)
        }
        XCTAssertEqual(grouped(["Copper Lantern (2020)/Copper Lantern (2020) 1080p.mkv"]).count, 1)
        // Its parse still says what it is (shown on its page while it's in the library).
        XCTAssertTrue(FilenameParser.parse("Copper Lantern (2020) 1080p.mkv.crdownload").isIncomplete)
    }
}
