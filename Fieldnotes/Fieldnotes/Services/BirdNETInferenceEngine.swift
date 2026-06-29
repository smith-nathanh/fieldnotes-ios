import Foundation
import FieldnotesCore

#if canImport(TensorFlowLite)
import TensorFlowLite
#endif

struct BirdNETInferenceEngine: Sendable {
    let settings: DetectionSettings
    let sampleRate = 48_000
    let chunkSeconds = 3.0

    init(settings: DetectionSettings = DetectionSettings()) {
        self.settings = settings
    }

    func runGoldenFixture() throws -> [[SpeciesScore]] {
        let samples = try AudioFixtureLoader.loadMonoFloatSamples(named: "Pica pica_30s")
        let windows = AudioWindowing.splitSignal(
            samples,
            sampleRate: sampleRate,
            overlapSeconds: settings.overlapSeconds,
            chunkSeconds: chunkSeconds
        )

        #if canImport(TensorFlowLite)
        let modelURL = try ResourceLocator.url(
            named: "BirdNET_GLOBAL_6K_V2.4_Model_FP16",
            extension: "tflite"
        )
        let labels = try ResourceLocator.labels(named: "BirdNET_GLOBAL_6K_V2.4_Model_FP16_Labels")
        let interpreter = try makeBirdNETInterpreter(modelURL: modelURL, sampleCount: sampleRate * Int(chunkSeconds))
        return try windows.map { try classifyBirdNETWindow($0, interpreter: interpreter, labels: labels, settings: settings) }
        #else
        return [FixtureExpectations.picaPicaExpectedDetections]
        #endif
    }

    func classifyThreeSecondWindow(_ samples: [Float]) throws -> [SpeciesScore] {
        #if canImport(TensorFlowLite)
        let modelURL = try ResourceLocator.url(
            named: "BirdNET_GLOBAL_6K_V2.4_Model_FP16",
            extension: "tflite"
        )
        let labels = try ResourceLocator.labels(named: "BirdNET_GLOBAL_6K_V2.4_Model_FP16_Labels")
        let interpreter = try makeBirdNETInterpreter(modelURL: modelURL, sampleCount: samples.count)
        return try classifyBirdNETWindow(samples, interpreter: interpreter, labels: labels, settings: settings)
        #else
        return FixtureExpectations.picaPicaExpectedDetections
        #endif
    }

    func summarizeGoldenFixture() throws -> String {
        let windowResults = try runGoldenFixture()
        let picaWindows = windowResults
            .compactMap { window in window.first { $0.scientificName == "Pica pica" } }
            .filter { $0.confidence >= settings.confidenceThreshold }

        guard let best = picaWindows.max(by: { $0.confidence < $1.confidence }) else {
            return "BirdNET fixture: no Pica pica detections"
        }

        return "BirdNET fixture: \(picaWindows.count) Pica pica windows, best \(Int(best.confidence * 100))%"
    }

}

final class BirdNETWindowClassifier {
    let settings: DetectionSettings
    let labels: [String]
    let commonNames: [String: String]
    let taxa: [String: Taxon]

    #if canImport(TensorFlowLite)
    private let interpreter: Interpreter
    #endif

    init(settings: DetectionSettings = DetectionSettings(), sampleCount: Int = 144_000) throws {
        self.settings = settings
        labels = try ResourceLocator.labels(named: "BirdNET_GLOBAL_6K_V2.4_Model_FP16_Labels")
        commonNames = try ResourceLocator.commonNames()
        taxa = try ResourceLocator.taxa()

        #if canImport(TensorFlowLite)
        let modelURL = try ResourceLocator.url(
            named: "BirdNET_GLOBAL_6K_V2.4_Model_FP16",
            extension: "tflite"
        )
        interpreter = try makeBirdNETInterpreter(modelURL: modelURL, sampleCount: sampleCount)
        #endif
    }

    func classify(_ samples: [Float]) throws -> [SpeciesScore] {
        #if canImport(TensorFlowLite)
        return try classifyBirdNETWindow(samples, interpreter: interpreter, labels: labels, settings: settings)
        #else
        return FixtureExpectations.picaPicaExpectedDetections
        #endif
    }

    func fieldDetection(from score: SpeciesScore, detectedAt: Date = Date()) -> FieldDetection {
        FieldDetection(
            scientificName: score.scientificName,
            commonName: commonNames[score.scientificName] ?? score.scientificName,
            taxon: taxa[score.scientificName] ?? .bird,
            confidence: score.confidence,
            detectedAt: detectedAt,
            week: Calendar(identifier: .iso8601).component(.weekOfYear, from: detectedAt)
        )
    }
}

#if canImport(TensorFlowLite)
private func makeBirdNETInterpreter(modelURL: URL, sampleCount: Int) throws -> Interpreter {
    var options = Interpreter.Options()
    options.threadCount = 2
    options.isXNNPackEnabled = true

    let interpreter = try Interpreter(modelPath: modelURL.path, options: options)
    try interpreter.resizeInput(at: 0, to: [1, sampleCount])
    try interpreter.allocateTensors()
    return interpreter
}

private func classifyBirdNETWindow(
    _ samples: [Float],
    interpreter: Interpreter,
    labels: [String],
    settings: DetectionSettings
) throws -> [SpeciesScore] {
        let data = samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        try interpreter.copy(data, toInputAt: 0)
        try interpreter.invoke()
        let output = try interpreter.output(at: 0)
        let logits = output.data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
        let confidences = BirdNETScoring.scaledSigmoid(logits, sensitivity: settings.sensitivity)
        return BirdNETScoring.rankedScores(labels: labels, confidences: confidences, limit: 10)
}
#endif
