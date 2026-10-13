import XCTest
@testable import ReelCore

final class CraftTests: XCTestCase {
    func testFilmAnamorphicFromWhatWasRead() {
        let specs = TechSpecs.read([
            "The film was shot on 35mm film using Kodak Vision3 500T 5219 stock and Panavision C-Series anamorphic lenses on a Panaflex Millennium XL2.",
            "Much of it was handheld, and the interiors were lit with natural light.",
        ])
        let craft = CraftIndex.make(from: specs, colour: ["color"], keywords: [])
        XCTAssertEqual(craft.shotOn, [.film, .anamorphic])
        XCTAssertTrue(craft.names.contains("Handheld"))
        XCTAssertTrue(craft.names.contains("Natural light"))
        XCTAssertTrue(craft.searchText.contains("35mm"), "a gauge is found written either way")
    }

    func testDigitalAndIMAX() {
        let specs = TechSpecs.read([
            "Nolan filmed the battle scenes with IMAX 65 mm film cameras, while the rest was shot digitally on the RED Monstro.",
        ])
        let craft = CraftIndex.make(from: specs, colour: nil, keywords: [])
        XCTAssertEqual(craft.shotOn, [.film, .digital, .imax])
    }

    func testBlackAndWhiteFromWikidataOnlyWhenNotAlsoColour() {
        let empty = TechSpecs.read([])
        XCTAssertEqual(CraftIndex.make(from: empty, colour: ["black-and-white"], keywords: []).shotOn, [.blackAndWhite])
        XCTAssertEqual(CraftIndex.make(from: empty, colour: ["black-and-white", "color"], keywords: []).shotOn, [],
                       "partly in colour isn't a black and white film")
        XCTAssertEqual(CraftIndex.make(from: empty, colour: nil, keywords: ["black and white"]).shotOn, [.blackAndWhite])
    }

    func testStaleness() {
        let now = Date()
        XCTAssertFalse(CraftIndex(readAt: now, shotOn: [], names: []).isStale(now: now))
        XCTAssertTrue(CraftIndex(readAt: now.addingTimeInterval(-200 * 86_400), shotOn: [], names: []).isStale(now: now))
        XCTAssertTrue(CraftIndex(version: 0, readAt: now, shotOn: [], names: []).isStale(now: now))
    }

    func testKeptWithTheFilmAndDroppedWhenItsMatchChanges() throws {
        var film = FilmEntry(driveID: "d", relativePath: "A/A.mkv", fileName: "A.mkv", size: 1, modified: nil, addedAt: Date())
        film.craft = CraftIndex(shotOn: [.film], names: ["Steadicam"])
        let data = try JSONEncoder().encode(film)
        XCTAssertEqual(try JSONDecoder().decode(FilmEntry.self, from: data).craft?.names, ["Steadicam"])
    }

    func testACinematographersHabitsAreWhatRecurs() {
        let films = [
            CraftIndex(shotOn: [.digital], names: ["ARRI Alexa", "Natural light", "Handheld"]),
            CraftIndex(shotOn: [.digital, .anamorphic], names: ["ARRI Alexa", "Natural light"]),
            CraftIndex(shotOn: [.film], names: ["Steadicam"]),
        ]
        let habits = CraftHabits.recurring(films)
        XCTAssertEqual(habits.map(\.name), ["Digital", "ARRI Alexa", "Natural light"])
        XCTAssertEqual(habits.map(\.films), [2, 2, 2])
        XCTAssertEqual(CraftHabits.recurring([films[2]]).map(\.name), ["Film", "Steadicam"], "one film: its own")
    }
}
