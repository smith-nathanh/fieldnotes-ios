import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ListenView()
                .tabItem {
                    Label("Listen", systemImage: "waveform")
                }

            PhotoClassifierView()
                .tabItem {
                    Label("Photo", systemImage: "camera.viewfinder")
                }

            DetectionsView()
                .tabItem {
                    Label("Log", systemImage: "list.bullet.rectangle")
                }

            StatsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.xaxis")
                }
        }
        .tint(FieldStyle.moss)
    }
}
