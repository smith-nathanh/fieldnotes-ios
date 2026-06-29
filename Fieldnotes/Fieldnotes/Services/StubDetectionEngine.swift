import Foundation
import FieldnotesCore

struct StubDetectionEngine: DetectionEngine {
    func events() -> AsyncThrowingStream<DetectionEngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let sequence: [(String, String, Taxon, Float)] = [
                    ("Pica pica", "Eurasian Magpie", .bird, 0.9316),
                    ("Calypte anna", "Anna's Hummingbird", .bird, 0.8840),
                    ("Oecanthus exclamationis", "Davis's Tree Cricket", .insect, 0.7420),
                    ("Corvus brachyrhynchos", "American Crow", .bird, 0.8125),
                    ("Pseudacris regilla", "Pacific Chorus Frog", .amphibian, 0.7950),
                ]

                var index = 0
                while !Task.isCancelled {
                    let item = sequence[index % sequence.count]
                    let now = Date()
                    let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: now)
                    continuation.yield(.diagnostics(DetectionDiagnostics(
                        windowsProcessed: index + 1,
                        topCandidateName: item.1,
                        topCandidateConfidence: item.3,
                        audioLevel: 0.42,
                        inferenceLatency: 0.18,
                        privacySuppressed: false,
                        rangeFilterActive: false,
                        rangeSpeciesCount: nil,
                        audioInputName: "Built-in Microphone"
                    )))
                    continuation.yield(.detection(
                        FieldDetection(
                            scientificName: item.0,
                            commonName: item.1,
                            taxon: item.2,
                            confidence: item.3,
                            detectedAt: now,
                            week: week
                        )
                    ))
                    index += 1
                    try? await Task.sleep(for: .seconds(4))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
