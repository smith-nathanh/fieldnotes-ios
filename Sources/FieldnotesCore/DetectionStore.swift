import Foundation

public enum DetectionStoreDecision: Equatable, Sendable {
    case insertWithClip
    case insertWithoutClip(existingID: UUID)
    case insertReplacingClip(existingID: UUID)
}

public struct DetectionStore: Sendable {
    public private(set) var detections: [FieldDetection]

    public init(detections: [FieldDetection] = []) {
        self.detections = detections
    }

    public mutating func record(_ detection: FieldDetection) -> DetectionStoreDecision {
        let decision = decision(for: detection)
        var detection = detection
        switch decision {
        case .insertWithClip:
            detections.append(detection)
        case .insertWithoutClip:
            detection.clipURL = nil
            detections.append(detection)
        case .insertReplacingClip(let existingID):
            if let index = detections.firstIndex(where: { $0.id == existingID }) {
                detections[index].clipURL = nil
            }
            detections.append(detection)
        }
        return decision
    }

    public func decision(for detection: FieldDetection) -> DetectionStoreDecision {
        let cooldown = Self.cooldownSeconds(for: detection.taxon)
        let windowStart = detection.detectedAt.addingTimeInterval(-cooldown)
        let candidates = detections.filter {
            $0.scientificName == detection.scientificName &&
            $0.detectedAt >= windowStart &&
            $0.detectedAt <= detection.detectedAt
        }

        guard let strongest = candidates.max(by: { $0.confidence < $1.confidence }) else {
            return .insertWithClip
        }
        if detection.confidence > strongest.confidence {
            return .insertReplacingClip(existingID: strongest.id)
        }
        return .insertWithoutClip(existingID: strongest.id)
    }

    public func summaries() -> [SpeciesSummary] {
        let grouped = Dictionary(grouping: detections, by: \.scientificName)
        return grouped.values.compactMap { items in
            guard let first = items.min(by: { $0.detectedAt < $1.detectedAt }),
                  let last = items.max(by: { $0.detectedAt < $1.detectedAt }),
                  let best = items.max(by: { $0.confidence < $1.confidence }) else {
                return nil
            }
            return SpeciesSummary(
                scientificName: first.scientificName,
                commonName: first.commonName,
                taxon: first.taxon,
                count: items.count,
                bestConfidence: best.confidence,
                firstSeen: first.detectedAt,
                lastSeen: last.detectedAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.lastSeen == rhs.lastSeen {
                return lhs.commonName < rhs.commonName
            }
            return lhs.lastSeen > rhs.lastSeen
        }
    }

    public static func cooldownSeconds(for taxon: Taxon) -> TimeInterval {
        switch taxon {
        case .bird, .mammal, .unknown:
            return 5 * 60
        case .amphibian:
            return 10 * 60
        case .insect:
            return 30 * 60
        }
    }
}
