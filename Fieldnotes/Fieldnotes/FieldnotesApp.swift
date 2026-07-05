import SwiftUI

@main
struct FieldnotesApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var placeNames = PlaceNameStore()

    init() {
        AlmanacFonts.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(placeNames)
                .task {
                    await model.load()
                }
        }
    }
}
