import XCTest
@testable import ReelCore

final class ExplorePicksTests: XCTestCase {
    func movie(_ id: Int, votes: Int = 900, vote: Double = 7.5, released: String = "2015-01-01", poster: String? = "/p.jpg",
               genres: [Int] = [18]) -> TMDBMovieSummary {
        TMDBMovieSummary(id: id, title: "Film \(id)", releaseDate: released, posterPath: poster, voteAverage: vote, voteCount: votes,
                         genreIDs: genres)
    }

    func seed(_ title: String, year: Int = 2015, genres: [String] = ["Drama"], features: LikenessFeatures? = nil) -> ExploreSeed {
        ExploreSeed(id: title.hashValue, title: title, year: year, genres: genres, features: features)
    }

    func testFilmsRecommendedAfterSeveralLovedFilmsComeFirst() {
        let sources = [
            (seed: seed("Her"), recommended: [movie(1), movie(2), movie(3)]),
            (seed: seed("Arrival"), recommended: [movie(3), movie(4)]),
        ]
        let found = ExplorePicks.candidates(from: sources, excluding: { _ in false }, today: "2026-10-07")
        XCTAssertEqual(found.first?.movie.id, 3, "on two lists")
        XCTAssertEqual(found.first?.seed.title, "Arrival", "first on Arrival's list, so that's the reason")
        XCTAssertEqual(Set(found.map(\.movie.id)), [1, 2, 3, 4])
    }

    func testUnknownUnreleasedPosterlessAndOwnedFilmsAreLeftOut() {
        let sources = [
            (seed: seed("Her"), recommended: [movie(1, votes: 40), movie(2, released: "2027-05-01"), movie(3, poster: nil),
                                              movie(4, vote: 6.5), movie(5), movie(6)]),
        ]
        let found = ExplorePicks.candidates(from: sources, excluding: { $0 == 6 }, today: "2026-10-07")
        XCTAssertEqual(found.map(\.movie.id), [5])
    }

    func testAnotherKindOfFilmOrAnotherTimeCountsLess() {
        let anora = seed("Anora", year: 2024, genres: ["Comedy", "Drama", "Romance"])
        let sources = [(seed: anora, recommended: [
            movie(1, released: "1938-05-26", genres: [35, 10749]),
            movie(2, released: "2022-01-01", genres: [27]),
            movie(3, released: "2021-01-01", genres: [35, 18]),
        ])]
        let found = ExplorePicks.candidates(from: sources, excluding: { _ in false }, today: "2026-10-07")
        XCTAssertEqual(found.map(\.movie.id), [3, 1], "a horror film shares nothing with Anora; a 1938 film comes after")
        XCTAssertLessThan(ExplorePicks.era(2024, 1938), 0.2)
        XCTAssertEqual(ExplorePicks.era(2024, 2015), 1)
    }

    func testOnlyFilmsTrulyAlikeAreKeptWhenThereAreEnough() {
        let features = LikenessFeatures(tmdbID: 1, directors: ["Yorgos Lanthimos"], writers: [], cinematographers: [], cast: [],
                                        genres: ["Comedy", "Science Fiction"], keywords: ["conspiracy", "kidnapping"],
                                        moods: [.dark], year: 2025)
        let bugonia = seed("Bugonia", year: 2025, genres: ["Comedy", "Science Fiction"], features: features)
        let candidates = [
            ExploreCandidate(movie: movie(10), score: 2, seed: bugonia),
            ExploreCandidate(movie: movie(11), score: 1, seed: bugonia),
        ]
        func details(_ id: Int, director: String, keywords: [String], genres: [String]) -> TMDBMovieDetails {
            let json = """
            {"id": \(id), "title": "F\(id)", "release_date": "2024-01-01",
             "genres": [\(genres.enumerated().map { "{\"id\": \($0.offset), \"name\": \"\($0.element)\"}" }.joined(separator: ","))],
             "keywords": {"keywords": [\(keywords.enumerated().map { "{\"id\": \($0.offset), \"name\": \"\($0.element)\"}" }.joined(separator: ","))]},
             "credits": {"cast": [], "crew": [{"name": "\(director)", "job": "Director"}]}}
            """
            return try! JSONDecoder().decode(TMDBMovieDetails.self, from: Data(json.utf8))
        }
        let found = ExplorePicks.refine(candidates, details: [
            10: details(10, director: "Someone Else", keywords: ["sports"], genres: ["Family"]),
            11: details(11, director: "Yorgos Lanthimos", keywords: ["conspiracy"], genres: ["Comedy", "Science Fiction"]),
        ], keep: 1, keywordCounts: ["conspiracy": 1, "kidnapping": 1], libraryCount: 40)
        XCTAssertEqual(found.map(\.movie.id), [11], "the unlike one is left out while one alike is enough")
        XCTAssertEqual(found.first?.reason, .director(film: "Bugonia"))
    }

    func testEachLaunchDrawsADifferentDozenAndAvoidsLastTimes() {
        let sources = [(seed: seed("Her"), recommended: (1...40).map { movie($0) })]
        let all = ExplorePicks.candidates(from: sources, excluding: { _ in false }, today: "2026-10-07")
        var first = SeededGenerator(state: 1)
        var second = SeededGenerator(state: 2)
        let monday = ExplorePicks.sample(all, count: 12, avoiding: [], using: &first)
        let tuesday = ExplorePicks.sample(all, count: 12, avoiding: Set(monday.map(\.movie.id)), using: &second)
        XCTAssertEqual(monday.count, 12)
        XCTAssertEqual(Set(monday.map(\.movie.id)).count, 12, "no film twice")
        XCTAssertTrue(Set(monday.map(\.movie.id)).isDisjoint(with: tuesday.map(\.movie.id)))
        XCTAssertEqual(monday.map(\.score), monday.map(\.score).sorted(by: >), "best first")
    }

    func testAMoodKeepsToItsGenresOrWhatTheFilmWasFoundToFeelLike() {
        let her = seed("Her")
        let comedy = ExploreCandidate(movie: movie(1, genres: [35, 10749]), score: 1, seed: her)
        let thriller = ExploreCandidate(movie: movie(2, genres: [53, 80]), score: 1, seed: her)
        let lookedAt = ExploreCandidate(movie: movie(3, genres: [35]), score: 1, seed: her, moods: [.dark, .funny])
        XCTAssertTrue(comedy.fits(.funny))
        XCTAssertTrue(comedy.fits(.feelGood))
        XCTAssertFalse(thriller.fits(.feelGood))
        XCTAssertTrue(thriller.fits(.gripping))
        XCTAssertFalse(lookedAt.fits(.feelGood), "its keywords said dark")
        let query = MoodGenres.of(.feelGood).query
        XCTAssertEqual(query.first { $0.name == "with_genres" }?.value, "16|35|10402|10751")
        XCTAssertEqual(query.first { $0.name == "without_genres" }?.value, "27,53,80,10752")
    }
}
