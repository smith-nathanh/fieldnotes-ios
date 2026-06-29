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

    func testMetadataRangeFilterProducesAllowedSpecies() throws {
        let labels = try ResourceLocator.labels(named: "BirdNET_GLOBAL_6K_V2.4_Model_FP16_Labels")
        let settings = DetectionSettings(
            latitude: 37.7749,
            longitude: -122.4194,
            week: 26
        )

        let filter = try BirdNETMetadataRangeFilter(labels: labels, settings: settings)

        XCTAssertGreaterThan(filter.allowedSpecies.count, 50)
        XCTAssertLessThan(filter.allowedSpecies.count, labels.count)
    }
}
