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

    func events() -> AsyncThrowingStream<DetectionEngineEvent, Error> {
        let audio = AudioCaptureService()
        let processingQueue = DispatchQueue(label: "fieldnotes.live-detection")
        let settings = settings
        let sampleRate = sampleRate
        let chunkSeconds = chunkSeconds
        let clipWriter = AudioClipWriter()

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
                    let chunkSampleCount = Int(Double(sampleRate) * chunkSeconds)
                    let clipSampleCount = max(
                        chunkSampleCount,
                        Int(Double(sampleRate) * settings.extractionLengthSeconds)
                    )
                    let postRollSampleCount = max(0, (clipSampleCount - chunkSampleCount) / 2)
                    let preRollSampleCount = max(0, clipSampleCount - chunkSampleCount - postRollSampleCount)
                    let rollingBuffer = RollingAudioBuffer(
                        maximumSampleCount: clipSampleCount + chunkSampleCount * 4
                    )
                    var windowsProcessed = 0
                    var pendingAcceptedDetection: PendingAcceptedDetection?
                    var pendingClipDetections: [PendingClipDetection] = []
                    var suppressNextWindowForPrivacy = false

                    func emitReadyClipDetections() {
                        guard !pendingClipDetections.isEmpty else {
                            return
                        }

                        var waitingForPostRoll: [PendingClipDetection] = []
                        for pendingClipDetection in pendingClipDetections {
                            let clipStart = pendingClipDetection.windowStartSampleIndex - Int64(preRollSampleCount)
                            guard let samples = rollingBuffer.extract(
                                startSampleIndex: clipStart,
                                sampleCount: clipSampleCount
                            ) else {
                                waitingForPostRoll.append(pendingClipDetection)
                                continue
                            }

                            var detection = pendingClipDetection.detection
                            detection.clipURL = try? clipWriter.writeClip(samples: samples, id: detection.id)
                            continuation.yield(.detection(detection))
                        }

                        pendingClipDetections = waitingForPostRoll
                    }

                    try audio.start { buffer, _ in
                        guard let samples = AudioSampleConverter.mono48kSamples(from: buffer) else {
                            return
                        }

                        processingQueue.async {
                            do {
                                rollingBuffer.append(samples)
                                emitReadyClipDetections()

                                let windows = windowBuffer.append(samples)
                                for window in windows {
                                    windowsProcessed += 1
                                    let audioLevel = AudioLevelMeter.rmsLevel(from: window.samples)
                                    let start = Date()
                                    let scores = try classifier.classify(window.samples)
                                    let latency = Date().timeIntervalSince(start)
                                    let isHumanWindow = settings.privacyFilterEnabled && HumanPrivacyFilter.isHumanWindow(
                                        scores,
                                        privacyThresholdPercent: settings.privacyThresholdPercent
                                    )
                                    let suppressCurrentForPrivacy = suppressNextWindowForPrivacy || isHumanWindow
                                    suppressNextWindowForPrivacy = isHumanWindow
                                    let acceptableScores = classifier.acceptableScores(from: scores)
                                    let acceptedScore = acceptableScores.first

                                    continuation.yield(.diagnostics(DetectionDiagnostics(
                                        windowsProcessed: windowsProcessed,
                                        topCandidateName: scores.first.map {
                                            classifier.commonNames[$0.scientificName] ?? $0.scientificName
                                        },
                                        topCandidateConfidence: scores.first?.confidence,
                                        acceptedCandidateName: acceptedScore.map {
                                            classifier.commonNames[$0.scientificName] ?? $0.scientificName
                                        },
                                        acceptedCandidateConfidence: acceptedScore?.confidence,
                                        audioLevel: audioLevel,
                                        inferenceLatency: latency,
                                        privacySuppressed: suppressCurrentForPrivacy,
                                        rangeFilterActive: classifier.rangeFilterActive,
                                        rangeSpeciesCount: classifier.rangeSpeciesCount,
                                        audioInputName: AudioCaptureService.currentInputName()
                                    )))

                                    guard settings.privacyFilterEnabled else {
                                        if let score = acceptedScore {
                                            pendingClipDetections.append(PendingClipDetection(
                                                detection: classifier.fieldDetection(from: score),
                                                windowStartSampleIndex: window.startSampleIndex
                                            ))
                                            emitReadyClipDetections()
                                        }
                                        continue
                                    }

                                    if isHumanWindow {
                                        pendingAcceptedDetection = nil
                                    }

                                    if suppressCurrentForPrivacy {
                                        continue
                                    }

                                    if let accepted = pendingAcceptedDetection {
                                        pendingClipDetections.append(PendingClipDetection(
                                            detection: accepted.detection,
                                            windowStartSampleIndex: accepted.windowStartSampleIndex
                                        ))
                                        emitReadyClipDetections()
                                        pendingAcceptedDetection = nil
                                    }

                                    if let score = acceptableScores.first {
                                        pendingAcceptedDetection = PendingAcceptedDetection(
                                            detection: classifier.fieldDetection(from: score),
                                            windowStartSampleIndex: window.startSampleIndex
                                        )
                                    }
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

nonisolated private struct PendingAcceptedDetection {
    var detection: FieldDetection
    var windowStartSampleIndex: Int64
}

nonisolated private struct PendingClipDetection {
    var detection: FieldDetection
    var windowStartSampleIndex: Int64
}

nonisolated private struct AudioWindow {
    var startSampleIndex: Int64
    var samples: [Float]
}

nonisolated private final class AudioWindowBuffer: @unchecked Sendable {
    private let chunkSampleCount: Int
    private let strideSampleCount: Int
    private var samples: [Float] = []
    private var nextWindowStartSampleIndex: Int64 = 0

    init(sampleRate: Int, chunkSeconds: Double, overlapSeconds: Double) {
        chunkSampleCount = Int(Double(sampleRate) * chunkSeconds)
        strideSampleCount = max(1, Int(Double(sampleRate) * (chunkSeconds - overlapSeconds)))
        samples.reserveCapacity(chunkSampleCount * 2)
    }

    func append(_ newSamples: [Float]) -> [AudioWindow] {
        samples.append(contentsOf: newSamples)

        var windows: [AudioWindow] = []
        while samples.count >= chunkSampleCount {
            windows.append(AudioWindow(
                startSampleIndex: nextWindowStartSampleIndex,
                samples: Array(samples.prefix(chunkSampleCount))
            ))
            samples.removeFirst(strideSampleCount)
            nextWindowStartSampleIndex += Int64(strideSampleCount)
        }

        let maximumBufferedSamples = chunkSampleCount * 4
        if samples.count > maximumBufferedSamples {
            samples.removeFirst(samples.count - maximumBufferedSamples)
        }

        return windows
    }
}

nonisolated private final class RollingAudioBuffer: @unchecked Sendable {
    private let maximumSampleCount: Int
    private var samples: [Float] = []
    private var startSampleIndex: Int64 = 0

    init(maximumSampleCount: Int) {
        self.maximumSampleCount = maximumSampleCount
        samples.reserveCapacity(maximumSampleCount)
    }

    func append(_ newSamples: [Float]) {
        samples.append(contentsOf: newSamples)

        if samples.count > maximumSampleCount {
            let overflowCount = samples.count - maximumSampleCount
            samples.removeFirst(overflowCount)
            startSampleIndex += Int64(overflowCount)
        }
    }

    func extract(startSampleIndex requestedStart: Int64, sampleCount: Int) -> [Float]? {
        let requestedEnd = requestedStart + Int64(sampleCount)
        let availableEnd = startSampleIndex + Int64(samples.count)

        guard requestedEnd <= availableEnd else {
            return nil
        }

        let clampedStart = max(requestedStart, startSampleIndex)
        let clampedEnd = min(requestedEnd, availableEnd)
        guard clampedStart <= clampedEnd else {
            return nil
        }

        var extracted: [Float] = []
        extracted.reserveCapacity(sampleCount)

        if requestedStart < clampedStart {
            extracted.append(contentsOf: repeatElement(0, count: Int(clampedStart - requestedStart)))
        }

        let sourceStart = Int(clampedStart - startSampleIndex)
        let sourceCount = Int(clampedEnd - clampedStart)
        if sourceCount > 0 {
            extracted.append(contentsOf: samples[sourceStart..<(sourceStart + sourceCount)])
        }

        if extracted.count < sampleCount {
            extracted.append(contentsOf: repeatElement(0, count: sampleCount - extracted.count))
        }

        return extracted
    }
}

private enum AudioLevelMeter {
    static func rmsLevel(from samples: [Float]) -> Float {
        guard !samples.isEmpty else {
            return 0
        }

        let sum = samples.reduce(Float(0)) { partial, sample in
            partial + sample * sample
        }
        return min(1, sqrt(sum / Float(samples.count)))
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
