import XCTest
import CoreLocation
import CoreML
import FieldnotesCore
import ImageIO
import UIKit
import UniformTypeIdentifiers
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

    func testBioCAPFixtureRanksExpectedSpeciesWhenLocalAssetsExist() throws {
        let (image, expected) = try loadBioCAPFixture()

        let classifier = try BioCAPImageClassifier(computeUnits: .cpuOnly)
        let predictions = try classifier.classify(image, limit: 5)

        XCTAssertEqual(predictions.first?.scientificName, expected.expectedScientificName)
        XCTAssertTrue(predictions.contains { $0.scientificName == expected.expectedScientificName })
    }

    func testBioCAPComputeUnitsMatchOnPhysicalDevice() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Accelerated BioCAP compute-unit parity is a physical-device test.")
#else
        let (image, _) = try loadBioCAPFixture()
        let configurations: [(name: String, units: MLComputeUnits)] = [
            ("cpuOnly", .cpuOnly),
            ("cpuAndGPU", .cpuAndGPU),
            ("all", .all),
        ]
        var baseline: [BioCAPPhotoPrediction]?

        for configuration in configurations {
            let start = Date()
            let predictions = try autoreleasepool {
                let classifier = try BioCAPImageClassifier(computeUnits: configuration.units)
                return try classifier.classify(image, limit: 5)
            }
            let elapsed = Date().timeIntervalSince(start)
            let summary = predictions
                .map { "\($0.scientificName)=\($0.score)" }
                .joined(separator: ", ")
            print("BioCAP \(configuration.name) \(elapsed)s: \(summary)")

            if let baseline {
                XCTAssertEqual(
                    predictions.first?.scientificName,
                    baseline.first?.scientificName,
                    "Top prediction changed for \(configuration.name)."
                )
                XCTAssertEqual(
                    Set(predictions.map(\.scientificName)),
                    Set(baseline.map(\.scientificName)),
                    "Top-five candidate set changed for \(configuration.name)."
                )
                let baselineScores = Dictionary(
                    uniqueKeysWithValues: baseline.map { ($0.scientificName, $0.score) }
                )
                for prediction in predictions {
                    guard let expectedScore = baselineScores[prediction.scientificName] else {
                        continue
                    }
                    XCTAssertEqual(
                        prediction.score,
                        expectedScore,
                        accuracy: 0.005,
                        "Similarity drifted for \(prediction.scientificName) on \(configuration.name)."
                    )
                }
            } else {
                baseline = predictions
            }
        }
#endif
    }

    func testBioCAPWarmPerformanceOnPhysicalDevice() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("BioCAP timing and memory metrics are physical-device measurements.")
#else
        let (image, expected) = try loadBioCAPFixture()
        let classifier = try BioCAPImageClassifier(computeUnits: .cpuOnly)
        _ = try classifier.classify(image, limit: 5)

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        var measurementError: Error?
        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric()],
            options: options
        ) {
            do {
                let predictions = try classifier.classify(image, limit: 5)
                XCTAssertEqual(
                    predictions.first?.scientificName,
                    expected.expectedScientificName
                )
            } catch {
                measurementError = error
            }
        }
        if let measurementError {
            throw measurementError
        }
#endif
    }

    func testBioCAPPolicyFallsBackToGenusWhenSpeciesMarginIsSmall() {
        let predictions = [
            photoPrediction(name: "Lucanus elaphus", similarity: 0.380, genus: "Lucanus", family: "Lucanidae"),
            photoPrediction(name: "Lucanus capreolus", similarity: 0.372, genus: "Lucanus", family: "Lucanidae"),
            photoPrediction(name: "Dorcus parallelus", similarity: 0.330, genus: "Dorcus", family: "Lucanidae"),
        ]

        let result = BioCAPIdentificationPolicy.evaluate(
            predictions: predictions,
            appliedNorthCarolinaPrior: false
        )

        XCTAssertEqual(result.suggestedRank, .genus)
        XCTAssertEqual(result.suggestedName, "Lucanus")
        XCTAssertNil(result.exactPrediction)
    }

    func testBioCAPPolicyAllowsOnlySeparatedTopSpecies() {
        let predictions = [
            photoPrediction(name: "Cardinalis cardinalis", similarity: 0.370, genus: "Cardinalis", family: "Cardinalidae"),
            photoPrediction(name: "Cardinalis sinuatus", similarity: 0.330, genus: "Cardinalis", family: "Cardinalidae"),
        ]

        let result = BioCAPIdentificationPolicy.evaluate(
            predictions: predictions,
            appliedNorthCarolinaPrior: true
        )

        XCTAssertEqual(result.suggestedRank, .species)
        XCTAssertEqual(result.exactPrediction?.scientificName, "Cardinalis cardinalis")
        XCTAssertEqual(result.top1Top2Margin ?? 0, Float(0.040), accuracy: Float(0.0001))
        XCTAssertTrue(result.appliedNorthCarolinaPrior)
    }

    func testBioCAPPolicyCollapsesSpeciesAndSubspeciesBeforeMeasuringMargin() {
        let predictions = [
            photoPrediction(name: "Sylvilagus floridanus nigronuchalis", similarity: 0.396, genus: "Sylvilagus", family: "Leporidae"),
            photoPrediction(name: "Sylvilagus floridanus", similarity: 0.375, genus: "Sylvilagus", family: "Leporidae"),
            photoPrediction(name: "Sylvilagus aquaticus", similarity: 0.350, genus: "Sylvilagus", family: "Leporidae"),
        ]

        let result = BioCAPIdentificationPolicy.evaluate(
            predictions: predictions,
            appliedNorthCarolinaPrior: true
        )

        XCTAssertEqual(result.predictions.count, 2)
        XCTAssertEqual(result.predictions.first?.scientificName, "Sylvilagus floridanus")
        XCTAssertEqual(result.predictions.first?.similarity ?? 0, 0.396, accuracy: 0.0001)
        XCTAssertEqual(result.suggestedRank, .species)
    }

    func testPhotoContextUsesOnlySoftPriorInsideNorthCarolinaBounds() {
        XCTAssertTrue(
            BioCAPPhotoContext(latitude: 35.2271, longitude: -80.8431, week: 28)
                .appliesNorthCarolinaPrior
        )
        XCTAssertFalse(
            BioCAPPhotoContext(latitude: 40.7128, longitude: -74.0060, week: 28)
                .appliesNorthCarolinaPrior
        )
        XCTAssertFalse(
            BioCAPPhotoContext(latitude: nil, longitude: nil, week: 28)
                .appliesNorthCarolinaPrior
        )
    }

    func testPhotoMetadataProvidesCaptureLocationAndDate() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let output = NSMutableData()
        guard let cgImage = image.cgImage,
              let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            return XCTFail("Could not create metadata fixture")
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 35.2271,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 80.8431,
                kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:04:02 14:30:00",
            ],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let data = output as Data
        XCTAssertEqual(data.embeddedCoordinate?.latitude ?? 0, 35.2271, accuracy: 0.0001)
        XCTAssertEqual(data.embeddedCoordinate?.longitude ?? 0, -80.8431, accuracy: 0.0001)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: try XCTUnwrap(data.embeddedCaptureDate)
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 2)
    }

    func testPhotoCropGeometryCentersTheLargestSquare() {
        let crop = PhotoCropGeometry.squareCrop(imageSize: CGSize(width: 400, height: 200))

        XCTAssertEqual(crop.minX, 0.25, accuracy: 0.0001)
        XCTAssertEqual(crop.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(crop.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(crop.height, 1, accuracy: 0.0001)
    }

    func testPhotoCropGeometryFramesAnOffCenterSubjectInsideBounds() {
        let subject = CGRect(x: 0.70, y: 0.20, width: 0.10, height: 0.20)
        let imageSize = CGSize(width: 400, height: 200)

        let crop = PhotoCropGeometry.squareCrop(around: subject, imageSize: imageSize)

        XCTAssertGreaterThanOrEqual(crop.minX, 0)
        XCTAssertGreaterThanOrEqual(crop.minY, 0)
        XCTAssertLessThanOrEqual(crop.maxX, 1)
        XCTAssertLessThanOrEqual(crop.maxY, 1)
        XCTAssertTrue(crop.contains(CGPoint(x: subject.midX, y: subject.midY)))
        XCTAssertEqual(crop.width * imageSize.width, crop.height * imageSize.height, accuracy: 0.001)
    }

    func testPhotoCropProducesSquareImage() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        let crop = PhotoCropGeometry.squareCrop(imageSize: image.size)

        let cropped = try XCTUnwrap(image.cropped(toNormalizedRect: crop))

        XCTAssertEqual(cropped.size.width, cropped.size.height, accuracy: 0.001)
        XCTAssertEqual(cropped.size.width, 200, accuracy: 0.001)
    }

    func testPhotoSubjectSuggestionReturnsValidSquareForFixture() async throws {
        let (image, _) = try loadBioCAPFixture()

        let suggestion = await PhotoSubjectCropper.suggestedCrop(for: image)
        let rect = suggestion.rect

        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 1)
        XCTAssertLessThanOrEqual(rect.maxY, 1)
        XCTAssertEqual(
            rect.width * image.size.width,
            rect.height * image.size.height,
            accuracy: 0.01
        )
    }

    private func photoPrediction(
        name: String,
        similarity: Float,
        genus: String,
        family: String
    ) -> BioCAPPhotoPrediction {
        BioCAPPhotoPrediction(
            scientificName: name,
            commonName: name,
            taxon: "insect",
            similarity: similarity,
            rankingScore: similarity,
            genus: genus,
            family: family,
            catalogTier: "regional"
        )
    }

    private func loadBioCAPFixture() throws -> (UIImage, BioCAPFixtureExpectation) {
        guard let fixtureURL = try? ResourceLocator.url(
            named: "BioCAPFixture",
            extension: "jpg"
        ),
              let expectedURL = try? ResourceLocator.url(
                named: "BioCAPFixture",
                extension: "json"
              ) else {
            throw XCTSkip("Generate local BioCAP assets with tools/biocap/export_ios_assets.py")
        }

        let expectedData = try Data(contentsOf: expectedURL)
        let expected = try JSONDecoder().decode(BioCAPFixtureExpectation.self, from: expectedData)
        let imageData = try Data(contentsOf: fixtureURL)
        guard let image = UIImage(data: imageData) else {
            throw BioCAPFixtureError.unreadableImage
        }
        return (image, expected)
    }
}

private struct BioCAPFixtureExpectation: Decodable {
    var expectedScientificName: String
}

private enum BioCAPFixtureError: Error {
    case unreadableImage
}
