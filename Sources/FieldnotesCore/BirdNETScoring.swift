import Foundation

public enum BirdNETScoring {
    public static func scaledSigmoid(_ logits: [Float], sensitivity: Float) -> [Float] {
        let shapedSensitivity = max(0.5, min(1.0 - (sensitivity - 1.0), 1.5))
        return logits.map { 1 / (1 + exp(-shapedSensitivity * $0)) }
    }

    public static func rankedScores(labels: [String], confidences: [Float], limit: Int? = nil) -> [SpeciesScore] {
        let ranked = zip(labels, confidences)
            .map { SpeciesScore(scientificName: $0.0, confidence: $0.1) }
            .sorted { $0.confidence > $1.confidence }

        guard let limit else {
            return ranked
        }
        return Array(ranked.prefix(limit))
    }

    public static func filteredDetections(
        rankedScores: [SpeciesScore],
        allowedSpecies: Set<String>,
        whitelist: Set<String>,
        settings: DetectionSettings
    ) -> [SpeciesScore] {
        rankedScores.filter { score in
            guard score.confidence >= settings.confidenceThreshold else {
                return false
            }
            if allowedSpecies.isEmpty || allowedSpecies.contains(score.scientificName) {
                return true
            }
            return whitelist.contains(score.scientificName)
        }
    }
}
