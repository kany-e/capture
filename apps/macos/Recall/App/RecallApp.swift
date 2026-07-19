import SwiftUI

enum RecallWindowID {
    static let main = "main"
    static let quickCapture = "quick-capture"
}

@main
struct RecallApp: App {
    @StateObject private var store = RecallStore()

    var body: some Scene {
        Window("Recall", id: RecallWindowID.main) {
            RecallRootView()
                .environmentObject(store)
        }
        .defaultSize(width: 1120, height: 720)

        Window("Quick Capture", id: RecallWindowID.quickCapture) {
            QuickCaptureView()
                .environmentObject(store)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        MenuBarExtra("Recall", systemImage: "sparkles.rectangle.stack") {
            MenuBarContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.menu)
    }
}
