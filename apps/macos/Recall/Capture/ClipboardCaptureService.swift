@preconcurrency import AppKit
import Foundation

struct ClipboardSnapshot: Equatable, Sendable {
    let text: String
    let sourceApplication: String?
}

enum ClipboardCaptureError: Error, LocalizedError {
    case noText
    case emptyText

    var errorDescription: String? {
        switch self {
        case .noText:
            return "The clipboard does not contain text."
        case .emptyText:
            return "The clipboard text is empty. Copy some text and try again."
        }
    }
}

@MainActor
protocol ClipboardCaptureServing {
    func readSnapshot() throws -> ClipboardSnapshot
}

@MainActor
final class SystemClipboardCaptureService: ClipboardCaptureServing {
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init(workspace: NSWorkspace = .shared) {
        rememberIfExternal(workspace.frontmostApplication)
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.rememberIfExternal(application)
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func readSnapshot() throws -> ClipboardSnapshot {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            throw ClipboardCaptureError.noText
        }
        guard text.nonEmptyTrimmed != nil else {
            throw ClipboardCaptureError.emptyText
        }

        let current = NSWorkspace.shared.frontmostApplication
        rememberIfExternal(current)
        let source = externalApplicationName(current)
            ?? externalApplicationName(lastExternalApplication)
            ?? "Clipboard"

        return ClipboardSnapshot(text: text, sourceApplication: source)
    }

    private func rememberIfExternal(_ application: NSRunningApplication?) {
        guard externalApplicationName(application) != nil else { return }
        lastExternalApplication = application
    }

    private func externalApplicationName(_ application: NSRunningApplication?) -> String? {
        guard let application else { return nil }
        if application.bundleIdentifier == Bundle.main.bundleIdentifier
            || application.localizedName == Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return nil
        }
        return application.localizedName?.nonEmptyTrimmed
    }
}
