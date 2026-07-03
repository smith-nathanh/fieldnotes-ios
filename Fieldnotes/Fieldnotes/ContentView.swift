import SwiftUI

struct ContentView: View {
    @State private var selection: AlmanacTab = .listen

    init() {
        // Hide the native tab bar entirely — we draw our own Almanac bar.
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selection) {
            ListenView()
                .tag(AlmanacTab.listen)
                .toolbar(.hidden, for: .tabBar)

            PhotoClassifierView()
                .tag(AlmanacTab.photo)
                .toolbar(.hidden, for: .tabBar)

            DetectionsView()
                .tag(AlmanacTab.log)
                .toolbar(.hidden, for: .tabBar)

            StatsView()
                .tag(AlmanacTab.stats)
                .toolbar(.hidden, for: .tabBar)
        }
        .overlay(alignment: .bottom) {
            AlmanacTabBar(selection: $selection)
        }
    }
}
