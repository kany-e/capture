import SwiftUI

enum RecallWindowID {
    static let main = "main"
    static let quickCapture = "quick-capture"
}

@main
struct RecallApp: App {
    @StateObject private var store: RecallStore
    @StateObject private var captureCoordinator: GlobalCaptureCoordinator
    @StateObject private var shortcutCenter: GlobalShortcutCenter

    init() {
        let store = RecallStore()
        let captureCoordinator = GlobalCaptureCoordinator(store: store)
        _store = StateObject(wrappedValue: store)
        _captureCoordinator = StateObject(
            wrappedValue: captureCoordinator
        )
        _shortcutCenter = StateObject(
            wrappedValue: GlobalShortcutCenter { [weak captureCoordinator] action in
                switch action {
                case .clipboard:
                    captureCoordinator?.handle(.clipboard)
                case .screenshot:
                    captureCoordinator?.handle(.screenshot)
                }
            }
        )
    }

    var body: some Scene {
        Window("Recall", id: RecallWindowID.main) {
            RecallRootView()
                .environmentObject(store)
                .environmentObject(captureCoordinator)
        }
        .defaultSize(width: 1120, height: 720)

        Window("Quick Capture", id: RecallWindowID.quickCapture) {
            QuickCaptureView()
                .environmentObject(store)
                .environmentObject(captureCoordinator)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(captureCoordinator)
                .environmentObject(shortcutCenter)
        } label: {
            CapturePresentationHost()
                .environmentObject(captureCoordinator)
                .environmentObject(shortcutCenter)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            ShortcutSettingsView()
                .environmentObject(shortcutCenter)
        }
    }
}
