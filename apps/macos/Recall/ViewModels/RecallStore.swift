import Foundation

struct QuickCaptureDraft: Equatable, Sendable {
    let clientCaptureID: String
    let capturedAt: String
    let selectedText: String
    let sourceApplication: String?
    var userNote: String = ""

    init(
        selectedText: String,
        sourceApplication: String?,
        userNote: String = "",
        clientCaptureID: String = UUID().uuidString.lowercased(),
        capturedAt: String = CaptureCreateRequest.currentTimestamp()
    ) {
        self.clientCaptureID = clientCaptureID
        self.capturedAt = capturedAt
        self.selectedText = selectedText
        self.sourceApplication = sourceApplication
        self.userNote = userNote
    }

    var characterCount: Int {
        selectedText.unicodeScalars.count
    }

    var noteCharacterCount: Int {
        userNote.unicodeScalars.count
    }
}

enum BackendConnectionState: Equatable, Sendable {
    case checking
    case connected(openAIConfigured: Bool)
    case degraded
    case disconnected
}

enum LibraryLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

struct AppNotice: Identifiable, Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case information
        case warning
        case error
    }

    let id = UUID()
    let style: Style
    let message: String
}

@MainActor
final class RecallStore: ObservableObject {
    static let maximumSelectedTextLength = 12_000
    static let maximumUserNoteLength = 4_000
    static let maximumSearchQueryLength = 512
    static let maximumSourceApplicationLength = 200

    @Published private(set) var captures: [Capture] = []
    @Published var selectedCaptureID: String?
    @Published var query = ""
    @Published private(set) var connectionState: BackendConnectionState = .checking
    @Published private(set) var loadState: LibraryLoadState = .idle
    @Published private(set) var isSearching = false
    @Published private(set) var searchError: String?
    @Published var quickCaptureDraft: QuickCaptureDraft?
    @Published private(set) var isSubmittingCapture = false
    @Published var quickCaptureError: String?
    @Published var notice: AppNotice?
    @Published private(set) var searchFocusToken = UUID()

    private let client: any RecallAPIClient
    private let clipboardService: any ClipboardCaptureServing
    private var libraryCaptures: [Capture] = []
    private var pollingTasks: [String: Task<Void, Never>] = [:]
    private var pollingGenerations: [String: UUID] = [:]
    private var hasStarted = false
    private var searchEndpointUnavailable = false
    private var didExplainSearchFallback = false
    private var searchGeneration = 0
    private var attemptedQuickCaptureRequest: CaptureCreateRequest?
    private let foregroundRefreshIntervalNanoseconds: UInt64
    private let pollingIntervalNanoseconds: UInt64
    private let pollingAttemptLimit: Int
    private let pollingTimeoutNanoseconds: UInt64

    init(
        client: any RecallAPIClient,
        clipboardService: any ClipboardCaptureServing,
        foregroundRefreshIntervalNanoseconds: UInt64 = 5_000_000_000,
        pollingIntervalNanoseconds: UInt64 = 2_000_000_000,
        pollingAttemptLimit: Int = 30,
        pollingTimeoutNanoseconds: UInt64 = 60_000_000_000
    ) {
        self.client = client
        self.clipboardService = clipboardService
        self.foregroundRefreshIntervalNanoseconds = foregroundRefreshIntervalNanoseconds
        self.pollingIntervalNanoseconds = pollingIntervalNanoseconds
        self.pollingAttemptLimit = pollingAttemptLimit
        self.pollingTimeoutNanoseconds = pollingTimeoutNanoseconds
    }

    convenience init(client: any RecallAPIClient = LiveRecallAPIClient()) {
        self.init(
            client: client,
            clipboardService: SystemClipboardCaptureService()
        )
    }

    var selectedCapture: Capture? {
        guard let selectedCaptureID else { return nil }
        return captures.first(where: { $0.id == selectedCaptureID })
            ?? libraryCaptures.first(where: { $0.id == selectedCaptureID })
    }

    var activePollingCaptureIDs: Set<String> {
        Set(pollingTasks.keys)
    }

    var isQuickCaptureRetryLocked: Bool {
        attemptedQuickCaptureRequest != nil
    }

    func start() async {
        guard !hasStarted else {
            await refresh()
            return
        }
        hasStarted = true
        async let healthCheck: Void = checkHealth()
        async let libraryLoad: Void = loadLibrary(initial: true)
        _ = await (healthCheck, libraryLoad)
    }

    func checkHealth() async {
        if connectionState == .disconnected || connectionState == .degraded {
            connectionState = .checking
        }
        do {
            let response = try await client.health()
            if response.status == "ok" && response.database == "ok" {
                connectionState = .connected(openAIConfigured: response.openAIConfigured)
            } else {
                connectionState = .degraded
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Self.isCancellation(error) else { return }
            connectionState = .disconnected
        }
    }

    func refresh() async {
        if query.nonEmptyTrimmed == nil {
            await loadLibrary(initial: false)
        } else {
            // A manual refresh is also an explicit probe for a backend that may
            // have gained the search route since this app session began.
            searchEndpointUnavailable = false
            await search(debounce: false)
        }
        await checkHealth()
    }

    func runForegroundRefreshLoop() async {
        while !Task.isCancelled {
            do {
                // A low-frequency list refresh discovers captures created by the
                // Chrome extension. Captures created by this app use the focused
                // two-second detail poll in `beginPolling` instead.
                try await Task.sleep(
                    nanoseconds: foregroundRefreshIntervalNanoseconds
                )
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            if query.nonEmptyTrimmed == nil {
                await loadLibrary(initial: false, silent: true)
            } else if searchEndpointUnavailable {
                await loadLibrary(initial: false, silent: true)
                captures = localMatches(for: query)
                preserveSelection()
            } else if !isSearching {
                await search(debounce: false, silent: true)
            }
        }
    }

    func loadLibrary(
        initial: Bool,
        silent: Bool = false
    ) async {
        if initial {
            loadState = .loading
        }

        do {
            let response = try await client.listCaptures(limit: 50, offset: 0)
            libraryCaptures = response.items
            if query.nonEmptyTrimmed == nil {
                captures = response.items
            }
            preserveSelection()
            connectionState = connectedStatePreservingAIConfiguration()
            loadState = .loaded
        } catch {
            guard !Self.isCancellation(error) else { return }
            updateConnectionState(after: error)
            if initial || libraryCaptures.isEmpty {
                loadState = .failed(error.recallUserMessage)
            } else if !silent {
                notice = AppNotice(style: .error, message: error.recallUserMessage)
            }
        }
    }

    func search(debounce: Bool = true, silent: Bool = false) async {
        searchGeneration &+= 1
        let generation = searchGeneration
        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedQuery.isEmpty else {
            searchError = nil
            isSearching = false
            captures = libraryCaptures
            preserveSelection()
            if libraryCaptures.isEmpty {
                await loadLibrary(initial: loadState == .idle)
            }
            return
        }

        if let validationMessage = Self.searchValidationMessage(for: submittedQuery) {
            searchError = validationMessage
            isSearching = false
            captures = []
            preserveSelection()
            return
        }

        isSearching = true
        defer {
            if generation == searchGeneration {
                isSearching = false
            }
        }

        if debounce {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
        }
        guard generation == searchGeneration,
              !Task.isCancelled,
              submittedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }

        if searchEndpointUnavailable {
            searchError = nil
            captures = localMatches(for: submittedQuery)
            preserveSelection()
            return
        }

        do {
            let response = try await client.search(query: submittedQuery, limit: 50)
            guard generation == searchGeneration,
                  !Task.isCancelled,
                  submittedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            searchError = nil
            captures = response.results.map(\.capture)
            preserveSelection()
            connectionState = connectedStatePreservingAIConfiguration()
        } catch let error as RecallAPIError where error.statusCode == 404 {
            guard generation == searchGeneration,
                  !Task.isCancelled,
                  submittedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            searchEndpointUnavailable = true
            await loadLibrary(initial: false, silent: true)
            guard generation == searchGeneration,
                  !Task.isCancelled,
                  submittedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            searchError = nil
            captures = localMatches(for: submittedQuery)
            preserveSelection()
            if !didExplainSearchFallback && !silent {
                didExplainSearchFallback = true
                notice = AppNotice(
                    style: .information,
                    message: "Search service is not available yet. Showing matches from the loaded library."
                )
            }
        } catch {
            guard !Self.isCancellation(error),
                  generation == searchGeneration,
                  !Task.isCancelled,
                  submittedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            searchError = error.recallUserMessage
            captures = []
            preserveSelection()
            updateConnectionState(after: error)
        }
    }

    func refreshSelectedCapture() async {
        guard let selectedCaptureID else { return }
        do {
            let capture = try await client.getCapture(id: selectedCaptureID)
            upsert(capture)
        } catch let error as RecallAPIError where error.code == "capture_not_found" {
            removeCapture(id: selectedCaptureID)
            notice = AppNotice(style: .warning, message: error.localizedDescription)
        } catch {
            guard !Self.isCancellation(error) else { return }
            updateConnectionState(after: error)
            notice = AppNotice(style: .error, message: error.recallUserMessage)
        }
    }

    @discardableResult
    func prepareClipboardCapture() -> Bool {
        do {
            let snapshot = try clipboardService.readSnapshot()
            quickCaptureDraft = QuickCaptureDraft(
                selectedText: snapshot.text,
                sourceApplication: snapshot.sourceApplication.map {
                    Self.prefixUnicodeScalars(
                        $0,
                        limit: Self.maximumSourceApplicationLength
                    )
                }
            )
            attemptedQuickCaptureRequest = nil
            quickCaptureError = nil
            return true
        } catch {
            quickCaptureDraft = nil
            attemptedQuickCaptureRequest = nil
            quickCaptureError = error.recallUserMessage
            notice = AppNotice(style: .warning, message: error.recallUserMessage)
            return false
        }
    }

    func submitQuickCapture() async -> Bool {
        guard let draft = quickCaptureDraft else { return false }
        guard !isSubmittingCapture else { return false }

        guard draft.characterCount <= Self.maximumSelectedTextLength else {
            quickCaptureError = "The selection is \(draft.characterCount.formatted()) characters. Recall can save up to \(Self.maximumSelectedTextLength.formatted()) characters without losing the original text."
            return false
        }

        guard draft.noteCharacterCount <= Self.maximumUserNoteLength else {
            quickCaptureError = "The note is \(draft.noteCharacterCount.formatted()) characters. Recall can save notes up to \(Self.maximumUserNoteLength.formatted()) characters. Your draft has not been changed."
            return false
        }

        let note = draft.userNote.nonEmptyTrimmed == nil ? nil : draft.userNote
        let currentRequest = CaptureCreateRequest.clipboard(
            clientCaptureID: draft.clientCaptureID,
            capturedAt: draft.capturedAt,
            text: draft.selectedText,
            sourceApp: draft.sourceApplication,
            userNote: note
        )

        let request: CaptureCreateRequest
        if let attemptedQuickCaptureRequest {
            guard attemptedQuickCaptureRequest == currentRequest else {
                quickCaptureError = "A previous save may already exist, so Recall must retry the original source and note. Cancel and capture again if you want to change the note."
                return false
            }
            request = attemptedQuickCaptureRequest
        } else {
            request = currentRequest
            attemptedQuickCaptureRequest = currentRequest
        }

        isSubmittingCapture = true
        quickCaptureError = nil
        defer { isSubmittingCapture = false }

        do {
            let capture = try await client.createCapture(request)
            query = ""
            upsert(capture, insertAtFront: true)
            selectedCaptureID = capture.id
            connectionState = connectedStatePreservingAIConfiguration()
            switch capture.status {
            case .processing:
                notice = AppNotice(
                    style: .information,
                    message: "Saved. Recall is processing this memory."
                )
                beginPolling(captureID: capture.id)
            case .ready:
                notice = AppNotice(
                    style: .information,
                    message: "Saved. This memory is ready."
                )
            case .error:
                notice = AppNotice(
                    style: .warning,
                    message: "Saved, but AI processing needs attention. Your source and note are safe."
                )
            case .captured:
                notice = AppNotice(
                    style: .warning,
                    message: "Saved, but processing has not started. Refresh or retry AI from the memory detail."
                )
            }
            return true
        } catch {
            guard !Self.isCancellation(error) else { return false }
            quickCaptureError = error.recallUserMessage
            updateConnectionState(after: error)
            return false
        }
    }

    func clearQuickCapture() {
        quickCaptureDraft = nil
        attemptedQuickCaptureRequest = nil
        quickCaptureError = nil
    }

    func retryEnrichment(id: String) async {
        do {
            let capture = try await client.enrich(id: id)
            upsert(capture)
            notice = AppNotice(style: .information, message: "AI processing restarted.")
            beginPolling(captureID: id)
        } catch let error as RecallAPIError where error.code == "capture_already_processing" {
            notice = AppNotice(style: .information, message: error.localizedDescription)
            beginPolling(captureID: id)
        } catch let error as RecallAPIError where error.code == "openai_not_configured" {
            notice = AppNotice(style: .warning, message: error.localizedDescription)
        } catch {
            guard !Self.isCancellation(error) else { return }
            updateConnectionState(after: error)
            notice = AppNotice(style: .error, message: error.recallUserMessage)
        }
    }

    func requestSearchFocus() {
        searchFocusToken = UUID()
    }

    func dismissNotice() {
        notice = nil
    }

    private func beginPolling(captureID: String) {
        pollingTasks[captureID]?.cancel()
        let generation = UUID()
        pollingGenerations[captureID] = generation
        pollingTasks[captureID] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.finishPolling(captureID: captureID, generation: generation)
            }

            let startedAt = DispatchTime.now().uptimeNanoseconds
            let deadline = startedAt &+ self.pollingTimeoutNanoseconds

            for _ in 0..<self.pollingAttemptLimit {
                let beforeSleep = DispatchTime.now().uptimeNanoseconds
                guard beforeSleep < deadline else { break }
                do {
                    try await Task.sleep(
                        nanoseconds: min(
                            self.pollingIntervalNanoseconds,
                            deadline - beforeSleep
                        )
                    )
                } catch {
                    return
                }
                let beforeRequest = DispatchTime.now().uptimeNanoseconds
                guard beforeRequest < deadline else { break }
                do {
                    let capture = try await Self.captureBeforeDeadline(
                        client: self.client,
                        captureID: captureID,
                        timeoutNanoseconds: deadline - beforeRequest
                    )
                    self.upsert(capture)
                    if capture.status == .ready || capture.status == .error {
                        return
                    }
                } catch is PollingDeadlineReached {
                    break
                } catch {
                    guard !Self.isCancellation(error) else { return }
                    self.updateConnectionState(after: error)
                }
            }

            guard self.libraryCaptures.first(where: { $0.id == captureID })?.status == .processing else {
                return
            }
            self.notice = AppNotice(
                style: .information,
                message: "This memory is still processing. Its original content is safely saved; refresh later for updates."
            )
        }
    }

    private func finishPolling(captureID: String, generation: UUID) {
        guard pollingGenerations[captureID] == generation else { return }
        pollingTasks[captureID] = nil
        pollingGenerations[captureID] = nil
    }

    private static func captureBeforeDeadline(
        client: any RecallAPIClient,
        captureID: String,
        timeoutNanoseconds: UInt64
    ) async throws -> Capture {
        try await withThrowingTaskGroup(of: Capture.self) { group in
            group.addTask {
                try await client.getCapture(id: captureID)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw PollingDeadlineReached()
            }
            defer { group.cancelAll() }
            guard let capture = try await group.next() else {
                throw PollingDeadlineReached()
            }
            return capture
        }
    }

    private func connectedStatePreservingAIConfiguration() -> BackendConnectionState {
        if case let .connected(openAIConfigured) = connectionState {
            return .connected(openAIConfigured: openAIConfigured)
        }
        return .connected(openAIConfigured: false)
    }

    static func searchValidationMessage(for query: String) -> String? {
        let characterCount = query.unicodeScalars.count
        if characterCount > maximumSearchQueryLength {
            return "Search can use up to \(maximumSearchQueryLength.formatted()) characters; this query has \(characterCount.formatted())."
        }
        if query.unicodeScalars.contains(
            where: { $0.value < 32 || $0.value == 127 }
        ) {
            return "Search cannot contain line breaks, tabs, or other control characters."
        }
        return nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError || Task.isCancelled {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }

    private static func prefixUnicodeScalars(_ value: String, limit: Int) -> String {
        guard value.unicodeScalars.count > limit else { return value }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: value.unicodeScalars.prefix(limit))
        return String(result)
    }

    private func updateConnectionState(after error: Error) {
        if let urlError = error as? URLError,
           urlError.code != .cancelled {
            connectionState = .disconnected
        } else if error is RecallAPIError,
                  connectionState != .degraded {
            connectionState = connectedStatePreservingAIConfiguration()
        }
    }

    private func upsert(_ capture: Capture, insertAtFront: Bool = false) {
        if let index = libraryCaptures.firstIndex(where: { $0.id == capture.id }) {
            libraryCaptures[index] = capture
        } else if insertAtFront {
            libraryCaptures.insert(capture, at: 0)
        } else {
            libraryCaptures.append(capture)
        }

        if query.nonEmptyTrimmed == nil {
            captures = libraryCaptures
        } else if let index = captures.firstIndex(where: { $0.id == capture.id }) {
            captures[index] = capture
        }
    }

    private func removeCapture(id: String) {
        libraryCaptures.removeAll(where: { $0.id == id })
        captures.removeAll(where: { $0.id == id })
        if selectedCaptureID == id {
            selectedCaptureID = captures.first?.id
        }
    }

    private func preserveSelection() {
        if let selectedCaptureID,
           captures.contains(where: { $0.id == selectedCaptureID }) {
            return
        }
        selectedCaptureID = captures.first?.id
    }

    private func localMatches(for query: String) -> [Capture] {
        let terms = query
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return libraryCaptures }

        return libraryCaptures.filter { capture in
            let searchableText = [
                capture.displayTitle,
                capture.sourceTitle,
                capture.sourceApp,
                capture.aiSummary,
                capture.problem,
                capture.keyInsight,
                capture.whySaved,
                capture.userNote,
                capture.selectedText,
                capture.surroundingContext,
                capture.tags.joined(separator: " "),
                capture.entities.joined(separator: " "),
                capture.searchAliases.joined(separator: " "),
            ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()

            return terms.allSatisfy(searchableText.contains)
        }
    }
}

private struct PollingDeadlineReached: Error {}
