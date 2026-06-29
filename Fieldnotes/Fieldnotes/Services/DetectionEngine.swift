import Foundation
import FieldnotesCore

protocol DetectionEngine: Sendable {
    func detections() -> AsyncThrowingStream<FieldDetection, Error>
}
