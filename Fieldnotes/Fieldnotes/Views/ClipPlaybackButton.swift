import AVFoundation
import SwiftUI

struct ClipPlaybackButton: View {
    enum Style {
        /// Small bordered circle for inline list rows.
        case compact
        /// Large filled rust circle for the signature-call module.
        case hero
    }

    var url: URL?
    var isBlocked = false
    var style: Style = .compact

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var delegate: ClipPlaybackDelegate?
    @State private var showsListeningAlert = false

    var body: some View {
        Button {
            togglePlayback()
        } label: {
            label
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .disabled(url == nil)
        .opacity(url == nil ? 0.28 : 1)
        .alert("Stop listening to play clips", isPresented: $showsListeningAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Clip playback uses the speaker audio session. Stop the current listening session, then tap play again.")
        }
        .onDisappear {
            stopPlayback(deactivateSession: false)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .compact:
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(url == nil ? Color.inkFaint : Color.rust)
                .frame(width: 32, height: 32)
                .background(Color.paperCard, in: Circle())
                .overlay { Circle().stroke(Color.ink, lineWidth: 1) }
                .contentShape(Circle())
        case .hero:
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.paper)
                .frame(width: 52, height: 52)
                .background(Circle().fill(url == nil ? Color.tan : Color.rust))
                .contentShape(Circle())
        }
    }

    private func togglePlayback() {
        if isBlocked {
            showsListeningAlert = true
            return
        }

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
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            let newDelegate = ClipPlaybackDelegate {
                player = nil
                delegate = nil
                isPlaying = false
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            newPlayer.delegate = newDelegate
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            delegate = newDelegate
            isPlaying = true
        } catch {
            player = nil
            delegate = nil
            isPlaying = false
        }
    }

    private func stopPlayback(deactivateSession: Bool) {
        player?.stop()
        player = nil
        delegate = nil
        isPlaying = false
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private var accessibilityLabel: String {
        if isBlocked {
            return "Stop listening to play clip"
        }
        return isPlaying ? "Stop clip" : "Play clip"
    }
}

private final class ClipPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: @MainActor () -> Void

    init(onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            onFinish()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            onFinish()
        }
    }
}
