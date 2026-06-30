import CoreGraphics
import CoreML
import Foundation
import UIKit

struct BioCAPPhotoPrediction: Equatable, Sendable {
    var scientificName: String
    var commonName: String
    var taxon: String
    var score: Float
}

struct BioCAPSpeciesMetadata: Decodable, Equatable {
    var index: Int
    var scientificName: String
    var commonName: String
    var taxon: String
}

struct BioCAPConfig: Decodable, Equatable {
    var embeddingDim: Int
    var speciesCount: Int
    var embeddingDtype: String
    var modelName: String
    var promptPreset: String
    var labelTextType: String
    var promptTemplateCount: Int
}

final class BioCAPImageClassifier {
    private let model: MLModel
    private let species: [BioCAPSpeciesMetadata]
    private let config: BioCAPConfig
    private let textEmbeddings: [Float]

    init(bundle: Bundle = .main) throws {
        self.model = try Self.loadModel(bundle: bundle)
        self.species = try Self.loadSpecies(bundle: bundle)
        self.config = try Self.loadConfig(bundle: bundle)
        self.textEmbeddings = try Self.loadEmbeddings(bundle: bundle)

        guard species.count == config.speciesCount else {
            throw BioCAPImageClassifierError.assetMismatch("Species count does not match config.")
        }
        guard textEmbeddings.count == config.speciesCount * config.embeddingDim else {
            throw BioCAPImageClassifierError.assetMismatch("Embedding matrix shape does not match config.")
        }
    }

    func classify(_ image: UIImage, limit: Int = 5) throws -> [BioCAPPhotoPrediction] {
        let input = try Self.preprocess(image)
        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: input)])
        let output = try model.prediction(from: provider)
        let imageEmbedding = try Self.firstMultiArray(in: output).floatArray()
        let normalizedImageEmbedding = try Self.l2Normalized(imageEmbedding)

        let scores = species.indices.map { index -> BioCAPPhotoPrediction in
            let rowStart = index * config.embeddingDim
            let score = Self.dot(
                normalizedImageEmbedding,
                textEmbeddings[rowStart..<(rowStart + config.embeddingDim)]
            )
            let item = species[index]
            return BioCAPPhotoPrediction(
                scientificName: item.scientificName,
                commonName: item.commonName,
                taxon: item.taxon,
                score: score
            )
        }

        return Array(scores.sorted { $0.score > $1.score }.prefix(limit))
    }

    private static func loadModel(bundle: Bundle) throws -> MLModel {
        let url: URL
        if let compiledURL = try? ResourceLocator.url(named: "BioCAPVisionEncoder", extension: "mlmodelc") {
            url = compiledURL
        } else {
            url = try ResourceLocator.url(named: "BioCAPVisionEncoder", extension: "mlpackage")
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    private static func loadSpecies(bundle: Bundle) throws -> [BioCAPSpeciesMetadata] {
        let url = try ResourceLocator.url(named: "BioCAPSpecies", extension: "json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([BioCAPSpeciesMetadata].self, from: data)
    }

    private static func loadConfig(bundle: Bundle) throws -> BioCAPConfig {
        let url = try ResourceLocator.url(named: "BioCAPConfig", extension: "json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BioCAPConfig.self, from: data)
    }

    private static func loadEmbeddings(bundle: Bundle) throws -> [Float] {
        let url = try ResourceLocator.url(named: "BioCAPTextEmbeddings", extension: "f32")
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }

    private static func firstMultiArray(in output: MLFeatureProvider) throws -> MLMultiArray {
        for featureName in output.featureNames {
            if let multiArray = output.featureValue(for: featureName)?.multiArrayValue {
                return multiArray
            }
        }
        throw BioCAPImageClassifierError.missingOutput
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

private extension MLMultiArray {
    func floatArray() throws -> [Float] {
        switch dataType {
        case .float16, .float32, .double:
            return (0..<count).map { Float(truncating: self[$0]) }
        default:
            throw BioCAPImageClassifierError.unsupportedOutput("Unsupported output data type: \(dataType)")
        }
    }
}

enum BioCAPImageClassifierError: LocalizedError {
    case assetMismatch(String)
    case invalidEmbedding(String)
    case invalidImage
    case missingOutput
    case unsupportedOutput(String)

    var errorDescription: String? {
        switch self {
        case .assetMismatch(let message):
            return message
        case .invalidEmbedding(let message):
            return message
        case .invalidImage:
            return "Could not preprocess photo for BioCAP."
        case .missingOutput:
            return "BioCAP model did not produce an embedding output."
        case .unsupportedOutput(let message):
            return message
        }
    }
}
