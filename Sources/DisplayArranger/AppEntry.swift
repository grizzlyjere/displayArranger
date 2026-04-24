import SwiftUI

@main
struct DisplayArrangerApp: App {
    init() {
        DisplayArrangerShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
