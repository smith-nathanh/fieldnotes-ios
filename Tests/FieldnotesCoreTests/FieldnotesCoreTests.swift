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

    func testSplitSignalSupportsOverlappingFieldWindows() {
        let sampleRate = 48_000
        let samples = Array(repeating: Float(0.2), count: sampleRate * 8)
        let chunks = AudioWindowing.splitSignal(samples, sampleRate: sampleRate, overlapSeconds: 1.5)

        XCTAssertEqual(chunks.count, 5)
        XCTAssertTrue(chunks.allSatisfy { $0.count == sampleRate * 3 })
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

    func testCooldownDeduplicatesRepeatDetectionsKeepingStrongest() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let originalID = UUID()
        let originalClip = URL(fileURLWithPath: "/tmp/original.caf")
        let weakerClip = URL(fileURLWithPath: "/tmp/weaker.caf")
        let strongerClip = URL(fileURLWithPath: "/tmp/stronger.caf")
        var store = DetectionStore(detections: [
            FieldDetection(
                id: originalID,
                scientificName: "Pica pica",
                commonName: "Eurasian Magpie",
                confidence: 0.80,
                detectedAt: start,
                clipURL: originalClip,
                week: 8
            )
        ])

        let weaker = FieldDetection(
            scientificName: "Pica pica",
            commonName: "Eurasian Magpie",
            confidence: 0.75,
            detectedAt: start.addingTimeInterval(60),
            clipURL: weakerClip,
            week: 8
        )
        let stronger = FieldDetection(
            scientificName: "Pica pica",
            commonName: "Eurasian Magpie",
            confidence: 0.92,
            detectedAt: start.addingTimeInterval(120),
            clipURL: strongerClip,
            week: 8
        )

        // A weaker repeat within the cooldown window is skipped — no new entry,
        // original clip and confidence preserved.
        XCTAssertEqual(store.record(weaker), .skip(existingID: originalID))
        XCTAssertEqual(store.detections.count, 1)
        XCTAssertEqual(store.detections[0].clipURL, originalClip)
        XCTAssertEqual(store.detections[0].confidence, 0.80, accuracy: 0.0001)

        // A stronger repeat within the window replaces the entry in place —
        // still one row, now with the stronger clip and confidence, same id.
        XCTAssertEqual(store.record(stronger), .replace(existingID: originalID))
        XCTAssertEqual(store.detections.count, 1)
        XCTAssertEqual(store.detections[0].id, originalID)
        XCTAssertEqual(store.detections[0].clipURL, strongerClip)
        XCTAssertEqual(store.detections[0].confidence, 0.92, accuracy: 0.0001)
    }

    func testDetectionPastCooldownWindowInsertsNewEntry() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var store = DetectionStore(detections: [
            FieldDetection(
                scientificName: "Pica pica",
                commonName: "Eurasian Magpie",
                confidence: 0.80,
                detectedAt: start,
                week: 8
            )
        ])

        // Just past the 5-minute bird cooldown — logged as a distinct entry.
        let later = FieldDetection(
            scientificName: "Pica pica",
            commonName: "Eurasian Magpie",
            confidence: 0.70,
            detectedAt: start.addingTimeInterval(5 * 60 + 1),
            week: 8
        )

        XCTAssertEqual(store.record(later), .insert)
        XCTAssertEqual(store.detections.count, 2)
    }

    func testReptileUsesLongerCooldownWindow() {
        XCTAssertEqual(DetectionStore.cooldownSeconds(for: .reptile), 10 * 60)
    }

    func testLegacyDetectionDecodingDefaultsSourceToAudio() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "scientificName": "Pica pica",
          "commonName": "Eurasian Magpie",
          "taxon": "bird",
          "confidence": 0.91,
          "detectedAt": "2026-07-01T12:00:00Z",
          "week": 27
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let detection = try decoder.decode(FieldDetection.self, from: Data(json.utf8))

        XCTAssertEqual(detection.source, .audio)
    }

    func testPhotoDetectionSourceRoundTrips() throws {
        let detection = FieldDetection(
            scientificName: "Sylvilagus floridanus",
            commonName: "Eastern Cottontail",
            taxon: .mammal,
            source: .photo,
            confidence: 0.396,
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000),
            week: 27
        )

        let encoded = try JSONEncoder().encode(detection)
        let decoded = try JSONDecoder().decode(FieldDetection.self, from: encoded)

        XCTAssertEqual(decoded.source, .photo)
        XCTAssertEqual(decoded.confidence, 0.396, accuracy: 0.0001)
    }

    func testSummaryTracksBestScoreSource() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let audio = FieldDetection(
            scientificName: "Pica pica",
            commonName: "Eurasian Magpie",
            confidence: 0.80,
            detectedAt: start,
            week: 8
        )
        let photo = FieldDetection(
            scientificName: "Pica pica",
            commonName: "Eurasian Magpie",
            source: .photo,
            confidence: 0.92,
            detectedAt: start.addingTimeInterval(60),
            week: 8
        )
        let store = DetectionStore(detections: [audio, photo])

        XCTAssertEqual(store.summaries().first?.bestSource, .photo)
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
