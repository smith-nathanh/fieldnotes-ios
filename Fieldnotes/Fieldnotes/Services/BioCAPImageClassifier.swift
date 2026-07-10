import CoreGraphics
import CoreML
import Foundation
import UIKit

nonisolated enum BioCAPGeographyMode: String, CaseIterable, Sendable {
    case automatic
    case selectedRegion
    case everywhere
}

nonisolated enum BioCAPUSRegion: String, CaseIterable, Sendable {
    case northeast
    case southeast
    case midwest
    case southCentral = "south-central"
    case southwest
    case mountainWest = "mountain-west"
    case pacific
    case alaska
    case hawaii

    var displayName: String {
        switch self {
        case .northeast: "Northeast"
        case .southeast: "Southeast"
        case .midwest: "Midwest"
        case .southCentral: "South Central"
        case .southwest: "Southwest"
        case .mountainWest: "Mountain West"
        case .pacific: "Pacific"
        case .alaska: "Alaska"
        case .hawaii: "Hawaii"
        }
    }
}

nonisolated struct BioCAPGeographyPreference: Equatable, Sendable {
    var mode: BioCAPGeographyMode = .automatic
    var regionID: String? = nil
}

nonisolated enum BioCAPUSRegionResolver {
    /// Offline, deliberately broad region resolution for an optional soft
    /// ranking hint. It never removes candidates, so state-line approximation
    /// errors cannot make an unusual observation unavailable.
    static func region(latitude: Double?, longitude: Double?) -> BioCAPUSRegion? {
        guard let latitude, let longitude else { return nil }
        if (50...72).contains(latitude), (-180 ... -129).contains(longitude) {
            return .alaska
        }
        if (18...23).contains(latitude), (-161 ... -154).contains(longitude) {
            return .hawaii
        }
        guard (24...50).contains(latitude), (-125 ... -66).contains(longitude) else {
            return nil
        }
        if longitude <= -117.5
            || (latitude < 35 && longitude <= -114.5)
            || (latitude >= 42 && longitude <= -116.5) {
            return .pacific
        }
        if longitude <= -103 {
            return latitude < 37 ? .southwest : .mountainWest
        }
        if longitude <= -90.5, latitude < 37.5 {
            return .southCentral
        }
        if latitude >= 39 || (longitude <= -88 && latitude >= 36.5) {
            return longitude >= -80 ? .northeast : .midwest
        }
        return .southeast
    }
}

nonisolated enum BioCAPGeographyRanking {
    static let matchingRegionBoost: Float = 0.005

    static func boost(stateMembership: UInt64, regionStateMask: UInt64) -> Float {
        stateMembership & regionStateMask == 0 ? 0 : matchingRegionBoost
    }
}

nonisolated struct BioCAPPhotoPrediction: Equatable, Sendable {
    var scientificName: String
    var commonName: String
    var taxon: String
    /// Raw cosine similarity from BioCAP. This is not a calibrated probability.
    var similarity: Float
    /// Similarity plus any documented soft context prior, used only for ordering.
    var rankingScore: Float
    var genus: String?
    var family: String?
    var catalogTier: String?

    // Compatibility for existing fixture/performance diagnostics while callers
    // migrate to the correctly named similarity field.
    var score: Float { similarity }
}

nonisolated struct BioCAPPhotoContext: Equatable, Sendable {
    var latitude: Double?
    var longitude: Double?
    var week: Int
    var horizontalAccuracy: Double? = nil
    var geographyPreference = BioCAPGeographyPreference()

    var preferredRegion: BioCAPUSRegion? {
        switch geographyPreference.mode {
        case .automatic:
            BioCAPUSRegionResolver.region(latitude: latitude, longitude: longitude)
        case .selectedRegion:
            geographyPreference.regionID.flatMap(BioCAPUSRegion.init(rawValue:))
        case .everywhere:
            nil
        }
    }
}

nonisolated enum BioCAPSuggestedRank: String, Equatable, Sendable {
    case species
    case genus
    case family
    case uncertain
}

nonisolated struct BioCAPClassificationResult: Equatable, Sendable {
    var predictions: [BioCAPPhotoPrediction]
    var suggestedRank: BioCAPSuggestedRank
    var suggestedName: String?
    var top1Top2Margin: Float?
    var appliedGeographyName: String?

    var exactPrediction: BioCAPPhotoPrediction? {
        suggestedRank == .species ? predictions.first : nil
    }
}

nonisolated enum BioCAPIdentificationPolicy {
    /// Pilot threshold selected on nc-v1. At 0.035, 8/9 accepted top-1 results
    /// were correct. This is intentionally not represented as confidence and
    /// must be recalibrated on a larger held-out/open-set dataset.
    static let exactSpeciesMargin: Float = 0.035
    static let contenderDelta: Float = 0.020

    static func evaluate(
        predictions: [BioCAPPhotoPrediction],
        appliedGeographyName: String?
    ) -> BioCAPClassificationResult {
        let predictions = collapsedSpeciesPredictions(predictions)
        guard let first = predictions.first else {
            return BioCAPClassificationResult(
                predictions: [],
                suggestedRank: .uncertain,
                suggestedName: nil,
                top1Top2Margin: nil,
                appliedGeographyName: appliedGeographyName
            )
        }
        let margin = predictions.dropFirst().first.map {
            first.rankingScore - $0.rankingScore
        }
        if margin.map({ $0 >= exactSpeciesMargin }) ?? true {
            return BioCAPClassificationResult(
                predictions: predictions,
                suggestedRank: .species,
                suggestedName: first.commonName,
                top1Top2Margin: margin,
                appliedGeographyName: appliedGeographyName
            )
        }

        let contenders = predictions.prefix {
            first.rankingScore - $0.rankingScore <= contenderDelta
        }
        let genera = Set(contenders.compactMap { normalized($0.genus) })
        if genera.count == 1, let genus = genera.first, contenders.count > 1 {
            return BioCAPClassificationResult(
                predictions: predictions,
                suggestedRank: .genus,
                suggestedName: genus,
                top1Top2Margin: margin,
                appliedGeographyName: appliedGeographyName
            )
        }
        let families = Set(contenders.compactMap { normalized($0.family) })
        if families.count == 1, let family = families.first, contenders.count > 1 {
            return BioCAPClassificationResult(
                predictions: predictions,
                suggestedRank: .family,
                suggestedName: family,
                top1Top2Margin: margin,
                appliedGeographyName: appliedGeographyName
            )
        }
        return BioCAPClassificationResult(
            predictions: predictions,
            suggestedRank: .uncertain,
            suggestedName: nil,
            top1Top2Margin: margin,
            appliedGeographyName: appliedGeographyName
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    /// Catalog sources can contain both a species and one or more infraspecies.
    /// They are one identification decision, not competing evidence. Keep the
    /// canonical species row when present while retaining the group's best score.
    private static func collapsedSpeciesPredictions(
        _ predictions: [BioCAPPhotoPrediction]
    ) -> [BioCAPPhotoPrediction] {
        let grouped = Dictionary(grouping: predictions, by: speciesKey)
        return grouped.values.compactMap { group in
            guard var representative = group.first(where: {
                $0.scientificName == speciesKey($0)
            }) ?? group.max(by: { $0.rankingScore < $1.rankingScore }) else {
                return nil
            }
            representative.similarity = group.map(\.similarity).max() ?? representative.similarity
            representative.rankingScore = group.map(\.rankingScore).max() ?? representative.rankingScore
            return representative
        }
        .sorted { $0.rankingScore > $1.rankingScore }
    }

    private static func speciesKey(_ prediction: BioCAPPhotoPrediction) -> String {
        prediction.scientificName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .joined(separator: " ")
    }
}

nonisolated struct BioCAPSpeciesMetadata: Decodable, Equatable {
    var index: Int
    var scientificName: String
    var commonName: String
    var taxon: String
    var kingdom: String?
    var phylum: String?
    var className: String?
    var order: String?
    var family: String?
    var genus: String?
    var species: String?
    var catalogTier: String?
    var alsoInTravelFallback: Bool?
    var regionalResearchObservations: Int?

    enum CodingKeys: String, CodingKey {
        case index
        case scientificName
        case commonName
        case taxon
        case kingdom
        case phylum
        case className = "class"
        case order
        case family
        case genus
        case species
        case catalogTier
        case alsoInTravelFallback
        case regionalResearchObservations
    }
}

nonisolated struct BioCAPConfig: Decodable, Equatable {
    var embeddingDim: Int
    var speciesCount: Int
    var embeddingDtype: String
    var modelName: String
    var promptPreset: String
    var labelTextType: String
    var promptTemplateCount: Int
    var geography: BioCAPGeographyConfig?
}

nonisolated struct BioCAPGeographyConfig: Decodable, Equatable {
    var stateCodes: [String]
    var stateRegionIndices: [Int]
    var regions: [BioCAPRegionDefinition]
}

nonisolated struct BioCAPRegionDefinition: Decodable, Equatable, Sendable {
    var id: String
    var displayName: String
}

nonisolated struct BioCAPAssetSummary: Equatable, Sendable {
    var speciesCount: Int
    var promptPreset: String
    var promptTemplateCount: Int
    var labelTextType: String
    var regions: [BioCAPRegionDefinition]
}

actor BioCAPImageClassificationService {
    private var classifier: BioCAPImageClassifier?

    func classifyJPEGData(
        _ data: Data,
        limit: Int = 5,
        context: BioCAPPhotoContext? = nil
    ) throws -> BioCAPClassificationResult {
        guard let image = UIImage(data: data) else {
            throw BioCAPImageClassifierError.invalidImage
        }
        let classifier = try cachedClassifier()
        let predictions = try classifier.classify(image, limit: limit, context: context)
        return BioCAPIdentificationPolicy.evaluate(
            predictions: predictions,
            appliedGeographyName: classifier.appliedGeographyName(for: context)
        )
    }

    private func cachedClassifier() throws -> BioCAPImageClassifier {
        if let classifier {
            return classifier
        }
        let classifier = try BioCAPImageClassifier()
        self.classifier = classifier
        return classifier
    }
}

nonisolated final class BioCAPImageClassifier {
    private static let inputName = "image"
    private static let inputShape = [1, 3, 224, 224]

    private let model: MLModel
    private let species: [BioCAPSpeciesMetadata]
    private let config: BioCAPConfig
    private let textEmbeddings: [Float]
    private let geographyMemberships: [UInt64]?
    private let geographyRegionMasks: [UInt64]?
    private let embeddingOutputName: String

    init(
        bundle: Bundle = .main,
        computeUnits: MLComputeUnits = .cpuOnly
    ) throws {
        let config = try Self.loadConfig(bundle: bundle)
        let species = try Self.loadSpecies(bundle: bundle)
        let textEmbeddings = try Self.loadEmbeddings(bundle: bundle)
        let geographyMemberships = try Self.loadGeographyMemberships(
            bundle: bundle,
            config: config
        )
        let model = try Self.loadModel(bundle: bundle, computeUnits: computeUnits)
        let embeddingOutputName = try Self.validateModelContract(model, config: config)
        try Self.validateAssets(
            species: species,
            config: config,
            textEmbeddings: textEmbeddings,
            geographyMemberships: geographyMemberships
        )

        self.model = model
        self.species = species
        self.config = config
        self.textEmbeddings = textEmbeddings
        self.geographyMemberships = geographyMemberships
        self.geographyRegionMasks = Self.regionMasks(config: config.geography)
        self.embeddingOutputName = embeddingOutputName
    }

    func classify(
        _ image: UIImage,
        limit: Int = 5,
        context: BioCAPPhotoContext? = nil
    ) throws -> [BioCAPPhotoPrediction] {
        guard limit > 0 else {
            return []
        }
        let input = try Self.preprocess(image)
        let provider = try MLDictionaryFeatureProvider(
            dictionary: [Self.inputName: MLFeatureValue(multiArray: input)]
        )
        let output = try model.prediction(from: provider)
        guard let outputFeature = output.featureValue(for: embeddingOutputName),
              let outputArray = outputFeature.multiArrayValue else {
            throw BioCAPImageClassifierError.missingOutput(embeddingOutputName)
        }
        let imageEmbedding = try outputArray.floatArray()
        guard imageEmbedding.count == config.embeddingDim else {
            throw BioCAPImageClassifierError.modelContract(
                "BioCAP output \(embeddingOutputName) has \(imageEmbedding.count) values; expected \(config.embeddingDim)."
            )
        }
        let normalizedImageEmbedding = try Self.l2Normalized(imageEmbedding)

        let scores = species.indices.map { index -> BioCAPPhotoPrediction in
            let rowStart = index * config.embeddingDim
            let score = Self.dot(
                normalizedImageEmbedding,
                textEmbeddings[rowStart..<(rowStart + config.embeddingDim)]
            )
            let item = species[index]
            let contextBoost = geographyBoost(
                speciesIndex: index,
                item: item,
                context: context
            )
            return BioCAPPhotoPrediction(
                scientificName: item.scientificName,
                commonName: item.commonName,
                taxon: item.taxon,
                similarity: score,
                rankingScore: score + contextBoost,
                genus: item.genus,
                family: item.family,
                catalogTier: item.catalogTier
            )
        }

        return Array(scores.sorted { $0.rankingScore > $1.rankingScore }.prefix(min(limit, species.count)))
    }

    static func assetSummary(bundle: Bundle = .main) throws -> BioCAPAssetSummary {
        let config = try loadConfig(bundle: bundle)
        return BioCAPAssetSummary(
            speciesCount: config.speciesCount,
            promptPreset: config.promptPreset,
            promptTemplateCount: config.promptTemplateCount,
            labelTextType: config.labelTextType,
            regions: config.geography?.regions
                ?? BioCAPUSRegion.allCases.map {
                    BioCAPRegionDefinition(id: $0.rawValue, displayName: $0.displayName)
                }
        )
    }

    func appliedGeographyName(for context: BioCAPPhotoContext?) -> String? {
        guard let region = context?.preferredRegion else { return nil }
        if let configuredRegion = config.geography?.regions.first(where: {
            $0.id == region.rawValue
        }) {
            return configuredRegion.displayName
        }
        if config.geography == nil, region == .southeast {
            return region.displayName
        }
        return nil
    }

    private func geographyBoost(
        speciesIndex: Int,
        item: BioCAPSpeciesMetadata,
        context: BioCAPPhotoContext?
    ) -> Float {
        guard let region = context?.preferredRegion else { return 0 }
        if let geographyMemberships,
           let geographyRegionMasks,
           let regionIndex = config.geography?.regions.firstIndex(where: {
               $0.id == region.rawValue
           }),
           regionIndex < geographyRegionMasks.count,
           geographyMemberships[speciesIndex] & geographyRegionMasks[regionIndex] != 0 {
            return BioCAPGeographyRanking.boost(
                stateMembership: geographyMemberships[speciesIndex],
                regionStateMask: geographyRegionMasks[regionIndex]
            )
        }
        // Compatibility for the currently shipped NC + travel bundle, which
        // predates BioCAPGeography.bin. Other selected regions receive no
        // artificial boost until the U.S. asset set is promoted.
        if config.geography == nil,
           region == .southeast,
           item.catalogTier == "regional" {
            return BioCAPGeographyRanking.matchingRegionBoost
        }
        return 0
    }

    private static func loadModel(bundle: Bundle, computeUnits: MLComputeUnits) throws -> MLModel {
        let url: URL
        if let compiledURL = try? ResourceLocator.url(
            named: "BioCAPVisionEncoder",
            extension: "mlmodelc",
            bundle: bundle
        ) {
            url = compiledURL
        } else {
            url = try ResourceLocator.url(
                named: "BioCAPVisionEncoder",
                extension: "mlpackage",
                bundle: bundle
            )
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    private static func loadSpecies(bundle: Bundle) throws -> [BioCAPSpeciesMetadata] {
        let url = try ResourceLocator.url(named: "BioCAPSpecies", extension: "json", bundle: bundle)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([BioCAPSpeciesMetadata].self, from: data)
    }

    private static func loadConfig(bundle: Bundle) throws -> BioCAPConfig {
        let url = try ResourceLocator.url(named: "BioCAPConfig", extension: "json", bundle: bundle)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BioCAPConfig.self, from: data)
    }

    private static func loadEmbeddings(bundle: Bundle) throws -> [Float] {
        let url = try ResourceLocator.url(
            named: "BioCAPTextEmbeddings",
            extension: "f32",
            bundle: bundle
        )
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }

    private static func loadGeographyMemberships(
        bundle: Bundle,
        config: BioCAPConfig
    ) throws -> [UInt64]? {
        guard config.geography != nil else { return nil }
        let url = try ResourceLocator.url(
            named: "BioCAPGeography",
            extension: "bin",
            bundle: bundle
        )
        let data = try Data(contentsOf: url)
        guard data.count.isMultiple(of: MemoryLayout<UInt64>.size) else {
            throw BioCAPImageClassifierError.assetMismatch(
                "BioCAP geography membership data is not aligned to UInt64 rows."
            )
        }
        return data.withUnsafeBytes { rawBuffer in
            stride(from: 0, to: rawBuffer.count, by: MemoryLayout<UInt64>.size).map {
                UInt64(littleEndian: rawBuffer.loadUnaligned(fromByteOffset: $0, as: UInt64.self))
            }
        }
    }

    private static func regionMasks(config: BioCAPGeographyConfig?) -> [UInt64]? {
        guard let config else { return nil }
        var masks = Array(repeating: UInt64.zero, count: config.regions.count)
        for (stateIndex, regionIndex) in config.stateRegionIndices.enumerated() {
            guard regionIndex >= 0, regionIndex < masks.count, stateIndex < 64 else {
                continue
            }
            masks[regionIndex] |= UInt64(1) << UInt64(stateIndex)
        }
        return masks
    }

    private static func validateModelContract(_ model: MLModel, config: BioCAPConfig) throws -> String {
        let description = model.modelDescription
        guard description.inputDescriptionsByName.count == 1,
              let input = description.inputDescriptionsByName[inputName],
              input.type == .multiArray,
              let inputConstraint = input.multiArrayConstraint else {
            throw BioCAPImageClassifierError.modelContract(
                "BioCAP model must have one multi-array input named \(inputName)."
            )
        }
        guard inputConstraint.shape.map(\.intValue) == inputShape,
              inputConstraint.dataType == .float16 else {
            throw BioCAPImageClassifierError.modelContract(
                "BioCAP input \(inputName) must be float16 with shape \(inputShape)."
            )
        }

        let outputs = description.outputDescriptionsByName
        guard outputs.count == 1,
              let (outputName, output) = outputs.first,
              output.type == .multiArray,
              let outputConstraint = output.multiArrayConstraint else {
            throw BioCAPImageClassifierError.modelContract(
                "BioCAP model must have exactly one multi-array embedding output."
            )
        }
        let expectedOutputShape = [1, config.embeddingDim]
        guard outputConstraint.shape.map(\.intValue) == expectedOutputShape,
              outputConstraint.dataType == .float16 else {
            throw BioCAPImageClassifierError.modelContract(
                "BioCAP output \(outputName) must be float16 with shape \(expectedOutputShape)."
            )
        }
        return outputName
    }

    private static func validateAssets(
        species: [BioCAPSpeciesMetadata],
        config: BioCAPConfig,
        textEmbeddings: [Float],
        geographyMemberships: [UInt64]?
    ) throws {
        guard config.embeddingDim > 0, config.speciesCount > 0 else {
            throw BioCAPImageClassifierError.assetMismatch(
                "BioCAP config must declare positive embedding and species dimensions."
            )
        }
        guard config.embeddingDtype == "float32" else {
            throw BioCAPImageClassifierError.assetMismatch(
                "Unsupported BioCAP text embedding dtype: \(config.embeddingDtype)."
            )
        }
        guard species.count == config.speciesCount else {
            throw BioCAPImageClassifierError.assetMismatch("Species count does not match config.")
        }
        guard textEmbeddings.count == config.speciesCount * config.embeddingDim else {
            throw BioCAPImageClassifierError.assetMismatch(
                "Embedding matrix shape does not match config."
            )
        }
        if let geography = config.geography {
            guard !geography.regions.isEmpty,
                  geography.regions.count <= 64,
                  geography.stateCodes.count == geography.stateRegionIndices.count,
                  geography.stateCodes.count <= 64,
                  Set(geography.stateCodes).count == geography.stateCodes.count,
                  Set(geography.regions.map(\.id)).count == geography.regions.count,
                  geography.stateRegionIndices.allSatisfy({
                      geography.regions.indices.contains($0)
                  }) else {
                throw BioCAPImageClassifierError.assetMismatch(
                    "BioCAP geography config has invalid states or regions."
                )
            }
            guard geographyMemberships?.count == config.speciesCount else {
                throw BioCAPImageClassifierError.assetMismatch(
                    "BioCAP geography membership count does not match config."
                )
            }
            let allowedMask: UInt64 = if geography.stateCodes.count == 64 {
                .max
            } else {
                (UInt64(1) << UInt64(geography.stateCodes.count)) - 1
            }
            guard geographyMemberships?.allSatisfy({
                $0 != 0 && $0 & ~allowedMask == 0
            }) == true else {
                throw BioCAPImageClassifierError.assetMismatch(
                    "BioCAP geography contains an empty or unknown state membership."
                )
            }
        } else if geographyMemberships != nil {
            throw BioCAPImageClassifierError.assetMismatch(
                "BioCAP geography data exists without a config declaration."
            )
        }

        for (expectedIndex, item) in species.enumerated() {
            guard item.index == expectedIndex else {
                throw BioCAPImageClassifierError.assetMismatch(
                    "Species metadata index \(item.index) is out of order at row \(expectedIndex)."
                )
            }
            guard !item.scientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.commonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BioCAPImageClassifierError.assetMismatch(
                    "Species metadata row \(expectedIndex) has an empty name."
                )
            }

            let rowStart = expectedIndex * config.embeddingDim
            var squaredNorm = Float.zero
            for offset in 0..<config.embeddingDim {
                let value = textEmbeddings[rowStart + offset]
                guard value.isFinite else {
                    throw BioCAPImageClassifierError.assetMismatch(
                        "Text embedding row \(expectedIndex) contains a non-finite value."
                    )
                }
                squaredNorm += value * value
            }
            let norm = sqrt(squaredNorm)
            guard norm.isFinite, abs(norm - 1) <= 0.001 else {
                throw BioCAPImageClassifierError.assetMismatch(
                    "Text embedding row \(expectedIndex) is not unit-normalized (norm \(norm))."
                )
            }
        }
    }

    private static func preprocess(_ image: UIImage) throws -> MLMultiArray {
        guard let cgImage = image.cgImage else {
            throw BioCAPImageClassifierError.invalidImage
        }

        let cropped = try centerCrop(cgImage)
        let resized = try resize(cropped, width: 224, height: 224)
        let array = try MLMultiArray(shape: [1, 3, 224, 224], dataType: .float16)
        guard let data = resized.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw BioCAPImageClassifierError.invalidImage
        }

        let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
        let std: [Float] = [0.26862954, 0.26130258, 0.27577711]
        let channelStride = 224 * 224

        for y in 0..<224 {
            for x in 0..<224 {
                let pixelOffset = (y * 224 + x) * 4
                let red = Float(bytes[pixelOffset]) / 255
                let green = Float(bytes[pixelOffset + 1]) / 255
                let blue = Float(bytes[pixelOffset + 2]) / 255
                let baseIndex = y * 224 + x
                array[baseIndex] = NSNumber(value: (red - mean[0]) / std[0])
                array[channelStride + baseIndex] = NSNumber(value: (green - mean[1]) / std[1])
                array[channelStride * 2 + baseIndex] = NSNumber(value: (blue - mean[2]) / std[2])
            }
        }
        return array
    }

    private static func centerCrop(_ image: CGImage) throws -> CGImage {
        let side = min(image.width, image.height)
        let x = max(0, (image.width - side) / 2)
        let y = max(0, (image.height - side) / 2)
        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else {
            throw BioCAPImageClassifierError.invalidImage
        }
        return cropped
    }

    private static func resize(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw BioCAPImageClassifierError.invalidImage
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else {
            throw BioCAPImageClassifierError.invalidImage
        }
        return resized
    }

    private static func dot(_ lhs: [Float], _ rhs: ArraySlice<Float>) -> Float {
        zip(lhs, rhs).reduce(Float(0)) { partial, pair in
            partial + pair.0 * pair.1
        }
    }

    private static func l2Normalized(_ values: [Float]) throws -> [Float] {
        guard values.allSatisfy(\.isFinite) else {
            throw BioCAPImageClassifierError.invalidEmbedding("BioCAP image embedding contains non-finite values.")
        }
        let norm = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 0 else {
            throw BioCAPImageClassifierError.invalidEmbedding("BioCAP image embedding has invalid norm: \(norm).")
        }
        return values.map { $0 / norm }
    }
}

private nonisolated extension MLMultiArray {
    func floatArray() throws -> [Float] {
        switch dataType {
        case .float16, .float32, .double:
            return (0..<count).map { Float(truncating: self[$0]) }
        default:
            throw BioCAPImageClassifierError.unsupportedOutput("Unsupported output data type: \(dataType)")
        }
    }
}

nonisolated enum BioCAPImageClassifierError: LocalizedError {
    case assetMismatch(String)
    case invalidEmbedding(String)
    case invalidImage
    case missingOutput(String)
    case modelContract(String)
    case unsupportedOutput(String)

    var errorDescription: String? {
        switch self {
        case .assetMismatch(let message):
            return message
        case .invalidEmbedding(let message):
            return message
        case .invalidImage:
            return "Could not preprocess photo for BioCAP."
        case .missingOutput(let name):
            return "BioCAP model did not produce the expected embedding output \(name)."
        case .modelContract(let message):
            return message
        case .unsupportedOutput(let message):
            return message
        }
    }
}
