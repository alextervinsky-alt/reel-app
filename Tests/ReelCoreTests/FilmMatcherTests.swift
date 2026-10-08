import XCTest
@testable import ReelCore

final class FilmMatcherTests: XCTestCase {
    func movie(_ id: Int, _ title: String, _ date: String, votes: Int = 1000, original: String? = nil) -> TMDBMovieSummary {
        TMDBMovieSummary(id: id, title: title, originalTitle: original, releaseDate: date, voteCount: votes)
    }

    func testNormalize() {
        XCTAssertEqual(TitleSimilarity.normalize("The Lord of the Rings: The Return of the King"),
                       "lord of the rings the return of the king")
        XCTAssertEqual(TitleSimilarity.normalize("Amélie"), "amelie")
        XCTAssertEqual(TitleSimilarity.normalize("Fast & Furious"), "fast and furious")
        XCTAssertEqual(TitleSimilarity.normalize("Schindler's List"), "schindlers list")
        XCTAssertEqual(TitleSimilarity.similarity("Mission Impossible Fallout", "Mission: Impossible - Fallout"), 1)
    }

    func testExactTitleAndYearIsAuto() {
        let r = FilmMatcher.rank([movie(2, "Judge Dredd", "1995-06-30"), movie(1, "Dredd", "2012-09-07")],
                                 title: "Dredd", year: 2012)
        XCTAssertEqual(r.best?.movie.id, 1)
        XCTAssertEqual(r.confidence, .auto)
    }

    func testMissingYearNeedsReview() {
        let r = FilmMatcher.rank([movie(335984, "Blade Runner 2049", "2017-10-04")], title: "Blade Runner 2049", year: nil)
        XCTAssertEqual(r.best?.movie.id, 335984)
        XCTAssertEqual(r.confidence, .review)
    }

    func testOriginalTitleCounts() {
        let r = FilmMatcher.rank([movie(5, "The Hunt", "2012-01-10", original: "Jagten")], title: "Jagten", year: 2012)
        XCTAssertEqual(r.confidence, .auto)
    }

    func testNothingFoundIsManual() {
        let r = FilmMatcher.rank([], title: "Some Home Video", year: nil)
        XCTAssertNil(r.best)
        XCTAssertEqual(r.confidence, .manual)

        let weak = FilmMatcher.rank([movie(9, "Completely Different", "1990-01-01")], title: "Dredd", year: 2012)
        XCTAssertEqual(weak.confidence, .manual)
    }

    func testTwinTitlesSameYearAskFirst() {
        let r = FilmMatcher.rank([movie(1, "Crash", "2004-09-10", votes: 900), movie(2, "Crash", "2004-01-01", votes: 600)],
                                 title: "Crash", year: 2004)
        XCTAssertEqual(r.confidence, .review)

        let clear = FilmMatcher.rank([movie(1, "Crash", "2004-09-10", votes: 9000), movie(2, "Crash", "2004-01-01", votes: 3)],
                                     title: "Crash", year: 2004)
        XCTAssertEqual(clear.best?.movie.id, 1)
        XCTAssertEqual(clear.confidence, .auto)
    }

    struct FakeDatabase: MovieDatabase {
        let withYear: [TMDBMovieSummary]
        let withoutYear: [TMDBMovieSummary]
        func searchMovies(query: String, year: Int?) async throws -> [TMDBMovieSummary] {
            year == nil ? withoutYear : withYear
        }
        func movieDetails(id: Int) async throws -> TMDBMovieDetails {
            TMDBMovieDetails(id: id, title: "x")
        }
    }

    func testRetriesWithoutYear() async throws {
        let db = FakeDatabase(withYear: [], withoutYear: [TMDBMovieSummary(id: 7, title: "Gone Girl", releaseDate: "2014-10-01")])
        let r = try await FilmMatcher(database: db).match(title: "Gone Girl", year: 2015)
        XCTAssertEqual(r.best?.movie.id, 7)
        XCTAssertEqual(r.confidence, .review)
    }

    func testDetailsDecodeAndTrim() throws {
        let json = """
        {"id": 49049, "title": "Dredd", "release_date": "2012-09-07", "runtime": 95,
         "genres": [{"id": 28, "name": "Action"}, {"id": 878, "name": "Science Fiction"}],
         "imdb_id": "tt1343727", "vote_average": 6.8,
         "videos": {"results": [{"key": "abc", "site": "YouTube", "type": "Teaser", "official": true},
                                {"key": "xyz", "site": "YouTube", "type": "Trailer", "official": true}]},
         "credits": {"cast": [{"name": "Karl Urban", "character": "Judge Dredd", "order": 0}],
                     "crew": [{"name": "Pete Travis", "job": "Director"}, {"name": "Someone", "job": "Grip"}]}}
        """
        let d = try JSONDecoder().decode(TMDBMovieDetails.self, from: Data(json.utf8)).trimmed()
        XCTAssertEqual(d.year, 2012)
        XCTAssertEqual(d.genreNames, ["Action", "Science Fiction"])
        XCTAssertEqual(Trailers.candidates(d.videos?.results ?? [], title: d.title, preferTeaser: false, originalLanguage: d.originalLanguage).first?.key, "xyz")
        XCTAssertEqual(d.directors, ["Pete Travis"])
        XCTAssertEqual(d.credits?.crew.count, 1)
    }
}
