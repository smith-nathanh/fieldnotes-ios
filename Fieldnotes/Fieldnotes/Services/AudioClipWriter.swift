import AVFoundation
import Foundation

nonisolated struct AudioClipWriter: Sendable {
    private let sampleRate: Double = 48_000

    func writeClip(samples: [Float], id: UUID) throws -> URL {
        let directory = try Self.clipsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("caf")
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
        let channel = buffer.floatChannelData?[0] else {
            throw AudioClipWriterError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let baseAddress = source.baseAddress {
                channel.update(from: baseAddress, count: samples.count)
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func deleteClip(at url: URL?) {
        guard let url else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    static func clipsDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documents.appendingPathComponent("Clips", isDirectory: true)
    }
}

private enum AudioClipWriterError: LocalizedError {
    case bufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Could not create audio clip buffer"
        }
    }
}
