import XCTest
@testable import ReelCore

final class YearInFilmStatsTests: XCTestCase {
    func testTheYearInNumbers() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 21))! }
        // 6, 13 and 20 March 2026 are Fridays.
        let films = [
            YearFilm(id: "a", title: "A", releaseYear: 2026, watchedOn: day(3, 6), runtime: 100, genres: ["Drama"], directors: ["X"],
                     yourRating: 5, score: 8, language: "ko", cast: ["Song Kang-ho", "Lee Sun-kyun"]),
            YearFilm(id: "b", title: "B", releaseYear: 2019, watchedOn: day(3, 13), runtime: 140, genres: ["Drama"], directors: ["X"],
                     yourRating: 4, score: 7, language: "ko", cast: ["Song Kang-ho"]),
            YearFilm(id: "c", title: "C", releaseYear: 1999, watchedOn: day(3, 20), runtime: 120, genres: ["Comedy"], directors: ["Y"],
                     yourRating: nil, score: 6, language: "en", cast: ["Tom Hanks"]),
            YearFilm(id: "d", title: "D", releaseYear: 2026, watchedOn: day(5, 15), runtime: nil, genres: [], directors: [],
                     yourRating: 3, score: nil, language: "fr", cast: [], elsewhere: true),
        ]
        let year = YearInFilm(year: 2026, from: films, calendar: calendar)
        XCTAssertEqual(year.averageRuntime, 120)
        XCTAssertEqual(year.averageStars ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(year.newReleases, 2)
        XCTAssertEqual(year.busiestMonth, 2, "March")
        XCTAssertEqual(year.favouriteWeekday, 6, "Fridays (a film seen elsewhere doesn't count: its date is a guess)")
        XCTAssertEqual(year.languages.first, Tally(name: "Korean", count: 2))
        XCTAssertEqual(year.languageCount, 3)
        XCTAssertEqual(year.topActors, [Tally(name: "Song Kang-ho", count: 2)])
        XCTAssertEqual(year.shortest?.id, "a")
        XCTAssertEqual(year.newest?.id, "a", "the first of the newest releases")
        XCTAssertEqual(year.starCounts, [0, 0, 1, 1, 1])
        XCTAssertEqual(year.averageAge, 9, "0, 7, 27 and 0 years old: 8.5")
        XCTAssertNil(year.longestRun, "a week apart")
        XCTAssertEqual(year.weekdays[5], 3, "three Fridays")
        XCTAssertEqual(year.warmerThanMost.map(\.film.id), ["a"], "5★ is 10 against 8: two points is enough (D has no score)")
    }

    func testRunsGapsAndCrew() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 1, day: d, hour: 22))! }
        func film(_ id: String, _ d: Int, stars: Int?, score: Double?, dp: [String] = [], elsewhere: Bool = false) -> YearFilm {
            YearFilm(id: id, title: id, releaseYear: 2000, watchedOn: day(d), runtime: 100, genres: [], directors: [],
                     yourRating: stars, score: score, elsewhere: elsewhere, cinematographers: dp)
        }
        let films = [
            film("a", 3, stars: 5, score: 6.1, dp: ["Roger Deakins"]),
            film("b", 4, stars: 1, score: 8.2, dp: ["Roger Deakins"]),
            film("c", 5, stars: 3, score: 6.0),
            film("d", 6, stars: nil, score: 7, elsewhere: true),
            film("e", 9, stars: 4, score: 7.9),
            film("f", 10, stars: nil, score: nil),
        ]
        let year = YearInFilm(year: 2026, from: films, calendar: calendar)
        XCTAssertEqual(year.longestRun?.nights, 3, "3, 4 and 5 January (a film seen elsewhere isn't a night)")
        XCTAssertEqual(year.longestRun?.start, calendar.startOfDay(for: day(3)))
        XCTAssertEqual(year.warmerThanMost.map(\.film.id), ["a"])
        XCTAssertEqual(year.coolerThanMost.map(\.film.id), ["b"])
        XCTAssertEqual(year.topCinematographers, [Tally(name: "Roger Deakins", count: 2)])
    }
}
