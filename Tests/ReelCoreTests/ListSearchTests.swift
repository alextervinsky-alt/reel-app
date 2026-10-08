import XCTest
@testable import ReelCore

final class ListSearchTests: XCTestCase {
    func testThemesAreRankedByHowWellTheyMatch() {
        let themes = [
            ListSearch.Theme(id: 1, name: "heist gone wrong"), ListSearch.Theme(id: 2, name: "art heist"),
            ListSearch.Theme(id: 3, name: "heist"), ListSearch.Theme(id: 4, name: "heists"), ListSearch.Theme(id: 5, name: "heist"),
        ]
        XCTAssertEqual(ListSearch.rank(themes, for: "Heist").map(\.id), [3, 1, 4, 2], "the word itself first, each once")
        XCTAssertEqual(ListSearch.Theme(id: 9, name: "time travel").title, "Time Travel")
    }

    func testCountriesAndDecadesAreFound() {
        XCTAssertEqual(ListSearch.cinema(for: "Japanese"), [.country(code: "JP")])
        XCTAssertEqual(ListSearch.cinema(for: "korea"), [.country(code: "KR")])
        XCTAssertEqual(ListSearch.cinema(for: "1970s"), [.decade(1970)])
        XCTAssertEqual(ListSearch.cinema(for: "80s"), [.decade(1980)])
        XCTAssertEqual(ListSearch.cinema(for: "heist"), [])
        XCTAssertEqual(DiscoverList.theme(ListSearch.Theme(id: 10051, name: "heist")).request().query.first?.value, "10051")
    }
}
