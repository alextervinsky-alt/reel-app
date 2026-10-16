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
}
