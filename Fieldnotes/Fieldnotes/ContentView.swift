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
                    Label("Atlas", systemImage: "book.closed")
                }

            StatsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.xaxis")
                }
        }
        .tint(FieldStyle.moss)
    }
}
