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
                    Label("Atlas", systemImage: "book.closed")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.xaxis")
                }
        }
    }
}
