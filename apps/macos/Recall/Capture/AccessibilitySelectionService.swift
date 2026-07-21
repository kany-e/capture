@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

/// Text selected in the application that currently owns the system-wide AX focus.
struct AccessibilitySelectionSnapshot: Equatable, Sendable {
    let text: String
    let sourceApplication: String?

    /// Bounds returned by `AXBoundsForRange`.
    ///
    /// These are deliberately kept in Accessibility's global screen coordinate
    /// space (origin at the upper-left of the primary display). The presentation
    /// layer owns conversion into AppKit coordinates because it also has the
    /// current screen layout needed to position and clamp a window correctly.
    let selectionBoundsInAXScreenCoordinates: CGRect?
}

/// Stable, user-facing failures from an explicit Accessibility selection read.
enum AccessibilitySelectionError: Error, Equatable, LocalizedError, Sendable {
    case permissionRequired
    case noFocusedApplication
    case currentApplication
    case noFocusedElement
    case secureTextInput
    case selectionUnavailable
    case noSelection
    case emptySelection
    case selectionTooLong

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return NSLocalizedString(
                "Recall needs Accessibility access to read selected text. Open System "
                    + "Settings > Privacy & Security > Accessibility, enable Recall, then try again.",
                comment: "Accessibility permission is required for selection capture"
            )
        case .noFocusedApplication:
            return NSLocalizedString(
                "Recall could not find the focused application. Return to the app, select text, "
                    + "and try again.",
                comment: "No focused application was available for selection capture"
            )
        case .currentApplication:
            return NSLocalizedString(
                "Return to another app, select text, then use Capture Selection again.",
                comment: "Recall itself is the focused application during selection capture"
            )
        case .noFocusedElement:
            return NSLocalizedString(
                "Recall could not find the focused control. Select text in the app and try again.",
                comment: "No focused control was available for selection capture"
            )
        case .secureTextInput:
            return NSLocalizedString(
                "Recall does not read selections from password or secure text fields.",
                comment: "Selection capture is blocked for secure text fields"
            )
        case .selectionUnavailable:
            return NSLocalizedString(
                "The focused control does not make its selected text available to macOS "
                    + "Accessibility. Copy the text and use Capture Clipboard instead.",
                comment: "The focused control does not support Accessibility selection reads"
            )
        case .noSelection:
            return NSLocalizedString(
                "No selected text was found. Select some text and try again.",
                comment: "No Accessibility text selection was present"
            )
        case .emptySelection:
            return NSLocalizedString(
                "The selected text is empty. Select non-whitespace text and try again.",
                comment: "The Accessibility text selection contained only whitespace"
            )
        case .selectionTooLong:
            return NSLocalizedString(
                "The selected text is longer than 12,000 characters. Select a smaller passage "
                    + "and try again; Recall did not truncate or save it.",
                comment: "The Accessibility text selection exceeded the source limit"
            )
        }
    }
}

/// Async so callers never need to perform cross-process AX messaging on the main actor.
protocol AccessibilitySelectionServing: Sendable {
    func isTrusted(promptIfNeeded: Bool) async -> Bool
    func readSelection(promptIfNeeded: Bool) async throws -> AccessibilitySelectionSnapshot
}

/// A semantic boundary around AX calls. Keeping elements generic lets unit tests
/// verify privacy-sensitive ordering without constructing process-owned AX objects.
protocol AccessibilitySelectionBackend: Sendable {
    associatedtype Element: Sendable

    func isProcessTrusted(promptIfNeeded: Bool) -> Bool
    func focusedApplication() throws -> Element
    func isCurrentApplication(_ application: Element) -> Bool
    func focusedElement(in application: Element) throws -> Element
    func subrole(of element: Element) throws -> String?
    func containsProtectedContent(of element: Element) throws -> Bool
    func selectedText(of element: Element) throws -> String?
    func selectionBounds(of element: Element) throws -> CGRect?
    func sourceApplicationName(for application: Element) -> String?
}

/// Generic implementation shared by the real AX backend and deterministic tests.
struct AccessibilitySelectionService<Backend: AccessibilitySelectionBackend>:
    AccessibilitySelectionServing,
    Sendable
{
    private static var secureTextFieldSubrole: String { "AXSecureTextField" }

    private let backend: Backend

    init(backend: Backend) {
        self.backend = backend
    }

    func isTrusted(promptIfNeeded: Bool) async -> Bool {
        let backend = backend
        let task = Task.detached(priority: .userInitiated) {
            backend.isProcessTrusted(promptIfNeeded: promptIfNeeded)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func readSelection(
        promptIfNeeded: Bool
    ) async throws -> AccessibilitySelectionSnapshot {
        let backend = backend
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard backend.isProcessTrusted(promptIfNeeded: promptIfNeeded) else {
                throw AccessibilitySelectionError.permissionRequired
            }
            try Task.checkCancellation()

            let application: Backend.Element
            do {
                application = try backend.focusedApplication()
            } catch {
                throw AccessibilitySelectionError.noFocusedApplication
            }
            try Task.checkCancellation()
            guard !backend.isCurrentApplication(application) else {
                throw AccessibilitySelectionError.currentApplication
            }
            try Task.checkCancellation()

            let focusedElement: Backend.Element
            do {
                focusedElement = try backend.focusedElement(in: application)
            } catch {
                throw AccessibilitySelectionError.noFocusedElement
            }
            try Task.checkCancellation()

            // The secure-subrole query intentionally precedes the selected-text
            // query. Any unexpected failure here is fail-closed: it is safer to
            // offer the clipboard fallback than risk reading a protected field.
            let subrole: String?
            do {
                subrole = try backend.subrole(of: focusedElement)
            } catch {
                throw AccessibilitySelectionError.selectionUnavailable
            }
            if subrole?.caseInsensitiveCompare(Self.secureTextFieldSubrole) == .orderedSame {
                throw AccessibilitySelectionError.secureTextInput
            }
            try Task.checkCancellation()

            let containsProtectedContent: Bool
            do {
                containsProtectedContent = try backend.containsProtectedContent(
                    of: focusedElement
                )
            } catch {
                throw AccessibilitySelectionError.selectionUnavailable
            }
            guard !containsProtectedContent else {
                throw AccessibilitySelectionError.secureTextInput
            }
            try Task.checkCancellation()

            let text: String?
            do {
                text = try backend.selectedText(of: focusedElement)
            } catch let error as AccessibilitySelectionBackendError {
                switch error {
                case .noValue:
                    throw AccessibilitySelectionError.noSelection
                case .unsupported, .invalidValue, .cannotComplete, .failure:
                    throw AccessibilitySelectionError.selectionUnavailable
                }
            } catch {
                throw AccessibilitySelectionError.selectionUnavailable
            }

            guard let text else {
                throw AccessibilitySelectionError.noSelection
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AccessibilitySelectionError.emptySelection
            }

            try Task.checkCancellation()
            // Bounds improve placement but are never allowed to invalidate a
            // successful text read. Many otherwise-compatible controls omit the
            // selected range or the parameterized bounds attribute.
            let bounds = try? backend.selectionBounds(of: focusedElement)
            try Task.checkCancellation()
            let sourceApplication = backend.sourceApplicationName(for: application)
            try Task.checkCancellation()
            return AccessibilitySelectionSnapshot(
                text: text,
                sourceApplication: sourceApplication,
                selectionBoundsInAXScreenCoordinates: bounds
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

typealias SystemAccessibilitySelectionService =
    AccessibilitySelectionService<SystemAccessibilitySelectionBackend>

extension AccessibilitySelectionService where Backend == SystemAccessibilitySelectionBackend {
    init(messagingTimeout: Float = SystemAccessibilitySelectionBackend.defaultMessagingTimeout) {
        self.init(
            backend: SystemAccessibilitySelectionBackend(messagingTimeout: messagingTimeout)
        )
    }
}

enum AccessibilitySelectionBackendError: Error, Equatable, Sendable {
    case unsupported
    case noValue
    case invalidValue
    case cannotComplete
    case failure
}

struct SystemAccessibilityElement: @unchecked Sendable {
    fileprivate let value: AXUIElement
}

struct SystemAccessibilitySelectionBackend: AccessibilitySelectionBackend, Sendable {
    static let defaultMessagingTimeout: Float = 0.8

    private let messagingTimeout: Float

    init(messagingTimeout: Float = defaultMessagingTimeout) {
        let finiteTimeout = messagingTimeout.isFinite
            ? messagingTimeout
            : Self.defaultMessagingTimeout
        self.messagingTimeout = min(max(finiteTimeout, 0.1), 2.0)
    }

    func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        guard promptIfNeeded else {
            return AXIsProcessTrusted()
        }
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func focusedApplication() throws -> SystemAccessibilityElement {
        let systemWideElement = AXUIElementCreateSystemWide()
        applyMessagingTimeout(to: systemWideElement)
        let application: AXUIElement = try copyElementAttribute(
            kAXFocusedApplicationAttribute as CFString,
            from: systemWideElement
        )
        applyMessagingTimeout(to: application)
        return SystemAccessibilityElement(value: application)
    }

    func isCurrentApplication(_ application: SystemAccessibilityElement) -> Bool {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(application.value, &processIdentifier) == .success else {
            // PID resolution is required both for the self-check and for source
            // attribution. Treat an unresolved app as unsafe to read.
            return true
        }
        if processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return true
        }
        guard let recallBundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }
        return NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
            == recallBundleIdentifier
    }

    func focusedElement(
        in application: SystemAccessibilityElement
    ) throws -> SystemAccessibilityElement {
        applyMessagingTimeout(to: application.value)
        let element: AXUIElement = try copyElementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: application.value
        )
        applyMessagingTimeout(to: element)
        return SystemAccessibilityElement(value: element)
    }

    func subrole(of element: SystemAccessibilityElement) throws -> String? {
        do {
            return try copyStringAttribute(
                kAXSubroleAttribute as CFString,
                from: element.value
            )
        } catch let error as AccessibilitySelectionBackendError
            where error == .unsupported || error == .noValue {
            return nil
        }
    }

    func containsProtectedContent(of element: SystemAccessibilityElement) throws -> Bool {
        let value: CFTypeRef?
        do {
            value = try copyAttribute(
                "AXContainsProtectedContent" as CFString,
                from: element.value
            )
        } catch let error as AccessibilitySelectionBackendError
            where error == .unsupported || error == .noValue {
            return false
        }
        guard let value else { return false }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw AccessibilitySelectionBackendError.invalidValue
        }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    func selectedText(of element: SystemAccessibilityElement) throws -> String? {
        let value: CFTypeRef?
        do {
            value = try copyAttribute(
                kAXSelectedTextAttribute as CFString,
                from: element.value
            )
        } catch let error as AccessibilitySelectionBackendError where error == .noValue {
            return nil
        }
        guard let value else { return nil }
        if let string = value as? String {
            return string
        }
        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }
        throw AccessibilitySelectionBackendError.invalidValue
    }

    func selectionBounds(of element: SystemAccessibilityElement) throws -> CGRect? {
        let selectedRange: CFTypeRef
        do {
            guard let value = try copyAttribute(
                kAXSelectedTextRangeAttribute as CFString,
                from: element.value
            ) else {
                return nil
            }
            selectedRange = value
        } catch let error as AccessibilitySelectionBackendError
            where error == .unsupported || error == .noValue {
            return nil
        }

        guard CFGetTypeID(selectedRange) == AXValueGetTypeID(),
              AXValueGetType(selectedRange as! AXValue) == .cfRange else {
            throw AccessibilitySelectionBackendError.invalidValue
        }

        var rawBounds: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element.value,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange,
            &rawBounds
        )
        try validate(result)
        guard let rawBounds else { return nil }
        guard CFGetTypeID(rawBounds) == AXValueGetTypeID() else {
            throw AccessibilitySelectionBackendError.invalidValue
        }
        let value = rawBounds as! AXValue
        guard AXValueGetType(value) == .cgRect else {
            throw AccessibilitySelectionBackendError.invalidValue
        }
        var bounds = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &bounds) else {
            throw AccessibilitySelectionBackendError.invalidValue
        }
        return bounds
    }

    func sourceApplicationName(for application: SystemAccessibilityElement) -> String? {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(application.value, &processIdentifier) == .success,
              let name = NSRunningApplication(
                processIdentifier: processIdentifier
              )?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    private func applyMessagingTimeout(to element: AXUIElement) {
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }

    private func copyElementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) throws -> AXUIElement {
        guard let value = try copyAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw AccessibilitySelectionBackendError.invalidValue
        }
        return value as! AXUIElement
    }

    private func copyStringAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) throws -> String? {
        guard let value = try copyAttribute(attribute, from: element) else {
            return nil
        }
        guard let string = value as? String else {
            throw AccessibilitySelectionBackendError.invalidValue
        }
        return string
    }

    private func copyAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        try validate(result)
        return value
    }

    private func validate(_ error: AXError) throws {
        switch error {
        case .success:
            return
        case .attributeUnsupported, .parameterizedAttributeUnsupported,
             .notImplemented:
            throw AccessibilitySelectionBackendError.unsupported
        case .noValue:
            throw AccessibilitySelectionBackendError.noValue
        case .illegalArgument, .invalidUIElement, .invalidUIElementObserver:
            throw AccessibilitySelectionBackendError.invalidValue
        case .cannotComplete, .apiDisabled:
            throw AccessibilitySelectionBackendError.cannotComplete
        default:
            throw AccessibilitySelectionBackendError.failure
        }
    }
}
