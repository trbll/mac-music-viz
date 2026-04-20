import SwiftUI

@main
struct MusicVizApp: App {
    var body: some Scene {
        WindowGroup("MusicViz") {
            ContentView()
                .frame(minWidth: 480, minHeight: 320)
        }
        .windowResizability(.contentMinSize)
    }
}
