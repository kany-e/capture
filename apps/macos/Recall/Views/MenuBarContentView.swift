import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var store: RecallStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Recall", systemImage: "rectangle.stack") {
            openMainWindow()
        }
        .keyboardShortcut("o")

        Button("Capture Clipboard", systemImage: "doc.on.clipboard") {
            _ = store.prepareClipboardCapture()
            openWindow(id: RecallWindowID.quickCapture)
            activateApplication()
        }
        .keyboardShortcut("n")

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

        Divider()

        Button("Quit Recall", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var connectionLabel: String {
        switch store.connectionState {
        case .checking: "Checking local service…"
        case let .connected(openAIConfigured):
            openAIConfigured ? "Connected · AI ready" : "Connected · AI not configured"
        case .disconnected: "Local service offline"
        }
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .checking: .orange
        case .connected: .green
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
}
