import SwiftUI

enum MemaWindowID {
    static let main = "main"
    static let quickCapture = "quick-capture"
}

@main
struct MemaApp: App {
    @StateObject private var store: MemaStore
    @StateObject private var captureCoordinator: GlobalCaptureCoordinator
    @StateObject private var shortcutCenter: GlobalShortcutCenter

    init() {
        let store = MemaStore()
        let captureCoordinator = GlobalCaptureCoordinator(store: store)
        _store = StateObject(wrappedValue: store)
        _captureCoordinator = StateObject(
            wrappedValue: captureCoordinator
        )
        _shortcutCenter = StateObject(
            wrappedValue: GlobalShortcutCenter { [weak captureCoordinator] action in
                switch action {
                case .selection:
                    captureCoordinator?.handle(.selection)
                case .clipboard:
                    captureCoordinator?.handle(.clipboard)
                case .screenshot:
                    captureCoordinator?.handle(.screenshot)
                }
            }
        )
    }

    var body: some Scene {
        Window("Mema", id: MemaWindowID.main) {
            MemaRootView()
                .environmentObject(store)
                .environmentObject(captureCoordinator)
        }
        .defaultSize(width: 1120, height: 720)

        Window("Quick Capture", id: MemaWindowID.quickCapture) {
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
                .environmentObject(store)
        }
    }
}
