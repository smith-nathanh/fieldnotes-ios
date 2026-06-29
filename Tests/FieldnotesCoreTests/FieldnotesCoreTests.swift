import Foundation
@testable import FieldnotesCore
import XCTest

final class FieldnotesCoreTests: XCTestCase {
    func testSplitSignalMatchesBirdNETWindowing() {
        let sampleRate = 48_000
        let samples = Array(repeating: Float(0.2), count: sampleRate * 8)
        let chunks = AudioWindowing.splitSignal(samples, sampleRate: sampleRate, overlapSeconds: 0)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.count == sampleRate * 3 })
        XCTAssertTrue(chunks[2].suffix(sampleRate).allSatisfy { $0 == 0 })
    }

    func testPrivacyFilterMasksHumanWindowAndNeighbors() {
        let predictions = [
            [SpeciesScore(scientificName: "Bird_A", confidence: 0.9)],
            [SpeciesScore(scientificName: "Human_Human", confidence: 0.95)],
            [SpeciesScore(scientificName: "Bird_B", confidence: 0.8)],
            [SpeciesScore(scientificName: "Bird_C", confidence: 0.8)],
        ]

        let filtered = HumanPrivacyFilter.filter(predictions, privacyThresholdPercent: 0)

        XCTAssertEqual(filtered[0].first?.scientificName, "Human_Human")
        XCTAssertEqual(filtered[1].first?.scientificName, "Human_Human")
        XCTAssertEqual(filtered[2].first?.scientificName, "Human_Human")
        XCTAssertEqual(filtered[3].first?.scientificName, "Bird_C")
    }

    func testPrivacyFilterIdentifiesHumanTopCandidate() {
        let predictions = [
            SpeciesScore(scientificName: "Bird_A", confidence: 0.91),
            SpeciesScore(scientificName: "Human_Human", confidence: 0.88),
        ]

        XCTAssertTrue(HumanPrivacyFilter.isHumanWindow(predictions, privacyThresholdPercent: 0))
    }

    func testCooldownKeepsStrongestRepresentativeDetection() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let originalID = UUID()
        var store = DetectionStore(detections: [
            FieldDetection(
                id: originalID,
                scientificName: "Pica pica",
                commonName: "Eurasian Magpie",
                confidence: 0.80,
                detectedAt: start,
                week: 8
            )
        ])

        let weaker = FieldDetection(
            scientificName: "Pica pica",
            commonName: "Eurasian Magpie",
            confidence: 0.75,
            detectedAt: start.addingTimeInterval(60),
            week: 8
        )
        let stronger = FieldDetection(
            scientificName: "Pica pica",
            commonName: "Eurasian Magpie",
            confidence: 0.92,
            detectedAt: start.addingTimeInterval(120),
            week: 8
        )

        XCTAssertEqual(store.record(weaker), .skip(existingID: originalID))
        XCTAssertEqual(store.detections.count, 1)

        let decision = store.record(stronger)
        guard case .replace(let replacedID) = decision else {
            XCTFail("Expected stronger detection to replace original")
            return
        }

        XCTAssertEqual(replacedID, originalID)
        XCTAssertEqual(store.detections.count, 1)
        XCTAssertEqual(store.detections[0].confidence, 0.92)
    }

    func testScoringAppliesConfidenceAndRangeGateWithWhitelistBypass() {
        let settings = DetectionSettings(confidenceThreshold: 0.7)
        let scores = [
            SpeciesScore(scientificName: "Bird_A", confidence: 0.9),
            SpeciesScore(scientificName: "Bird_B", confidence: 0.8),
            SpeciesScore(scientificName: "Frog_A", confidence: 0.85),
            SpeciesScore(scientificName: "Bird_C", confidence: 0.4),
        ]

        let filtered = BirdNETScoring.filteredDetections(
            rankedScores: scores,
            allowedSpecies: ["Bird_A"],
            whitelist: ["Frog_A"],
            settings: settings
        )

        XCTAssertEqual(filtered.map(\.scientificName), ["Bird_A", "Frog_A"])
    }
}
