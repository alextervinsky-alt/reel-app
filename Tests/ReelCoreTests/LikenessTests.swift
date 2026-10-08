import XCTest
@testable import ReelCore

final class LikenessTests: XCTestCase {
    private func film(_ id: Int, director: String, genres: [String], keywords: [String], moods: [Mood],
                      year: Int = 2020, cast: [String] = []) -> LikenessFeatures {
        LikenessFeatures(tmdbID: id, directors: [director], writers: [], cinematographers: [], cast: cast,
                         genres: genres, keywords: keywords, moods: moods, year: year)
    }

    private lazy var bugonia = film(1, director: "Yorgos Lanthimos", genres: ["Science Fiction", "Comedy", "Thriller"],
                                    keywords: ["alien", "conspiracy", "kidnapping", "dark comedy"], moods: [.dark, .funny, .gripping])
    private lazy var liloAndStitch = film(2, director: "Dean Fleischer Camp", genres: ["Family", "Science Fiction", "Comedy", "Adventure"],
                                          keywords: ["alien", "hawaii", "sisters"], moods: [.feelGood, .funny])
    private lazy var poorThings = film(3, director: "Yorgos Lanthimos", genres: ["Science Fiction", "Romance", "Comedy"],
                                       keywords: ["victorian", "frankenstein"], moods: [.funny, .mindBending])
    private lazy var underTheSkin = film(4, director: "Jonathan Glazer", genres: ["Science Fiction", "Thriller", "Drama"],
                                         keywords: ["alien", "seduction", "scotland"], moods: [.dark, .mindBending])
    private lazy var paddington = film(5, director: "Paul King", genres: ["Family", "Comedy", "Adventure"],
                                       keywords: ["bear", "london"], moods: [.feelGood, .funny])
    private lazy var heat = film(6, director: "Michael Mann", genres: ["Crime", "Thriller", "Drama"],
                                 keywords: ["heist", "los angeles"], moods: [.gripping, .dark], year: 1995)

    private var library: [LikenessFeatures] { [bugonia, liloAndStitch, poorThings, underTheSkin, paddington, heat] }

    private func ranked(for a: LikenessFeatures, recommended: [Int: Int] = [:]) -> [Int] {
        let counts = Likeness.keywordCounts(library)
        return library
            .filter { $0.tmdbID != a.tmdbID }
            .map { ($0.tmdbID!, Likeness.score(a, $0, recommended: recommended, keywordCounts: counts, libraryCount: library.count)) }
            .filter { $0.1 >= Likeness.threshold }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    func testFamilyFilmIsNotLikeADarkAdultFilmBecauseBothHaveAliens() {
        let result = ranked(for: bugonia)
        XCTAssertFalse(result.contains(2), "Lilo & Stitch shouldn't be like Bugonia")
        XCTAssertEqual(result.first, 3, "the same director comes first")
        XCTAssertTrue(result.contains(4), "a dark sci-fi thriller about an alien is alike")
    }

    func testFamilyFilmsStayTogether() {
        let result = ranked(for: liloAndStitch)
        XCTAssertEqual(result.first, 5)
        XCTAssertFalse(result.contains(4))
    }

    func testWhatViewersWentOnToLikeCountsMost() {
        // TMDB's top recommendation for Bugonia (made up here) comes first.
        let result = ranked(for: bugonia, recommended: [6: 0])
        XCTAssertEqual(Array(result.prefix(2)), [6, 3])
    }

    func testRareThemesCountMoreThanCommonOnes() {
        let a = film(10, director: "A", genres: ["Drama"], keywords: ["lighthouse", "based on novel"], moods: [])
        let rare = film(11, director: "B", genres: ["Drama"], keywords: ["lighthouse"], moods: [])
        let common = film(12, director: "C", genres: ["Drama"], keywords: ["based on novel"], moods: [])
        let others = (13...30).map { film($0, director: "D\($0)", genres: ["Drama"], keywords: ["based on novel"], moods: []) }
        let all = [a, rare, common] + others
        let counts = Likeness.keywordCounts(all)
        XCTAssertGreaterThan(Likeness.score(a, rare, keywordCounts: counts, libraryCount: all.count),
                             Likeness.score(a, common, keywordCounts: counts, libraryCount: all.count))
    }

    func testAGentleAnimatedFantasyIsNotLikeABloodyOneBecauseBothHaveWitches() {
        func film(_ id: Int, _ director: String, _ genres: [String], _ keywords: [String], year: Int) -> LikenessFeatures {
            LikenessFeatures(tmdbID: id, directors: [director], writers: [], cinematographers: [], cast: [],
                             genres: genres, keywords: keywords,
                             moods: MoodClassifier.moods(genres: genres, keywords: keywords, runtime: 120), year: year)
        }
        let howl = film(1, "Hayao Miyazaki", ["Fantasy", "Animation", "Adventure"],
                        ["witch", "magic", "curse", "wizard", "castle", "war", "based on novel or book"], year: 2004)
        let northman = film(2, "Robert Eggers", ["Action", "Adventure", "Fantasy", "Drama"],
                            ["witch", "curse", "magic", "revenge", "viking", "sword", "brutality", "iceland"], year: 2022)
        let wolfwalkers = film(3, "Tomm Moore", ["Animation", "Family", "Adventure", "Fantasy"],
                               ["magic", "wolf", "ireland", "curse", "friendship"], year: 2020)
        let others = (10...60).map { film($0, "D\($0)", ["Drama"], ["based on novel or book", "new york city"], year: 2010) }
        let all = [howl, northman, wolfwalkers] + others
        let counts = Likeness.keywordCounts(all)
        func score(_ b: LikenessFeatures) -> Double {
            Likeness.score(howl, b, recommended: [2: 12], keywordCounts: counts, libraryCount: all.count)
        }
        XCTAssertTrue(howl.isGentle)
        XCTAssertTrue(northman.isIntense)
        XCTAssertLessThan(score(northman), Likeness.threshold, "even when TMDB recommends it")
        XCTAssertGreaterThanOrEqual(score(wolfwalkers), Likeness.threshold)
    }

    func testViolenceIsReadFromWholeWordsAndAnAnimatedFilmIsNotMadeIntenseByItsMonsters() {
        XCTAssertTrue(LikenessFeatures.isViolent("extreme violence"))
        XCTAssertTrue(LikenessFeatures.isViolent("brutality"))
        XCTAssertFalse(LikenessFeatures.isViolent("skyscraper"))
        XCTAssertFalse(LikenessFeatures.isViolent("nonviolence"))
        let genres = ["Fantasy", "Animation", "Adventure"]
        let keywords = ["witch", "demon", "monster", "creature", "magic"]
        let howl = LikenessFeatures(tmdbID: 1, directors: ["Hayao Miyazaki"], writers: [], cinematographers: [], cast: [],
                                    genres: genres, keywords: keywords,
                                    moods: MoodClassifier.moods(genres: genres, keywords: keywords, runtime: 119), year: 2004)
        XCTAssertTrue(howl.moods.contains(.scary), "the keywords alone make it scary")
        XCTAssertTrue(howl.isGentle, "but an animated film needs real violence or a grim genre to be intense")
    }
}
