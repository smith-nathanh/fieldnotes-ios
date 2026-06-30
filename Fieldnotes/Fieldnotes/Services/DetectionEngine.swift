import Foundation
import FieldnotesCore

struct DetectionDiagnostics: Equatable, Sendable {
    var windowsProcessed: Int
    var topCandidateName: String?
    var topCandidateConfidence: Float?
    var acceptedCandidateName: String?
    var acceptedCandidateConfidence: Float?
    var audioLevel: Float
    var inferenceLatency: TimeInterval?
    var privacySuppressed: Bool
    var rangeFilterActive: Bool
    var rangeSpeciesCount: Int?
    var audioInputName: String?

    static let empty = DetectionDiagnostics(
        windowsProcessed: 0,
        topCandidateName: nil,
        topCandidateConfidence: nil,
        acceptedCandidateName: nil,
        acceptedCandidateConfidence: nil,
        audioLevel: 0,
        inferenceLatency: nil,
        privacySuppressed: false,
        rangeFilterActive: false,
        rangeSpeciesCount: nil,
        audioInputName: nil
    )
}

enum DetectionEngineEvent: Sendable {
    case detection(FieldDetection)
    case diagnostics(DetectionDiagnostics)
}

protocol DetectionEngine: Sendable {
    func events() -> AsyncThrowingStream<DetectionEngineEvent, Error>
}
