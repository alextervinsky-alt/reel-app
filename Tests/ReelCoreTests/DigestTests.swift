import XCTest
@testable import ReelCore

final class DigestTests: XCTestCase {
    let paragraphs = [
        "Principal photography began in May 2018 in Seoul and lasted about four months. The house was a set built on a backlot, designed around the story's stairs. Production designer Lee Ha-jun drew every room to the director's storyboards.",
        "The flood scenes were filmed in a large water tank, with the street rebuilt at full size so the water could rise for real.",
    ]

    func testTheLeadIsTheOpeningSentences() {
        let lead = Digest.lead(of: paragraphs, limit: 160)
        XCTAssertEqual(lead, "Principal photography began in May 2018 in Seoul and lasted about four months. The house was a set built on a backlot, designed around the story's stairs.")
        XCTAssertTrue(Digest.hasMore(paragraphs, lead: lead))
        XCTAssertFalse(Digest.hasMore(["A short section that says only one thing about the film."],
                                      lead: "A short section that says only one thing about the film."))
    }

    func testAVeryLongFirstSentenceIsCutAtAWord() {
        let long = String(repeating: "word ", count: 120) + "end."
        let lead = Digest.lead(of: [long], limit: 100)
        XCTAssertLessThanOrEqual(lead.count, 102)
        XCTAssertTrue(lead.hasSuffix("…"))
    }

    func testFactsComeFromTheirSectionAndDontRepeatTheLead() {
        let facts = [
            FunFact(category: "On set", text: "Production designer Lee Ha-jun drew every room to the director's storyboards."),
            FunFact(category: "On set", text: "Principal photography began in May 2018 in Seoul and lasted about four months."),
            FunFact(category: "Music", text: "The score was recorded in a church to give the strings a natural echo."),
        ]
        let lead = Digest.lead(of: paragraphs, limit: 100)
        XCTAssertEqual(Digest.facts(facts, in: paragraphs, lead: lead).map(\.category), ["On set"])
        XCTAssertEqual(Digest.minutes(paragraphs), 1)
    }

    func testSectionsUnderOneHeadingBecomeOneChapter() {
        let sections = [
            FilmArticle.Section(id: 1, title: "About the Film", paragraphs: ["Intro paragraph that is long enough to keep."]),
            FilmArticle.Section(id: 2, title: "Production · Development", paragraphs: ["Development paragraph."]),
            FilmArticle.Section(id: 3, title: "Production · Filming", paragraphs: ["Filming paragraph."]),
            FilmArticle.Section(id: 4, title: "Release", paragraphs: ["Release paragraph."]),
        ]
        let chapters = Digest.chapters(sections)
        XCTAssertEqual(chapters.map(\.title), ["About the Film", "Production", "Release"])
        XCTAssertEqual(chapters[1].parts.map(\.title), ["Development", "Filming"])
        XCTAssertEqual(chapters[1].paragraphs, ["Development paragraph.", "Filming paragraph."])
        XCTAssertNil(chapters[0].parts[0].title)
    }

    func testSentencesKeepNamesAndAbbreviationsWhole() {
        let text = "The film was directed by Bong Joon Ho. Its U.S. release came later, through Neon. Dr. Kim was played by J. Lee. Short one."
        XCTAssertEqual(Digest.sentences(in: text), [
            "The film was directed by Bong Joon Ho.",
            "Its U.S. release came later, through Neon.",
            "Dr. Kim was played by J. Lee.",
            "Short one.",
        ])
        let lead = Digest.lead(of: [text], limit: 80, skipping: "The film was directed by Bong Joon Ho.")
        XCTAssertEqual(lead, "Its U.S. release came later, through Neon. Dr. Kim was played by J. Lee.")
    }

    func testFactsFromNoSectionAreLeftOver() {
        let sections = [FilmArticle.Section(id: 1, title: "Production", paragraphs: ["Filming began in Seoul.  It lasted four months."])]
        let facts = [FunFact(category: "On set", text: "It lasted four months."), FunFact(category: "Awards", text: "It won the Palme d'Or.")]
        XCTAssertEqual(Digest.leftover(facts, sections: sections).map(\.text), ["It won the Palme d'Or."])
    }

    func testTheArticleIsToldInTheOrderTheFilmLivedIt() {
        let sections = [
            FilmArticle.Section(id: 1, title: "About the Film", paragraphs: ["Intro."]),
            FilmArticle.Section(id: 2, title: "Release", paragraphs: ["Release text."]),
            FilmArticle.Section(id: 3, title: "Production · Filming", paragraphs: ["Filming text."]),
            FilmArticle.Section(id: 4, title: "Production · Development", paragraphs: ["Development text."]),
            FilmArticle.Section(id: 5, title: "Production · Music", paragraphs: ["Music text."]),
            FilmArticle.Section(id: 6, title: "Reception · Box office", paragraphs: ["Box office text."]),
            FilmArticle.Section(id: 7, title: "Reception · Critical response", paragraphs: ["Critics text."]),
            FilmArticle.Section(id: 8, title: "Accolades", paragraphs: ["Awards text."]),
            FilmArticle.Section(id: 9, title: "Casting", paragraphs: ["Casting text."]),
            FilmArticle.Section(id: 10, title: "Controversy", paragraphs: ["Controversy text."]),
        ]
        let story = Digest.story(sections)
        XCTAssertEqual(story.map(\.stage), [.idea, .casting, .shoot, .music, .release, .reception, .awards, .other])
        XCTAssertEqual(story.map(\.chapter.title), ["The Idea", "Casting", "The Shoot", "Music and Sound", "Release",
                                                    "How It Was Received", "Awards", "Controversy"])
        XCTAssertEqual(story[5].chapter.parts.map(\.title), ["Box office", "Critical response"])
        XCTAssertNil(story[4].chapter.parts[0].title, "a single section under its own heading needs no heading inside")
        XCTAssertEqual(Digest.story([FilmArticle.Section(id: 1, title: "Production", paragraphs: ["Text."])]).map(\.chapter.title),
                       ["Making the Film"])
    }

    func testAPullQuoteIsSomeonesWords() {
        let paragraphs = [
            "Filming began in May. The crew spent 77 days in Seoul.",
            "Bong said he \"wanted the house to feel like a character of its own, watching the family\" from the start.",
        ]
        XCTAssertEqual(Digest.pullQuote(in: paragraphs, skipping: "Filming began in May."),
                       "Bong said he \"wanted the house to feel like a character of its own, watching the family\" from the start.")
        XCTAssertNil(Digest.pullQuote(in: ["It was called \"the best film of the year\" by many."], skipping: ""),
                     "too short to set apart")
    }

    func testWhereItWasShot() {
        let sections = [FilmArticle.Section(id: 1, title: "Production · Filming", paragraphs: [
            "Principal photography began on 12 July 2016 in Budapest, Hungary. The crew was large. Interiors were built at Origo Studios.",
            "The protein farm scenes were filmed in the greenhouses of Almería. Critics later praised the look.",
        ])]
        XCTAssertEqual(Digest.locationSentences(sections), [
            "Principal photography began on 12 July 2016 in Budapest, Hungary.",
            "Interiors were built at Origo Studios.",
            "The protein farm scenes were filmed in the greenhouses of Almería.",
        ])
    }
}
