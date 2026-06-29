import AVFoundation
import SwiftUI

struct ClipPlaybackButton: View {
    var url: URL?

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        Button {
            togglePlayback()
        } label: {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isPlaying ? "Stop clip" : "Play clip")
        .disabled(url == nil)
        .opacity(url == nil ? 0.28 : 1)
        .onDisappear {
            stopPlayback(deactivateSession: false)
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback(deactivateSession: true)
        } else {
            play()
        }
    }

    private func play() {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            isPlaying = true

            let nanoseconds = UInt64(max(0.1, newPlayer.duration) * 1_000_000_000)
            Task {
                try? await Task.sleep(nanoseconds: nanoseconds)
                await MainActor.run {
                    if player === newPlayer {
                        player = nil
                        isPlaying = false
                    }
                }
            }
        } catch {
            player = nil
            isPlaying = false
        }
    }

    private func stopPlayback(deactivateSession: Bool) {
        player?.stop()
        player = nil
        isPlaying = false
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
