import XCTest
@testable import ReelCore

/// Reel 1.9.4: the wrong Shot on tags the 1.9.3 audit found, each with the true sentences that look
/// like it kept (the sentences are shaped like the real ones; the films and people are made up).
final class ShotOnAuditTests: XCTestCase {
    private func read(_ paragraphs: [String], source: String = "American Cinematographer", title: String? = "The Quiet Harbour",
                      dp: [String] = ["Jane Doe"], isList: Bool = false) -> (specs: TechSpecs, craft: CraftIndex) {
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: source, paragraphs: paragraphs, isList: isList)],
                                   cinematographers: dp, title: title)
        return (specs, CraftIndex.make(from: specs, colour: nil, keywords: []))
    }

    private func tags(_ sentence: String, source: String = "American Cinematographer", title: String? = "The Quiet Harbour") -> [ShotOn] {
        read([sentence], source: source, title: title).craft.shotOn
    }

    func testMoviecamAloneIsTheLenses() {
        XCTAssertEqual(tags("Doe used Moviecam, which was sharp in texture, to photograph the duels, and Iron Glass primes for the close-ups."),
                       [], "Moviecam alone is a set of lenses")
        XCTAssertEqual(tags("We shot the night exteriors on a Moviecam Compact loaded with Kodak 5219."), [.film])
        XCTAssertEqual(tags("Doe chose two Moviecam cameras for the car work."), [.film])
        XCTAssertEqual(tags("For the rooftop, the crew used the Moviecam, which was light enough to rig."), [.film])
        XCTAssertEqual(tags("We also used the Moviecams for the duels and the infrared scenes, because their ability to resolve was important."),
                       [], "the Moviecams, resolving: lenses")
    }

    /// Film and Digital both show when a film mixes them; "in part" is for the other tags.
    func testWhatsUsedForPartOfTheFilmIsInPart() {
        let dreams = read(["The camera crew shot the dream sequences on 35mm film, a habit of the director's, using anamorphic lenses."]).specs
        XCTAssertEqual(dreams.specs.first { $0.name.lowercased().contains("anamorphic") }?.partial, true,
                       "the lenses of a clause about the dream sequences")
        let aerial = read(["Doe shot the film on Kodak 5219.", "An IMAX camera was also used for some aerial work."]).craft
        XCTAssertEqual(aerial.evidence(for: .imax)?.partial, true)
        XCTAssertEqual(aerial.label(for: .imax), "IMAX (in part)")
        let whole = read(["We shot the film using Arri Alexa 35 cameras with anamorphic lenses."]).craft
        XCTAssertEqual(whole.evidence(for: .anamorphic)?.partial, false)
    }

    func testWhatWasTestedIsNotWhatItWasShotOn() {
        let tests = read(["For this film, I performed some simple tests. I shot 35mm Double-X, 35mm color film [5219], and with the Arri Alexa."]).craft
        XCTAssertEqual(tests.shotOn, [])
        XCTAssertEqual(read(["We tested many cameras. In the end we shot on the Arri Alexa 65."]).craft.shotOn, [.digital])
        XCTAssertEqual(read(["After testing, they chose Kodak Double-X. We shot on 35mm film."]).craft.shotOn.contains(.film), true)
        XCTAssertEqual(read(["We did weeks of camera tests. The film was shot on the Alexa 65 with Ultra Vista lenses."]).craft.shotOn, [.digital])
        XCTAssertEqual(read(["The costume and makeup tests began in May. Doe shot on Kodak 5219."]).craft.shotOn, [.film],
                       "tests of something else")
    }

    func testAFilmAboutChildhoodIsStillThisFilm() {
        XCTAssertEqual(tags("To capture the haze of childhood memory, we shot on Super 16."), [.film])
        XCTAssertEqual(tags("When I was a kid I shot everything on my father's Super 8 camera."), [])
    }

    /// One film's own sheet with an A and a B camera isn't a round-up; nor is the next film's sheet ours
    /// when our entry has none.
    func testRoundUpsAreSeveralFilmsSheets() {
        let own = read(["A Camera: ARRI Alexa 35 B Camera: Sony Venice 2 Lenses: Cooke S7/i Format: Digital",
                        "Doe lit the house with practicals."]).specs
        XCTAssertTrue(own.roundups.isEmpty)
        let roundup = read([
            "The Quiet Harbour Dir. Carl Example, DP: Jane Doe — a ghost story told in long takes and fog.",
            "Glass Rivers Dir. Dana Example, DP: Eve Sample — two sisters and a river that keeps rising.",
            "We wanted the water to feel like a character, so everything was handheld and close.",
            "Format: 35mm Camera: ARRICAM LT Lenses: Cooke Anamorphic/i",
            "Sun Over Water Dir. Ann Example, DP: Bob Sample — a summer at the coast, remembered.",
            "Format: Super 16mm Camera: ARRIFLEX 416 Lenses: Zeiss Ultra 16",
        ], source: "IndieWire").craft
        XCTAssertEqual(roundup.shotOn, [], "the next film's sheet isn't ours")
    }

    func testTheMagazinesOwnLinesAreNotTheFilmmakers() {
        XCTAssertEqual(tags("Filmmaker: Doe first started making movies as a kid on his dad’s Super 8 camera and also used it for his short films.",
                            source: "Filmmaker"), [])
        XCTAssertEqual(tags("Doe first started making movies as a kid on his dad’s Super 8 camera."), [], "childhood isn't this film")
        XCTAssertEqual(tags("For the dream sequences, Doe shot on Super 8 film."), [.film])
    }

    func testWhatsSaidOfAnotherFilmInAComparison() {
        let sentence = "This was chosen as a visual balance between Night Garden, which was shot using anamorphic lenses in a 2.39:1 aspect ratio, "
            + "and Night Gardens, which was filmed using spherical lenses."
        XCTAssertEqual(tags(sentence, title: "Night Garden: Return"), [])
        XCTAssertEqual(tags("Unlike Paper Moons, which was shot on 35mm film, the sequel was captured on the Alexa 35.", title: "Paper Moons II"),
                       [.digital])
        // This film's own clause still counts.
        XCTAssertEqual(tags("Doe shot the film using Arri Alexa 35 cameras, which was a first for him.", title: "Paper Moons II"), [.digital])
        XCTAssertEqual(tags("It looks like Paper Moons, which was shot on 35mm film.", title: "Paper Moons"), [.film],
                       "its own title in the clause")
    }

    /// A round-up printed as spec sheets, one block a film, no titles in quotes: only the block that
    /// names this film is read.
    func testARoundUpsSpecSheetsAreReadOnlyForThisFilm() {
        let paragraphs = [
            "Sun Over Water Dir. Ann Example, DP: Bob Sample",
            "We wanted the beach to feel like memory.",
            "Format: Super 16mm, Kodak 7219 500T film stock Camera: ARRIFLEX 416 Lenses: Zeiss Ultra 16",
            "The Quiet Harbour Dir. Carl Example, DP: Jane Doe",
            "The harbour was lit by the boats themselves.",
            "Format: Digital Camera: ARRI Alexa 65 Lenses: Cooke S4/i",
            "Glass Rivers Dir. Dana Example, DP: Eve Sample",
            "Format: 35mm Camera: ARRICAM LT Lenses: Cooke Anamorphic/i",
        ]
        let (specs, craft) = read(paragraphs, source: "IndieWire")
        XCTAssertEqual(specs.roundups, ["IndieWire"])
        XCTAssertEqual(craft.shotOn, [.digital])
        XCTAssertEqual(specs.names(.camera), ["ARRI Alexa 65"])
        // One film's own article, with its sheet once, is read in full.
        let own = read(["Doe and the director wanted the harbour to feel cold.", "Format: 35mm film Camera: ARRICAM LT Lenses: Cooke Anamorphic/i"])
        XCTAssertTrue(own.specs.roundups.isEmpty)
        XCTAssertEqual(Set(own.craft.shotOn), [.film, .anamorphic])
    }

    func testAListPageIsReadOnlyWhereItNamesTheFilm() {
        let list = [
            "Shot on hi-con b/w 16mm film stock, this film has such a strong sense of being that it’s as if two old masters joined forces.",
            "The Quiet Harbour, shot by Jane Doe on the Sony Venice, glows like a lamp in a window.",
        ]
        XCTAssertEqual(read(list, source: "Filmmaker", isList: true).craft.shotOn, [.digital])
        XCTAssertTrue(CameraSources.isListPage(title: "The 25 Best Films of 2024", url: URL(string: "https://example.com/a")!))
        XCTAssertTrue(CameraSources.isListPage(title: "Notes", url: URL(string: "https://example.com/our-favorite-films-of-the-year/")!))
        XCTAssertTrue(CameraSources.isListPage(title: "Sundance 2024 round-up: the cameras behind the films", url: URL(string: "https://example.com/b")!))
        XCTAssertFalse(CameraSources.isListPage(title: "Jane Doe on lighting The Quiet Harbour", url: URL(string: "https://example.com/c")!))
        XCTAssertFalse(CameraSources.isListPage(title: "Best Cinematography nominee Jane Doe on The Quiet Harbour",
                                                url: URL(string: "https://example.com/d")!))
    }

    func testTheReadingLogSaysWhy() throws {
        let page = CameraReading.Source(title: "Lighting The Quiet Harbour", site: "American Cinematographer",
                                        url: URL(string: "https://example.com/harbour")!,
                                        paragraphs: ["Doe chose the Sony Venice 2 as the main camera.", "I had shot another feature using a Red Epic.",
                                                     "We lit the docks with practicals."])
        let other = CameraReading.Source(title: "The Quiet Harbour (1958)", site: "British Cinematographer",
                                         url: URL(string: "https://example.com/old")!, paragraphs: [])
        let reading = CameraReading(sources: [page], more: [], cinematographer: nil, unanswered: ["Kodak"],
                                    skipped: [CameraReading.Skipped(source: other, reason: "another film of that title")])
        let json = #"{"id": 77, "title": "The Quiet Harbour", "release_date": "2023-05-01", "credits": {"cast": [], "crew": [{"name": "Jane Doe", "job": "Director of Photography"}]}}"#
        let details = try JSONDecoder().decode(TMDBMovieDetails.self, from: Data(json.utf8))
        let evaluated = CraftReader.evaluate(details, article: nil, reading: reading, colour: nil, otherTitles: [], now: Date())
        let log = CraftLog.text(details: details, articleTitle: nil, articleRead: false, reading: reading, specs: evaluated.specs,
                                index: evaluated.index)
        XCTAssertTrue(log.contains("How The Quiet Harbour (2023) was shot"))
        XCTAssertTrue(log.contains("• American Cinematographer: Lighting The Quiet Harbour (3 paragraphs)"))
        XCTAssertTrue(log.contains("another film of that title"))
        XCTAssertTrue(log.contains("DIDN'T ANSWER (read again later): Kodak"))
        XCTAssertTrue(log.contains("• Digital — American Cinematographer: “Doe chose the Sony Venice 2 as the main camera.”"), log)
        XCTAssertTrue(log.contains("Red Epic — about other work"), log)
        XCTAssertEqual(CraftLog.fileName(for: details), "The Quiet Harbour (2023) 77.txt")
    }
}
