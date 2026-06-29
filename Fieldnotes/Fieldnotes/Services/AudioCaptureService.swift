import AVFoundation
import Foundation

final class AudioCaptureService {
    private let engine = AVAudioEngine()

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4_096, format: format, block: onBuffer)
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    static func currentInputName() -> String? {
        let route = AVAudioSession.sharedInstance().currentRoute
        guard let input = route.inputs.first else {
            return nil
        }

        if input.portType == .bluetoothHFP {
            return "\(input.portName) HFP"
        }
        return input.portName
    }
}
