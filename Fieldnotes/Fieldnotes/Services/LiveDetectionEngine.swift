import AVFoundation
import Foundation
import FieldnotesCore

final class LiveDetectionEngine: DetectionEngine, @unchecked Sendable {
    private let settings: DetectionSettings
    private let sampleRate = 48_000
    private let chunkSeconds = 3.0

    init(settings: DetectionSettings = DetectionSettings()) {
        self.settings = settings
    }

    func detections() -> AsyncThrowingStream<FieldDetection, Error> {
        let audio = AudioCaptureService()
        let processingQueue = DispatchQueue(label: "fieldnotes.live-detection")
        let settings = settings
        let sampleRate = sampleRate
        let chunkSeconds = chunkSeconds

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard await audio.requestPermission() else {
                        throw LiveDetectionError.microphonePermissionDenied
                    }

                    let classifier = try BirdNETWindowClassifier(
                        settings: settings,
                        sampleCount: Int(Double(sampleRate) * chunkSeconds)
                    )
                    let windowBuffer = AudioWindowBuffer(
                        sampleRate: sampleRate,
                        chunkSeconds: chunkSeconds,
                        overlapSeconds: settings.overlapSeconds
                    )

                    try audio.start { buffer, _ in
                        guard let samples = AudioSampleConverter.mono48kSamples(from: buffer) else {
                            return
                        }

                        processingQueue.async {
                            do {
                                let windows = windowBuffer.append(samples)
                                for window in windows {
                                    guard let score = try classifier.classify(window).first(where: {
                                        $0.confidence >= settings.confidenceThreshold
                                    }) else {
                                        continue
                                    }
                                    continuation.yield(classifier.fieldDetection(from: score))
                                }
                            } catch {
                                audio.stop()
                                continuation.finish(throwing: error)
                            }
                        }
                    }

                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(1))
                    }
                    audio.stop()
                    continuation.finish()
                } catch is CancellationError {
                    audio.stop()
                    continuation.finish()
                } catch {
                    audio.stop()
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                processingQueue.async {
                    audio.stop()
                }
            }
        }
    }
}

private final class AudioWindowBuffer {
    private let chunkSampleCount: Int
    private let strideSampleCount: Int
    private var samples: [Float] = []

    init(sampleRate: Int, chunkSeconds: Double, overlapSeconds: Double) {
        chunkSampleCount = Int(Double(sampleRate) * chunkSeconds)
        strideSampleCount = max(1, Int(Double(sampleRate) * (chunkSeconds - overlapSeconds)))
        samples.reserveCapacity(chunkSampleCount * 2)
    }

    func append(_ newSamples: [Float]) -> [[Float]] {
        samples.append(contentsOf: newSamples)

        var windows: [[Float]] = []
        while samples.count >= chunkSampleCount {
            windows.append(Array(samples.prefix(chunkSampleCount)))
            samples.removeFirst(strideSampleCount)
        }

        let maximumBufferedSamples = chunkSampleCount * 4
        if samples.count > maximumBufferedSamples {
            samples.removeFirst(samples.count - maximumBufferedSamples)
        }

        return windows
    }
}

private enum AudioSampleConverter {
    static func mono48kSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        if buffer.format.commonFormat == .pcmFormatFloat32,
           buffer.format.sampleRate == targetFormat.sampleRate,
           buffer.format.channelCount == 1,
           let channel = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }

        let frameRatio = targetFormat.sampleRate / buffer.format.sampleRate
        let targetCapacity = AVAudioFrameCount(Double(buffer.frameLength) * frameRatio) + 1
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity),
              let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            return nil
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
            return buffer
        }

        guard conversionError == nil, status != .error, let channel = targetBuffer.floatChannelData?[0] else {
            return nil
        }

        return Array(UnsafeBufferPointer(start: channel, count: Int(targetBuffer.frameLength)))
    }
}

enum LiveDetectionError: LocalizedError {
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        }
    }
}
