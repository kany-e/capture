import CoreGraphics
import Foundation
import XCTest

@testable import Recall

@MainActor
final class AccessibilitySelectionServiceTests: XCTestCase {
    func testDeniedPermissionFailsClosedBeforeReadingAttributes() async {
        let backend = AccessibilityBackendStub(isTrusted: false)
        let service = AccessibilitySelectionService(backend: backend)

        await assertReadThrows(.permissionRequired) {
            try await service.readSelection(promptIfNeeded: true)
        }

        XCTAssertEqual(backend.calls, [.trust(promptIfNeeded: true)])
    }

    func testTrustCheckPassesPromptChoiceAndRunsOffMainThread() async {
        let backend = AccessibilityBackendStub(isTrusted: true)
        let service = AccessibilitySelectionService(backend: backend)

        let isTrusted = await service.isTrusted(promptIfNeeded: true)

        XCTAssertTrue(isTrusted)
        XCTAssertEqual(backend.calls, [.trust(promptIfNeeded: true)])
        XCTAssertEqual(backend.wasMainThread, [false])
    }

    func testSuccessfulReadUsesFocusedApplicationThenFocusedElementAndPreservesText() async throws {
        let bounds = CGRect(x: 120, y: 80, width: 240, height: 32)
        let originalText = "\n  Keep this spacing exactly.  \t"
        let backend = AccessibilityBackendStub(
            selectedText: originalText,
            bounds: bounds,
            sourceApplication: "Pages"
        )
        let service = AccessibilitySelectionService(backend: backend)

        let snapshot = try await service.readSelection(promptIfNeeded: false)

        XCTAssertEqual(snapshot.text, originalText)
        XCTAssertEqual(snapshot.sourceApplication, "Pages")
        XCTAssertEqual(snapshot.selectionBoundsInAXScreenCoordinates, bounds)
        XCTAssertEqual(snapshot.captureMethod, .accessibility)
        XCTAssertEqual(
            backend.calls,
            [
                .trust(promptIfNeeded: false),
                .focusedApplication,
                .currentApplication,
                .focusedElement,
                .subrole,
                .protectedContent,
                .selectedText,
                .selectionBounds,
                .sourceApplication
            ]
        )
        XCTAssertTrue(backend.wasMainThread.allSatisfy { !$0 })
    }

    func testSecureSubroleIsRejectedBeforeSelectedTextIsRead() async {
        let backend = AccessibilityBackendStub(subrole: "AXSecureTextField")
        let service = AccessibilitySelectionService(backend: backend)

        await assertReadThrows(.secureTextInput) {
            try await service.readSelection(promptIfNeeded: false)
        }

        XCTAssertEqual(
            backend.calls,
            [
                .trust(promptIfNeeded: false),
                .focusedApplication,
                .currentApplication,
                .focusedElement,
                .subrole
            ]
        )
    }

    func testSecureSubroleComparisonIsCaseInsensitive() async {
        let backend = AccessibilityBackendStub(subrole: "axsecuretextfield")
        let service = AccessibilitySelectionService(backend: backend)

        await assertReadThrows(.secureTextInput) {
            try await service.readSelection(promptIfNeeded: false)
        }

        XCTAssertFalse(backend.calls.contains(.selectedText))
    }

    func testSubroleReadFailureFailsClosedBeforeSelectedText() async {
        let backend = AccessibilityBackendStub(subroleError: .cannotComplete)
        let service = AccessibilitySelectionService(backend: backend)

        await assertReadThrows(.selectionSafetyUnavailable) {
            try await service.readSelection(promptIfNeeded: false)
        }

        XCTAssertFalse(backend.calls.contains(.selectedText))
    }

    func testProtectedContentReadFailureCannotEnableClipboardFallback() async {
        let backend = AccessibilityBackendStub(protectedContentError: .cannotComplete)
        let service = AccessibilitySelectionService(backend: backend)

        await assertReadThrows(.selectionSafetyUnavailable) {
            try await service.readSelection(promptIfNeeded: false)
        }

        XCTAssertFalse(backend.calls.contains(.selectedText))
    }

    func testCurrentApplicationIsRejectedBeforeFocusedElementIsRead() async {
        let backend = AccessibilityBackendStub(isCurrentApplication: true)
        let service = AccessibilitySelectionService(backend: backend)

        await assertReadThrows(.currentApplication) {
            try await service.readSelection(promptIfNeeded: false)
        }

        XCTAssertEqual(
            backend.calls,
            [
                .trust(promptIfNeeded: false),
                .focusedApplication,
                .currentApplication
            ]
        )
    }

    func testProtectedContentIsRejectedBeforeSelectedTextIsRead() async {
        let backend = AccessibilityBackendStub(containsProtectedContent: true)
        let service = AccessibilitySelectionService(backend: backend)

        await assertReadThrows(.secureTextInput) {
            try await service.readSelection(promptIfNeeded: false)
        }

        XCTAssertEqual(
            backend.calls,
            [
                .trust(promptIfNeeded: false),
                .focusedApplication,
                .currentApplication,
                .focusedElement,
                .subrole,
                .protectedContent
            ]
        )
    }

    func testWhitespaceOnlySelectionIsRejectedWithoutReadingBounds() async {
        let backend = AccessibilityBackendStub(selectedText: " \n\t ")
        let service = AccessibilitySelectionService(backend: backend)

        await assertReadThrows(.emptySelection) {
            try await service.readSelection(promptIfNeeded: false)
        }

        XCTAssertFalse(backend.calls.contains(.selectionBounds))
        XCTAssertFalse(backend.calls.contains(.sourceApplication))
    }

    func testMissingSelectedTextMapsToNoSelection() async {
        let backend = AccessibilityBackendStub(selectedText: nil)
        let service = AccessibilitySelectionService(backend: backend)

        await assertReadThrows(.noSelection) {
            try await service.readSelection(promptIfNeeded: false)
        }
    }

    func testSelectedTextBackendFailuresHaveStableMappings() async {
        for backendError in [
            AccessibilitySelectionBackendError.unsupported,
            .invalidValue,
            .cannotComplete,
            .failure
        ] {
            let backend = AccessibilityBackendStub(selectedTextError: backendError)
            let service = AccessibilitySelectionService(backend: backend)

            await assertReadThrows(.selectionUnavailable) {
                try await service.readSelection(promptIfNeeded: false)
            }
        }

        let noValueBackend = AccessibilityBackendStub(selectedTextError: .noValue)
        let noValueService = AccessibilitySelectionService(backend: noValueBackend)
        await assertReadThrows(.noSelection) {
            try await noValueService.readSelection(promptIfNeeded: false)
        }
    }

    func testFallbackReadReturnsTicketForTheExactCheckedApplicationAndControl() async throws {
        let backend = AccessibilityBackendStub(
            selectedTextError: .unsupported,
            sourceApplication: "WeChat",
            processIdentifier: 4_201
        )
        let service = AccessibilitySelectionService(backend: backend)

        let outcome = try await service.readSelectionForClipboardFallback(
            promptIfNeeded: false
        )

        guard case let .clipboardFallback(ticket) = outcome else {
            return XCTFail("Expected a clipboard fallback ticket")
        }
        XCTAssertEqual(ticket.processIdentifier, 4_201)
        XCTAssertEqual(ticket.sourceApplication, "WeChat")
        XCTAssertNil(ticket.systemFocusedElement)
        XCTAssertEqual(backend.fallbackFocusedElementWasProvided, true)
        XCTAssertEqual(
            backend.calls,
            [
                .trust(promptIfNeeded: false),
                .focusedApplication,
                .currentApplication,
                .focusedElement,
                .subrole,
                .protectedContent,
                .selectedText,
                .fallbackTicket,
            ]
        )
    }

    func testFallbackReadCreatesApplicationTicketWhenFocusedElementIsUnavailable() async throws {
        let backend = AccessibilityBackendStub(
            focusedElementError: .noValue,
            sourceApplication: "WeChat",
            processIdentifier: 4_202
        )
        let service = AccessibilitySelectionService(backend: backend)

        let outcome = try await service.readSelectionForClipboardFallback(
            promptIfNeeded: false
        )

        guard case let .clipboardFallback(ticket) = outcome else {
            return XCTFail("Expected an application-scoped fallback ticket")
        }
        XCTAssertEqual(ticket.processIdentifier, 4_202)
        XCTAssertEqual(ticket.sourceApplication, "WeChat")
        XCTAssertEqual(backend.fallbackFocusedElementWasProvided, false)
        XCTAssertEqual(
            backend.calls,
            [
                .trust(promptIfNeeded: false),
                .focusedApplication,
                .currentApplication,
                .focusedElement,
                .fallbackTicket,
            ]
        )
    }

    func testFallbackReadTreatsNoSelectedTextValueAsClipboardEligible() async throws {
        let backend = AccessibilityBackendStub(selectedTextError: .noValue)
        let service = AccessibilitySelectionService(backend: backend)

        let outcome = try await service.readSelectionForClipboardFallback(
            promptIfNeeded: false
        )

        guard case .clipboardFallback = outcome else {
            return XCTFail("Expected a clipboard fallback ticket")
        }
        XCTAssertEqual(backend.fallbackFocusedElementWasProvided, true)
    }

    func testFallbackReadUsesApplicationTicketWhenSafetyAttributesAreMissing() async throws {
        for backend in [
            AccessibilityBackendStub(
                subroleWasAvailable: false,
                selectedTextError: .unsupported
            ),
            AccessibilityBackendStub(
                protectedContentWasAvailable: false,
                selectedTextError: .cannotComplete
            ),
            AccessibilityBackendStub(subroleError: .cannotComplete),
        ] {
            let service = AccessibilitySelectionService(backend: backend)
            let outcome = try await service.readSelectionForClipboardFallback(
                promptIfNeeded: false
            )

            guard case .clipboardFallback = outcome else {
                return XCTFail("Expected an application-scoped fallback ticket")
            }
            XCTAssertEqual(backend.fallbackFocusedElementWasProvided, false)
        }
    }

    func testFallbackReadStillRejectsKnownSecureAndProtectedControls() async {
        for backend in [
            AccessibilityBackendStub(subrole: "AXSecureTextField"),
            AccessibilityBackendStub(containsProtectedContent: true),
        ] {
            let service = AccessibilitySelectionService(backend: backend)
            do {
                _ = try await service.readSelectionForClipboardFallback(
                    promptIfNeeded: false
                )
                XCTFail("Expected the known secure control to be rejected")
            } catch {
                XCTAssertEqual(
                    error as? AccessibilitySelectionError,
                    .secureTextInput
                )
            }
            XCTAssertNil(backend.fallbackFocusedElementWasProvided)
        }
    }

    func testSelectedTextFailureIsNotFallbackEligibleWithoutCompleteSafetyEvidence() async {
        let missingSubroleEvidence = AccessibilityBackendStub(
            subroleWasAvailable: false,
            selectedTextError: .unsupported
        )
        let missingProtectedEvidence = AccessibilityBackendStub(
            protectedContentWasAvailable: false,
            selectedTextError: .cannotComplete
        )

        for backend in [missingSubroleEvidence, missingProtectedEvidence] {
            let service = AccessibilitySelectionService(backend: backend)
            await assertReadThrows(.selectionSafetyUnavailable) {
                try await service.readSelection(promptIfNeeded: false)
            }
        }
    }

    func testOnlyPostSafetySelectedTextFailureAllowsClipboardFallback() {
        XCTAssertTrue(AccessibilitySelectionError.selectionUnavailable.allowsClipboardFallback)
        for error in [
            AccessibilitySelectionError.permissionRequired,
            .noFocusedApplication,
            .currentApplication,
            .noFocusedElement,
            .secureTextInput,
            .selectionSafetyUnavailable,
            .noSelection,
            .emptySelection,
            .selectionTooLong,
            .clipboardFallbackUnavailable,
            .clipboardChangedDuringFallback,
            .clipboardRestoreFailed,
        ] {
            XCTAssertFalse(error.allowsClipboardFallback, "Unexpected: \(error)")
        }
    }

    func testFocusFailuresHaveStableMappings() async {
        let applicationBackend = AccessibilityBackendStub(
            focusedApplicationError: .cannotComplete
        )
        let applicationService = AccessibilitySelectionService(backend: applicationBackend)
        await assertReadThrows(.noFocusedApplication) {
            try await applicationService.readSelection(promptIfNeeded: false)
        }
        XCTAssertEqual(
            applicationBackend.calls,
            [.trust(promptIfNeeded: false), .focusedApplication]
        )

        let elementBackend = AccessibilityBackendStub(focusedElementError: .noValue)
        let elementService = AccessibilitySelectionService(backend: elementBackend)
        await assertReadThrows(.noFocusedElement) {
            try await elementService.readSelection(promptIfNeeded: false)
        }
        XCTAssertEqual(
            elementBackend.calls,
            [
                .trust(promptIfNeeded: false),
                .focusedApplication,
                .currentApplication,
                .focusedElement
            ]
        )
    }

    func testBoundsFailureDoesNotInvalidateSuccessfulTextRead() async throws {
        let backend = AccessibilityBackendStub(
            selectedText: "Selected text",
            boundsError: .unsupported,
            sourceApplication: "Safari"
        )
        let service = AccessibilitySelectionService(backend: backend)

        let snapshot = try await service.readSelection(promptIfNeeded: false)

        XCTAssertEqual(snapshot.text, "Selected text")
        XCTAssertEqual(snapshot.sourceApplication, "Safari")
        XCTAssertNil(snapshot.selectionBoundsInAXScreenCoordinates)
    }

    func testErrorsProvideActionableStableMessages() {
        XCTAssertTrue(
            AccessibilitySelectionError.permissionRequired.localizedDescription
                .contains("Privacy & Security > Accessibility")
        )
        XCTAssertTrue(
            AccessibilitySelectionError.selectionUnavailable.localizedDescription
                .contains("Clipboard Compatibility Mode")
        )
        XCTAssertTrue(
            AccessibilitySelectionError.secureTextInput.localizedDescription
                .contains("secure text fields")
        )
    }

    private func assertReadThrows(
        _ expectedError: AccessibilitySelectionError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> AccessibilitySelectionSnapshot
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expectedError)", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? AccessibilitySelectionError,
                expectedError,
                file: file,
                line: line
            )
        }
    }
}

private enum AccessibilityBackendCall: Equatable, Sendable {
    case trust(promptIfNeeded: Bool)
    case focusedApplication
    case currentApplication
    case focusedElement
    case subrole
    case protectedContent
    case selectedText
    case selectionBounds
    case sourceApplication
    case fallbackTicket
}

private enum AccessibilityStubElement: Sendable {
    case application
    case focusedElement
}

private final class AccessibilityBackendStub:
    AccessibilitySelectionBackend,
    @unchecked Sendable
{
    typealias Element = AccessibilityStubElement

    private let trusted: Bool
    private let focusedApplicationError: AccessibilitySelectionBackendError?
    private let currentApplication: Bool
    private let focusedElementError: AccessibilitySelectionBackendError?
    private let subroleValue: String?
    private let subroleError: AccessibilitySelectionBackendError?
    private let subroleWasAvailable: Bool
    private let protectedContent: Bool
    private let protectedContentError: AccessibilitySelectionBackendError?
    private let protectedContentWasAvailable: Bool
    private let selectedTextValue: String?
    private let selectedTextError: AccessibilitySelectionBackendError?
    private let boundsValue: CGRect?
    private let boundsError: AccessibilitySelectionBackendError?
    private let applicationName: String?
    private let applicationProcessIdentifier: pid_t

    private let lock = NSLock()
    private var recordedCalls: [AccessibilityBackendCall] = []
    private var recordedMainThreadStates: [Bool] = []
    private var recordedFallbackFocusedElementWasProvided: Bool?

    init(
        isTrusted: Bool = true,
        focusedApplicationError: AccessibilitySelectionBackendError? = nil,
        isCurrentApplication: Bool = false,
        focusedElementError: AccessibilitySelectionBackendError? = nil,
        subrole: String? = "AXTextField",
        subroleError: AccessibilitySelectionBackendError? = nil,
        subroleWasAvailable: Bool = true,
        containsProtectedContent: Bool = false,
        protectedContentError: AccessibilitySelectionBackendError? = nil,
        protectedContentWasAvailable: Bool = true,
        selectedText: String? = "Selected text",
        selectedTextError: AccessibilitySelectionBackendError? = nil,
        bounds: CGRect? = nil,
        boundsError: AccessibilitySelectionBackendError? = nil,
        sourceApplication: String? = "TextEdit",
        processIdentifier: pid_t = 4_200
    ) {
        trusted = isTrusted
        self.focusedApplicationError = focusedApplicationError
        currentApplication = isCurrentApplication
        self.focusedElementError = focusedElementError
        subroleValue = subrole
        self.subroleError = subroleError
        self.subroleWasAvailable = subroleWasAvailable
        protectedContent = containsProtectedContent
        self.protectedContentError = protectedContentError
        self.protectedContentWasAvailable = protectedContentWasAvailable
        selectedTextValue = selectedText
        self.selectedTextError = selectedTextError
        boundsValue = bounds
        self.boundsError = boundsError
        applicationName = sourceApplication
        applicationProcessIdentifier = processIdentifier
    }

    var calls: [AccessibilityBackendCall] {
        lock.withLock { recordedCalls }
    }

    var wasMainThread: [Bool] {
        lock.withLock { recordedMainThreadStates }
    }

    var fallbackFocusedElementWasProvided: Bool? {
        lock.withLock { recordedFallbackFocusedElementWasProvided }
    }

    func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        record(.trust(promptIfNeeded: promptIfNeeded))
        return trusted
    }

    func focusedApplication() throws -> AccessibilityStubElement {
        record(.focusedApplication)
        if let focusedApplicationError { throw focusedApplicationError }
        return .application
    }

    func isCurrentApplication(_ application: AccessibilityStubElement) -> Bool {
        record(.currentApplication)
        return currentApplication
    }

    func focusedElement(
        in application: AccessibilityStubElement
    ) throws -> AccessibilityStubElement {
        record(.focusedElement)
        if let focusedElementError { throw focusedElementError }
        return .focusedElement
    }

    func securityInspection(
        of element: AccessibilityStubElement
    ) throws -> AccessibilitySelectionSecurityInspection {
        record(.subrole)
        if let subroleError { throw subroleError }
        if subroleValue?.caseInsensitiveCompare("AXSecureTextField") == .orderedSame {
            return AccessibilitySelectionSecurityInspection(
                subrole: subroleValue,
                containsProtectedContent: false,
                hasCompleteFallbackEvidence: false
            )
        }

        record(.protectedContent)
        if let protectedContentError { throw protectedContentError }
        return AccessibilitySelectionSecurityInspection(
            subrole: subroleValue,
            containsProtectedContent: protectedContent,
            hasCompleteFallbackEvidence: subroleWasAvailable
                && protectedContentWasAvailable
        )
    }

    func selectedText(of element: AccessibilityStubElement) throws -> String? {
        record(.selectedText)
        if let selectedTextError { throw selectedTextError }
        return selectedTextValue
    }

    func selectionBounds(of element: AccessibilityStubElement) throws -> CGRect? {
        record(.selectionBounds)
        if let boundsError { throw boundsError }
        return boundsValue
    }

    func sourceApplicationName(for application: AccessibilityStubElement) -> String? {
        record(.sourceApplication)
        return applicationName
    }

    func clipboardFallbackTicket(
        for application: AccessibilityStubElement,
        focusedElement: AccessibilityStubElement?
    ) throws -> AccessibilitySelectionFallbackTicket {
        record(.fallbackTicket)
        lock.withLock {
            recordedFallbackFocusedElementWasProvided = focusedElement != nil
        }
        return AccessibilitySelectionFallbackTicket(
            processIdentifier: applicationProcessIdentifier,
            sourceApplication: applicationName
        )
    }

    private func record(_ call: AccessibilityBackendCall) {
        lock.withLock {
            recordedCalls.append(call)
            recordedMainThreadStates.append(Thread.isMainThread)
        }
    }
}
