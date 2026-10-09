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
                     yourRating: 5, score: 8, language: "ko", countries: ["South Korea"], cast: ["Song Kang-ho", "Lee Sun-kyun"]),
            YearFilm(id: "b", title: "B", releaseYear: 2019, watchedOn: day(3, 13), runtime: 140, genres: ["Drama"], directors: ["X"],
                     yourRating: 4, score: 7, language: "ko", countries: ["South Korea"], cast: ["Song Kang-ho"]),
            YearFilm(id: "c", title: "C", releaseYear: 1999, watchedOn: day(3, 20), runtime: 120, genres: ["Comedy"], directors: ["Y"],
                     yourRating: nil, score: 6, language: "en", countries: ["United States of America"], cast: ["Tom Hanks"]),
            YearFilm(id: "d", title: "D", releaseYear: 2026, watchedOn: day(5, 15), runtime: nil, genres: [], directors: [],
                     yourRating: 3, score: nil, language: "fr", countries: ["France"], cast: [], elsewhere: true),
        ]
        let year = YearInFilm(year: 2026, from: films, calendar: calendar)
        XCTAssertEqual(year.averageRuntime, 120)
        XCTAssertEqual(year.averageStars ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(year.newReleases, 2)
        XCTAssertEqual(year.busiestMonth, 2, "March")
        XCTAssertEqual(year.favouriteWeekday, 6, "Fridays (a film seen elsewhere doesn't count: its date is a guess)")
        XCTAssertEqual(year.languages.first, Tally(name: "Korean", count: 2))
        XCTAssertEqual(year.languageCount, 3)
        XCTAssertEqual(year.countries.map(\.name), ["South Korea", "France", "United States"], "the most films first, then A–Z")
        XCTAssertEqual(year.countries.first?.films.map(\.title), ["A", "B"])
        XCTAssertEqual(year.topActors, [Tally(name: "Song Kang-ho", count: 2)])
    }
}
