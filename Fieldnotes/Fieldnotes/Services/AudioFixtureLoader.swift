import AVFoundation
import Foundation

enum AudioFixtureLoader {
    static func loadMonoFloatSamples(named name: String, extension ext: String = "wav") throws -> [Float] {
        let url = try ResourceLocator.url(named: name, extension: ext)
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioFixtureError.unsupportedFormat
        }

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount),
              let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            throw AudioFixtureError.couldNotAllocateBuffer
        }

        try file.read(into: sourceBuffer)

        if sourceFormat == targetFormat {
            guard let channel = sourceBuffer.floatChannelData?[0] else {
                throw AudioFixtureError.couldNotReadSamples
            }
            return Array(UnsafeBufferPointer(start: channel, count: Int(sourceBuffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioFixtureError.unsupportedFormat
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: targetBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let conversionError {
            throw conversionError
        }
        guard status != .error, let channel = targetBuffer.floatChannelData?[0] else {
            throw AudioFixtureError.couldNotReadSamples
        }

        return Array(UnsafeBufferPointer(start: channel, count: Int(targetBuffer.frameLength)))
    }
}

enum AudioFixtureError: LocalizedError {
    case unsupportedFormat
    case couldNotAllocateBuffer
    case couldNotReadSamples

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported audio fixture format"
        case .couldNotAllocateBuffer:
            return "Could not allocate audio fixture buffer"
        case .couldNotReadSamples:
            return "Could not read audio fixture samples"
        }
    }
}
