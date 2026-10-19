import XCTest
@testable import ReelCore

/// Reel 1.9.1: what Reel says is what the sources say about this film. Each test is a kind of
/// mistake found in a real library (the sentences are shaped like the real ones).
final class TrustTests: XCTestCase {
    private func craft(_ sentences: [String], source: String = "American Cinematographer", dp: [String] = ["Jane Doe"],
                       directors: [String] = [], year: Int? = nil, title: String? = nil) -> CraftIndex {
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: source, paragraphs: sentences)], cinematographers: dp,
                                   directors: directors, year: year, title: title)
        return CraftIndex.make(from: specs, colour: nil, keywords: [])
    }

    // MARK: Another film

    func testSomeonesWorkOnAnotherFilm() {
        let read = craft(["The same weekend, Lachman won the Spirit Award for his Super 16mm work on Carol, a film shot entirely on film."],
                         dp: ["Emmanuel Lubezki"], year: 2015, title: "The Revenant")
        XCTAssertFalse(read.names.contains { $0.contains("16") }, "\(read.names)")
        let own = craft(["Deakins used the ARRI Alexa XT for his work on Sicario."], dp: ["Roger Deakins"], year: 2015, title: "Sicario")
        XCTAssertTrue(own.shotOn.contains(.digital), "his work on this film counts")
    }

    func testAnotherDirectorsFilmByTitle() {
        XCTAssertTrue(TechSpecs.aboutOtherFilm("A high-water mark was Christopher Nolan's Oppenheimer, shot on 65mm and IMAX.",
                                               year: 2025, people: ["Robbie Ryan", "Yorgos Lanthimos"]))
        XCTAssertFalse(TechSpecs.aboutOtherFilm("Denis Villeneuve's Dune was shot on the Alexa LF.", year: 2021,
                                                people: ["Greig Fraser", "Denis Villeneuve"]), "this film's own director")
        XCTAssertFalse(TechSpecs.aboutOtherFilm("They shot on Eastman Kodak's Vision3 500T.", year: 2020, people: []), "a maker, not a film")
        let read = craft(["A high-water mark was Christopher Nolan's Oppenheimer, which was shot on 65mm and IMAX cameras."],
                         dp: ["Robbie Ryan"], directors: ["Yorgos Lanthimos"], year: 2025)
        XCTAssertFalse(read.shotOn.contains(.imax))
    }

    func testAnEarlierYearIsEarlierWork() {
        XCTAssertTrue(TechSpecs.aboutOtherFilm("Back in 1993, he shot on a Sony F900 digital camera.", year: 2024, people: []))
        XCTAssertFalse(TechSpecs.aboutOtherFilm("In 2023 they prepped, shooting the next spring.", year: 2024, people: []))
        XCTAssertFalse(TechSpecs.aboutOtherFilm("In 2019, Pope recalled shooting it on Super 35.", year: 1999, people: []),
                       "a later year is often an interview looking back")
        XCTAssertFalse(TechSpecs.aboutOtherFilm("It was finished at 2048 x 858 and 1920p.", year: 2015, people: []), "not years")
    }

    /// Found by reading the evidence for well-known films in CI.
    func testNotEnoughAndCamerasInGeneral() {
        XCTAssertFalse(craft(["I shot in Super 35 partially because I had too many cameras to come up with enough anamorphic lenses."],
                             dp: ["Bill Pope"]).shotOn.contains(.anamorphic), "The Matrix wasn't anamorphic")
        XCTAssertFalse(craft(["Every digital camera is trying hard to emulate 35mm film, and there's a reason for that."])
            .shotOn.contains(.digital), "a remark about cameras in general")
        XCTAssertTrue(craft(["Two cameras roll, one capturing the scene in anamorphic 35mm, the other recording the action in 65mm."])
            .shotOn.contains(.film))
    }

    /// True facts that look like the mistakes, kept.
    func testTrueSentencesThatLookLikeMistakes() {
        XCTAssertFalse(TechSpecs.aboutOtherFilm("It was the first 65 mm feature since Far and Away (1992).", year: 2012, people: []))
        XCTAssertFalse(TechSpecs.aboutOtherFilm("Filming began in 2002 on 35 mm and lasted twelve years.", year: 2014, people: []))
        XCTAssertFalse(TechSpecs.aboutOtherFilm("He used Cooke lenses from 1965 for the interiors.", year: 2020, people: []))
        XCTAssertFalse(TechSpecs.aboutOtherFilm("Fraser shot Frank Herbert's Dune on the Alexa LF.", year: 2021, people: ["Greig Fraser"], title: "Dune"),
                       "the author of what this film is")
        XCTAssertFalse(TechSpecs.aboutOtherFilm("Hong framed Bong Joon Ho's Parasite in 2.39:1.", year: 2019, people: ["Bong Joon-ho"]),
                       "a name written without its hyphen")
        XCTAssertTrue(craft(["They shot against blue screen on the ARRI Alexa 65."]).shotOn.contains(.digital))
        XCTAssertTrue(craft(["Camera tests confirmed the ARRI Alexa 65 for the shoot."]).shotOn.contains(.digital))
        XCTAssertTrue(craft(["In his work on Sicario Deakins shot with the ARRI Alexa XT."], dp: ["Roger Deakins"], title: "Sicario")
            .shotOn.contains(.digital))
        XCTAssertTrue(craft(["The camera work for the film was shot with Panavision anamorphic lenses."]).shotOn.contains(.anamorphic))
        XCTAssertTrue(craft(["Principal photography with 35 mm film cameras finished in May."]).shotOn.contains(.film))
        let anamorphic = craft(["They shot with Panavision anamorphic lenses (IMAX for key action sequences)."])
        XCTAssertEqual(anamorphic.label(for: .anamorphic), "Anamorphic", "the brackets are a clause of their own")
    }

    // MARK: Decisions and tests

    func testDecidedAgainstAndTests() {
        XCTAssertFalse(craft(["This informed their decision against shooting with anamorphic lenses because it felt too much like a movie."])
            .shotOn.contains(.anamorphic))
        XCTAssertFalse(craft(["We shot split screen tests of digital cameras versus 3-perf 35mm and 16mm film, which looked gorgeous."])
            .shotOn.contains(.film))
        XCTAssertTrue(craft(["After testing several lenses, they shot with Panavision C-Series anamorphic lenses."])
            .shotOn.contains(.anamorphic), "the choice after the tests counts")
    }

    // MARK: Finishing

    func testFinishingIsNotShooting() {
        XCTAssertFalse(craft(["Fraser's hybrid photochemical finishing gave the images their texture."]).shotOn.contains(.film))
        XCTAssertFalse(craft(["New 70 mm prints were made for the anniversary screenings."]).shotOn.contains(.film))
        XCTAssertTrue(craft(["The film was shot on 35 mm film and finished photochemically."]).shotOn.contains(.film),
                      "shot on it, then finished: still shot on it")
    }

    // MARK: Part of the film

    func testPartOfTheFilm() {
        let read = craft(["Richardson shot with Kodak Vision3 500T, along with some Double-X black-and-white for simulated television footage."])
        XCTAssertEqual(read.label(for: .blackAndWhite), "Black & white (in part)")
        XCTAssertEqual(read.label(for: .film), "Film", "film and digital show both when mixed: never 'in part'")
        let imax = craft(["The battle scenes were shot with IMAX cameras.", "The whole film was shot on IMAX film cameras by van Hoytema."])
        XCTAssertEqual(imax.label(for: .imax), "IMAX", "said of the whole film once: the whole film")
    }

    // MARK: Reviews

    func testToneAloneIsNotADislike() {
        let critics = [ReviewText(text: "Derek Elley of Variety notes the film is anchored by a performance of grim determination.", rating: nil, isCritic: true)]
        let summary = ReceptionAnalyzer.summarize(critics, sentiment: { _ in -0.7 })
        XCTAssertEqual(summary?.disliked ?? [], [], "praise in a dark tone")
        let warm = [ReviewText(text: "A close-knit family with some bubbling trauma gives the characters their setting.", rating: 9)]
        XCTAssertEqual(ReceptionAnalyzer.summarize(warm, sentiment: { _ in -0.6 })?.disliked ?? [], [])
        let low = [ReviewText(text: "The story felt hollow and lifeless from start to finish.", rating: 3)]
        XCTAssertTrue((ReceptionAnalyzer.summarize(low, sentiment: { _ in -0.7 })?.disliked ?? []).map(\.aspect).contains("Story"),
                      "a viewer who rated it low and says so")
    }

    // MARK: Did You Know?

    func testAFolderThatSaysBeatsAGuessFromTheName() {
        let found = FilePicture.of(FilenameParser.parse("Film.2019.1080p.WEB-DL.x265-GRP.mkv"),
                                   ownFolder: FilenameParser.parse("Film (2019) 1080p DV HDR10"))
        XCTAssertEqual(found.range, .dolbyVision)
        XCTAssertEqual(found.basis, .folder)
    }

    func testCriticsFaultInMoreWords() {
        let critics = [ReviewText(text: "Several critics found the second half sluggish and the story derivative.", rating: nil, isCritic: true)]
        XCTAssertFalse((ReceptionAnalyzer.summarize(critics, sentiment: { _ in -0.6 })?.disliked ?? []).isEmpty)
    }

    func testFactsAreWholeSentences() {
        let sentences = ReceptionAnalyzer.sentences(in: "Time Out listed Léon at No. 5 among action films. It was filmed in St. Louis and Paris.")
        XCTAssertEqual(sentences.count, 2)
        XCTAssertTrue(sentences[0].hasSuffix("action films."))
        XCTAssertTrue(FunFactExtractor.startsWithSomeone("He was inspired by a road sign he once saw in England."))
        XCTAssertFalse(FunFactExtractor.startsWithSomeone("Hesitant at first, the studio agreed to shoot in New York."))
        XCTAssertTrue(FunFactExtractor.startsWithSomeone("He's said the ending came to him in a dream."))
        XCTAssertEqual(ReceptionAnalyzer.sentences(in: "It was released widely in the U.S. It grossed $50 million in its first month.").count, 2)
    }
}
