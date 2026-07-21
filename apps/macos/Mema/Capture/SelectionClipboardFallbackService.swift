@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Carbon
import CoreGraphics
import Foundation

enum SelectionClipboardFallbackError: Error, Equatable, Sendable {
    case noExternalApplication
    case eventPostingNotAuthorized
    case secureEventInput
    case sourceApplicationChanged
    case shortcutModifiersStillPressed
    case pasteboardSnapshotUnavailable
    case pasteboardSnapshotTooLarge
    case eventCreationFailed
    case copyTimedOut
    case copiedContentHasNoText
    case copiedContentIsEmpty
    case clipboardChangedConcurrently
    case restoreFailed

    var accessibilityError: AccessibilitySelectionError {
        switch self {
        case .secureEventInput:
            return .secureTextInput
        case .clipboardChangedConcurrently:
            return .clipboardChangedDuringFallback
        case .restoreFailed:
            return .clipboardRestoreFailed
        default:
            return .clipboardFallbackUnavailable
        }
    }
}

/// A detached, byte-for-byte copy of pasteboard contents. NSPasteboardItem
/// instances themselves become stale when ownership changes, so neither the
/// original clipboard nor a Copy candidate is retained as AppKit objects.
struct SelectionPasteboardArchive: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        struct Representation: Equatable, Sendable {
            let typeRawValue: String
            let data: Data
        }

        let representations: [Representation]
    }

    let originalChangeCount: Int
    let items: [Item]
}

protocol SelectionClipboardFallbackServing: Sendable {
    func captureSelection(
        using ticket: AccessibilitySelectionFallbackTicket
    ) async throws -> AccessibilitySelectionSnapshot
}

protocol SelectionClipboardFallbackBackend: AnyObject, Sendable {
    func shortcutModifiersArePressed() -> Bool
    func snapshotPasteboard() throws -> SelectionPasteboardArchive
    var pasteboardChangeCount: Int { get }

    /// Revalidates the ticket's frontmost PID, exact AX focused element when
    /// available, exposed safety evidence, Secure Event Input, and event-posting
    /// permission as one operation immediately adjacent to posting Command-C.
    func postCopyIfTargetStillSafe(
        _ ticket: AccessibilitySelectionFallbackTicket
    ) throws

    /// Rechecks the application/control ticket and its available safety evidence
    /// after each asynchronous pasteboard observation.
    func targetStillMatches(_ ticket: AccessibilitySelectionFallbackTicket) -> Bool
    func copiedText() -> String?
    func restorePasteboard(
        _ archive: SelectionPasteboardArchive,
        expectedChangeCount: Int
    ) throws
}

struct SelectionClipboardFallbackTiming: Equatable, Sendable {
    let modifierPollNanoseconds: UInt64
    let modifierPollAttempts: Int
    let copyPollNanoseconds: UInt64
    let copyPollAttempts: Int
    let stableCopyPollsRequired: Int

    static let production = SelectionClipboardFallbackTiming(
        modifierPollNanoseconds: 20_000_000,
        modifierPollAttempts: 25,
        copyPollNanoseconds: 20_000_000,
        copyPollAttempts: 100,
        stableCopyPollsRequired: 2
    )
}

actor SelectionClipboardFallbackService<Backend: SelectionClipboardFallbackBackend>:
    SelectionClipboardFallbackServing
{
    private struct CopyCandidate {
        let archive: SelectionPasteboardArchive
        let text: String?
    }

    private let backend: Backend
    private let timing: SelectionClipboardFallbackTiming

    init(
        backend: Backend,
        timing: SelectionClipboardFallbackTiming = .production
    ) {
        self.backend = backend
        self.timing = timing
    }

    func captureSelection(
        using ticket: AccessibilitySelectionFallbackTicket
    ) async throws -> AccessibilitySelectionSnapshot {
        try Task.checkCancellation()
        try await waitForShortcutModifiersToBeReleased()
        try Task.checkCancellation()

        let originalArchive = try backend.snapshotPasteboard()
        guard backend.pasteboardChangeCount == originalArchive.originalChangeCount else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }
        try Task.checkCancellation()

        // A single observed change can belong to a clipboard manager or another
        // application. Never call it ours. We only restore after two consecutive
        // copies to the same AX control produce byte-identical archives and text
        // at the exact next two change counts.
        try backend.postCopyIfTargetStillSafe(ticket)

        let firstChangeCount = try await observeExactNextStableChange(
            after: originalArchive.originalChangeCount
        )
        guard backend.targetStillMatches(ticket) else {
            throw SelectionClipboardFallbackError.sourceApplicationChanged
        }
        let firstCandidate = try captureCandidate(
            expectedChangeCount: firstChangeCount
        )
        guard backend.targetStillMatches(ticket) else {
            throw SelectionClipboardFallbackError.sourceApplicationChanged
        }
        guard backend.pasteboardChangeCount == firstChangeCount else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }

        // Cancellation after the first event deliberately does not stop this
        // confirmation attempt. If the second result is causal and identical we
        // can safely restore, then surface CancellationError below. If it cannot
        // be confirmed, every failure path leaves the current clipboard alone.
        try backend.postCopyIfTargetStillSafe(ticket)

        let secondChangeCount = try await observeExactNextStableChange(
            after: firstChangeCount
        )
        guard backend.targetStillMatches(ticket) else {
            throw SelectionClipboardFallbackError.sourceApplicationChanged
        }
        let secondCandidate = try captureCandidate(
            expectedChangeCount: secondChangeCount
        )
        guard firstCandidate.archive.items == secondCandidate.archive.items,
              firstCandidate.text == secondCandidate.text else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }
        guard backend.targetStillMatches(ticket) else {
            throw SelectionClipboardFallbackError.sourceApplicationChanged
        }
        guard backend.pasteboardChangeCount == secondChangeCount else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }

        try backend.restorePasteboard(
            originalArchive,
            expectedChangeCount: secondChangeCount
        )

        try Task.checkCancellation()
        guard let text = secondCandidate.text else {
            throw SelectionClipboardFallbackError.copiedContentHasNoText
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SelectionClipboardFallbackError.copiedContentIsEmpty
        }

        return AccessibilitySelectionSnapshot(
            text: text,
            sourceApplication: ticket.sourceApplication,
            selectionBoundsInAXScreenCoordinates: nil,
            captureMethod: .clipboardFallback
        )
    }

    private func captureCandidate(
        expectedChangeCount: Int
    ) throws -> CopyCandidate {
        guard backend.pasteboardChangeCount == expectedChangeCount else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }
        let archive = try backend.snapshotPasteboard()
        guard archive.originalChangeCount == expectedChangeCount,
              backend.pasteboardChangeCount == expectedChangeCount else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }
        let text = backend.copiedText()
        guard backend.pasteboardChangeCount == expectedChangeCount else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }
        return CopyCandidate(archive: archive, text: text)
    }

    private func waitForShortcutModifiersToBeReleased() async throws {
        let attempts = max(timing.modifierPollAttempts, 1)
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            if !backend.shortcutModifiersArePressed() {
                return
            }
            if attempt + 1 < attempts {
                await delay(nanoseconds: timing.modifierPollNanoseconds)
            }
        }
        throw SelectionClipboardFallbackError.shortcutModifiersStillPressed
    }

    /// Accepts only predecessor + 1. A skipped count, a second writer, a value
    /// that changes during stabilization, or a change arriving too late is not
    /// attributable to our Copy and must never authorize restoration.
    private func observeExactNextStableChange(after predecessor: Int) async throws -> Int {
        let (expectedChangeCount, overflow) = predecessor.addingReportingOverflow(1)
        guard !overflow else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }

        let attempts = max(timing.copyPollAttempts, 1)
        let requiredStablePolls = max(timing.stableCopyPollsRequired, 0)
        var sawExpectedChange = false
        var stablePolls = 0

        for attempt in 0..<attempts {
            let currentChangeCount = backend.pasteboardChangeCount
            switch currentChangeCount {
            case predecessor where !sawExpectedChange:
                break
            case expectedChangeCount:
                if sawExpectedChange {
                    stablePolls += 1
                } else {
                    sawExpectedChange = true
                    stablePolls = 0
                }
                if stablePolls >= requiredStablePolls {
                    return expectedChangeCount
                }
            default:
                throw SelectionClipboardFallbackError.clipboardChangedConcurrently
            }

            if attempt + 1 < attempts {
                await delay(nanoseconds: timing.copyPollNanoseconds)
            }
        }
        throw SelectionClipboardFallbackError.copyTimedOut
    }

    private func delay(nanoseconds: UInt64) async {
        guard nanoseconds > 0 else {
            await Task.yield()
            return
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .nanoseconds(Int(clamping: nanoseconds))
            ) {
                continuation.resume()
            }
        }
    }
}

typealias SystemSelectionClipboardFallbackService =
    SelectionClipboardFallbackService<SystemSelectionClipboardFallbackBackend>

extension SelectionClipboardFallbackService
where Backend == SystemSelectionClipboardFallbackBackend {
    init() {
        self.init(backend: SystemSelectionClipboardFallbackBackend())
    }
}

final class SystemSelectionClipboardFallbackBackend: SelectionClipboardFallbackBackend,
    @unchecked Sendable
{
    private static let maximumItemCount = 100
    private static let maximumTypeCountPerItem = 128
    private static let maximumTotalDataBytes = 64 * 1_024 * 1_024
    private static let cKeyCode: CGKeyCode = 8
    private static let accessibilityMessagingTimeout: Float = 0.8

    private let pasteboard: NSPasteboard
    private let workspace: NSWorkspace

    init(
        pasteboard: NSPasteboard = .general,
        workspace: NSWorkspace = .shared
    ) {
        self.pasteboard = pasteboard
        self.workspace = workspace
    }

    func shortcutModifiersArePressed() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let shortcutModifiers: CGEventFlags = [
            .maskCommand,
            .maskAlternate,
            .maskShift,
            .maskControl,
        ]
        return !flags.intersection(shortcutModifiers).isEmpty
    }

    func snapshotPasteboard() throws -> SelectionPasteboardArchive {
        let originalChangeCount = pasteboard.changeCount
        let pasteboardItems: [NSPasteboardItem]
        if let currentItems = pasteboard.pasteboardItems {
            pasteboardItems = currentItems
        } else if pasteboard.types?.isEmpty ?? true {
            pasteboardItems = []
        } else {
            throw SelectionClipboardFallbackError.pasteboardSnapshotUnavailable
        }

        guard pasteboardItems.count <= Self.maximumItemCount else {
            throw SelectionClipboardFallbackError.pasteboardSnapshotTooLarge
        }

        var totalDataBytes = 0
        var archivedItems: [SelectionPasteboardArchive.Item] = []
        archivedItems.reserveCapacity(pasteboardItems.count)

        for item in pasteboardItems {
            let types = item.types
            guard !types.isEmpty,
                  types.count <= Self.maximumTypeCountPerItem else {
                throw SelectionClipboardFallbackError.pasteboardSnapshotUnavailable
            }

            var representations: [SelectionPasteboardArchive.Item.Representation] = []
            representations.reserveCapacity(types.count)
            for type in types {
                guard let data = item.data(forType: type) else {
                    throw SelectionClipboardFallbackError.pasteboardSnapshotUnavailable
                }
                let (nextTotal, overflow) = totalDataBytes.addingReportingOverflow(data.count)
                guard !overflow, nextTotal <= Self.maximumTotalDataBytes else {
                    throw SelectionClipboardFallbackError.pasteboardSnapshotTooLarge
                }
                totalDataBytes = nextTotal
                representations.append(
                    SelectionPasteboardArchive.Item.Representation(
                        typeRawValue: type.rawValue,
                        data: data
                    )
                )
            }
            archivedItems.append(
                SelectionPasteboardArchive.Item(representations: representations)
            )
        }

        guard pasteboard.changeCount == originalChangeCount else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }
        return SelectionPasteboardArchive(
            originalChangeCount: originalChangeCount,
            items: archivedItems
        )
    }

    var pasteboardChangeCount: Int {
        pasteboard.changeCount
    }

    func postCopyIfTargetStillSafe(
        _ ticket: AccessibilitySelectionFallbackTicket
    ) throws {
        _ = try validateTarget(for: ticket)
        guard !IsSecureEventInputEnabled() else {
            throw SelectionClipboardFallbackError.secureEventInput
        }
        guard CGPreflightPostEventAccess() else {
            throw SelectionClipboardFallbackError.eventPostingNotAuthorized
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let copyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: Self.cKeyCode,
                keyDown: true
              ),
              let copyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: Self.cKeyCode,
                keyDown: false
              ) else {
            throw SelectionClipboardFallbackError.eventCreationFailed
        }

        copyDown.flags = .maskCommand
        copyUp.flags = .maskCommand

        // Event construction is intentionally followed by one last complete
        // check so there is no separately callable "validated" state that can
        // go stale before posting.
        _ = try validateTarget(for: ticket)
        guard !IsSecureEventInputEnabled() else {
            throw SelectionClipboardFallbackError.secureEventInput
        }
        guard CGPreflightPostEventAccess() else {
            throw SelectionClipboardFallbackError.eventPostingNotAuthorized
        }
        // AX safety attributes are cross-process calls and can block. Bind
        // their result back to the still-focused ticket element immediately
        // before the first key event, rather than relying on the pre-query
        // focus check above.
        _ = try validateTarget(for: ticket)

        // The C events carry the Command flag themselves. Avoiding separate
        // modifier events narrows the interval in which the target app could
        // react to Command-down and move focus before receiving C.
        for event in [copyDown, copyUp] {
            event.postToPid(ticket.processIdentifier)
        }
    }

    func targetStillMatches(_ ticket: AccessibilitySelectionFallbackTicket) -> Bool {
        do {
            _ = try validateTarget(for: ticket)
        } catch {
            return false
        }
        return !IsSecureEventInputEnabled()
    }

    func copiedText() -> String? {
        pasteboard.string(forType: .string)
    }

    func restorePasteboard(
        _ archive: SelectionPasteboardArchive,
        expectedChangeCount: Int
    ) throws {
        let restoredItems = try archive.items.map { archivedItem in
            let item = NSPasteboardItem()
            for representation in archivedItem.representations {
                let didSet = item.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(
                        rawValue: representation.typeRawValue
                    )
                )
                guard didSet else {
                    throw SelectionClipboardFallbackError.restoreFailed
                }
            }
            return item
        }

        guard pasteboard.changeCount == expectedChangeCount else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }
        pasteboard.clearContents()
        guard restoredItems.isEmpty || pasteboard.writeObjects(restoredItems) else {
            throw SelectionClipboardFallbackError.restoreFailed
        }
    }

    /// Revalidates the frontmost application and returns its current AX focused
    /// element when one exists. Exact-element tickets require identity plus
    /// complete evidence. Application-scoped tickets are used only for
    /// custom-drawn apps that expose no stable focused element; for those, any
    /// security attributes that are available remain fail-closed, while absent
    /// attributes defer to Secure Event Input and the explicit user gesture.
    private func validateTarget(
        for ticket: AccessibilitySelectionFallbackTicket
    ) throws -> AXUIElement? {
        guard ticket.processIdentifier > 0,
              ticket.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              workspace.frontmostApplication?.processIdentifier == ticket.processIdentifier else {
            throw SelectionClipboardFallbackError.sourceApplicationChanged
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        applyMessagingTimeout(to: systemWideElement)
        if let focusedApplication = copyElementAttribute(
            kAXFocusedApplicationAttribute as CFString,
            from: systemWideElement
        ) {
            applyMessagingTimeout(to: focusedApplication)
            var focusedApplicationPID: pid_t = 0
            guard AXUIElementGetPid(focusedApplication, &focusedApplicationPID) == .success,
                  focusedApplicationPID == ticket.processIdentifier else {
                throw SelectionClipboardFallbackError.sourceApplicationChanged
            }
        }

        let applicationElement = AXUIElementCreateApplication(ticket.processIdentifier)
        applyMessagingTimeout(to: applicationElement)
        let currentFocusedElement = copyElementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: applicationElement
        )
        if let currentFocusedElement {
            applyMessagingTimeout(to: currentFocusedElement)
        }

        if let expectedFocusedElement = ticket.systemFocusedElement {
            var ticketElementPID: pid_t = 0
            guard AXUIElementGetPid(expectedFocusedElement, &ticketElementPID) == .success,
                  ticketElementPID == ticket.processIdentifier,
                  let currentFocusedElement,
                  CFEqual(currentFocusedElement, expectedFocusedElement) else {
                throw SelectionClipboardFallbackError.sourceApplicationChanged
            }
            try requireCompleteNonsecureEvidence(of: currentFocusedElement)
            return currentFocusedElement
        }

        if let currentFocusedElement {
            try rejectKnownSecureEvidence(of: currentFocusedElement)
        }
        return currentFocusedElement
    }

    private func rejectKnownSecureEvidence(of element: AXUIElement) throws {
        if let rawSubrole = copyAttribute(
            kAXSubroleAttribute as CFString,
            from: element
        ) {
            guard let subrole = rawSubrole as? String else {
                throw SelectionClipboardFallbackError.sourceApplicationChanged
            }
            guard subrole.caseInsensitiveCompare("AXSecureTextField") != .orderedSame else {
                throw SelectionClipboardFallbackError.secureEventInput
            }
        }

        if let protectedContentValue = copyAttribute(
            "AXContainsProtectedContent" as CFString,
            from: element
        ) {
            guard CFGetTypeID(protectedContentValue) == CFBooleanGetTypeID() else {
                throw SelectionClipboardFallbackError.sourceApplicationChanged
            }
            guard !CFBooleanGetValue((protectedContentValue as! CFBoolean)) else {
                throw SelectionClipboardFallbackError.secureEventInput
            }
        }
    }

    private func requireCompleteNonsecureEvidence(of element: AXUIElement) throws {
        guard let rawSubrole = copyAttribute(
            kAXSubroleAttribute as CFString,
            from: element
        ), let subrole = rawSubrole as? String else {
            throw SelectionClipboardFallbackError.sourceApplicationChanged
        }
        guard subrole.caseInsensitiveCompare("AXSecureTextField") != .orderedSame else {
            throw SelectionClipboardFallbackError.secureEventInput
        }

        guard let protectedContentValue = copyAttribute(
            "AXContainsProtectedContent" as CFString,
            from: element
        ), CFGetTypeID(protectedContentValue) == CFBooleanGetTypeID() else {
            throw SelectionClipboardFallbackError.sourceApplicationChanged
        }
        guard !CFBooleanGetValue((protectedContentValue as! CFBoolean)) else {
            throw SelectionClipboardFallbackError.secureEventInput
        }
    }

    private func applyMessagingTimeout(to element: AXUIElement) {
        _ = AXUIElementSetMessagingTimeout(element, Self.accessibilityMessagingTimeout)
    }

    private func copyElementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = copyAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func copyAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success else {
            return nil
        }
        return rawValue
    }
}
