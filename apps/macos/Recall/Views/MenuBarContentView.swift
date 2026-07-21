import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var store: RecallStore
    @EnvironmentObject private var captureCoordinator: GlobalCaptureCoordinator
    @EnvironmentObject private var shortcutCenter: GlobalShortcutCenter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Recall", systemImage: "rectangle.stack") {
            openMainWindow()
        }
        .keyboardShortcut("o")

        Button(
            "Capture Selection (\(shortcutLabel(for: .selection)))",
            systemImage: "text.cursor"
        ) {
            captureCoordinator.prepareAccessibilitySelectionCapture()
        }

        Button(
            "Capture Clipboard (\(shortcutLabel(for: .clipboard)))",
            systemImage: "doc.on.clipboard"
        ) {
            captureCoordinator.prepareClipboardCapture()
        }

        Button(
            "Capture Screenshot Note (\(shortcutLabel(for: .screenshot)))",
            systemImage: "viewfinder"
        ) {
            captureCoordinator.prepareScreenshotCapture()
        }

        Button("Search", systemImage: "magnifyingglass") {
            openMainWindow()
            DispatchQueue.main.async {
                store.requestSearchFocus()
            }
        }
        .keyboardShortcut("f")

        Divider()

        HStack {
            Text(connectionLabel)
            Spacer()
            Circle()
                .fill(connectionColor)
                .frame(width: 7, height: 7)
        }

        Button("Check Connection", systemImage: "arrow.clockwise") {
            Task {
                await store.checkHealth()
                await store.loadLibrary(initial: false)
            }
        }

        if let shortcutError = shortcutCenter.registrationErrorMessage {
            Divider()
            Text(shortcutError)
            Button("Retry Global Shortcuts", systemImage: "arrow.clockwise") {
                shortcutCenter.retryRegistration()
            }
        }

        SettingsLink {
            Label("Shortcut Settings…", systemImage: "keyboard")
        }

        Divider()

        Button("Quit Recall", systemImage: "power") {
            Task { @MainActor in
                await captureCoordinator.cancelPendingCaptureAndWait()
                shortcutCenter.deactivate()
                NSApplication.shared.terminate(nil)
            }
        }
        .keyboardShortcut("q")
    }

    private var connectionLabel: String {
        switch store.connectionState {
        case .checking: "Checking local service…"
        case let .connected(openAIConfigured):
            openAIConfigured ? "Connected · AI ready" : "Connected · AI not configured"
        case .degraded: "Local storage unavailable"
        case .disconnected: "Local service offline"
        }
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .checking: .orange
        case .connected: .green
        case .degraded: .red
        case .disconnected: .red
        }
    }

    private func openMainWindow() {
        openWindow(id: RecallWindowID.main)
        activateApplication()
    }

    private func activateApplication() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func shortcutLabel(for action: GlobalShortcutAction) -> String {
        let shortcut = shortcutCenter.configuration[action]
        return shortcut.isEnabled ? shortcut.displayName : "Off"
    }
}
