import XCTest
@testable import ReelCore

final class CraftGlossaryTests: XCTestCase {
    func testTheMostSpecificExplanationWins() {
        XCTAssertTrue(CraftGlossary.explain("ARRI Alexa 65")?.contains("large-format") == true)
        XCTAssertTrue(CraftGlossary.explain("ARRI Alexa Mini")?.contains("small Super 35") == true)
        XCTAssertTrue(CraftGlossary.explain("Digital intermediate")?.contains("digital grade") == true)
        XCTAssertTrue(CraftGlossary.explain("Film emulation")?.contains("grain, colour") == true)
        XCTAssertTrue(CraftGlossary.explain("LED volume")?.contains("LED screens") == true)
        XCTAssertTrue(CraftGlossary.explain("Technocrane")?.contains("telescopic") == true)
        XCTAssertTrue(CraftGlossary.explain("2.39:1")?.contains("scope") == true)
        XCTAssertTrue(CraftGlossary.explain("Film")?.contains("celluloid") == true)
        XCTAssertTrue(CraftGlossary.explain("RED Epic Dragon")?.contains("RED") == true)
    }

    func testNothingMadeUp() {
        XCTAssertNil(CraftGlossary.explain("Colour"))
        XCTAssertNil(CraftGlossary.explain("Infrared"))
        XCTAssertNil(CraftGlossary.explain("Colored gels"))
    }
}
