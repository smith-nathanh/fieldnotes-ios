import Foundation

public enum HumanPrivacyFilter {
    public static func filter(
        _ predictions: [[SpeciesScore]],
        privacyThresholdPercent: Float,
        modelClassCount: Int = 6_000
    ) -> [[SpeciesScore]] {
        guard !predictions.isEmpty else {
            return []
        }

        let humanCutoff = max(10, Int(Float(modelClassCount) * privacyThresholdPercent / 100))
        var humanMask = Array(repeating: false, count: predictions.count)

        for index in predictions.indices {
            let window = predictions[index].prefix(humanCutoff)
            humanMask[index] = window.contains { $0.scientificName.localizedCaseInsensitiveContains("Human") }
        }

        var neighborMask = Array(repeating: false, count: predictions.count)
        for index in humanMask.indices {
            if index > 0, humanMask[index - 1] {
                neighborMask[index] = true
            }
            if index < humanMask.count - 1, humanMask[index + 1] {
                neighborMask[index] = true
            }
        }

        return predictions.indices.map { index in
            if humanMask[index] || neighborMask[index] {
                return [SpeciesScore(scientificName: "Human_Human", confidence: 0)]
            }
            return Array(predictions[index].prefix(10))
        }
    }
}
