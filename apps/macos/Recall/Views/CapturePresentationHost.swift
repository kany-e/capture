import AppKit
import SwiftUI

struct CapturePresentationHost: View {
    @EnvironmentObject private var coordinator: GlobalCaptureCoordinator
    @EnvironmentObject private var shortcutCenter: GlobalShortcutCenter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(
            "Recall",
            systemImage: shortcutCenter.registrationErrorMessage == nil
                ? "sparkles.rectangle.stack"
                : "exclamationmark.triangle"
        )
            .onChange(of: coordinator.quickCapturePresentationRequest) {
                openWindow(id: RecallWindowID.quickCapture)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification
                )
            ) { _ in
                coordinator.cancelPendingCapture()
                shortcutCenter.deactivate()
            }
    }
}
