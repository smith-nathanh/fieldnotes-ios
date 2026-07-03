import Foundation

public enum DetectionStoreDecision: Equatable, Sendable {
    /// No recent detection of this species — log a new entry.
    case insert
    /// A recent (in-cooldown) entry exists and this call is stronger — replace it in place.
    case replace(existingID: UUID)
    /// A recent (in-cooldown) entry exists and is at least as strong — discard this call.
    case skip(existingID: UUID)
}

public struct DetectionStore: Sendable {
    public private(set) var detections: [FieldDetection]

    public init(detections: [FieldDetection] = []) {
        self.detections = detections
    }

    /// Records a detection with cooldown-gated deduplication: repeated calls of
    /// the same species within its taxon's cooldown window collapse into a single
    /// entry, keeping the strongest. This prevents a frequently-calling animal
    /// from flooding the log (e.g. a wren logged seven times a minute).
    public mutating func record(_ detection: FieldDetection) -> DetectionStoreDecision {
        let decision = decision(for: detection)
        switch decision {
        case .insert:
            detections.append(detection)
        case .replace(let existingID):
            if let index = detections.firstIndex(where: { $0.id == existingID }) {
                var replacement = detection
                // Update the entry in place with the stronger call's data while
                // preserving the original entry's identity and first-of-species flag.
                replacement.id = detections[index].id
                replacement.isFirstOfSpecies = detections[index].isFirstOfSpecies
                detections[index] = replacement
            }
        case .skip:
            break
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
            return .insert
        }
        if detection.confidence > strongest.confidence {
            return .replace(existingID: strongest.id)
        }
        return .skip(existingID: strongest.id)
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
                bestSource: best.source,
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

    /// Groups detections captured during the same listening session into outings,
    /// most recent first. Detections without an `outingId` (e.g. photo captures)
    /// are excluded.
    public func outings() -> [Outing] {
        let grouped = Dictionary(grouping: detections.compactMap { detection in
            detection.outingId.map { (outingId: $0, detection: detection) }
        }, by: \.outingId)

        return grouped.map { id, pairs in
            let items = pairs.map(\.detection)
            let times = items.map(\.detectedAt)
            return Outing(
                id: id,
                startedAt: times.min() ?? .distantPast,
                endedAt: times.max() ?? .distantPast,
                speciesCount: Set(items.map(\.scientificName)).count,
                detectionCount: items.count
            )
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    public static func cooldownSeconds(for taxon: Taxon) -> TimeInterval {
        switch taxon {
        case .bird, .mammal, .unknown:
            return 5 * 60
        case .amphibian, .reptile:
            return 10 * 60
        case .insect:
            return 30 * 60
        }
    }
}
