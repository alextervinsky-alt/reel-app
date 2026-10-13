import XCTest
@testable import ReelCore

final class DoubleFeatureTests: XCTestCase {
    private func film(_ id: String, directors: [String] = [], dop: [String] = [], genres: [String] = ["Drama"],
                      keywords: [String] = [], moods: [Mood] = [], year: Int = 2000, shotOn: Set<ShotOn> = [],
                      craft: [String] = [], watched: Bool = false, series: Int? = nil) -> DoubleFeature.Film {
        DoubleFeature.Film(id: id, features: LikenessFeatures(tmdbID: nil, directors: directors, writers: [], cinematographers: dop,
                                                              cast: [], genres: genres, keywords: keywords, moods: moods, year: year),
                           collectionID: series, shotOn: shotOn, craftNames: craft, watched: watched)
    }

    func testTheSameDirectorMakesThePairWithTheYearsBetween() {
        let me = film("a", directors: ["Denis Villeneuve"], year: 2016)
        let others = [film("b", directors: ["Someone"], year: 2016), film("c", directors: ["Denis Villeneuve"], year: 2023)]
        let pick = DoubleFeature.pick(for: me, from: others, keywordCounts: [:], libraryCount: 3)
        XCTAssertEqual(pick, DoubleFeature.Pick(id: "c", reason: "Two by Denis Villeneuve, 7 years apart"))
    }

    func testTheWayItWasShot() {
        let me = film("a", craft: ["16 mm", "Handheld"])
        let pick = DoubleFeature.pick(for: me, from: [film("b", craft: ["16 mm"])], keywordCounts: [:], libraryCount: 2)
        XCTAssertEqual(pick?.reason, "Both shot on 16 mm")
    }

    func testNoPairForASequelOrAFilmOfAnotherTone() {
        let me = film("a", directors: ["X"], genres: ["Animation", "Family"], moods: [.feelGood], series: 1)
        let sequel = film("b", directors: ["X"], genres: ["Animation", "Family"], moods: [.feelGood], series: 1)
        let grim = film("c", directors: ["X"], genres: ["Horror"], moods: [.scary])
        XCTAssertNil(DoubleFeature.pick(for: me, from: [sequel, grim], keywordCounts: [:], libraryCount: 3))
    }

    func testARareThemeOnly() {
        let me = film("a", keywords: ["lighthouse", "based on novel or book"])
        let other = film("b", keywords: ["lighthouse", "based on novel or book"])
        let pick = DoubleFeature.pick(for: me, from: [other], keywordCounts: ["lighthouse": 2, "based on novel or book": 2], libraryCount: 40)
        XCTAssertEqual(pick?.reason, "A shared theme: lighthouse")
    }
}
