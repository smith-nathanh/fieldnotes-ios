import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ListenView()
                .tabItem {
                    Label("Listen", systemImage: "waveform")
                }

            DetectionsView()
                .tabItem {
                    Label("Detections", systemImage: "list.bullet.rectangle")
                }
        }
    }
}
