import XCTest
@testable import ReelCore

final class ReceptionTests: XCTestCase {
    /// Wikipedia's critics, as for Spirited Away; the sentiment model is wrong on purpose (it
    /// calls everything a little negative), as the Mac's often is on reported speech.
    func testCriticsAreReadByWhatTheyDid() {
        let critics = [
            "Orlando Sentinel's critic Jay Boyar also praised Miyazaki's direction and said the film is \"the perfect choice for a child who has moved into a new home.\"",
            "On Metacritic, it has a weighted average score of 96 out of 100 based on reviews from 41 critics, indicating \"universal acclaim\".",
            "Kenneth Turan of the Los Angeles Times praised the voice acting.",
            "In 2021, the Writers Guild of America ranked Spirited Away's screenplay the 67th greatest of the 21st century so far.",
            "Some critics faulted the pacing of the second half, which they found slow.",
        ].map { ReviewText(text: $0, rating: nil, isCritic: true) }
        let summary = try! XCTUnwrap(ReceptionAnalyzer.summarize(critics, sentiment: { _ in -0.3 }))
        let liked = summary.liked.map(\.aspect)
        let disliked = summary.disliked.map(\.aspect)
        XCTAssertTrue(liked.contains("Direction"), "\(liked)")
        XCTAssertTrue(liked.contains("Acting"), "\(liked)")
        XCTAssertFalse(disliked.contains("Music and sound"), "a rating's score isn't the music")
        XCTAssertFalse(disliked.contains("Story"), "a ranking isn't a dislike")
        XCTAssertEqual(disliked, ["Pacing"])
        XCTAssertFalse(summary.liked.compactMap(\.quote).contains { $0.hasPrefix("\"") }, "no stray quote marks")
    }

    func testEachPartOfASentenceCountsOnItsOwn() {
        let reviews = [
            ReviewText(text: "The visuals are gorgeous but the pacing is tedious in the middle.", rating: 6),
            ReviewText(text: "Honestly the pacing is tedious from the start to the end.", rating: 5),
        ]
        let sentiment: (String) -> Double = { s in
            let l = s.lowercased()
            if l.contains("gorgeous") { return 0.7 }
            if l.contains("tedious") { return -0.6 }
            return 0
        }
        let summary = try! XCTUnwrap(ReceptionAnalyzer.summarize(reviews, sentiment: sentiment))
        XCTAssertEqual(summary.liked.first?.aspect, "Visuals")
        XCTAssertTrue(summary.disliked.map(\.aspect).contains("Pacing"))
    }

    /// A warm film whose few complaints don't name an aspect, or are about what most loved.
    func testRealComplaintsAreFound() {
        let reviews = [
            ReviewText(text: "The story is beautiful and the animation is stunning in every frame.", rating: 9),
            ReviewText(text: "A beautiful story, gorgeous visuals and a wonderful score.", rating: 10),
            ReviewText(text: "I loved it. My only complaint is that the middle section drags a little.", rating: 8),
            ReviewText(text: "Wonderful film, although the story is a bit confusing at times for younger kids.", rating: 8),
            ReviewText(text: "No complaints at all, a masterpiece from start to finish.", rating: 10),
        ]
        let sentiment: (String) -> Double = { s in
            let l = s.lowercased()
            if ["beautiful", "stunning", "gorgeous", "wonderful", "loved", "masterpiece"].contains(where: { l.contains($0) }) { return 0.7 }
            return 0
        }
        let summary = try! XCTUnwrap(ReceptionAnalyzer.summarize(reviews, sentiment: sentiment))
        let disliked = summary.disliked.map(\.aspect)
        XCTAssertTrue(disliked.contains("Pacing"), "\(disliked)")
        XCTAssertTrue(disliked.contains("Story"), "a complaint about what most liked still counts: \(disliked)")
        XCTAssertTrue(summary.liked.map(\.aspect).contains("Story"))
    }

    /// Nothing negative said: nothing is made up.
    func testNoComplaintsNoDislikes() {
        let reviews = [
            ReviewText(text: "The story is beautiful and the animation is stunning in every frame.", rating: 9),
            ReviewText(text: "No complaints at all, the music is a masterpiece.", rating: 10),
        ]
        let summary = try! XCTUnwrap(ReceptionAnalyzer.summarize(reviews, sentiment: { $0.lowercased().contains("beautiful") ? 0.7 : 0.1 }))
        XCTAssertEqual(summary.disliked, [])
    }

    /// Praise that only looks like a complaint inside other words.
    func testComplaintsAreWholeWords() {
        let reviews = [
            ReviewText(text: "The cinematography is gorgeous, all inky blacks and shallow focus.", rating: 9),
            ReviewText(text: "An unpredictable story, almost mesmerizing from start to end.", rating: 9),
        ]
        let summary = try! XCTUnwrap(ReceptionAnalyzer.summarize(reviews, sentiment: { _ in 0.3 }))
        XCTAssertEqual(summary.disliked, [])
        XCTAssertNil(ReceptionAnalyzer.word("lacks", in: "inky blacks"))
        XCTAssertNotNil(ReceptionAnalyzer.word("lacks", in: "it lacks tension"))
    }

    func testOrdinaryWordsAreNotVerdicts() {
        XCTAssertEqual(ReceptionAnalyzer.reported("ebert called the cinematography flawless"), 0)
        XCTAssertEqual(ReceptionAnalyzer.reported("another reviewer praised the score"), 1)
        XCTAssertEqual(ReceptionAnalyzer.reported("nevertheless, critics praised the acting"), 1)
        XCTAssertEqual(ReceptionAnalyzer.reported("it never disappoints"), 1)
        XCTAssertEqual(ReceptionAnalyzer.reported("critics were not impressed by the story"), -1)
        XCTAssertEqual(ReceptionAnalyzer.reported("critics not only praised the acting"), 1)
        XCTAssertEqual(ReceptionAnalyzer.aspects(in: "it scored a perfect 100 on the site"), [])
        XCTAssertEqual(ReceptionAnalyzer.clauses(of: "The visuals are stunning, however, the pacing drags badly.").count, 2)
        XCTAssertTrue(ReceptionAnalyzer.reportsFigures("It won the Academy Award for Best Original Score.", critic: true))
        XCTAssertEqual(ReceptionAnalyzer.aspects(in: "the score of this movie is phenomenal"), ["Music and sound"])
        XCTAssertFalse(ReceptionAnalyzer.reportsFigures("Upon its release, it received widespread acclaim, with praise for its direction.", critic: true))
        XCTAssertTrue(ReceptionAnalyzer.reportsFigures("It was ranked the 67th greatest screenplay of the century.", critic: true))
    }

    func testQuotesKeepTheirOwnMarks() {
        XCTAssertEqual(ReceptionAnalyzer.tidyQuotes("\"\" Orlando said it is \"perfect.\""), "Orlando said it is \"perfect.\"")
        XCTAssertEqual(ReceptionAnalyzer.sentences(in: "He called it \"a small, perfect gem.\" The rest of the cast is just as good here.").first,
                       "He called it \"a small, perfect gem.\"")
    }

    // MARK: - 1.11 (spec §6.4): fewer but right

    /// The kinds of wrong dislike found in 1.10 (scorecard 5.6), in made-up sentences.
    func testPraiseOtherFilmsAndPlotsAreNotDislikes() {
        let reviews = [
            "Not a single line of dialogue is wasted in this one.",
            "Nothing about this felt boring like people said it would.",
            "In spite of a few complaints the plot holds together well.",
            "His performance in ‘The Other Picture’ was far weaker than anything here.",
            "Why does everyone say the ending is disappointing?",
            "A lot of films I've seen lately feel bloated and far too long.",
            "The story follows a poor family who move into a big house.",
        ].map { ReviewText(text: $0, rating: 8) }
        let summary = ReceptionAnalyzer.summarize(reviews, title: "Example", year: 2020, sentiment: { _ in 0 })
        XCTAssertEqual(summary?.disliked ?? [], [], "\(summary?.disliked.map(\.quote) ?? [])")
    }

    /// What a complaint is about is the aspect next to it, not every aspect in the sentence.
    func testAComplaintIsAboutTheAspectNextToIt() {
        let found = ReceptionAnalyzer.judgements(in: "It's an incredibly boring and lazy style of writing.", startsSentence: true)
        XCTAssertEqual(Set(found.map(\.aspect)), ["Story"])
        XCTAssertEqual(found.map(\.sign), [-1, -1])
        XCTAssertEqual(ReceptionAnalyzer.judgements(in: "Critics praised the score and faulted nothing", startsSentence: true).map(\.aspect), ["Music and sound"])
        XCTAssertEqual(ReceptionAnalyzer.judgements(in: "It was ranked above Toy Story by the magazine", startsSentence: true), [])
        XCTAssertEqual(ReceptionAnalyzer.judgements(in: "The acting is not good", startsSentence: true).map(\.sign), [-1])
    }

    /// Quotes are one whole sentence; a review's paragraphs never run together.
    func testQuotesAreWholeSentences() {
        XCTAssertTrue(ReceptionAnalyzer.isQuotable("The score is superb from the first scene to the last."))
        XCTAssertFalse(ReceptionAnalyzer.isQuotable("the score is superb from the first scene to the last."), "starts mid-sentence")
        XCTAssertFalse(ReceptionAnalyzer.isQuotable("The score is superb from the first scene to the last"), "no full stop")
        XCTAssertFalse(ReceptionAnalyzer.isQuotable("He wrote, \"Worst of all, the score is superb and loud."), "a quotation left open")
        let text = ReceptionAnalyzer.clean("The acting is superb throughout the whole film.\r\n\r\nThe ending, though, is a real letdown for me.")
        XCTAssertEqual(ReceptionAnalyzer.sentences(in: text).count, 2)
        let summary = ReceptionAnalyzer.summarize([ReviewText(text: "The acting is superb throughout the whole film.\r\n\r\nThe story is weak and predictable at the end of it.", rating: 6)],
                                                  sentiment: { _ in 0 })
        XCTAssertEqual(summary?.liked.first?.quote, "The acting is superb throughout the whole film.")
        XCTAssertEqual(summary?.disliked.first?.quote, "The story is weak and predictable at the end of it.")
    }
}
