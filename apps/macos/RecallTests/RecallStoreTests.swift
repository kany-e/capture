import Foundation
import XCTest

@testable import Recall

@MainActor
final class RecallStoreTests: XCTestCase {
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

    func testSuccessfulSubmissionInsertsProcessingCaptureAndPreservesLayers() async throws {
        let client = RecordingAPIClient()
        let store = RecallStore(
            client: client,
            clipboardService: ClipboardServiceStub(
                result: .failure(ClipboardCaptureError.noText)
            )
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
}

@MainActor
private struct ClipboardServiceStub: ClipboardCaptureServing {
    let result: Result<ClipboardSnapshot, Error>

    func readSnapshot() throws -> ClipboardSnapshot {
        try result.get()
    }
}

private actor RecordingAPIClient: RecallAPIClient {
    private var createRequests: [CaptureCreateRequest] = []

    func creationCount() -> Int {
        createRequests.count
    }

    func lastCreateRequest() -> CaptureCreateRequest? {
        createRequests.last
    }

    func health() async throws -> HealthResponse {
        HealthResponse(status: "ok", database: "ok", openAIConfigured: false)
    }

    func createCapture(_ request: CaptureCreateRequest) async throws -> Capture {
        createRequests.append(request)
        return capture(from: request)
    }

    func listCaptures(limit: Int, offset: Int) async throws -> CaptureListEnvelope {
        CaptureListEnvelope(items: [], limit: limit, offset: offset)
    }

    func getCapture(id: String) async throws -> Capture {
        throw RecallAPIError.http(
            statusCode: 404,
            code: "capture_not_found",
            message: "Capture was not found."
        )
    }

    func search(query: String, limit: Int) async throws -> SearchResponse {
        SearchResponse(query: query, results: [])
    }

    func enrich(id: String) async throws -> Capture {
        throw RecallAPIError.http(
            statusCode: 404,
            code: "capture_not_found",
            message: "Capture was not found."
        )
    }

    private func capture(from request: CaptureCreateRequest) -> Capture {
        let timestamp = "2026-07-18T22:00:00.123456Z"
        return Capture(
            id: UUID().uuidString.lowercased(),
            clientCaptureID: request.clientCaptureID,
            createdAt: timestamp,
            updatedAt: timestamp,
            capturedAt: request.capturedAt,
            status: .processing,
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
}
