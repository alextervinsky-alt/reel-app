import XCTest
@testable import ReelCore

final class SearchQueryTests: XCTestCase {
    func testStandIns() {
        XCTAssertEqual(SearchQuery.terms("cartoon"), [["cartoon", "animation", "animated"]])
        XCTAssertEqual(SearchQuery.terms("Sci-Fi westerns"), [["science fiction"], ["westerns", "western"]])
        XCTAssertEqual(SearchQuery.terms("black & white"), [["black and white"]])
        XCTAssertEqual(SearchQuery.terms("16mm"), [["16mm"]])
    }

    func testSlipsOnlyForLongerWords() {
        XCTAssertEqual(SearchQuery.typoAllowance("nolan"), 1)
        XCTAssertEqual(SearchQuery.typoAllowance("cartoon"), 1)
        XCTAssertEqual(SearchQuery.typoAllowance("villenueve"), 2)
        XCTAssertEqual(SearchQuery.typoAllowance("doc"), 0)
        XCTAssertGreaterThan(TitleSimilarity.distance("cartoon", "carson"), SearchQuery.typoAllowance("cartoon"))
    }
}
