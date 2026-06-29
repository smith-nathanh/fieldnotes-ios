import XCTest
import FieldnotesCore
@testable import Fieldnotes

final class FieldnotesTests: XCTestCase {
    func testBirdNETGoldenFixtureDetectsPicaPica() throws {
        let engine = BirdNETInferenceEngine()
        let windowResults = try engine.runGoldenFixture()
        let picaWindows = windowResults
            .compactMap { window in window.first { $0.scientificName == "Pica pica" } }
            .filter { $0.confidence >= 0.70 }

        XCTAssertGreaterThanOrEqual(picaWindows.count, 3)
        XCTAssertGreaterThanOrEqual(picaWindows.map(\.confidence).max() ?? 0, 0.88)
    }
}
