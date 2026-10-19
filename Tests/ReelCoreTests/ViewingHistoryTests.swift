import XCTest
@testable import ReelCore

/// Every time you watch a film is kept: Year in Film counts each viewing in its own year.
final class ViewingHistoryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 21) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func decode(_ json: String) throws -> PersonalRecord {
        try JSONStore.decode(PersonalRecord.self, from: Data(json.utf8))
    }

    // MARK: Migration and saving

    /// A record as Reel 1.8.7 saved it (the shape of a real Your Notes).
    func testOldDateBecomesOneViewing() throws {
        let record = try decode(#"{"favorite":false,"note":"","rating":4,"watched":true,"watchedOn":"2026-09-14T21:00:00Z","watchlist":false}"#)
        XCTAssertEqual(record.viewings, [ISO8601DateFormatter().date(from: "2026-09-14T21:00:00Z")!])
        XCTAssertEqual(record.watchedOn, record.viewings.last)
        XCTAssertEqual(record.rating, 4)
    }

    func testWatchedWithoutADateHasNoViewings() throws {
        let record = try decode(#"{"favorite":false,"note":"","rating":5,"watched":false,"watchlist":false}"#)
        XCTAssertEqual(record.viewings, [])
        XCTAssertNil(record.watchedOn)
    }

    func testSavingAndReadingAgainNeverDuplicates() throws {
        var record = try decode(#"{"favorite":false,"note":"","watched":true,"watchedOn":"2025-11-14T22:00:00Z","watchlist":false}"#)
        record.addViewing(date(2026, 10, 1), calendar: calendar)
        var again = record
        for _ in 0..<3 {
            again = try JSONStore.decode(PersonalRecord.self, from: JSONStore.encode(again))
        }
        XCTAssertEqual(again, record)
        XCTAssertEqual(again.viewings.count, 2)
    }

    /// Reel 1.8.7 and older read "watchedOn": it's still saved, as the last viewing.
    func testOlderReelStillReadsTheLastDate() throws {
        var record = PersonalRecord(watched: true, watchedOn: date(2025, 3, 1))
        record.addViewing(date(2026, 5, 2), calendar: calendar)
        let json = try JSONSerialization.jsonObject(with: JSONStore.encode(record)) as? [String: Any]
        XCTAssertNotNil(json?["watchedOn"])
        XCTAssertEqual((json?["viewings"] as? [Any])?.count, 2)
        struct OldRecord: Decodable { let watched: Bool; let watchedOn: Date? }
        let old = try JSONStore.decode(OldRecord.self, from: JSONStore.encode(record))
        XCTAssertEqual(old.watchedOn, date(2026, 5, 2))
    }

    func testRecordsWithoutViewingsSaveAsBefore() throws {
        let json = try JSONSerialization.jsonObject(with: JSONStore.encode(PersonalRecord(rating: 3))) as? [String: Any]
        XCTAssertNil(json?["viewings"])
        XCTAssertNil(json?["watchedOn"])
    }

    /// The one date an older Reel can change: if it isn't among the viewings, it's added.
    func testDateFromAnOlderReelIsKept() throws {
        let record = try decode(#"{"favorite":false,"note":"","watched":true,"watchedOn":"2026-02-01T21:00:00Z","watchlist":false,"viewings":["2025-01-01T21:00:00Z"]}"#)
        XCTAssertEqual(record.viewings.count, 2)
        XCTAssertEqual(record.watchedOn, ISO8601DateFormatter().date(from: "2026-02-01T21:00:00Z"))
    }

    func testOneViewingPerDay() {
        XCTAssertEqual(PersonalRecord.tidy([date(2026, 1, 1, hour: 23), date(2026, 1, 1, hour: 9), date(2025, 1, 1)], calendar: calendar),
                       [date(2025, 1, 1), date(2026, 1, 1, hour: 9)])
        let a = PersonalRecord(watched: true, watchedOn: date(2026, 1, 1, hour: 9))
        let b = PersonalRecord(watched: true, watchedOn: date(2026, 1, 1, hour: 22))
        XCTAssertEqual(a.merged(with: b).viewings.count, 1, "two copies of one evening are one viewing")
    }

    // MARK: Viewing actions

    func testWatchingAgainAddsAViewing() {
        var record = PersonalRecord(watched: true, watchlist: false, watchedOn: date(2025, 2, 14))
        record.addViewing(date(2026, 10, 13), calendar: calendar)
        XCTAssertEqual(record.viewings, [date(2025, 2, 14), date(2026, 10, 13)])
        XCTAssertEqual(record.watchedOn, date(2026, 10, 13))
    }

    func testTheSameDayCountsOnce() {
        var record = PersonalRecord(watched: true, watchedOn: date(2026, 10, 13, hour: 20))
        record.addViewing(date(2026, 10, 13, hour: 23), calendar: calendar)
        XCTAssertEqual(record.viewings.count, 1)
    }

    func testFirstViewingMarksWatchedAndLeavesTheWatchlist() {
        var record = PersonalRecord(watchlist: true)
        record.addViewing(date(2026, 1, 5), calendar: calendar)
        XCTAssertTrue(record.watched)
        XCTAssertFalse(record.watchlist)
        XCTAssertEqual(record.viewings, [date(2026, 1, 5)])
    }

    func testCorrectingTheDateChangesOnlyTheLastViewing() {
        var record = PersonalRecord(watched: true, watchedOn: date(2024, 6, 1))
        record.addViewing(date(2026, 10, 13), calendar: calendar)
        record.watchedOn = date(2026, 9, 1)
        XCTAssertEqual(record.viewings, [date(2024, 6, 1), date(2026, 9, 1)])
        // Moved before the earlier one: kept in order.
        record.watchedOn = date(2023, 1, 1)
        XCTAssertEqual(record.viewings, [date(2023, 1, 1), date(2024, 6, 1)])
    }

    func testDatingAFilmWithoutADateGivesItOne() {
        var record = PersonalRecord(watched: true)
        record.watchedOn = date(2026, 3, 1)
        XCTAssertEqual(record.viewings, [date(2026, 3, 1)])
    }

    /// Unwatched means not seen: its viewings go, as its date did before.
    func testUnwatchingForgetsTheViewings() {
        var record = PersonalRecord(watched: true, watchedOn: date(2025, 1, 1))
        record.addViewing(date(2026, 1, 1), calendar: calendar)
        record.watched = false
        record.watchedOn = nil
        XCTAssertEqual(record.viewings, [])
    }

    func testMergingKeepsEveryViewingOnce() {
        let a = PersonalRecord(watched: true, watchedOn: date(2025, 1, 1))
        var b = PersonalRecord(watched: true, watchedOn: date(2025, 1, 1))
        b.addViewing(date(2026, 1, 1), calendar: calendar)
        XCTAssertEqual(a.merged(with: b).viewings, [date(2025, 1, 1), date(2026, 1, 1)])
    }

    // MARK: Year in Film

    private func viewing(_ key: String, _ when: Date, runtime: Int = 100, director: String = "X") -> YearFilm {
        YearFilm(id: key, title: key, releaseYear: 2000, watchedOn: when, runtime: runtime, genres: ["Drama"],
                 directors: [director], yourRating: 4, score: 7)
    }

    func testARewatchCountsInBothYears() {
        let all = [viewing("tmdb:1", date(2025, 5, 1)), viewing("tmdb:1", date(2026, 2, 1)), viewing("tmdb:2", date(2026, 3, 1))]
        let before = YearInFilm(year: 2025, from: all, calendar: calendar)
        let now = YearInFilm(year: 2026, from: all, calendar: calendar)
        XCTAssertEqual(before.uniqueFilms.map(\.key), ["tmdb:1"], "the earlier year keeps its viewing")
        XCTAssertEqual(before.rewatches, 0)
        XCTAssertEqual(now.uniqueFilms.map(\.key), ["tmdb:1", "tmdb:2"])
        XCTAssertEqual(now.rewatches, 1, "seen in 2025 first")
        XCTAssertEqual(YearInFilm.years(in: all, calendar: calendar), [2026, 2025])
    }

    func testTwiceInOneYearIsOneFilmAndTwoNights() {
        let all = [viewing("tmdb:1", date(2026, 1, 10), runtime: 120), viewing("tmdb:1", date(2026, 1, 11), runtime: 120),
                   viewing("tmdb:2", date(2026, 4, 1), runtime: 90, director: "Y")]
        let year = YearInFilm(year: 2026, from: all, calendar: calendar)
        XCTAssertEqual(year.uniqueFilms.count, 2, "films: each once")
        XCTAssertEqual(year.films.count, 3, "viewings: every one")
        XCTAssertEqual(year.minutes, 330, "time spent counts every viewing")
        XCTAssertEqual(year.months[0], 2)
        XCTAssertEqual(year.longestRun?.nights, 2)
        XCTAssertEqual(year.rewatches, 1)
        XCTAssertEqual(year.topDirectors, [], "watching one director's film twice isn't coming back to them")
        XCTAssertEqual(year.averageRuntime, 105, "the average film, each film once")
        XCTAssertEqual(Set(year.films.map(\.id)).count, 3, "each viewing has its own id")
    }
}
