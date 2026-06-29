import Foundation

public enum HumanPrivacyFilter {
    public static func isHumanWindow(
        _ predictions: [SpeciesScore],
        privacyThresholdPercent: Float,
        modelClassCount: Int = 6_000
    ) -> Bool {
        let humanCutoff = max(10, Int(Float(modelClassCount) * privacyThresholdPercent / 100))
        return predictions.prefix(humanCutoff).contains {
            $0.scientificName.localizedCaseInsensitiveContains("Human")
        }
    }

    public static func filter(
        _ predictions: [[SpeciesScore]],
        privacyThresholdPercent: Float,
        modelClassCount: Int = 6_000
    ) -> [[SpeciesScore]] {
        guard !predictions.isEmpty else {
            return []
        }

        var humanMask = Array(repeating: false, count: predictions.count)

        for index in predictions.indices {
            humanMask[index] = isHumanWindow(
                predictions[index],
                privacyThresholdPercent: privacyThresholdPercent,
                modelClassCount: modelClassCount
            )
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
