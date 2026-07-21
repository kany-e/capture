import AppKit
import SwiftUI

struct CapturePresentationHost: View {
    @EnvironmentObject private var coordinator: GlobalCaptureCoordinator
    @EnvironmentObject private var shortcutCenter: GlobalShortcutCenter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label {
            Text(
                shortcutCenter.registrationErrorMessage == nil
                    ? "Recall"
                    : "Recall — shortcut setup requires attention"
            )
        } icon: {
            Image("RecallMarkTemplate")
                .renderingMode(.template)
        }
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
