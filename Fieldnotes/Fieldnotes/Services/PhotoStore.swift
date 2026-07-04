import Foundation
import UIKit

/// Persists capture images for photo detections, mirroring `AudioClipWriter`.
nonisolated struct PhotoStore: Sendable {
    func writePhoto(_ image: UIImage, id: UUID) throws -> URL {
        let directory = try Self.photosDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw PhotoStoreError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    func deletePhoto(at url: URL?) {
        guard let url else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    static func photosDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documents.appendingPathComponent("Photos", isDirectory: true)
    }
}

private enum PhotoStoreError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode capture image"
        }
    }
}
