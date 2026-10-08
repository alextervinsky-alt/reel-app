import XCTest
@testable import ReelCore

/// Repeatable randomness for the tests.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class RecommenderTests: XCTestCase {
    private func film(_ id: String, score: Double = 7, genre: String = "Drama", moods: [Mood] = [], runtime: Int? = 120,
                      watchlist: Bool = false) -> Recommendable {
        Recommendable(id: id, score: score, onWatchlist: watchlist, isOnline: true, genre: genre, moods: moods, runtime: runtime)
    }

    func testChipsOnlyForMoodsWithEnoughFilms() {
        let pool = [
            film("a", moods: [.dark, .gripping], runtime: 95),
            film("b", moods: [.dark], runtime: 88),
            film("c", moods: [.dark, .funny], runtime: 99),
            film("d", moods: [.funny], runtime: 140),
        ]
        let chips = Recommender.choices(for: pool)
        XCTAssertEqual(chips.map { $0.choice }, [.any, .mood(.dark), .short])
        XCTAssertEqual(chips.map { $0.count }, [4, 3, 3])
        XCTAssertEqual(Recommender.choices(for: pool, keeping: .mood(.funny)).map { $0.choice },
                       [.any, .mood(.funny), .mood(.dark), .short], "the chip you're on stays while it has films")
    }

    func testPicksStayInsideTheChosenMoodAndVaryGenres() {
        var pool = (0..<20).map { film("drama\($0)", score: 8, genre: "Drama", moods: [.moving]) }
        pool += ["Comedy", "Thriller", "Romance", "Horror"].map { film($0, score: 6, genre: $0, moods: [.moving]) }
        pool += (0..<10).map { film("other\($0)", score: 9.5, genre: "Action", moods: [.epic]) }
        var generator = SeededGenerator(state: 1)

        let moving = Recommender.pick(from: pool, choice: .mood(.moving), using: &generator)
        XCTAssertEqual(moving.count, 5)
        XCTAssertFalse(moving.contains { $0.hasPrefix("other") }, "only films with the chosen mood")
        XCTAssertEqual(moving.filter { $0.hasPrefix("drama") }.count, 1, "five different genres when they exist")

        // Earlier picks still on show stay; only the empty places are filled.
        let kept = Array(moving.prefix(3))
        let refilled = Recommender.pick(from: pool, choice: .mood(.moving), keeping: kept, using: &generator)
        XCTAssertEqual(Array(refilled.prefix(3)), kept)
        XCTAssertEqual(refilled.count, 5)
    }

    func testLastLaunchAndShuffledAwayFilmsComeBackLessOften() {
        let pool = (0..<10).map { film("f\($0)", score: 7, genre: "G\($0)") }
        let last = Set(["f0", "f1", "f2", "f3", "f4"])
        var repeats = 0
        var generator = SeededGenerator(state: 7)
        for _ in 0..<50 {
            let picks = Recommender.pick(from: pool, choice: .any, lastLaunch: last, using: &generator)
            repeats += picks.filter { last.contains($0) }.count
        }
        XCTAssertLessThan(repeats, 25, "last launch's films are mostly avoided")

        let short = Recommender.pick(from: [film("long", runtime: 150), film("unknown", runtime: nil), film("quick", runtime: 85)],
                                     choice: .short, using: &generator)
        XCTAssertEqual(short, ["quick"])
    }

    // MARK: Year in Film

    func testSeenElsewhereIsDatedTheMonthAfterItCameOut() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Tallinn")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8))!
        func parts(_ date: Date?) -> [Int] {
            date.map { [calendar.component(.year, from: $0), calendar.component(.month, from: $0)] } ?? []
        }
        XCTAssertEqual(parts(SeenDate.afterRelease("2004-11-20", now: now, calendar: calendar)), [2004, 12])
        XCTAssertEqual(parts(SeenDate.afterRelease("2015-12-03", now: now, calendar: calendar)), [2016, 1], "over the new year")
        XCTAssertEqual(SeenDate.afterRelease("2026-09-30", now: now, calendar: calendar), now, "this month: now")
        XCTAssertEqual(SeenDate.afterRelease("2026-10-02", now: now, calendar: calendar), now, "never a month to come")
        XCTAssertNil(SeenDate.afterRelease(nil, now: now, calendar: calendar))
        XCTAssertNil(SeenDate.afterRelease("", now: now, calendar: calendar))
    }

    func testEveryYearStaysIntoTheNextOne() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Tallinn")!
        func film(_ id: String, _ year: Int, _ month: Int) -> YearFilm {
            YearFilm(id: id, title: id, releaseYear: 2000, watchedOn: calendar.date(from: DateComponents(year: year, month: month, day: 15))!,
                     runtime: 100, genres: [], directors: [], yourRating: nil, score: nil)
        }
        let films = [film("a", 2019, 3), film("b", 2026, 12), film("c", 2027, 1), film("d", 2024, 6)]
        XCTAssertEqual(YearInFilm.years(in: films, calendar: calendar), [2027, 2026, 2024, 2019])
        XCTAssertEqual(YearInFilm(year: 2026, from: films, calendar: calendar).films.map(\.id), ["b"])
        XCTAssertEqual(YearInFilm(year: 2027, from: films, calendar: calendar).months, [1] + Array(repeating: 0, count: 11))
    }

    func testYearInFilmCountsOnlyThatYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        func seen(_ id: String, _ when: Date, runtime: Int?, genres: [String], director: String, rating: Int? = nil,
                  released: Int?) -> YearFilm {
            YearFilm(id: id, title: id, releaseYear: released, watchedOn: when, runtime: runtime, genres: genres,
                     directors: [director], yourRating: rating, score: 7)
        }
        let films = [
            seen("Stalker", date(2026, 1, 4), runtime: 162, genres: ["Drama", "Sci-Fi"], director: "Tarkovsky", rating: 5, released: 1979),
            seen("Solaris", date(2026, 1, 20), runtime: 167, genres: ["Drama", "Sci-Fi"], director: "Tarkovsky", released: 1972),
            seen("Her", date(2026, 3, 2), runtime: 126, genres: ["Romance", "Drama"], director: "Jonze", rating: 4, released: 2013),
            seen("Old", date(2025, 12, 31), runtime: 90, genres: ["Horror"], director: "Shyamalan", released: 2021),
        ]
        let year = YearInFilm(year: 2026, from: films, calendar: calendar)
        XCTAssertEqual(year.films.map { $0.id }, ["Stalker", "Solaris", "Her"])
        XCTAssertEqual(year.minutes, 455)
        XCTAssertEqual(Array(year.months.prefix(3)), [2, 0, 1])
        XCTAssertEqual(year.topGenres.first, Tally(name: "Drama", count: 3))
        XCTAssertEqual(year.topDirectors, [Tally(name: "Tarkovsky", count: 2)])
        XCTAssertEqual(year.favourite?.id, "Stalker")
        XCTAssertEqual(year.longest?.id, "Solaris")
        XCTAssertEqual(year.oldest?.id, "Solaris")
        XCTAssertEqual(year.decades.map { $0.name }, ["1970s", "2010s"])
        XCTAssertEqual(YearInFilm.years(in: films, calendar: calendar), [2026, 2025])
    }
}
