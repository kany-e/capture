@preconcurrency import AppKit
import Foundation

struct ClipboardSnapshot: Equatable, Sendable {
    let text: String
    let sourceApplication: String?
}

enum ClipboardCaptureError: Error, LocalizedError {
    case noText
    case emptyText
    case changedDuringRead

    var errorDescription: String? {
        switch self {
        case .noText:
            return "The clipboard does not contain text."
        case .emptyText:
            return "The clipboard text is empty. Copy some text and try again."
        case .changedDuringRead:
            return "The clipboard changed while Mema was reading it. Try capturing again."
        }
    }
}

@MainActor
protocol ClipboardCaptureServing {
    func readSnapshot() throws -> ClipboardSnapshot
}

@MainActor
protocol ClipboardPasteboardReading: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    var types: [NSPasteboard.PasteboardType]? { get }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func data(forType dataType: NSPasteboard.PasteboardType) -> Data?
}

extension NSPasteboard: ClipboardPasteboardReading {}

@MainActor
final class SystemClipboardCaptureService: ClipboardCaptureServing {
    private static let maximumPasteboardItemCount = 16
    private static let maximumTypeCountPerItem = 32
    private static let maximumRepresentationCount = 32
    private static let maximumTotalRepresentationBytes = 4 * 1_024 * 1_024

    private let pasteboard: any ClipboardPasteboardReading
    private let workspace: NSWorkspace
    private let workspaceNotificationCenter: NotificationCenter
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init(
        pasteboard: any ClipboardPasteboardReading = NSPasteboard.general,
        workspace: NSWorkspace = .shared
    ) {
        self.pasteboard = pasteboard
        self.workspace = workspace
        workspaceNotificationCenter = workspace.notificationCenter
        rememberIfExternal(workspace.frontmostApplication)
        activationObserver = workspaceNotificationCenter.addObserver(
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
            workspaceNotificationCenter.removeObserver(activationObserver)
        }
    }

    func readSnapshot() throws -> ClipboardSnapshot {
        let initialChangeCount = pasteboard.changeCount
        let items = supportedTextItems()
        guard pasteboard.changeCount == initialChangeCount else {
            throw ClipboardCaptureError.changedDuringRead
        }
        guard let text = ClipboardTextResolver.resolve(items: items) else {
            throw ClipboardCaptureError.noText
        }
        guard text.nonEmptyTrimmed != nil else {
            throw ClipboardCaptureError.emptyText
        }

        let current = workspace.frontmostApplication
        rememberIfExternal(current)
        let source = externalApplicationName(current)
            ?? externalApplicationName(lastExternalApplication)
            ?? "Clipboard"

        return ClipboardSnapshot(text: text, sourceApplication: source)
    }

    private func supportedTextItems() -> [ClipboardTextItem] {
        var textItems: [ClipboardTextItem] = []
        var totalBytes = 0
        var representationCount = 0

        func appendRepresentation(
            type: NSPasteboard.PasteboardType,
            data: Data,
            to representations: inout [ClipboardTextRepresentation]
        ) {
            guard representationCount < Self.maximumRepresentationCount,
                  data.count <= ClipboardTextResolver.maximumStructuredRepresentationBytes else {
                return
            }
            let (nextTotal, overflow) = totalBytes.addingReportingOverflow(data.count)
            guard !overflow, nextTotal <= Self.maximumTotalRepresentationBytes else { return }
            totalBytes = nextTotal
            representationCount += 1
            representations.append(
                ClipboardTextRepresentation(typeRawValue: type.rawValue, data: data)
            )
        }

        if let items = pasteboard.pasteboardItems {
            guard items.count <= Self.maximumPasteboardItemCount else {
                return [ClipboardTextItem(
                    plainText: pasteboard.string(forType: .string),
                    representations: []
                )]
            }
            for item in items {
                let plainText = item.string(forType: .string)
                var representations: [ClipboardTextRepresentation] = []
                guard item.types.count <= Self.maximumTypeCountPerItem else {
                    if plainText != nil {
                        textItems.append(ClipboardTextItem(
                            plainText: plainText,
                            representations: []
                        ))
                    }
                    continue
                }
                for type in item.types {
                    guard type != .string,
                          ClipboardTextResolver.isSupportedRepresentationType(type.rawValue),
                          let data = item.data(forType: type) else {
                        continue
                    }
                    appendRepresentation(
                        type: type,
                        data: data,
                        to: &representations
                    )
                }
                let textItem = ClipboardTextItem(
                    plainText: plainText,
                    representations: representations
                )
                textItems.append(textItem)
            }
            return textItems
        }

        let plainText = pasteboard.string(forType: .string)
        var representations: [ClipboardTextRepresentation] = []
        let types = pasteboard.types ?? []
        guard types.count <= Self.maximumTypeCountPerItem else {
            return [ClipboardTextItem(plainText: plainText, representations: [])]
        }
        for type in types {
            guard type != .string,
                  ClipboardTextResolver.isSupportedRepresentationType(type.rawValue),
                  let data = pasteboard.data(forType: type) else {
                continue
            }
            appendRepresentation(type: type, data: data, to: &representations)
        }
        return [ClipboardTextItem(
            plainText: plainText,
            representations: representations
        )]
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
