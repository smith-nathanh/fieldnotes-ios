import Foundation
import FieldnotesCore

struct DetectionRepository: Sendable {
    private let fileName = "detections.json"

    func load() async throws -> [FieldDetection] {
        let fileURL = try storageURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.fieldnotes.decode([FieldDetection].self, from: data)
    }

    func save(_ detections: [FieldDetection]) async throws {
        let fileURL = try storageURL()
        let data = try JSONEncoder.fieldnotes.encode(detections)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func storageURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appendingPathComponent(fileName)
    }
}

private extension JSONEncoder {
    static var fieldnotes: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var fieldnotes: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
