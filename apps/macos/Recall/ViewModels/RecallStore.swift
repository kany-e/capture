import Foundation

struct QuickCaptureDraft: Equatable, Sendable {
    let selectedText: String
    let sourceApplication: String?
    var userNote: String = ""

    var characterCount: Int {
        selectedText.unicodeScalars.count
    }
}

enum BackendConnectionState: Equatable, Sendable {
    case checking
    case connected(openAIConfigured: Bool)
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

    @Published private(set) var captures: [Capture] = []
    @Published var selectedCaptureID: String?
    @Published var query = ""
    @Published private(set) var connectionState: BackendConnectionState = .checking
    @Published private(set) var loadState: LibraryLoadState = .idle
    @Published private(set) var isSearching = false
    @Published var quickCaptureDraft: QuickCaptureDraft?
    @Published private(set) var isSubmittingCapture = false
    @Published var quickCaptureError: String?
    @Published var notice: AppNotice?
    @Published private(set) var searchFocusToken = UUID()

    private let client: any RecallAPIClient
    private let clipboardService: any ClipboardCaptureServing
    private var libraryCaptures: [Capture] = []
    private var pollingTasks: [String: Task<Void, Never>] = [:]
    private var hasStarted = false
    private var searchEndpointUnavailable = false
    private var didExplainSearchFallback = false

    init(
        client: any RecallAPIClient,
        clipboardService: any ClipboardCaptureServing
    ) {
        self.client = client
        self.clipboardService = clipboardService
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
        if connectionState == .disconnected {
            connectionState = .checking
        }
        do {
            let response = try await client.health()
            connectionState = .connected(openAIConfigured: response.openAIConfigured)
        } catch is CancellationError {
            return
        } catch {
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
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            if query.nonEmptyTrimmed == nil {
                await loadLibrary(initial: false, silent: true)
            } else if !searchEndpointUnavailable {
                await search(debounce: false, silent: true)
            } else {
                await loadLibrary(initial: false, silent: true)
                captures = localMatches(for: query)
                preserveSelection()
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
        } catch is CancellationError {
            return
        } catch {
            connectionState = .disconnected
            if initial || libraryCaptures.isEmpty {
                loadState = .failed(error.recallUserMessage)
            } else if !silent {
                notice = AppNotice(style: .error, message: error.recallUserMessage)
            }
        }
    }

    func search(debounce: Bool = true, silent: Bool = false) async {
        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedQuery.isEmpty else {
            captures = libraryCaptures
            preserveSelection()
            if libraryCaptures.isEmpty {
                await loadLibrary(initial: loadState == .idle)
            }
            return
        }

        if debounce {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
        }
        guard submittedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }

        if searchEndpointUnavailable {
            captures = localMatches(for: submittedQuery)
            preserveSelection()
            return
        }

        isSearching = true
        defer { isSearching = false }
        do {
            let response = try await client.search(query: submittedQuery, limit: 50)
            guard submittedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            captures = response.results.map(\.capture)
            preserveSelection()
            connectionState = connectedStatePreservingAIConfiguration()
        } catch is CancellationError {
            return
        } catch let error as RecallAPIError where error.statusCode == 404 {
            searchEndpointUnavailable = true
            await loadLibrary(initial: false, silent: true)
            guard submittedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
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
            captures = localMatches(for: submittedQuery)
            preserveSelection()
            if !silent {
                notice = AppNotice(style: .error, message: error.recallUserMessage)
            }
        }
    }

    func refreshSelectedCapture() async {
        guard let selectedCaptureID else { return }
        do {
            let capture = try await client.getCapture(id: selectedCaptureID)
            upsert(capture)
        } catch is CancellationError {
            return
        } catch let error as RecallAPIError where error.code == "capture_not_found" {
            removeCapture(id: selectedCaptureID)
            notice = AppNotice(style: .warning, message: error.localizedDescription)
        } catch {
            notice = AppNotice(style: .error, message: error.recallUserMessage)
        }
    }

    @discardableResult
    func prepareClipboardCapture() -> Bool {
        do {
            let snapshot = try clipboardService.readSnapshot()
            quickCaptureDraft = QuickCaptureDraft(
                selectedText: snapshot.text,
                sourceApplication: snapshot.sourceApplication
            )
            quickCaptureError = nil
            return true
        } catch {
            quickCaptureDraft = nil
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

        let note = draft.userNote.nonEmptyTrimmed == nil ? nil : draft.userNote
        let request = CaptureCreateRequest.clipboard(
            text: draft.selectedText,
            sourceApp: draft.sourceApplication,
            userNote: note
        )

        isSubmittingCapture = true
        quickCaptureError = nil
        defer { isSubmittingCapture = false }

        do {
            let capture = try await client.createCapture(request)
            query = ""
            upsert(capture, insertAtFront: true)
            selectedCaptureID = capture.id
            connectionState = connectedStatePreservingAIConfiguration()
            notice = AppNotice(style: .information, message: "Saved. Recall is processing this memory.")
            beginPolling(captureID: capture.id)
            return true
        } catch is CancellationError {
            return false
        } catch {
            quickCaptureError = error.recallUserMessage
            if error is URLError {
                connectionState = .disconnected
            }
            return false
        }
    }

    func clearQuickCapture() {
        quickCaptureDraft = nil
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
        pollingTasks[captureID] = Task { [weak self] in
            for _ in 0..<30 {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    return
                }
                guard let self else { return }
                do {
                    let capture = try await self.client.getCapture(id: captureID)
                    self.upsert(capture)
                    if capture.status == .ready || capture.status == .error {
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if let urlError = error as? URLError,
                       urlError.code == .cannotConnectToHost {
                        self.connectionState = .disconnected
                    }
                }
            }

            guard let self,
                  self.libraryCaptures.first(where: { $0.id == captureID })?.status == .processing else {
                return
            }
            self.notice = AppNotice(
                style: .information,
                message: "This memory is still processing. Its original content is safely saved; refresh later for updates."
            )
        }
    }

    private func connectedStatePreservingAIConfiguration() -> BackendConnectionState {
        if case let .connected(openAIConfigured) = connectionState {
            return .connected(openAIConfigured: openAIConfigured)
        }
        return .connected(openAIConfigured: false)
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
