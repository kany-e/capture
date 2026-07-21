import Foundation
import XCTest

@testable import Mema

@MainActor
final class SelectionClipboardFallbackServiceTests: XCTestCase {
    private let defaultTicket = AccessibilitySelectionFallbackTicket(
        identifier: UUID(uuidString: "A19E404A-E2E7-4542-974B-2BFBF62F3752")!,
        processIdentifier: 4_201,
        sourceApplication: "WeChat"
    )

    func testTwoMatchingCopiesPreserveExactUnicodeAndRestoreOriginalArchiveOnce() async throws {
        let originalArchive = makeArchive(
            changeCount: 40,
            representations: [
                ("public.utf8-plain-text", Data("old clipboard".utf8)),
                ("public.rtf", Data([0x7B, 0x5C, 0x72, 0x74, 0x66, 0x31, 0x7D])),
            ]
        )
        let exactText = " 你好 👩🏽‍💻\nsecond line\t "
        let backend = successfulBackend(
            ticket: defaultTicket,
            originalArchive: originalArchive,
            copiedText: exactText
        )
        let service = makeService(backend: backend)

        let snapshot = try await service.captureSelection(using: defaultTicket)

        XCTAssertEqual(snapshot.text, exactText)
        XCTAssertEqual(snapshot.sourceApplication, "WeChat")
        XCTAssertNil(snapshot.selectionBoundsInAXScreenCoordinates)
        XCTAssertEqual(snapshot.captureMethod, .clipboardFallback)
        XCTAssertEqual(backend.postedTicketIdentifiers, [
            defaultTicket.identifier,
            defaultTicket.identifier,
        ])
        XCTAssertEqual(backend.copiedTextCallCount, 2)
        XCTAssertEqual(backend.restoreRequests.count, 1)
        XCTAssertEqual(backend.restoreRequests.first?.archive, originalArchive)
        XCTAssertEqual(backend.restoreRequests.first?.expectedChangeCount, 42)
    }

    func testPasteboardTransactionRunsOffTheMainThread() async throws {
        let backend = successfulBackend(ticket: defaultTicket)
        let service = makeService(backend: backend)

        _ = try await service.captureSelection(using: defaultTicket)

        XCTAssertFalse(try XCTUnwrap(backend.snapshotThreadWasMain.first))
        XCTAssertTrue(backend.snapshotThreadWasMain.allSatisfy { !$0 })
    }

    func testTicketSourceNameIsUsedWithoutRecapturingApplicationIdentity() async throws {
        let backend = successfulBackend(ticket: defaultTicket)
        let service = makeService(backend: backend)

        let snapshot = try await service.captureSelection(using: defaultTicket)

        XCTAssertEqual(snapshot.sourceApplication, defaultTicket.sourceApplication)
        XCTAssertEqual(Set(backend.postedTicketIdentifiers), [defaultTicket.identifier])
    }

    func testWaitsForShortcutModifiersBeforeFirstSafetyCheckAndCopy() async throws {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.modifierStates = [true, true, false]
        let service = makeService(
            backend: backend,
            timing: SelectionClipboardFallbackTiming(
                modifierPollNanoseconds: 0,
                modifierPollAttempts: 3,
                copyPollNanoseconds: 0,
                copyPollAttempts: 2,
                stableCopyPollsRequired: 0
            )
        )

        _ = try await service.captureSelection(using: defaultTicket)

        XCTAssertEqual(backend.shortcutModifierCallCount, 3)
        let firstCopyIndex = try XCTUnwrap(backend.calls.firstIndex(of: .postCopyIfSafe))
        let finalModifierIndex = try XCTUnwrap(
            backend.calls.lastIndex(of: .shortcutModifiers)
        )
        XCTAssertGreaterThan(firstCopyIndex, finalModifierIndex)
    }

    func testDifferentControlTicketForSamePIDIsRejectedBeforeCopy() async {
        let backend = successfulBackend(ticket: defaultTicket)
        let otherTicket = AccessibilitySelectionFallbackTicket(
            processIdentifier: defaultTicket.processIdentifier,
            sourceApplication: defaultTicket.sourceApplication
        )
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .sourceApplicationChanged,
            service: service,
            ticket: otherTicket
        )

        XCTAssertTrue(backend.postedTicketIdentifiers.isEmpty)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testEventPostingPermissionFailureDoesNotCopyOrRestore() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.eventsAuthorized = false
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .eventPostingNotAuthorized,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertTrue(backend.postedTicketIdentifiers.isEmpty)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testSecureEventInputDoesNotCopyOrRestore() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.secureInputEnabled = true
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .secureEventInput,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertTrue(backend.postedTicketIdentifiers.isEmpty)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testIncompleteSafetyEvidenceDoesNotCopyOrRestore() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.completeSafetyEvidence = false
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .sourceApplicationChanged,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertTrue(backend.postedTicketIdentifiers.isEmpty)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testPasteboardChangeDuringOriginalSnapshotDoesNotCopyOrRestore() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.onSnapshot = { backend, callCount in
            if callCount == 1 {
                backend.changeCount += 1
            }
        }
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .clipboardChangedConcurrently,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertTrue(backend.postedTicketIdentifiers.isEmpty)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testFirstCopySkippingNextChangeCountIsNeverAcceptedOrRestored() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.onPostCopy = { backend, postCount in
            if postCount == 1 {
                backend.changeCount += 2
            } else {
                backend.changeCount += 1
            }
        }
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .clipboardChangedConcurrently,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.postedTicketIdentifiers.count, 1)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testSecondCopySkippingNextChangeCountIsNeverAcceptedOrRestored() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.onPostCopy = { backend, postCount in
            backend.changeCount += postCount == 1 ? 1 : 2
        }
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .clipboardChangedConcurrently,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.postedTicketIdentifiers.count, 2)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testOneExternalWriteCannotMasqueradeAsOurCopy() async {
        let externalArchive = makeArchive(
            changeCount: 11,
            representations: [
                ("public.utf8-plain-text", Data("external writer".utf8)),
            ]
        )
        let backend = SelectionClipboardFallbackBackendFake()
        backend.matchingTicketIdentifier = defaultTicket.identifier
        backend.changeCount = 10
        backend.snapshotResults = [makeArchive(changeCount: 10), externalArchive]
        backend.copiedTextResults = ["external writer"]
        backend.onPostCopy = { backend, postCount in
            // A foreign writer races the first Copy; the target's Copy itself
            // has no effect both times. One observed change is not ownership.
            if postCount == 1 {
                backend.changeCount = 11
            }
        }
        let service = makeService(
            backend: backend,
            timing: SelectionClipboardFallbackTiming(
                modifierPollNanoseconds: 0,
                modifierPollAttempts: 1,
                copyPollNanoseconds: 0,
                copyPollAttempts: 3,
                stableCopyPollsRequired: 0
            )
        )

        await assertCaptureThrows(
            .copyTimedOut,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.postedTicketIdentifiers.count, 2)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testFocusedControlChangeAfterFirstCandidateRejectsSecondCopyAndNeverRestores() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.onCopiedText = { backend, callCount in
            if callCount == 1 {
                backend.targetMatches = false
            }
        }
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .sourceApplicationChanged,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.postedTicketIdentifiers.count, 1)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testFocusedControlChangeAfterSecondCandidateNeverRestoresOrReturns() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.onCopiedText = { backend, callCount in
            if callCount == 2 {
                backend.targetMatches = false
            }
        }
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .sourceApplicationChanged,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.postedTicketIdentifiers.count, 2)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testControlBecomingSecureAfterFirstCandidateRejectsSecondCopy() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.onCopiedText = { backend, callCount in
            if callCount == 1 {
                backend.secureInputEnabled = true
            }
        }
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .sourceApplicationChanged,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.postedTicketIdentifiers.count, 1)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testSafetyEvidenceChangingAfterSecondCandidatePreventsRestore() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.onCopiedText = { backend, callCount in
            if callCount == 2 {
                backend.completeSafetyEvidence = false
            }
        }
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .sourceApplicationChanged,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.postedTicketIdentifiers.count, 2)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testTwoCopiesWithDifferentArchiveItemsNeverRestoreOrReturn() async {
        let original = makeArchive(changeCount: 20)
        let first = makeArchive(
            changeCount: 21,
            representations: [("public.utf8-plain-text", Data("first".utf8))]
        )
        let second = makeArchive(
            changeCount: 22,
            representations: [("public.utf8-plain-text", Data("second".utf8))]
        )
        let backend = successfulBackend(
            ticket: defaultTicket,
            originalArchive: original,
            copiedText: "same extracted text"
        )
        backend.snapshotResults = [original, first, second]
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .clipboardChangedConcurrently,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testTwoCopiesWithDifferentExtractedTextNeverRestoreOrReturn() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.copiedTextResults = ["first", "second"]
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .clipboardChangedConcurrently,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testClipboardChangeAfterSecondReadNeverRestoresOrReturns() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.onCopiedText = { backend, callCount in
            if callCount == 2 {
                backend.changeCount += 1
            }
        }
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .clipboardChangedConcurrently,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testCopyArrivingAtEndOfPollingWindowIsNotRestored() async {
        let backend = SelectionClipboardFallbackBackendFake()
        backend.matchingTicketIdentifier = defaultTicket.identifier
        backend.changeCount = 25
        backend.snapshotResults = [makeArchive(changeCount: 25)]
        // First value is the post-snapshot check. The exact next count appears
        // only on the final poll and cannot satisfy the stability requirement.
        backend.scriptedChangeCounts = [25, 25, 25, 26]
        let service = makeService(
            backend: backend,
            timing: SelectionClipboardFallbackTiming(
                modifierPollNanoseconds: 0,
                modifierPollAttempts: 1,
                copyPollNanoseconds: 0,
                copyPollAttempts: 3,
                stableCopyPollsRequired: 1
            )
        )

        await assertCaptureThrows(
            .copyTimedOut,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testCopyArrivingAfterPollingCompletesIsNeverRestoredLater() async {
        let backend = SelectionClipboardFallbackBackendFake()
        backend.matchingTicketIdentifier = defaultTicket.identifier
        backend.changeCount = 50
        backend.snapshotResults = [makeArchive(changeCount: 50)]
        let service = makeService(
            backend: backend,
            timing: SelectionClipboardFallbackTiming(
                modifierPollNanoseconds: 0,
                modifierPollAttempts: 1,
                copyPollNanoseconds: 0,
                copyPollAttempts: 3,
                stableCopyPollsRequired: 0
            )
        )

        await assertCaptureThrows(
            .copyTimedOut,
            service: service,
            ticket: defaultTicket
        )
        backend.changeCount = 51

        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testConfirmedNonTextCopiesRestoreThenReportNoText() async {
        let backend = successfulBackend(ticket: defaultTicket, copiedText: nil)
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .copiedContentHasNoText,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.restoreRequests.count, 1)
        XCTAssertEqual(backend.restoreRequests.first?.expectedChangeCount, 12)
    }

    func testConfirmedWhitespaceCopiesRestoreThenReportEmptyText() async {
        let backend = successfulBackend(ticket: defaultTicket, copiedText: " \n\t ")
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .copiedContentIsEmpty,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.restoreRequests.count, 1)
    }

    func testCancellationAfterFirstCopyFinishesConfirmationAndRestoreBeforeEscaping() async {
        let backend = successfulBackend(ticket: defaultTicket)
        let service = makeService(
            backend: backend,
            timing: SelectionClipboardFallbackTiming(
                modifierPollNanoseconds: 0,
                modifierPollAttempts: 1,
                copyPollNanoseconds: 1_000_000,
                copyPollAttempts: 100,
                stableCopyPollsRequired: 20
            )
        )

        let captureTask = Task {
            try await service.captureSelection(using: defaultTicket)
        }
        for _ in 0..<100 where backend.postedTicketIdentifiers.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(backend.postedTicketIdentifiers.count, 1)
        captureTask.cancel()

        do {
            _ = try await captureTask.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(backend.postedTicketIdentifiers.count, 2)
        XCTAssertEqual(backend.restoreRequests.count, 1)
    }

    func testCancellationWithUnconfirmedSecondCopyNeverRestores() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.onPostCopy = { backend, postCount in
            if postCount == 1 {
                backend.changeCount += 1
            }
        }
        let service = makeService(
            backend: backend,
            timing: SelectionClipboardFallbackTiming(
                modifierPollNanoseconds: 0,
                modifierPollAttempts: 1,
                copyPollNanoseconds: 1_000_000,
                copyPollAttempts: 30,
                stableCopyPollsRequired: 2
            )
        )

        let captureTask = Task {
            try await service.captureSelection(using: defaultTicket)
        }
        for _ in 0..<100 where backend.postedTicketIdentifiers.count < 1 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        captureTask.cancel()
        _ = try? await captureTask.value

        XCTAssertEqual(backend.postedTicketIdentifiers.count, 2)
        XCTAssertEqual(backend.restoreRequests.count, 0)
    }

    func testRestoreFailureSurfacesStableRestoreErrorWithoutRetrying() async {
        let backend = successfulBackend(ticket: defaultTicket)
        backend.restoreError = .restoreFailed
        let service = makeService(backend: backend)

        await assertCaptureThrows(
            .restoreFailed,
            service: service,
            ticket: defaultTicket
        )

        XCTAssertEqual(backend.restoreRequests.count, 1)
    }

    func testSameOriginalAndCopiedTextIsAcceptedOnlyAfterTwoCountAdvances() async throws {
        let sameText = "identical text"
        let original = makeArchive(
            changeCount: 90,
            representations: [
                ("public.utf8-plain-text", Data(sameText.utf8)),
            ]
        )
        let backend = successfulBackend(
            ticket: defaultTicket,
            originalArchive: original,
            copiedText: sameText
        )
        let service = makeService(backend: backend)

        let snapshot = try await service.captureSelection(using: defaultTicket)

        XCTAssertEqual(snapshot.text, sameText)
        XCTAssertEqual(backend.postedTicketIdentifiers.count, 2)
        XCTAssertEqual(backend.restoreRequests.first?.expectedChangeCount, 92)
    }

    private func makeService(
        backend: SelectionClipboardFallbackBackendFake,
        timing: SelectionClipboardFallbackTiming = SelectionClipboardFallbackTiming(
            modifierPollNanoseconds: 0,
            modifierPollAttempts: 1,
            copyPollNanoseconds: 0,
            copyPollAttempts: 2,
            stableCopyPollsRequired: 0
        )
    ) -> SelectionClipboardFallbackService<SelectionClipboardFallbackBackendFake> {
        SelectionClipboardFallbackService(backend: backend, timing: timing)
    }

    private func successfulBackend(
        ticket: AccessibilitySelectionFallbackTicket,
        originalArchive: SelectionPasteboardArchive? = nil,
        copiedText: String? = "selected text"
    ) -> SelectionClipboardFallbackBackendFake {
        let backend = SelectionClipboardFallbackBackendFake()
        backend.matchingTicketIdentifier = ticket.identifier
        let original = originalArchive ?? makeArchive(changeCount: 10)
        let firstCandidate = makeCopiedArchive(
            changeCount: original.originalChangeCount + 1,
            text: copiedText ?? "non-text selection"
        )
        let secondCandidate = SelectionPasteboardArchive(
            originalChangeCount: original.originalChangeCount + 2,
            items: firstCandidate.items
        )
        backend.changeCount = original.originalChangeCount
        backend.snapshotResults = [original, firstCandidate, secondCandidate]
        backend.copiedTextResults = [copiedText, copiedText]
        backend.onPostCopy = { backend, _ in
            backend.changeCount += 1
        }
        return backend
    }

    private func makeCopiedArchive(
        changeCount: Int,
        text: String
    ) -> SelectionPasteboardArchive {
        makeArchive(
            changeCount: changeCount,
            representations: [
                ("public.utf8-plain-text", Data(text.utf8)),
                ("public.rtf", Data("{\\rtf1 copied}".utf8)),
            ]
        )
    }

    private func makeArchive(
        changeCount: Int,
        representations: [(String, Data)] = [
            ("public.utf8-plain-text", Data("original clipboard".utf8)),
        ]
    ) -> SelectionPasteboardArchive {
        SelectionPasteboardArchive(
            originalChangeCount: changeCount,
            items: [
                SelectionPasteboardArchive.Item(
                    representations: representations.map {
                        SelectionPasteboardArchive.Item.Representation(
                            typeRawValue: $0.0,
                            data: $0.1
                        )
                    }
                ),
            ]
        )
    }

    private func assertCaptureThrows(
        _ expectedError: SelectionClipboardFallbackError,
        service: SelectionClipboardFallbackService<SelectionClipboardFallbackBackendFake>,
        ticket: AccessibilitySelectionFallbackTicket,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await service.captureSelection(using: ticket)
            XCTFail("Expected \(expectedError)", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? SelectionClipboardFallbackError,
                expectedError,
                file: file,
                line: line
            )
        }
    }
}

private final class SelectionClipboardFallbackBackendFake:
    SelectionClipboardFallbackBackend, @unchecked Sendable
{
    enum Call: Equatable {
        case shortcutModifiers
        case snapshot
        case changeCount
        case postCopyIfSafe
        case targetStillMatches
        case copiedText
        case restore
    }

    struct RestoreRequest: Equatable {
        let archive: SelectionPasteboardArchive
        let expectedChangeCount: Int
    }

    var matchingTicketIdentifier: UUID?
    var targetMatches = true
    var completeSafetyEvidence = true
    var eventsAuthorized = true
    var secureInputEnabled = false
    var modifierStates: [Bool] = [false]
    var snapshotResults: [SelectionPasteboardArchive] = []
    var changeCount = 0
    var scriptedChangeCounts: [Int] = []
    var copiedTextResults: [String?] = []
    var restoreError: SelectionClipboardFallbackError?
    var onSnapshot: ((SelectionClipboardFallbackBackendFake, Int) -> Void)?
    var onPostCopy: ((SelectionClipboardFallbackBackendFake, Int) -> Void)?
    var onCopiedText: ((SelectionClipboardFallbackBackendFake, Int) -> Void)?

    private(set) var calls: [Call] = []
    private(set) var shortcutModifierCallCount = 0
    private(set) var snapshotCallCount = 0
    private(set) var copiedTextCallCount = 0
    private(set) var postedTicketIdentifiers: [UUID] = []
    private(set) var restoreRequests: [RestoreRequest] = []
    private(set) var snapshotThreadWasMain: [Bool] = []

    func shortcutModifiersArePressed() -> Bool {
        calls.append(.shortcutModifiers)
        shortcutModifierCallCount += 1
        if modifierStates.count > 1 {
            return modifierStates.removeFirst()
        }
        return modifierStates.first ?? false
    }

    func snapshotPasteboard() throws -> SelectionPasteboardArchive {
        calls.append(.snapshot)
        snapshotThreadWasMain.append(Thread.isMainThread)
        snapshotCallCount += 1
        let result: SelectionPasteboardArchive
        if snapshotResults.isEmpty {
            result = SelectionPasteboardArchive(
                originalChangeCount: changeCount,
                items: []
            )
        } else {
            result = snapshotResults.removeFirst()
        }
        onSnapshot?(self, snapshotCallCount)
        return result
    }

    var pasteboardChangeCount: Int {
        calls.append(.changeCount)
        if !scriptedChangeCounts.isEmpty {
            changeCount = scriptedChangeCounts.removeFirst()
        }
        return changeCount
    }

    func postCopyIfTargetStillSafe(
        _ ticket: AccessibilitySelectionFallbackTicket
    ) throws {
        calls.append(.postCopyIfSafe)
        guard targetMatches,
              matchingTicketIdentifier == ticket.identifier else {
            throw SelectionClipboardFallbackError.sourceApplicationChanged
        }
        guard completeSafetyEvidence else {
            throw SelectionClipboardFallbackError.sourceApplicationChanged
        }
        guard !secureInputEnabled else {
            throw SelectionClipboardFallbackError.secureEventInput
        }
        guard eventsAuthorized else {
            throw SelectionClipboardFallbackError.eventPostingNotAuthorized
        }
        postedTicketIdentifiers.append(ticket.identifier)
        onPostCopy?(self, postedTicketIdentifiers.count)
    }

    func targetStillMatches(_ ticket: AccessibilitySelectionFallbackTicket) -> Bool {
        calls.append(.targetStillMatches)
        return targetMatches
            && matchingTicketIdentifier == ticket.identifier
            && completeSafetyEvidence
            && !secureInputEnabled
    }

    func copiedText() -> String? {
        calls.append(.copiedText)
        copiedTextCallCount += 1
        let result: String?
        if copiedTextResults.isEmpty {
            result = nil
        } else {
            result = copiedTextResults.removeFirst()
        }
        onCopiedText?(self, copiedTextCallCount)
        return result
    }

    func restorePasteboard(
        _ archive: SelectionPasteboardArchive,
        expectedChangeCount: Int
    ) throws {
        calls.append(.restore)
        restoreRequests.append(
            RestoreRequest(
                archive: archive,
                expectedChangeCount: expectedChangeCount
            )
        )
        if let restoreError {
            throw restoreError
        }
        guard changeCount == expectedChangeCount else {
            throw SelectionClipboardFallbackError.clipboardChangedConcurrently
        }
        changeCount += 1
    }
}
