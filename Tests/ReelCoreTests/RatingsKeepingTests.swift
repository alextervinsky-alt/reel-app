import XCTest
@testable import ReelCore

/// 1.11.2: OMDb stopped sending Rotten Tomatoes (checked on CI, 26 Nov 2026), and the refresh of
/// 24 Nov wrote "none" over the stored scores. Now an answer only adds, and Wikidata fills the gap.
final class RatingsKeepingTests: XCTestCase {
    private func film() -> FilmEntry {
        FilmEntry(driveID: "D", relativePath: "Film.mkv", fileName: "Film.mkv", size: 1, modified: nil, addedAt: Date())
    }

    private func details(_ id: Int, stills: [String] = []) -> TMDBMovieDetails {
        var d = TMDBMovieDetails(id: id, title: "Film \(id)")
        d.images = TMDBImageSet(backdrops: stills.map { TMDBImageInfo(filePath: $0) }, logos: nil)
        return d
    }

    func testAnAnswerWithoutRottenTomatoesKeepsTheStoredScore() {
        var entry = film()
        entry.apply(details(1), ratings: ExternalRatings(imdb: 8.0, rottenTomatoes: 91, metacritic: 80), reception: nil)
        // What OMDb sends now: IMDb and Metacritic only.
        entry.apply(details(1), ratings: ExternalRatings(imdb: 8.1, imdbVotes: 900, metacritic: 81), reception: nil)
        XCTAssertEqual(entry.ratings?.rottenTomatoes, 91)
        XCTAssertEqual(entry.ratings?.imdb, 8.1)
        XCTAssertEqual(entry.ratings?.metacritic, 81)
        XCTAssertEqual(entry.ratings?.imdbVotes, 900)
        // The ratings-only refresh keeps it too.
        entry.applyRatings(ExternalRatings(imdb: 8.2), failed: false)
        XCTAssertEqual(entry.ratings?.rottenTomatoes, 91)
        XCTAssertEqual(entry.ratings?.metacritic, 81)
        // A newer score replaces the old one.
        entry.applyRatings(ExternalRatings(rottenTomatoes: 93), failed: false)
        XCTAssertEqual(entry.ratings?.rottenTomatoes, 93)
    }

    func testAnotherFilmsScoresNeverCarryOver() {
        var entry = film()
        entry.apply(details(1), ratings: ExternalRatings(imdb: 8.0, rottenTomatoes: 91), reception: nil)
        // A corrected match: another film, whose answer has no Rotten Tomatoes.
        entry.apply(details(2), ratings: ExternalRatings(imdb: 6.0), reception: nil)
        XCTAssertNil(entry.ratings?.rottenTomatoes)
        XCTAssertEqual(entry.ratings?.imdb, 6.0)
        // And when the other film's ratings can't be fetched, the first film's aren't shown for it.
        var other = film()
        other.apply(details(1), ratings: ExternalRatings(imdb: 8.0, rottenTomatoes: 91), reception: nil)
        other.apply(details(3), ratings: nil, ratingsFailed: true, reception: nil)
        XCTAssertNil(other.ratings)
        XCTAssertTrue(other.ratingsDue)
    }

    func testWikidataTomatometerTheLatestByDate() {
        let json = """
        {"head": {"vars": ["imdb", "score", "date"]}, "results": {"bindings": [
          {"imdb": {"type": "literal", "value": "tt0110912"}, "score": {"type": "literal", "value": "92%"},
           "date": {"type": "literal", "value": "2026-01-16T00:00:00Z"}},
          {"imdb": {"type": "literal", "value": "tt0110912"}, "score": {"type": "literal", "value": "94%"},
           "date": {"type": "literal", "value": "2019-03-02T00:00:00Z"}},
          {"imdb": {"type": "literal", "value": "tt1375666"}, "score": {"type": "literal", "value": "87%"}},
          {"imdb": {"type": "literal", "value": "tt1375666"}, "score": {"type": "literal", "value": "86%"},
           "date": {"type": "literal", "value": "2022-11-29T00:00:00Z"}},
          {"imdb": {"type": "literal", "value": "tt0000001"}, "score": {"type": "literal", "value": "7.8/10"}},
          {"imdb": {"type": "literal", "value": "tt0000002"}, "score": {"type": "literal", "value": "140%"}}
        ]}}
        """
        let scores = WikidataScores.parse(Data(json.utf8))
        XCTAssertEqual(scores["tt0110912"], 92, "the latest dated score")
        XCTAssertEqual(scores["tt1375666"], 86, "a dated score over an undated one")
        XCTAssertNil(scores["tt0000001"], "an average rating isn't a Tomatometer")
        XCTAssertNil(scores["tt0000002"])
        XCTAssertTrue(WikidataScores.parse(Data("not json".utf8)).isEmpty)
    }

    func testWikidataQueryOnlyTakesIMDbIDs() {
        let query = WikidataScores.query(imdbIDs: ["tt0110912", "tt1375666", "\" } DELETE {", "nm0000233"])
        XCTAssertTrue(query.contains(#"VALUES ?imdb { "tt0110912" "tt1375666" }"#))
        XCTAssertTrue(query.contains("pq:P447 wd:Q105584"))
        XCTAssertTrue(query.contains("pq:P459 wd:Q108403393"))
        XCTAssertFalse(query.contains("DELETE"))
    }

    func testReorderedStillsKeepTheCheck() {
        var entry = film()
        entry.apply(details(1, stills: ["/a.jpg", "/b.jpg", "/c.jpg"]), ratings: nil, reception: nil)
        entry.checkedStills = ["/a.jpg", "/c.jpg"]
        // TMDB sends the same stills in another order: the check stands.
        entry.apply(details(1, stills: ["/c.jpg", "/a.jpg", "/b.jpg"]), ratings: nil, reception: nil)
        XCTAssertEqual(entry.checkedStills, ["/a.jpg", "/c.jpg"])
        // A new still: checked again.
        entry.apply(details(1, stills: ["/c.jpg", "/a.jpg", "/b.jpg", "/d.jpg"]), ratings: nil, reception: nil)
        XCTAssertNil(entry.checkedStills)
    }
}

/// 1.11.4: scores for films outside the library, by TMDB id, in one query.
final class WikidataFilmScoresTests: XCTestCase {
    private func row(_ tmdb: String, imdb: String? = nil, score: String? = nil, by: String? = nil, method: String? = nil, date: String? = nil) -> String {
        var parts = [#""tmdb": {"type": "literal", "value": "\#(tmdb)"}"#]
        let entity = "http://www.wikidata.org/entity/"
        if let imdb { parts.append(#""imdb": {"type": "literal", "value": "\#(imdb)"}"#) }
        if let score { parts.append(#""score": {"type": "literal", "value": "\#(score)"}"#) }
        if let by { parts.append(#""by": {"type": "uri", "value": "\#(entity)\#(by)"}"#) }
        if let method { parts.append(#""method": {"type": "uri", "value": "\#(entity)\#(method)"}"#) }
        if let date { parts.append(#""date": {"type": "literal", "value": "\#(date)"}"#) }
        return "{" + parts.joined(separator: ", ") + "}"
    }

    func testScoresByTMDB() {
        let rows = [
            row("680", imdb: "tt0110912", score: "92%", by: "Q105584", method: "Q108403393", date: "2026-01-16T00:00:00Z"),
            row("680", imdb: "tt0110912", score: "94%", by: "Q105584", method: "Q108403393", date: "2019-03-02T00:00:00Z"),
            row("680", imdb: "tt0110912", score: "9/10", by: "Q105584", method: "Q108403540"),
            row("680", imdb: "tt0110912", score: "95/100", by: "Q150248"),
            row("680", imdb: "tt0110912", score: "9.2/10", by: "Q150248"),
            row("27205", imdb: "tt1375666", score: "74", by: "Q150248", date: "2010-07-16T00:00:00Z"),
            row("27205", imdb: "tt1375666", score: "87%", by: "Q105584", method: "Q108403393"),
            row("1", imdb: "tt0000001"),
            row("2"),
        ]
        let json = #"{"head": {"vars": []}, "results": {"bindings": ["# + rows.joined(separator: ", ") + "]}}"
        let films = WikidataScores.parseByTMDB(Data(json.utf8))
        XCTAssertEqual(films[680], WikidataScores.FilmScores(imdbID: "tt0110912", rottenTomatoes: 92, metacritic: 95))
        XCTAssertEqual(films[27205], WikidataScores.FilmScores(imdbID: "tt1375666", rottenTomatoes: 87, metacritic: 74))
        XCTAssertEqual(films[1], WikidataScores.FilmScores(imdbID: "tt0000001"))
        XCTAssertEqual(films[2], WikidataScores.FilmScores())
    }

    func testTMDBQuery() {
        let query = WikidataScores.query(tmdbIDs: [680, 27205, 0, -3])
        XCTAssertTrue(query.contains(#"VALUES ?tmdb { "680" "27205" }"#))
        XCTAssertTrue(query.contains("wdt:P4947"))
        XCTAssertTrue(query.contains("wd:Q150248"))
    }
}
