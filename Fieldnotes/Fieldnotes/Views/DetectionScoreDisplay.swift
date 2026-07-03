import FieldnotesCore
import SwiftUI

struct DetectionScoreDisplay {
    var value: String
    var label: String
    var color: Color

    init(source: DetectionSource, score: Float) {
        switch source {
        case .audio:
            value = "\(Int(score * 100))%"
            label = "confidence"
            color = FieldStyle.confidenceColor(score)
        case .photo:
            value = score.formatted(.number.precision(.fractionLength(3)))
            label = "similarity"
            color = FieldStyle.inkMuted
        }
    }
}
