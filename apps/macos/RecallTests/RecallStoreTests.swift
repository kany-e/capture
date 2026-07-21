import Foundation
import XCTest

@testable import Recall

@MainActor
final class RecallStoreTests: XCTestCase {
    func testAccessibilitySelectionCapturePreservesExactTextAndBounds() async {
        let text = " 你好 👩‍💻\nsecond line "
        let bounds = CGRect(x: 100, y: 220, width: 180, height: 42)
        let service = AccessibilitySelectionServiceStub(
            result: .success(
                AccessibilitySelectionSnapshot(
                    text: text,
                    sourceApplication: "TextEdit",
                    selectionBoundsInAXScreenCoordinates: bounds
                )
            )
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: service
        )

        let snapshot = await store.prepareAccessibilitySelectionCapture()

        XCTAssertEqual(snapshot?.selectionBoundsInAXScreenCoordinates, bounds)
        XCTAssertEqual(store.quickCaptureDraft?.kind, .selection)
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, text)
        XCTAssertEqual(store.quickCaptureDraft?.sourceApplication, "TextEdit")
        XCTAssertNil(store.accessibilitySelectionError)
        let readCount = await service.readCount()
        XCTAssertEqual(readCount, 1)
    }

    func testAccessibilitySelectionSavesThroughExistingClipboardContract() async throws {
        let client = RecordingAPIClient()
        let service = AccessibilitySelectionServiceStub(
            result: .success(
                AccessibilitySelectionSnapshot(
                    text: "Exact native selection",
                    sourceApplication: "Preview",
                    selectionBoundsInAXScreenCoordinates: nil
                )
            )
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: service
        )
        let preparedSnapshot = await store.prepareAccessibilitySelectionCapture()
        XCTAssertNotNil(preparedSnapshot)
        store.quickCaptureDraft?.userNote = "Why this matters"

        let submitted = await store.submitQuickCapture()
        XCTAssertTrue(submitted)

        let recordedRequest = await client.lastCreateRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.sourceType, .clipboard)
        XCTAssertEqual(request.selectedText, "Exact native selection")
        XCTAssertEqual(request.sourceApp, "Preview")
        XCTAssertEqual(request.userNote, "Why this matters")
        XCTAssertNil(request.sourceTitle)
        XCTAssertNil(request.sourceURL)
        XCTAssertNil(request.surroundingContext)
        XCTAssertFalse(request.contextTruncated)
    }

    func testAccessibilitySelectionBoundsSourceApplicationWithoutChangingText() async {
        let source = String(
            repeating: "s",
            count: RecallStore.maximumSourceApplicationLength + 20
        )
        let service = AccessibilitySelectionServiceStub(
            result: .success(
                AccessibilitySelectionSnapshot(
                    text: "Keep exact text",
                    sourceApplication: source,
                    selectionBoundsInAXScreenCoordinates: nil
                )
            )
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: service
        )

        _ = await store.prepareAccessibilitySelectionCapture()

        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "Keep exact text")
        XCTAssertEqual(
            store.quickCaptureDraft?.sourceApplication?.unicodeScalars.count,
            RecallStore.maximumSourceApplicationLength
        )
    }

    func testExistingDraftRejectsAccessibilityReadBeforeCallingService() async {
        let service = AccessibilitySelectionServiceStub(
            result: .success(
                AccessibilitySelectionSnapshot(
                    text: "Do not read this",
                    sourceApplication: "Notes",
                    selectionBoundsInAXScreenCoordinates: nil
                )
            )
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .success(
                    ClipboardSnapshot(text: "Keep this draft", sourceApplication: "Safari")
                )
            ),
            accessibilitySelectionService: service
        )
        XCTAssertTrue(store.prepareClipboardCapture())
        let originalDraftID = store.quickCaptureDraft?.clientCaptureID

        let snapshot = await store.prepareAccessibilitySelectionCapture()

        XCTAssertNil(snapshot)
        let readCount = await service.readCount()
        XCTAssertEqual(readCount, 0)
        XCTAssertEqual(store.quickCaptureDraft?.clientCaptureID, originalDraftID)
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "Keep this draft")
    }

    func testAccessibilityFailureCreatesExplicitClipboardRecoveryState() async {
        let service = AccessibilitySelectionServiceStub(
            result: .failure(.permissionRequired)
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: service
        )

        let snapshot = await store.prepareAccessibilitySelectionCapture()

        XCTAssertNil(snapshot)
        XCTAssertNil(store.quickCaptureDraft)
        XCTAssertEqual(store.accessibilitySelectionError, .permissionRequired)
        XCTAssertTrue(store.quickCaptureError?.contains("Accessibility") == true)
    }

    func testEligibleAccessibilityFailureUsesEnabledClipboardFallback() async {
        let accessibilityService = AccessibilitySelectionServiceStub(
            result: .failure(.selectionUnavailable)
        )
        let fallbackService = SelectionClipboardFallbackServiceStub(
            result: .success(
                AccessibilitySelectionSnapshot(
                    text: " 微信 fallback 👋\nsecond line ",
                    sourceApplication: "WeChat",
                    selectionBoundsInAXScreenCoordinates: nil,
                    captureMethod: .clipboardFallback
                )
            )
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: accessibilityService,
            selectionClipboardFallbackService: fallbackService,
            selectionClipboardFallbackIsEnabled: true
        )

        let snapshot = await store.prepareAccessibilitySelectionCapture()

        XCTAssertEqual(snapshot?.captureMethod, .clipboardFallback)
        XCTAssertEqual(store.quickCaptureDraft?.kind, .selection)
        XCTAssertEqual(store.quickCaptureDraft?.selectionCaptureMethod, .clipboardFallback)
        XCTAssertEqual(
            store.quickCaptureDraft?.selectedText,
            " 微信 fallback 👋\nsecond line "
        )
        XCTAssertEqual(store.quickCaptureDraft?.sourceApplication, "WeChat")
        XCTAssertNil(store.accessibilitySelectionError)
        XCTAssertEqual(fallbackService.captureCount, 1)
        XCTAssertEqual(fallbackService.capturedTickets.first?.processIdentifier, 4_242)
    }

    func testDisabledClipboardFallbackPreservesExplicitRecoveryWithoutReadingClipboard() async {
        let fallbackService = SelectionClipboardFallbackServiceStub(
            result: .failure(SelectionClipboardFallbackError.copyTimedOut)
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: AccessibilitySelectionServiceStub(
                result: .failure(.selectionUnavailable)
            ),
            selectionClipboardFallbackService: fallbackService,
            selectionClipboardFallbackIsEnabled: false
        )

        let snapshot = await store.prepareAccessibilitySelectionCapture()

        XCTAssertNil(snapshot)
        XCTAssertNil(store.quickCaptureDraft)
        XCTAssertEqual(store.accessibilitySelectionError, .selectionUnavailable)
        XCTAssertEqual(fallbackService.captureCount, 0)
    }

    func testClipboardFallbackNeverRunsForIneligibleAccessibilityFailures() async {
        let ineligibleErrors: [AccessibilitySelectionError] = [
            .permissionRequired,
            .noFocusedApplication,
            .currentApplication,
            .noFocusedElement,
            .secureTextInput,
            .selectionSafetyUnavailable,
            .noSelection,
            .emptySelection,
            .selectionTooLong,
        ]

        for selectionError in ineligibleErrors {
            let fallbackService = SelectionClipboardFallbackServiceStub(
                result: .failure(SelectionClipboardFallbackError.copyTimedOut)
            )
            let store = RecallStore(
                client: RecordingAPIClient(),
                clipboardService: ClipboardServiceStub(
                    result: .failure(ClipboardCaptureError.noText)
                ),
                accessibilitySelectionService: AccessibilitySelectionServiceStub(
                    result: .failure(selectionError)
                ),
                selectionClipboardFallbackService: fallbackService,
                selectionClipboardFallbackIsEnabled: true
            )

            _ = await store.prepareAccessibilitySelectionCapture()

            XCTAssertEqual(store.accessibilitySelectionError, selectionError)
            XCTAssertEqual(fallbackService.captureCount, 0, "Unexpected: \(selectionError)")
        }
    }

    func testClipboardFallbackFailureHasSpecificRecoveryState() async {
        let fallbackService = SelectionClipboardFallbackServiceStub(
            result: .failure(SelectionClipboardFallbackError.clipboardChangedConcurrently)
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: AccessibilitySelectionServiceStub(
                result: .failure(.selectionUnavailable)
            ),
            selectionClipboardFallbackService: fallbackService,
            selectionClipboardFallbackIsEnabled: true
        )

        let snapshot = await store.prepareAccessibilitySelectionCapture()

        XCTAssertNil(snapshot)
        XCTAssertNil(store.quickCaptureDraft)
        XCTAssertEqual(
            store.accessibilitySelectionError,
            .clipboardChangedDuringFallback
        )
        XCTAssertTrue(store.quickCaptureError?.contains("competing clipboard activity") == true)
    }

    func testOversizedClipboardFallbackIsRestoredThenRejectedBeforeDraftRendering() async {
        let fallbackService = SelectionClipboardFallbackServiceStub(
            result: .success(
                AccessibilitySelectionSnapshot(
                    text: String(
                        repeating: "x",
                        count: RecallStore.maximumSelectedTextLength + 1
                    ),
                    sourceApplication: "WeChat",
                    selectionBoundsInAXScreenCoordinates: nil,
                    captureMethod: .clipboardFallback
                )
            )
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: AccessibilitySelectionServiceStub(
                result: .failure(.selectionUnavailable)
            ),
            selectionClipboardFallbackService: fallbackService,
            selectionClipboardFallbackIsEnabled: true
        )

        let snapshot = await store.prepareAccessibilitySelectionCapture()

        XCTAssertNil(snapshot)
        XCTAssertNil(store.quickCaptureDraft)
        XCTAssertEqual(store.accessibilitySelectionError, .selectionTooLong)
        XCTAssertEqual(fallbackService.captureCount, 1)
    }

    func testClipboardFallbackPreferenceIsOptInAndPersistsExplicitChanges() {
        let suiteName = "RecallStoreTests.clipboardFallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fallbackService = SelectionClipboardFallbackServiceStub(
            result: .failure(SelectionClipboardFallbackError.copyTimedOut)
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            selectionClipboardFallbackService: fallbackService,
            selectionClipboardFallbackIsEnabled: false,
            selectionPreferenceUserDefaults: defaults
        )

        XCTAssertFalse(store.selectionClipboardFallbackIsEnabled)
        store.setSelectionClipboardFallbackEnabled(true)

        XCTAssertTrue(store.selectionClipboardFallbackIsEnabled)
        XCTAssertTrue(
            defaults.bool(forKey: RecallStore.selectionClipboardFallbackUserDefaultsKey)
        )
    }

    func testOversizedAccessibilitySelectionIsRejectedBeforeDraftRendering() async {
        let oversized = String(
            repeating: "x",
            count: RecallStore.maximumSelectedTextLength + 1
        )
        let service = AccessibilitySelectionServiceStub(
            result: .success(
                AccessibilitySelectionSnapshot(
                    text: oversized,
                    sourceApplication: "Pages",
                    selectionBoundsInAXScreenCoordinates: nil
                )
            )
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: service
        )

        let snapshot = await store.prepareAccessibilitySelectionCapture()

        XCTAssertNil(snapshot)
        XCTAssertNil(store.quickCaptureDraft)
        XCTAssertEqual(store.accessibilitySelectionError, .selectionTooLong)
        XCTAssertTrue(store.quickCaptureError?.contains("12,000") == true)
    }

    func testCoordinatorDeduplicatesAccessibilityReadsAndPreservesAnchor() async {
        let service = SuspendedAccessibilitySelectionService()
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: service
        )
        let coordinator = GlobalCaptureCoordinator(store: store)
        let bounds = CGRect(x: 40, y: 50, width: 120, height: 30)

        coordinator.prepareAccessibilitySelectionCapture()
        coordinator.prepareAccessibilitySelectionCapture()
        for _ in 0..<100 {
            if await service.readCount() > 0 { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let readCount = await service.readCount()
        XCTAssertEqual(readCount, 1)

        await service.complete(
            with: .success(
                AccessibilitySelectionSnapshot(
                    text: "One read",
                    sourceApplication: "TextEdit",
                    selectionBoundsInAXScreenCoordinates: bounds
                )
            )
        )
        await waitUntil { coordinator.quickCapturePresentationRequest == 1 }

        XCTAssertEqual(
            coordinator.quickCapturePresentationContext?
                .selectionBoundsInAXScreenCoordinates,
            bounds
        )
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "One read")
    }

    func testCoordinatorPresentsPermissionRecoveryOnceAndRequestsPrompt() async {
        let service = AccessibilitySelectionServiceStub(
            result: .failure(.permissionRequired)
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: service
        )
        let coordinator = GlobalCaptureCoordinator(store: store)

        coordinator.prepareAccessibilitySelectionCapture()
        await waitUntil { coordinator.quickCapturePresentationRequest == 1 }

        XCTAssertNil(store.quickCaptureDraft)
        XCTAssertEqual(store.accessibilitySelectionError, .permissionRequired)
        XCTAssertNil(
            coordinator.quickCapturePresentationContext?
                .selectionBoundsInAXScreenCoordinates
        )
        let prompts = await service.readPromptValues()
        XCTAssertEqual(prompts, [true])
    }

    func testCancelledAccessibilityReadCannotRestoreLateDraftOrPresentation() async {
        let service = SuspendedAccessibilitySelectionService()
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            accessibilitySelectionService: service
        )
        let coordinator = GlobalCaptureCoordinator(store: store)

        coordinator.prepareAccessibilitySelectionCapture()
        for _ in 0..<100 {
            if await service.readCount() > 0 { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        coordinator.cancelPendingCapture()
        await service.complete(
            with: .success(
                AccessibilitySelectionSnapshot(
                    text: "Late selection",
                    sourceApplication: "TextEdit",
                    selectionBoundsInAXScreenCoordinates: .zero
                )
            )
        )
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertNil(store.quickCaptureDraft)
        XCTAssertNil(store.quickCaptureError)
        XCTAssertNil(store.accessibilitySelectionError)
        XCTAssertEqual(coordinator.quickCapturePresentationRequest, 0)
    }

    func testPreparingScreenshotCaptureKeepsImageTransientAndDefaultsToGPT() async {
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([1, 2, 3]),
                        mediaType: "image/png",
                        sourceApplication: "Preview"
                    )
                )
            )
        )

        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        XCTAssertEqual(store.quickCaptureDraft?.kind, .screenshot)
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "")
        XCTAssertEqual(store.quickCaptureDraft?.sourceApplication, "Preview")
        XCTAssertEqual(store.screenshotPreviewData, Data([1, 2, 3]))
        XCTAssertEqual(store.screenshotExtractionMode, .gpt)
    }

    func testGPTScreenshotExtractionAddsExactTextToSourceOnly() async throws {
        let client = RecordingAPIClient(screenshotOCRText: "Exact GPT text")
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([1, 2, 3]),
                        mediaType: "image/png",
                        sourceApplication: "Safari"
                    )
                )
            )
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)

        let extracted = await store.extractScreenshotText()

        XCTAssertTrue(extracted)
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "Exact GPT text")
        XCTAssertEqual(store.quickCaptureDraft?.userNote, "")
        XCTAssertEqual(store.screenshotExtractionSummary, "gpt-5.6 · Cloud extraction")
        let recordedOCRRequest = await client.lastOCRRequest()
        let request = try XCTUnwrap(recordedOCRRequest)
        XCTAssertEqual(Data(base64Encoded: request.imageBase64), Data([1, 2, 3]))
    }

    func testAppleVisionScreenshotExtractionStaysLocalAndUsesSameDraftPath() async {
        let client = RecordingAPIClient()
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([4, 5, 6]),
                        mediaType: "image/png",
                        sourceApplication: "Preview"
                    )
                )
            ),
            localScreenshotExtractor: LocalExtractorStub(result: .success("Local text"))
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        store.screenshotExtractionMode = .appleVision

        let extracted = await store.extractScreenshotText()

        XCTAssertTrue(extracted)
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "Local text")
        XCTAssertEqual(store.quickCaptureDraft?.userNote, "")
        XCTAssertEqual(
            store.screenshotExtractionSummary,
            "Apple Vision · Processed on this Mac"
        )
        let ocrRequestCount = await client.ocrRequestCount()
        XCTAssertEqual(ocrRequestCount, 0)
    }

    func testOversizedLocalScreenshotTextIsRejectedWithoutTruncating() async {
        let oversized = String(
            repeating: "x",
            count: RecallStore.maximumSelectedTextLength + 1
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([7]),
                        mediaType: "image/png",
                        sourceApplication: nil
                    )
                )
            ),
            localScreenshotExtractor: LocalExtractorStub(result: .success(oversized))
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        store.screenshotExtractionMode = .appleVision

        let extracted = await store.extractScreenshotText()

        XCTAssertFalse(extracted)
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "")
        XCTAssertEqual(store.quickCaptureDraft?.userNote, "")
        XCTAssertNotNil(store.quickCaptureError)
    }

    func testLocalScreenshotTextAtSourceLimitIsAcceptedWithoutTruncating() async {
        let exact = String(
            repeating: "x",
            count: RecallStore.maximumSelectedTextLength
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([7, 8]),
                        mediaType: "image/png",
                        sourceApplication: nil
                    )
                )
            ),
            localScreenshotExtractor: LocalExtractorStub(result: .success(exact))
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        store.screenshotExtractionMode = .appleVision

        let extracted = await store.extractScreenshotText()

        XCTAssertTrue(extracted)
        XCTAssertEqual(
            store.quickCaptureDraft?.selectedText.unicodeScalars.count,
            RecallStore.maximumSelectedTextLength
        )
        XCTAssertEqual(store.quickCaptureDraft?.userNote, "")
    }

    func testReExtractionPreservesTheUsersIndependentNote() async {
        let client = RecordingAPIClient(screenshotOCRText: "Original text")
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([8]),
                        mediaType: "image/png",
                        sourceApplication: nil
                    )
                )
            )
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        let firstExtraction = await store.extractScreenshotText()
        XCTAssertTrue(firstExtraction)
        store.quickCaptureDraft?.userNote = "My edited note"

        let extractedAgain = await store.extractScreenshotText()

        XCTAssertTrue(extractedAgain)
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "Original text")
        XCTAssertEqual(store.quickCaptureDraft?.userNote, "My edited note")
        let ocrRequestCount = await client.ocrRequestCount()
        XCTAssertEqual(ocrRequestCount, 2)
    }

    func testClearingDraftDuringExtractionPreventsLateResultFromRestoringIt() async {
        let client = RecordingAPIClient(
            screenshotOCRText: "Late OCR result",
            screenshotOCRDelayNanoseconds: 50_000_000
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([8, 9]),
                        mediaType: "image/png",
                        sourceApplication: nil
                    )
                )
            )
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)

        let extractionTask = Task { await store.extractScreenshotText() }
        await waitUntil { store.isExtractingScreenshot }
        store.clearQuickCapture()
        let extracted = await extractionTask.value

        XCTAssertFalse(extracted)
        XCTAssertNil(store.quickCaptureDraft)
        XCTAssertNil(store.screenshotPreviewData)
        XCTAssertNil(store.screenshotExtractionSummary)
        XCTAssertFalse(store.isExtractingScreenshot)
    }

    func testScreenshotCannotSubmitOlderSourceWhileReExtractionIsRunning() async {
        let client = RecordingAPIClient(
            screenshotOCRText: "Replacement source",
            screenshotOCRDelayNanoseconds: 50_000_000
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([8, 9, 10]),
                        mediaType: "image/png",
                        sourceApplication: nil
                    )
                )
            )
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        store.quickCaptureDraft?.selectedText = "Older source"
        store.quickCaptureDraft?.userNote = "Independent note"

        let extractionTask = Task { await store.extractScreenshotText() }
        await waitUntil { store.isExtractingScreenshot }
        let saved = await store.submitQuickCapture()

        XCTAssertFalse(saved)
        XCTAssertTrue(store.quickCaptureError?.contains("finish") == true)
        let creationCount = await client.creationCount()
        XCTAssertEqual(creationCount, 0)
        store.clearQuickCapture()
        _ = await extractionTask.value
    }

    func testScreenshotTextSavesThroughExistingCapturePipelineAndClearsImage() async throws {
        let client = RecordingAPIClient(
            createStatus: .ready,
            screenshotOCRText: "Screenshot note"
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([9]),
                        mediaType: "image/png",
                        sourceApplication: "Keynote"
                    )
                )
            )
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        let extracted = await store.extractScreenshotText()
        XCTAssertTrue(extracted)
        store.quickCaptureDraft?.userNote = "Use this wording in tomorrow's demo."

        let saved = await store.submitQuickCapture()
        XCTAssertTrue(saved)
        let recordedCreateRequest = await client.lastCreateRequest()
        let request = try XCTUnwrap(recordedCreateRequest)
        XCTAssertEqual(request.sourceType, .screenshot)
        XCTAssertEqual(request.sourceApp, "Keynote")
        XCTAssertEqual(request.selectedText, "Screenshot note")
        XCTAssertEqual(request.userNote, "Use this wording in tomorrow's demo.")

        store.clearQuickCapture()
        XCTAssertNil(store.screenshotPreviewData)
        XCTAssertNil(store.quickCaptureDraft)
    }

    func testScreenshotCanSaveOriginalImageWithOptionalBackgroundAnalysis() async throws {
        let client = RecordingAPIClient(createStatus: .ready)
        let imageData = Data([1, 2, 3, 4])
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            imageAnalysisIsEnabled: true,
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: imageData,
                        mediaType: "image/png",
                        sourceApplication: "Gemini"
                    )
                )
            )
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        XCTAssertTrue(store.screenshotImageAnalysisIsEnabled)
        store.screenshotNoteKind = .image
        store.quickCaptureDraft?.userNote = "Find the logistic derivation later."

        let saved = await store.submitQuickCapture()
        XCTAssertTrue(saved)

        let requests = await client.allImageCreateRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.imageData, imageData)
        XCTAssertEqual(request.mediaType, "image/png")
        XCTAssertEqual(request.metadata.sourceApp, "Gemini")
        XCTAssertEqual(request.metadata.userNote, "Find the logistic derivation later.")
        XCTAssertTrue(request.metadata.analyzeImage)
        let textCreationCount = await client.creationCount()
        XCTAssertEqual(textCreationCount, 0)
        XCTAssertNotNil(store.selectedCapture?.primaryImageAttachment)
        XCTAssertEqual(store.selectedCapture?.selectedText, "")
    }

    func testImageAnalysisDefaultPersistsWhileDraftChoiceCanBeOverridden() async {
        let suiteName = "RecallStoreTests.image-analysis.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            imageAnalysisIsEnabled: false,
            imageAnalysisPreferenceUserDefaults: defaults
        )

        store.imageAnalysisIsEnabled = true

        XCTAssertTrue(defaults.bool(forKey: RecallStore.imageAnalysisUserDefaultsKey))
        store.screenshotImageAnalysisIsEnabled = false
        XCTAssertTrue(store.imageAnalysisIsEnabled)
        XCTAssertTrue(defaults.bool(forKey: RecallStore.imageAnalysisUserDefaultsKey))
    }

    func testImageAnalysisDraftOverrideIsSentWithoutChangingFutureDefault() async throws {
        let client = RecordingAPIClient(createStatus: .ready)
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            imageAnalysisIsEnabled: true,
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([7, 8, 9]),
                        mediaType: "image/png",
                        sourceApplication: "Preview"
                    )
                )
            )
        )

        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        store.screenshotNoteKind = .image
        store.screenshotImageAnalysisIsEnabled = false
        let saved = await store.submitQuickCapture()
        XCTAssertTrue(saved)

        let requests = await client.allImageCreateRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertFalse(request.metadata.analyzeImage)
        XCTAssertTrue(store.imageAnalysisIsEnabled)
    }

    func testImageAnalysisMasterSwitchBlocksDraftOverrideAndUploadFlag() async throws {
        let client = RecordingAPIClient(createStatus: .ready)
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            imageAnalysisIsEnabled: false,
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([4, 5, 6]),
                        mediaType: "image/png",
                        sourceApplication: "Preview"
                    )
                )
            )
        )

        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        store.screenshotNoteKind = .image
        store.screenshotImageAnalysisIsEnabled = true
        XCTAssertFalse(store.screenshotImageAnalysisWillRun)

        let saved = await store.submitQuickCapture()
        XCTAssertTrue(saved)
        let requests = await client.allImageCreateRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertFalse(request.metadata.analyzeImage)

        store.imageAnalysisIsEnabled = true
        XCTAssertTrue(store.screenshotImageAnalysisIsEnabled)
        XCTAssertTrue(store.screenshotImageAnalysisWillRun)
        store.imageAnalysisIsEnabled = false
        XCTAssertFalse(store.screenshotImageAnalysisIsEnabled)
        XCTAssertFalse(store.screenshotImageAnalysisWillRun)
    }

    func testAttachmentImageLoadsOnceAndDeleteRemovesTheMemory() async throws {
        let client = RecordingAPIClient(createStatus: .ready)
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([4, 5, 6]),
                        mediaType: "image/png",
                        sourceApplication: "Preview"
                    )
                )
            )
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        store.screenshotNoteKind = .image
        let saved = await store.submitQuickCapture()
        XCTAssertTrue(saved)
        let capture = try XCTUnwrap(store.selectedCapture)
        let attachment = try XCTUnwrap(capture.primaryImageAttachment)

        await store.loadAttachmentImage(attachment)
        XCTAssertEqual(store.attachmentImageData[attachment.id], Data([9, 8, 7]))
        let deleted = await store.deleteCapture(id: capture.id)
        XCTAssertTrue(deleted)

        let deletedIDs = await client.allDeletedCaptureIDs()
        XCTAssertEqual(deletedIDs, [capture.id])
        XCTAssertNil(store.selectedCapture)
        XCTAssertNil(store.attachmentImageData[attachment.id])
    }

    func testClosingDuringAmbiguousSavePreservesRetryAndBlocksANewDraft() async throws {
        let client = RecordingAPIClient(
            failFirstCreate: true,
            createStatus: .ready,
            createDelayNanoseconds: 50_000_000
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .success(
                    ClipboardSnapshot(text: "New clipboard", sourceApplication: "TextEdit")
                )
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .success(
                    ScreenshotSnapshot(
                        imageData: Data([11, 12, 13]),
                        mediaType: "image/png",
                        sourceApplication: "Preview"
                    )
                )
            )
        )
        let prepared = await store.prepareScreenshotCapture()
        XCTAssertTrue(prepared)
        store.quickCaptureDraft?.selectedText = "Original screenshot source"
        store.quickCaptureDraft?.userNote = "Original personal note"
        XCTAssertNotNil(store.screenshotPreviewData)

        let firstSave = Task { await store.submitQuickCapture() }
        await waitUntil { store.isSubmittingCapture }
        store.dismissQuickCapturePresentation()

        XCTAssertNil(store.screenshotPreviewData)
        XCTAssertNotNil(store.quickCaptureDraft)
        XCTAssertTrue(store.isQuickCaptureRetryLocked)
        XCTAssertFalse(store.prepareClipboardCapture())
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "Original screenshot source")

        let firstSaved = await firstSave.value
        XCTAssertFalse(firstSaved)
        XCTAssertFalse(store.prepareClipboardCapture())
        XCTAssertEqual(store.quickCaptureDraft?.userNote, "Original personal note")

        let retried = await store.submitQuickCapture()
        XCTAssertTrue(retried)
        let requests = await client.allCreateRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0], requests[1])
    }

    func testUnsubmittedDraftIsNotReplacedByAnotherCapture() async {
        let screenshotService = CountingScreenshotService(
            result: .success(
                ScreenshotSnapshot(
                    imageData: Data([21]),
                    mediaType: "image/png",
                    sourceApplication: "Preview"
                )
            )
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .success(
                    ClipboardSnapshot(text: "Keep this draft", sourceApplication: "TextEdit")
                )
            ),
            screenshotCaptureService: screenshotService
        )
        XCTAssertTrue(store.prepareClipboardCapture())
        store.quickCaptureDraft?.userNote = "Do not overwrite"
        let originalID = store.quickCaptureDraft?.clientCaptureID

        let prepared = await store.prepareScreenshotCapture()

        XCTAssertFalse(prepared)
        XCTAssertEqual(screenshotService.callCount, 0)
        XCTAssertEqual(store.quickCaptureDraft?.clientCaptureID, originalID)
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "Keep this draft")
        XCTAssertEqual(store.quickCaptureDraft?.userNote, "Do not overwrite")
        XCTAssertTrue(store.quickCaptureError?.contains("Finish or cancel") == true)
    }

    func testConcurrentScreenshotPreparationLaunchesOnlyOneSelector() async {
        let screenshotService = SuspendedScreenshotService()
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: screenshotService
        )

        let firstPreparation = Task { await store.prepareScreenshotCapture() }
        await waitUntil { store.isPreparingScreenshot }

        let secondPrepared = await store.prepareScreenshotCapture()

        XCTAssertFalse(secondPrepared)
        XCTAssertEqual(screenshotService.callCount, 1)
        screenshotService.complete(
            with: .success(
                ScreenshotSnapshot(
                    imageData: Data([22]),
                    mediaType: "image/png",
                    sourceApplication: "Preview"
                )
            )
        )
        let firstPrepared = await firstPreparation.value
        XCTAssertTrue(firstPrepared)
        XCTAssertFalse(store.isPreparingScreenshot)
    }

    func testGlobalCaptureCoordinatorDoesNotPresentAfterScreenshotCancellation() async {
        let screenshotService = CountingScreenshotService(
            result: .failure(ScreenshotCaptureError.cancelled)
        )
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: screenshotService
        )
        let coordinator = GlobalCaptureCoordinator(store: store)

        coordinator.prepareScreenshotCapture()
        await waitUntil { screenshotService.callCount == 1 }
        await waitUntil { !store.isPreparingScreenshot }

        XCTAssertEqual(coordinator.quickCapturePresentationRequest, 0)
        XCTAssertNil(store.quickCaptureDraft)
        XCTAssertNil(store.screenshotPreviewData)
    }

    func testScreenshotPermissionDenialHasActionableSystemSettingsMessage() async {
        let service = SystemScreenshotCaptureService(
            permissionService: ScreenCapturePermissionStub(
                authorized: false,
                requestGranted: false
            ),
            codeSigningIdentityService: CodeSigningIdentityStub(isStable: true)
        )

        do {
            _ = try await service.captureInteractive()
            XCTFail("Expected Screen Recording permission denial")
        } catch {
            XCTAssertEqual(error as? ScreenshotCaptureError, .permissionDenied)
            XCTAssertTrue(error.localizedDescription.contains("System Settings"))
            XCTAssertTrue(error.localizedDescription.contains("Screen"))
        }
    }

    func testScreenshotPermissionErrorIsPublishedForTheUnavailableWindow() async {
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            screenshotCaptureService: ScreenshotServiceStub(
                result: .failure(ScreenshotCaptureError.permissionDenied)
            )
        )

        let prepared = await store.prepareScreenshotCapture()
        XCTAssertFalse(prepared)
        XCTAssertNil(store.quickCaptureDraft)
        XCTAssertTrue(store.quickCaptureError?.contains("System Settings") == true)
        XCTAssertTrue(store.notice?.message.contains("System Settings") == true)
    }

    func testPreparingClipboardCapturePreservesTextAndSourceApplication() {
        let client = RecordingAPIClient()
        let service = ClipboardServiceStub(
            result: .success(
                ClipboardSnapshot(
                    text: "Exact clipboard source",
                    sourceApplication: "TextEdit"
                )
            )
        )
        let store = RecallStore(client: client, clipboardService: service)

        XCTAssertTrue(store.prepareClipboardCapture())
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, "Exact clipboard source")
        XCTAssertEqual(store.quickCaptureDraft?.sourceApplication, "TextEdit")
        XCTAssertNil(store.quickCaptureError)
    }

    func testPreparingClipboardCaptureBoundsDerivedSourceApplication() {
        let client = RecordingAPIClient()
        let source = String(
            repeating: "s",
            count: RecallStore.maximumSourceApplicationLength + 1
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .success(
                    ClipboardSnapshot(text: "Exact clipboard source", sourceApplication: source)
                )
            )
        )

        XCTAssertTrue(store.prepareClipboardCapture())
        XCTAssertEqual(
            store.quickCaptureDraft?.sourceApplication?.unicodeScalars.count,
            RecallStore.maximumSourceApplicationLength
        )
    }

    func testOversizedSelectionIsNotSubmittedOrTruncated() async {
        let client = RecordingAPIClient()
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )
        let original = String(repeating: "a", count: RecallStore.maximumSelectedTextLength + 1)
        store.quickCaptureDraft = QuickCaptureDraft(
            selectedText: original,
            sourceApplication: "TextEdit"
        )

        let saved = await store.submitQuickCapture()

        XCTAssertFalse(saved)
        XCTAssertEqual(store.quickCaptureDraft?.selectedText, original)
        XCTAssertNotNil(store.quickCaptureError)
        let creationCount = await client.creationCount()
        XCTAssertEqual(creationCount, 0)
    }

    func testOversizedNoteIsNotSubmittedOrTruncated() async {
        let client = RecordingAPIClient()
        let original = String(repeating: "n", count: RecallStore.maximumUserNoteLength + 1)
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )
        store.quickCaptureDraft = QuickCaptureDraft(
            selectedText: "Keep the source",
            sourceApplication: "TextEdit",
            userNote: original
        )

        let saved = await store.submitQuickCapture()

        XCTAssertFalse(saved)
        XCTAssertEqual(store.quickCaptureDraft?.userNote, original)
        XCTAssertNotNil(store.quickCaptureError)
        let creationCount = await client.creationCount()
        XCTAssertEqual(creationCount, 0)
    }

    func testNoteAtContractLimitCanBeSubmitted() async throws {
        let client = RecordingAPIClient(createStatus: .ready)
        let note = String(repeating: "n", count: RecallStore.maximumUserNoteLength)
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )
        store.quickCaptureDraft = QuickCaptureDraft(
            selectedText: "Keep the source",
            sourceApplication: "TextEdit",
            userNote: note
        )

        let saved = await store.submitQuickCapture()
        let recordedRequest = await client.lastCreateRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertTrue(saved)
        XCTAssertEqual(request.userNote, note)
        XCTAssertTrue(store.activePollingCaptureIDs.isEmpty)
    }

    func testRetryReusesCompleteCreateRequestAfterResponseFailure() async throws {
        let client = RecordingAPIClient(failFirstCreate: true, createStatus: .ready)
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )
        store.quickCaptureDraft = QuickCaptureDraft(
            selectedText: "A response can be lost after persistence.",
            sourceApplication: "Preview",
            userNote: "Retry safely.",
            clientCaptureID: "1667edbf-4f34-4367-8347-8556fda61bbd",
            capturedAt: "2026-07-19T12:00:00.000Z"
        )

        let firstAttempt = await store.submitQuickCapture()
        let secondAttempt = await store.submitQuickCapture()
        XCTAssertFalse(firstAttempt)
        XCTAssertTrue(secondAttempt)

        let requests = await client.allCreateRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0], requests[1])
        XCTAssertEqual(
            requests[1].clientCaptureID,
            "1667edbf-4f34-4367-8347-8556fda61bbd"
        )
        XCTAssertEqual(requests[1].capturedAt, "2026-07-19T12:00:00.000Z")
        XCTAssertTrue(store.activePollingCaptureIDs.isEmpty)
    }

    func testRetryRejectsEditsThatCouldBeLostToIdempotentReplay() async {
        let client = RecordingAPIClient(failFirstCreate: true, createStatus: .ready)
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )
        store.quickCaptureDraft = QuickCaptureDraft(
            selectedText: "A response may be lost after persistence.",
            sourceApplication: "Preview",
            userNote: "Original note"
        )

        let firstAttempt = await store.submitQuickCapture()
        XCTAssertFalse(firstAttempt)
        XCTAssertTrue(store.isQuickCaptureRetryLocked)
        store.quickCaptureDraft?.userNote = "Edited after the ambiguous failure"

        let retried = await store.submitQuickCapture()

        XCTAssertFalse(retried)
        XCTAssertTrue(store.quickCaptureError?.contains("original") == true)
        let creationCount = await client.creationCount()
        XCTAssertEqual(creationCount, 1)
    }

    func testSearchRejectsOversizedAndControlCharacterQueriesLocally() async {
        let client = RecordingAPIClient()
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )

        store.query = String(repeating: "q", count: RecallStore.maximumSearchQueryLength + 1)
        await store.search(debounce: false)
        XCTAssertNotNil(store.searchError)

        store.query = "line\nbreak"
        await store.search(debounce: false)
        XCTAssertNotNil(store.searchError)

        store.query = "delete\u{007F}character"
        await store.search(debounce: false)
        XCTAssertNotNil(store.searchError)
        let searchCount = await client.searchCount()
        XCTAssertEqual(searchCount, 0)
    }

    func testSearchAtContractLimitIsSent() async {
        let client = RecordingAPIClient()
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )
        store.query = String(repeating: "q", count: RecallStore.maximumSearchQueryLength)

        await store.search(debounce: false)

        XCTAssertNil(store.searchError)
        let searchCount = await client.searchCount()
        XCTAssertEqual(searchCount, 1)
    }

    func testInvalidQueryClearsAnOlderSearchProgressState() async {
        let client = RecordingAPIClient(searchDelayNanoseconds: 100_000_000)
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )
        store.query = "valid query"

        let olderSearch = Task { await store.search(debounce: false) }
        await waitUntil { store.isSearching }

        store.query = String(
            repeating: "q",
            count: RecallStore.maximumSearchQueryLength + 1
        )
        await store.search(debounce: false)

        XCTAssertFalse(store.isSearching)
        XCTAssertNotNil(store.searchError)
        olderSearch.cancel()
        await olderSearch.value
    }

    func testSearchFailureDoesNotMasqueradeAsLocalSearchResults() async {
        let client = RecordingAPIClient(
            listedCaptures: Capture.previewSamples,
            searchFailure: .http(
                statusCode: 500,
                code: "internal_error",
                message: "Search failed."
            )
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )
        await store.loadLibrary(initial: true)
        store.query = "systemd"

        await store.search(debounce: false)

        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertEqual(store.searchError, "Search failed.")
        let searchCount = await client.searchCount()
        XCTAssertEqual(searchCount, 1)
    }

    func testForegroundRefreshSkipsWhileServerSearchIsActive() async {
        let client = RecordingAPIClient(searchDelayNanoseconds: 100_000_000)
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            foregroundRefreshIntervalNanoseconds: 1_000_000
        )
        await store.loadLibrary(initial: true)
        store.query = "server search"

        let searchTask = Task { await store.search(debounce: false) }
        await waitUntil { store.isSearching }
        let refreshTask = Task { await store.runForegroundRefreshLoop() }
        try? await Task.sleep(nanoseconds: 20_000_000)

        let listRequestCount = await client.listRequestCount()
        XCTAssertEqual(listRequestCount, 1)
        refreshTask.cancel()
        searchTask.cancel()
        await refreshTask.value
        await searchTask.value
    }

    func testPollingStopsAndCleansUpWhenCaptureBecomesReady() async {
        let client = RecordingAPIClient(
            createStatus: .processing,
            pollStatus: .ready
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            pollingIntervalNanoseconds: 1_000_000,
            pollingAttemptLimit: 3
        )
        store.quickCaptureDraft = QuickCaptureDraft(
            selectedText: "Poll this capture",
            sourceApplication: "Xcode"
        )

        let saved = await store.submitQuickCapture()
        XCTAssertTrue(saved)
        await waitUntil {
            store.captures.first?.status == .ready
                && store.activePollingCaptureIDs.isEmpty
        }

        XCTAssertEqual(store.captures.first?.status, .ready)
        let detailRequestCount = await client.detailRequestCount()
        XCTAssertEqual(detailRequestCount, 1)
    }

    func testDegradedHealthIsDistinctFromOffline() async {
        let client = RecordingAPIClient(
            healthResponse: HealthResponse(
                status: "degraded",
                database: "error",
                openAIConfigured: false
            )
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )

        await store.checkHealth()

        XCTAssertEqual(store.connectionState, .degraded)
    }

    func testAPIFailureDoesNotOverwriteDegradedHealthState() async {
        let client = RecordingAPIClient(
            listFailure: .http(
                statusCode: 500,
                code: "database_unavailable",
                message: "Storage unavailable."
            ),
            healthResponse: HealthResponse(
                status: "degraded",
                database: "error",
                openAIConfigured: true
            )
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )

        await store.checkHealth()
        await store.loadLibrary(initial: true)

        XCTAssertEqual(store.connectionState, .degraded)
    }

    func testPollingUsesWallClockDeadlineAndCleansUp() async {
        let client = RecordingAPIClient(
            createStatus: .processing,
            pollStatus: .processing,
            detailDelayNanoseconds: 1_000_000_000
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            pollingIntervalNanoseconds: 1_000_000,
            pollingAttemptLimit: 30,
            pollingTimeoutNanoseconds: 100_000_000
        )
        store.quickCaptureDraft = QuickCaptureDraft(
            selectedText: "Deadline-bound polling",
            sourceApplication: "Xcode"
        )

        let saved = await store.submitQuickCapture()
        XCTAssertTrue(saved)
        await waitUntil { store.activePollingCaptureIDs.isEmpty }

        XCTAssertEqual(store.captures.first?.status, .processing)
        let detailRequestCount = await client.detailRequestCount()
        XCTAssertEqual(detailRequestCount, 1)
    }

    func testSuccessfulSubmissionInsertsProcessingCaptureAndPreservesLayers() async throws {
        let client = RecordingAPIClient()
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            pollingAttemptLimit: 0
        )
        store.quickCaptureDraft = QuickCaptureDraft(
            selectedText: "The original selection",
            sourceApplication: "Preview",
            userNote: "  Keep my spacing and reason.  "
        )

        let saved = await store.submitQuickCapture()

        XCTAssertTrue(saved)
        let recordedRequest = await client.lastCreateRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.selectedText, "The original selection")
        XCTAssertEqual(request.sourceApp, "Preview")
        XCTAssertEqual(request.userNote, "  Keep my spacing and reason.  ")
        XCTAssertEqual(store.captures.first?.selectedText, request.selectedText)
        XCTAssertEqual(store.captures.first?.userNote, request.userNote)
        XCTAssertEqual(store.captures.first?.status, .processing)
        XCTAssertEqual(store.selectedCaptureID, store.captures.first?.id)
    }

    func testClipboardWarningAutomaticallyExpires() async {
        let store = RecallStore(
            client: RecordingAPIClient(),
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            noticeTimeoutOverrideNanoseconds: 1_000_000
        )

        XCTAssertFalse(store.prepareClipboardCapture())
        XCTAssertEqual(store.notice?.scope, .clipboard)
        await waitUntil { store.notice == nil }
    }

    func testSortPreferenceRequestsBackendAndPersists() async {
        let suiteName = "RecallStoreTests.sort.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = RecordingAPIClient()
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            ),
            sortingPreferenceUserDefaults: defaults
        )

        await store.start()
        await store.setSortOrder(.editedOldest)

        XCTAssertEqual(store.sortOrder, .editedOldest)
        XCTAssertEqual(
            defaults.string(forKey: RecallStore.captureSortOrderUserDefaultsKey),
            CaptureSortOrder.editedOldest.rawValue
        )
        let requests = await client.allRequestedSortOrders()
        XCTAssertEqual(requests, [.createdNewest, .editedOldest])
    }

    func testUpdateCapturePublishesUserLayerAndStaleAIState() async throws {
        let original = try JSONDecoder().decode(
            Capture.self,
            from: ContractFixtures.readyCaptureData()
        )
        var updated = original
        updated.userEditedAt = "2026-07-21T20:00:00Z"
        updated.userTitle = "My title"
        updated.userTags = ["manual"]
        updated.aiContentStale = true
        updated.aiInterpretationHidden = true
        let client = RecordingAPIClient(
            listedCaptures: [original],
            updateResponse: updated
        )
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
        )
        await store.start()
        let request = CaptureUpdateRequest(
            selectedText: "Corrected source",
            userNote: "Updated note",
            sourceApp: nil,
            sourceTitle: nil,
            sourceURL: nil,
            userTitle: "My title",
            userProblem: nil,
            userKeyInsight: nil,
            userWhySaved: nil,
            userCaveats: nil,
            userTags: ["manual"],
            showAIInterpretation: true
        )

        let saved = await store.updateCapture(id: original.id, request: request)

        XCTAssertTrue(saved)
        XCTAssertEqual(store.selectedCapture?.displayTitle, "My title")
        XCTAssertEqual(store.selectedCapture?.displayTags, ["manual"])
        XCTAssertTrue(store.selectedCapture?.aiContentStale == true)
        XCTAssertEqual(store.notice?.style, .warning)
        let requests = await client.allUpdateRequests()
        XCTAssertEqual(requests, [request])
    }

    private func waitUntil(
        timeoutIterations: Int = 100,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for asynchronous store state")
    }
}

@MainActor
private struct ClipboardServiceStub: ClipboardCaptureServing {
    let result: Result<ClipboardSnapshot, Error>

    func readSnapshot() throws -> ClipboardSnapshot {
        try result.get()
    }
}

@MainActor
private struct ScreenshotServiceStub: ScreenshotCaptureServing {
    let result: Result<ScreenshotSnapshot, Error>

    func captureInteractive() async throws -> ScreenshotSnapshot {
        try result.get()
    }
}

private actor AccessibilitySelectionServiceStub: AccessibilitySelectionServing {
    private let result: Result<AccessibilitySelectionSnapshot, AccessibilitySelectionError>
    private var reads = 0
    private var readPrompts: [Bool] = []
    private var trustChecks: [Bool] = []

    init(result: Result<AccessibilitySelectionSnapshot, AccessibilitySelectionError>) {
        self.result = result
    }

    func isTrusted(promptIfNeeded: Bool) async -> Bool {
        trustChecks.append(promptIfNeeded)
        return true
    }

    func readSelection(
        promptIfNeeded: Bool
    ) async throws -> AccessibilitySelectionSnapshot {
        reads += 1
        readPrompts.append(promptIfNeeded)
        return try result.get()
    }

    func readSelectionForClipboardFallback(
        promptIfNeeded: Bool
    ) async throws -> AccessibilitySelectionReadOutcome {
        reads += 1
        readPrompts.append(promptIfNeeded)
        do {
            return .selection(try result.get())
        } catch let error where error == .selectionUnavailable {
            return .clipboardFallback(
                AccessibilitySelectionFallbackTicket(
                    processIdentifier: 4_242,
                    sourceApplication: "WeChat"
                )
            )
        } catch {
            throw error
        }
    }

    func readCount() -> Int { reads }
    func readPromptValues() -> [Bool] { readPrompts }
}

private actor SuspendedAccessibilitySelectionService: AccessibilitySelectionServing {
    private var continuation: CheckedContinuation<AccessibilitySelectionSnapshot, Error>?
    private var reads = 0

    func isTrusted(promptIfNeeded: Bool) async -> Bool { true }

    func readSelection(
        promptIfNeeded: Bool
    ) async throws -> AccessibilitySelectionSnapshot {
        reads += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func readSelectionForClipboardFallback(
        promptIfNeeded: Bool
    ) async throws -> AccessibilitySelectionReadOutcome {
        .selection(try await readSelection(promptIfNeeded: promptIfNeeded))
    }

    func readCount() -> Int { reads }

    func complete(with result: Result<AccessibilitySelectionSnapshot, Error>) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}

@MainActor
private final class SelectionClipboardFallbackServiceStub:
    SelectionClipboardFallbackServing
{
    private let result: Result<AccessibilitySelectionSnapshot, Error>
    private(set) var captureCount = 0
    private(set) var capturedTickets: [AccessibilitySelectionFallbackTicket] = []

    init(result: Result<AccessibilitySelectionSnapshot, Error>) {
        self.result = result
    }

    func captureSelection(
        using ticket: AccessibilitySelectionFallbackTicket
    ) async throws -> AccessibilitySelectionSnapshot {
        captureCount += 1
        capturedTickets.append(ticket)
        return try result.get()
    }
}

@MainActor
private final class CountingScreenshotService: ScreenshotCaptureServing {
    private let result: Result<ScreenshotSnapshot, Error>
    private(set) var callCount = 0

    init(result: Result<ScreenshotSnapshot, Error>) {
        self.result = result
    }

    func captureInteractive() async throws -> ScreenshotSnapshot {
        callCount += 1
        return try result.get()
    }
}

@MainActor
private final class SuspendedScreenshotService: ScreenshotCaptureServing {
    private var continuation: CheckedContinuation<ScreenshotSnapshot, Error>?
    private(set) var callCount = 0

    func captureInteractive() async throws -> ScreenshotSnapshot {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(with result: Result<ScreenshotSnapshot, Error>) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}

private struct ScreenCapturePermissionStub: ScreenCapturePermissionServing {
    let authorized: Bool
    let requestGranted: Bool

    func isAuthorized() -> Bool { authorized }
    func requestAccess() -> Bool { requestGranted }
}

private struct CodeSigningIdentityStub: CodeSigningIdentityServing {
    let isStable: Bool

    var hasStablePrivacyIdentity: Bool { isStable }
}

private struct LocalExtractorStub: LocalScreenshotTextExtracting {
    let result: Result<String, ScreenshotTextExtractionError>

    func extractText(from imageData: Data) async throws -> String {
        try result.get()
    }
}

private actor RecordingAPIClient: RecallAPIClient {
    private var createRequests: [CaptureCreateRequest] = []
    private var imageCreateRequests: [ImageCaptureUploadRequest] = []
    private var deletedCaptureIDs: [String] = []
    private var updateRequests: [CaptureUpdateRequest] = []
    private var requestedSortOrders: [CaptureSortOrder] = []
    private var searchQueries: [String] = []
    private var detailRequests = 0
    private var listRequests = 0
    private var ocrRequests: [ScreenshotOCRRequest] = []
    private var shouldFailNextCreate: Bool
    private let createStatus: CaptureStatus
    private let createDelayNanoseconds: UInt64
    private let pollStatus: CaptureStatus?
    private let detailDelayNanoseconds: UInt64
    private let listedCaptures: [Capture]
    private let listFailure: RecallAPIError?
    private let searchFailure: RecallAPIError?
    private let searchDelayNanoseconds: UInt64
    private let healthResponse: HealthResponse
    private let screenshotOCRText: String
    private let screenshotOCRDelayNanoseconds: UInt64
    private let updateResponse: Capture?

    init(
        failFirstCreate: Bool = false,
        createStatus: CaptureStatus = .processing,
        createDelayNanoseconds: UInt64 = 0,
        pollStatus: CaptureStatus? = nil,
        detailDelayNanoseconds: UInt64 = 0,
        listedCaptures: [Capture] = [],
        listFailure: RecallAPIError? = nil,
        searchFailure: RecallAPIError? = nil,
        searchDelayNanoseconds: UInt64 = 0,
        screenshotOCRText: String = "Extracted screenshot text",
        screenshotOCRDelayNanoseconds: UInt64 = 0,
        updateResponse: Capture? = nil,
        healthResponse: HealthResponse = HealthResponse(
            status: "ok",
            database: "ok",
            openAIConfigured: false
        )
    ) {
        shouldFailNextCreate = failFirstCreate
        self.createStatus = createStatus
        self.createDelayNanoseconds = createDelayNanoseconds
        self.pollStatus = pollStatus
        self.detailDelayNanoseconds = detailDelayNanoseconds
        self.listedCaptures = listedCaptures
        self.listFailure = listFailure
        self.searchFailure = searchFailure
        self.searchDelayNanoseconds = searchDelayNanoseconds
        self.healthResponse = healthResponse
        self.screenshotOCRText = screenshotOCRText
        self.screenshotOCRDelayNanoseconds = screenshotOCRDelayNanoseconds
        self.updateResponse = updateResponse
    }

    func creationCount() -> Int {
        createRequests.count
    }

    func lastCreateRequest() -> CaptureCreateRequest? {
        createRequests.last
    }

    func allCreateRequests() -> [CaptureCreateRequest] {
        createRequests
    }

    func allImageCreateRequests() -> [ImageCaptureUploadRequest] {
        imageCreateRequests
    }

    func allDeletedCaptureIDs() -> [String] {
        deletedCaptureIDs
    }

    func allUpdateRequests() -> [CaptureUpdateRequest] {
        updateRequests
    }

    func allRequestedSortOrders() -> [CaptureSortOrder] {
        requestedSortOrders
    }

    func searchCount() -> Int {
        searchQueries.count
    }

    func detailRequestCount() -> Int {
        detailRequests
    }

    func listRequestCount() -> Int {
        listRequests
    }

    func ocrRequestCount() -> Int {
        ocrRequests.count
    }

    func lastOCRRequest() -> ScreenshotOCRRequest? {
        ocrRequests.last
    }

    func health() async throws -> HealthResponse {
        healthResponse
    }

    func createCapture(_ request: CaptureCreateRequest) async throws -> Capture {
        createRequests.append(request)
        if createDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: createDelayNanoseconds)
        }
        if shouldFailNextCreate {
            shouldFailNextCreate = false
            throw URLError(.timedOut)
        }
        return capture(from: request, status: createStatus)
    }

    func createImageCapture(_ request: ImageCaptureUploadRequest) async throws -> Capture {
        imageCreateRequests.append(request)
        if createDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: createDelayNanoseconds)
        }
        if shouldFailNextCreate {
            shouldFailNextCreate = false
            throw URLError(.timedOut)
        }
        return imageCapture(from: request, status: createStatus)
    }

    func listCaptures(limit: Int, offset: Int) async throws -> CaptureListEnvelope {
        listRequests += 1
        if let listFailure {
            throw listFailure
        }
        return CaptureListEnvelope(
            items: listedCaptures,
            limit: limit,
            offset: offset
        )
    }

    func listCaptures(
        limit: Int,
        offset: Int,
        sort: CaptureSortOrder
    ) async throws -> CaptureListEnvelope {
        requestedSortOrders.append(sort)
        return try await listCaptures(limit: limit, offset: offset)
    }

    func getCapture(id: String) async throws -> Capture {
        detailRequests += 1
        if detailDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: detailDelayNanoseconds)
        }
        if let pollStatus,
           let request = createRequests.last {
            return capture(from: request, status: pollStatus)
        }
        if let pollStatus,
           let request = imageCreateRequests.last {
            return imageCapture(from: request, status: pollStatus)
        }
        throw RecallAPIError.http(
            statusCode: 404,
            code: "capture_not_found",
            message: "Capture was not found."
        )
    }

    func updateCapture(id: String, request: CaptureUpdateRequest) async throws -> Capture {
        updateRequests.append(request)
        guard let updateResponse else {
            throw RecallAPIError.http(
                statusCode: 501,
                code: "capture_update_unavailable",
                message: "Capture editing is not configured in this test."
            )
        }
        return updateResponse
    }

    func search(query: String, limit: Int) async throws -> SearchResponse {
        searchQueries.append(query)
        if searchDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: searchDelayNanoseconds)
        }
        if let searchFailure {
            throw searchFailure
        }
        return SearchResponse(query: query, results: [])
    }

    func enrich(id: String) async throws -> Capture {
        throw RecallAPIError.http(
            statusCode: 404,
            code: "capture_not_found",
            message: "Capture was not found."
        )
    }

    func attachmentData(contentPath: String) async throws -> Data {
        Data([9, 8, 7])
    }

    func deleteCapture(id: String) async throws {
        deletedCaptureIDs.append(id)
    }

    func extractScreenshotText(_ request: ScreenshotOCRRequest) async throws -> ScreenshotOCRResponse {
        ocrRequests.append(request)
        if screenshotOCRDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: screenshotOCRDelayNanoseconds)
        }
        return ScreenshotOCRResponse(
            text: screenshotOCRText,
            provider: .openai,
            processingLocation: .cloud,
            model: "gpt-5.6"
        )
    }

    private func capture(
        from request: CaptureCreateRequest,
        status: CaptureStatus
    ) -> Capture {
        let timestamp = "2026-07-18T22:00:00.123456Z"
        return Capture(
            id: "4b3a30b7-55d9-4ef8-93ef-34281c826e52",
            clientCaptureID: request.clientCaptureID,
            createdAt: timestamp,
            updatedAt: timestamp,
            capturedAt: request.capturedAt,
            status: status,
            sourceType: request.sourceType,
            sourceApp: request.sourceApp,
            sourceTitle: request.sourceTitle,
            sourceURL: request.sourceURL,
            selectedText: request.selectedText,
            surroundingContext: request.surroundingContext,
            contextTruncated: request.contextTruncated,
            userNote: request.userNote,
            aiTitle: nil,
            aiSummary: nil,
            problem: nil,
            keyInsight: nil,
            whySaved: nil,
            caveats: [],
            tags: [],
            entities: [],
            searchAliases: [],
            errorMessage: nil,
            enrichmentVersion: 1
        )
    }

    private func imageCapture(
        from request: ImageCaptureUploadRequest,
        status: CaptureStatus
    ) -> Capture {
        let timestamp = "2026-07-21T17:30:00.123456Z"
        let attachmentID = "4cfe5742-43e0-4bf4-9f79-bec7ef9954c2"
        return Capture(
            id: "4b3a30b7-55d9-4ef8-93ef-34281c826e52",
            clientCaptureID: request.metadata.clientCaptureID,
            createdAt: timestamp,
            updatedAt: timestamp,
            capturedAt: request.metadata.capturedAt,
            status: status,
            sourceType: .screenshot,
            sourceApp: request.metadata.sourceApp,
            sourceTitle: nil,
            sourceURL: nil,
            selectedText: "",
            surroundingContext: nil,
            contextTruncated: false,
            userNote: request.metadata.userNote,
            aiTitle: nil,
            aiSummary: nil,
            problem: nil,
            keyInsight: nil,
            whySaved: nil,
            caveats: [],
            tags: [],
            entities: [],
            searchAliases: [],
            errorMessage: nil,
            enrichmentVersion: 1,
            attachments: [
                CaptureAttachment(
                    id: attachmentID,
                    kind: "image",
                    mediaType: request.mediaType,
                    byteSize: request.imageData.count,
                    pixelWidth: 10,
                    pixelHeight: 8,
                    sha256: String(repeating: "a", count: 64),
                    contentPath: "/v1/attachments/\(attachmentID)/content"
                )
            ]
        )
    }
}
