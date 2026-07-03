import Foundation

public enum Taxon: String, Codable, CaseIterable, Sendable {
    case bird
    case mammal
    case amphibian
    case reptile
    case insect
    case unknown
}

public enum DetectionSource: String, Codable, Sendable {
    case audio
    case photo
}

public struct DetectionSettings: Codable, Equatable, Sendable {
    public var confidenceThreshold: Float
    public var sensitivity: Float
    public var overlapSeconds: Double
    public var privacyFilterEnabled: Bool
    public var privacyThresholdPercent: Float
    public var speciesFrequencyThreshold: Float
    public var extractionLengthSeconds: Double
    public var latitude: Double?
    public var longitude: Double?
    public var week: Int?

    public init(
        confidenceThreshold: Float = 0.60,
        sensitivity: Float = 1.25,
        overlapSeconds: Double = 1.5,
        privacyFilterEnabled: Bool = false,
        privacyThresholdPercent: Float = 0,
        speciesFrequencyThreshold: Float = 0.03,
        extractionLengthSeconds: Double = 6,
        latitude: Double? = nil,
        longitude: Double? = nil,
        week: Int? = nil
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.sensitivity = sensitivity
        self.overlapSeconds = overlapSeconds
        self.privacyFilterEnabled = privacyFilterEnabled
        self.privacyThresholdPercent = privacyThresholdPercent
        self.speciesFrequencyThreshold = speciesFrequencyThreshold
        self.extractionLengthSeconds = extractionLengthSeconds
        self.latitude = latitude
        self.longitude = longitude
        self.week = week
    }
}

public struct SpeciesLabel: Codable, Hashable, Sendable {
    public var scientificName: String
    public var commonName: String
    public var taxon: Taxon

    public init(scientificName: String, commonName: String, taxon: Taxon = .bird) {
        self.scientificName = scientificName
        self.commonName = commonName
        self.taxon = taxon
    }
}

public struct SpeciesScore: Codable, Equatable, Sendable {
    public var scientificName: String
    public var confidence: Float

    public init(scientificName: String, confidence: Float) {
        self.scientificName = scientificName
        self.confidence = confidence
    }
}

public struct FieldDetection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var scientificName: String
    public var commonName: String
    public var taxon: Taxon
    public var source: DetectionSource
    public var confidence: Float
    public var detectedAt: Date
    public var clipURL: URL?
    public var latitude: Double?
    public var longitude: Double?
    public var week: Int

    public init(
        id: UUID = UUID(),
        scientificName: String,
        commonName: String,
        taxon: Taxon = .bird,
        source: DetectionSource = .audio,
        confidence: Float,
        detectedAt: Date,
        clipURL: URL? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        week: Int
    ) {
        self.id = id
        self.scientificName = scientificName
        self.commonName = commonName
        self.taxon = taxon
        self.source = source
        self.confidence = confidence
        self.detectedAt = detectedAt
        self.clipURL = clipURL
        self.latitude = latitude
        self.longitude = longitude
        self.week = week
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case scientificName
        case commonName
        case taxon
        case source
        case confidence
        case detectedAt
        case clipURL
        case latitude
        case longitude
        case week
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        scientificName = try container.decode(String.self, forKey: .scientificName)
        commonName = try container.decode(String.self, forKey: .commonName)
        taxon = try container.decode(Taxon.self, forKey: .taxon)
        source = try container.decodeIfPresent(DetectionSource.self, forKey: .source) ?? .audio
        confidence = try container.decode(Float.self, forKey: .confidence)
        detectedAt = try container.decode(Date.self, forKey: .detectedAt)
        clipURL = try container.decodeIfPresent(URL.self, forKey: .clipURL)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        week = try container.decode(Int.self, forKey: .week)
    }
}

public struct SpeciesSummary: Identifiable, Equatable, Sendable {
    public var id: String { scientificName }
    public var scientificName: String
    public var commonName: String
    public var taxon: Taxon
    public var count: Int
    public var bestConfidence: Float
    public var bestSource: DetectionSource
    public var firstSeen: Date
    public var lastSeen: Date

    public init(
        scientificName: String,
        commonName: String,
        taxon: Taxon,
        count: Int,
        bestConfidence: Float,
        bestSource: DetectionSource = .audio,
        firstSeen: Date,
        lastSeen: Date
    ) {
        self.scientificName = scientificName
        self.commonName = commonName
        self.taxon = taxon
        self.count = count
        self.bestConfidence = bestConfidence
        self.bestSource = bestSource
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}
