import Foundation

public enum Taxon: String, Codable, CaseIterable, Sendable {
    case bird
    case mammal
    case amphibian
    case insect
    case unknown
}

public struct DetectionSettings: Codable, Equatable, Sendable {
    public var confidenceThreshold: Float
    public var sensitivity: Float
    public var overlapSeconds: Double
    public var privacyThresholdPercent: Float
    public var speciesFrequencyThreshold: Float
    public var extractionLengthSeconds: Double

    public init(
        confidenceThreshold: Float = 0.70,
        sensitivity: Float = 1.25,
        overlapSeconds: Double = 0,
        privacyThresholdPercent: Float = 0,
        speciesFrequencyThreshold: Float = 0.003,
        extractionLengthSeconds: Double = 6
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.sensitivity = sensitivity
        self.overlapSeconds = overlapSeconds
        self.privacyThresholdPercent = privacyThresholdPercent
        self.speciesFrequencyThreshold = speciesFrequencyThreshold
        self.extractionLengthSeconds = extractionLengthSeconds
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
        self.confidence = confidence
        self.detectedAt = detectedAt
        self.clipURL = clipURL
        self.latitude = latitude
        self.longitude = longitude
        self.week = week
    }
}

public struct SpeciesSummary: Identifiable, Equatable, Sendable {
    public var id: String { scientificName }
    public var scientificName: String
    public var commonName: String
    public var taxon: Taxon
    public var count: Int
    public var bestConfidence: Float
    public var firstSeen: Date
    public var lastSeen: Date

    public init(
        scientificName: String,
        commonName: String,
        taxon: Taxon,
        count: Int,
        bestConfidence: Float,
        firstSeen: Date,
        lastSeen: Date
    ) {
        self.scientificName = scientificName
        self.commonName = commonName
        self.taxon = taxon
        self.count = count
        self.bestConfidence = bestConfidence
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}
