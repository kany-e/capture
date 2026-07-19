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

private actor RecordingAPIClient: RecallAPIClient {
    private var createRequests: [CaptureCreateRequest] = []
    private var searchQueries: [String] = []
    private var detailRequests = 0
    private var listRequests = 0
    private var shouldFailNextCreate: Bool
    private let createStatus: CaptureStatus
    private let pollStatus: CaptureStatus?
    private let detailDelayNanoseconds: UInt64
    private let listedCaptures: [Capture]
    private let listFailure: RecallAPIError?
    private let searchFailure: RecallAPIError?
    private let searchDelayNanoseconds: UInt64
    private let healthResponse: HealthResponse

    init(
        failFirstCreate: Bool = false,
        createStatus: CaptureStatus = .processing,
        pollStatus: CaptureStatus? = nil,
        detailDelayNanoseconds: UInt64 = 0,
        listedCaptures: [Capture] = [],
        listFailure: RecallAPIError? = nil,
        searchFailure: RecallAPIError? = nil,
        searchDelayNanoseconds: UInt64 = 0,
        healthResponse: HealthResponse = HealthResponse(
            status: "ok",
            database: "ok",
            openAIConfigured: false
        )
    ) {
        shouldFailNextCreate = failFirstCreate
        self.createStatus = createStatus
        self.pollStatus = pollStatus
        self.detailDelayNanoseconds = detailDelayNanoseconds
        self.listedCaptures = listedCaptures
        self.listFailure = listFailure
        self.searchFailure = searchFailure
        self.searchDelayNanoseconds = searchDelayNanoseconds
        self.healthResponse = healthResponse
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

    func searchCount() -> Int {
        searchQueries.count
    }

    func detailRequestCount() -> Int {
        detailRequests
    }

    func listRequestCount() -> Int {
        listRequests
    }

    func health() async throws -> HealthResponse {
        healthResponse
    }

    func createCapture(_ request: CaptureCreateRequest) async throws -> Capture {
        createRequests.append(request)
        if shouldFailNextCreate {
            shouldFailNextCreate = false
            throw URLError(.timedOut)
        }
        return capture(from: request, status: createStatus)
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

    func getCapture(id: String) async throws -> Capture {
        detailRequests += 1
        if detailDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: detailDelayNanoseconds)
        }
        if let pollStatus,
           let request = createRequests.last {
            return capture(from: request, status: pollStatus)
        }
        throw RecallAPIError.http(
            statusCode: 404,
            code: "capture_not_found",
            message: "Capture was not found."
        )
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
}
