import Foundation

struct QuickCaptureDraft: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case selection
        case clipboard
        case screenshot
    }

    let clientCaptureID: String
    let capturedAt: String
    let kind: Kind
    var selectedText: String
    let sourceApplication: String?
    let selectionCaptureMethod: NativeSelectionCaptureMethod?
    var userNote: String = ""

    init(
        selectedText: String,
        sourceApplication: String?,
        userNote: String = "",
        kind: Kind = .clipboard,
        selectionCaptureMethod: NativeSelectionCaptureMethod? = nil,
        clientCaptureID: String = UUID().uuidString.lowercased(),
        capturedAt: String = CaptureCreateRequest.currentTimestamp()
    ) {
        self.clientCaptureID = clientCaptureID
        self.capturedAt = capturedAt
        self.kind = kind
        self.selectedText = selectedText
        self.sourceApplication = sourceApplication
        self.selectionCaptureMethod = selectionCaptureMethod
        self.userNote = userNote
    }

    var characterCount: Int {
        selectedText.unicodeScalars.count
    }

    var noteCharacterCount: Int {
        userNote.unicodeScalars.count
    }
}

enum ScreenshotExtractionMode: String, CaseIterable, Identifiable, Sendable {
    case gpt
    case appleVision

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gpt: "GPT · Cloud"
        case .appleVision: "Apple Vision · On device"
        }
    }
}

enum ScreenshotNoteKind: String, CaseIterable, Identifiable, Sendable {
    case image
    case text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .image: "Image note"
        case .text: "Text note"
        }
    }
}

private enum PendingQuickCaptureRequest: Equatable, Sendable {
    case text(CaptureCreateRequest)
    case image(ImageCaptureUploadRequest)
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

    enum Scope: Equatable, Sendable {
        case general
        case connection
        case clipboard
        case processing(String)
    }

    enum Lifetime: Equatable, Sendable {
        case timed(UInt64)
        case untilStateChanges
        case persistent
    }

    let id = UUID()
    let style: Style
    let message: String
    let scope: Scope
    let lifetime: Lifetime

    init(
        style: Style,
        message: String,
        scope: Scope = .general,
        lifetime: Lifetime? = nil
    ) {
        self.style = style
        self.message = message
        self.scope = scope
        self.lifetime = lifetime ?? {
            switch style {
            case .information: .timed(4_000_000_000)
            case .warning: .timed(7_000_000_000)
            case .error: .persistent
            }
        }()
    }
}

@MainActor
final class RecallStore: ObservableObject {
    static let selectionClipboardFallbackUserDefaultsKey =
        "selectionClipboardFallbackEnabled.v1"
    static let imageAnalysisUserDefaultsKey = "imageAnalysisEnabled.v1"
    static let captureSortOrderUserDefaultsKey = "captureSortOrder.v1"
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
    @Published private(set) var accessibilitySelectionError: AccessibilitySelectionError?
    @Published private(set) var isPreparingAccessibilitySelection = false
    @Published private(set) var selectionClipboardFallbackIsEnabled: Bool
    @Published private(set) var screenshotPreviewData: Data?
    @Published var screenshotExtractionMode: ScreenshotExtractionMode = .gpt
    @Published var screenshotNoteKind: ScreenshotNoteKind = .text
    @Published var imageAnalysisIsEnabled: Bool {
        didSet {
            imageAnalysisPreferenceUserDefaults?.set(
                imageAnalysisIsEnabled,
                forKey: Self.imageAnalysisUserDefaultsKey
            )
            screenshotImageAnalysisIsEnabled = imageAnalysisIsEnabled
        }
    }
    @Published var screenshotImageAnalysisIsEnabled = false
    var screenshotImageAnalysisWillRun: Bool {
        imageAnalysisIsEnabled && screenshotImageAnalysisIsEnabled
    }
    @Published private(set) var isPreparingScreenshot = false
    @Published private(set) var isExtractingScreenshot = false
    @Published private(set) var screenshotExtractionSummary: String?
    @Published private(set) var sortOrder: CaptureSortOrder
    @Published private(set) var isUpdatingCapture = false
    @Published private(set) var captureUpdateError: String?
    @Published private(set) var notice: AppNotice? {
        didSet { scheduleNoticeDismissal() }
    }
    @Published private(set) var searchFocusToken = UUID()
    @Published private(set) var attachmentImageData: [String: Data] = [:]

    private let client: any RecallAPIClient
    private let clipboardService: any ClipboardCaptureServing
    private let accessibilitySelectionService: any AccessibilitySelectionServing
    private let selectionClipboardFallbackService: any SelectionClipboardFallbackServing
    private let selectionPreferenceUserDefaults: UserDefaults?
    private let imageAnalysisPreferenceUserDefaults: UserDefaults?
    private let sortingPreferenceUserDefaults: UserDefaults?
    private let screenshotCaptureService: any ScreenshotCaptureServing
    private let localScreenshotExtractor: any LocalScreenshotTextExtracting
    private var libraryCaptures: [Capture] = []
    private var pollingTasks: [String: Task<Void, Never>] = [:]
    private var pollingGenerations: [String: UUID] = [:]
    private var hasStarted = false
    private var searchEndpointUnavailable = false
    private var didExplainSearchFallback = false
    private var searchGeneration = 0
    private var attemptedQuickCaptureRequest: PendingQuickCaptureRequest?
    private var loadingAttachmentIDs: Set<String> = []
    private var activeScreenshotExtractionID: UUID?
    private var noticeDismissalTask: Task<Void, Never>?
    private var screenshotMediaType = "image/png"
    private let foregroundRefreshIntervalNanoseconds: UInt64
    private let pollingIntervalNanoseconds: UInt64
    private let pollingAttemptLimit: Int
    private let pollingTimeoutNanoseconds: UInt64
    private let noticeTimeoutOverrideNanoseconds: UInt64?

    init(
        client: any RecallAPIClient,
        clipboardService: any ClipboardCaptureServing,
        accessibilitySelectionService: any AccessibilitySelectionServing = SystemAccessibilitySelectionService(),
        selectionClipboardFallbackService: any SelectionClipboardFallbackServing = SystemSelectionClipboardFallbackService(),
        selectionClipboardFallbackIsEnabled: Bool = false,
        selectionPreferenceUserDefaults: UserDefaults? = nil,
        imageAnalysisIsEnabled: Bool = false,
        imageAnalysisPreferenceUserDefaults: UserDefaults? = nil,
        sortOrder: CaptureSortOrder = .createdNewest,
        sortingPreferenceUserDefaults: UserDefaults? = nil,
        screenshotCaptureService: any ScreenshotCaptureServing = SystemScreenshotCaptureService(),
        localScreenshotExtractor: any LocalScreenshotTextExtracting = AppleVisionScreenshotTextExtractor(),
        foregroundRefreshIntervalNanoseconds: UInt64 = 5_000_000_000,
        pollingIntervalNanoseconds: UInt64 = 2_000_000_000,
        pollingAttemptLimit: Int = 30,
        pollingTimeoutNanoseconds: UInt64 = 60_000_000_000,
        noticeTimeoutOverrideNanoseconds: UInt64? = nil
    ) {
        self.client = client
        self.clipboardService = clipboardService
        self.accessibilitySelectionService = accessibilitySelectionService
        self.selectionClipboardFallbackService = selectionClipboardFallbackService
        self.selectionClipboardFallbackIsEnabled = selectionClipboardFallbackIsEnabled
        self.selectionPreferenceUserDefaults = selectionPreferenceUserDefaults
        self.imageAnalysisIsEnabled = imageAnalysisIsEnabled
        self.screenshotImageAnalysisIsEnabled = imageAnalysisIsEnabled
        self.imageAnalysisPreferenceUserDefaults = imageAnalysisPreferenceUserDefaults
        self.sortOrder = sortOrder
        self.sortingPreferenceUserDefaults = sortingPreferenceUserDefaults
        self.screenshotCaptureService = screenshotCaptureService
        self.localScreenshotExtractor = localScreenshotExtractor
        self.foregroundRefreshIntervalNanoseconds = foregroundRefreshIntervalNanoseconds
        self.pollingIntervalNanoseconds = pollingIntervalNanoseconds
        self.pollingAttemptLimit = pollingAttemptLimit
        self.pollingTimeoutNanoseconds = pollingTimeoutNanoseconds
        self.noticeTimeoutOverrideNanoseconds = noticeTimeoutOverrideNanoseconds
    }

    convenience init(client: any RecallAPIClient = LiveRecallAPIClient()) {
        let userDefaults = UserDefaults.standard
        let sortOrder = CaptureSortOrder(
            rawValue: userDefaults.string(forKey: Self.captureSortOrderUserDefaultsKey) ?? ""
        ) ?? .createdNewest
        self.init(
            client: client,
            clipboardService: SystemClipboardCaptureService(),
            accessibilitySelectionService: SystemAccessibilitySelectionService(),
            selectionClipboardFallbackService: SystemSelectionClipboardFallbackService(),
            selectionClipboardFallbackIsEnabled: userDefaults.bool(
                forKey: Self.selectionClipboardFallbackUserDefaultsKey
            ),
            selectionPreferenceUserDefaults: userDefaults,
            imageAnalysisIsEnabled: userDefaults.bool(
                forKey: Self.imageAnalysisUserDefaultsKey
            ),
            imageAnalysisPreferenceUserDefaults: userDefaults,
            sortOrder: sortOrder,
            sortingPreferenceUserDefaults: userDefaults,
            screenshotCaptureService: SystemScreenshotCaptureService(),
            localScreenshotExtractor: AppleVisionScreenshotTextExtractor()
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

    var quickCaptureCanSubmit: Bool {
        guard let draft = quickCaptureDraft,
              draft.noteCharacterCount <= Self.maximumUserNoteLength,
              draft.characterCount <= Self.maximumSelectedTextLength else {
            return false
        }
        if draft.kind == .screenshot, screenshotNoteKind == .image {
            return screenshotPreviewData != nil
        }
        return draft.characterCount > 0
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
            if response.status == "ok"
                && response.database == "ok"
                && response.attachments == "ok" {
                connectionState = .connected(openAIConfigured: response.openAIConfigured)
                dismissNotice(scope: .connection)
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
            let response = try await client.listCaptures(
                limit: 50,
                offset: 0,
                sort: sortOrder
            )
            libraryCaptures = response.items
            if case let .processing(captureID) = notice?.scope,
               let status = response.items.first(where: { $0.id == captureID })?.status,
               status == .ready || status == .error {
                resolveProcessingNotice(captureID: captureID, status: status)
            }
            if query.nonEmptyTrimmed == nil {
                captures = response.items
            }
            preserveSelection()
            connectionState = connectedStatePreservingAIConfiguration()
            dismissNotice(scope: .connection)
            loadState = .loaded
        } catch {
            guard !Self.isCancellation(error) else { return }
            updateConnectionState(after: error)
            if initial || libraryCaptures.isEmpty {
                loadState = .failed(error.recallUserMessage)
            } else if !silent {
                notice = AppNotice(
                    style: .error,
                    message: error.recallUserMessage,
                    scope: .connection,
                    lifetime: .untilStateChanges
                )
            }
        }
    }

    func setSortOrder(_ newValue: CaptureSortOrder) async {
        guard sortOrder != newValue else { return }
        sortOrder = newValue
        sortingPreferenceUserDefaults?.set(
            newValue.rawValue,
            forKey: Self.captureSortOrderUserDefaultsKey
        )
        sortLibraryCaptures()
        if query.nonEmptyTrimmed == nil {
            captures = libraryCaptures
            preserveSelection()
            await loadLibrary(initial: false, silent: true)
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
            dismissNotice(scope: .connection)
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
            notice = AppNotice(
                style: .error,
                message: error.recallUserMessage,
                scope: error is URLError ? .connection : .general,
                lifetime: error is URLError ? .untilStateChanges : .persistent
            )
        }
    }

    @discardableResult
    func prepareClipboardCapture() -> Bool {
        guard !isPreparingScreenshot, !isPreparingAccessibilitySelection else { return false }
        guard canPrepareNewQuickCapture() else { return false }
        do {
            let snapshot = try clipboardService.readSnapshot()
            invalidateScreenshotExtraction()
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
            accessibilitySelectionError = nil
            screenshotPreviewData = nil
            screenshotExtractionSummary = nil
            screenshotMediaType = "image/png"
            dismissNotice(scope: .clipboard)
            return true
        } catch {
            clearQuickCapture()
            quickCaptureError = error.recallUserMessage
            notice = AppNotice(
                style: .warning,
                message: error.recallUserMessage,
                scope: .clipboard
            )
            return false
        }
    }

    func prepareAccessibilitySelectionCapture(
        promptIfNeeded: Bool = true
    ) async -> AccessibilitySelectionSnapshot? {
        guard !isPreparingScreenshot, !isPreparingAccessibilitySelection else { return nil }
        guard canPrepareNewQuickCapture() else { return nil }
        isPreparingAccessibilitySelection = true
        defer { isPreparingAccessibilitySelection = false }

        do {
            if selectionClipboardFallbackIsEnabled {
                let outcome = try await accessibilitySelectionService
                    .readSelectionForClipboardFallback(promptIfNeeded: promptIfNeeded)
                switch outcome {
                case let .selection(snapshot):
                    return prepareNativeSelectionDraft(from: snapshot)
                case let .clipboardFallback(ticket):
                    do {
                        let snapshot = try await selectionClipboardFallbackService
                            .captureSelection(using: ticket)
                        return prepareNativeSelectionDraft(from: snapshot)
                    } catch {
                        guard !Self.isCancellation(error), !Task.isCancelled else { return nil }
                        let fallbackError = (error as? SelectionClipboardFallbackError)?
                            .accessibilityError ?? .clipboardFallbackUnavailable
                        publishAccessibilitySelectionError(fallbackError)
                        return nil
                    }
                }
            } else {
                let snapshot = try await accessibilitySelectionService.readSelection(
                    promptIfNeeded: promptIfNeeded
                )
                return prepareNativeSelectionDraft(from: snapshot)
            }
        } catch let selectionError as AccessibilitySelectionError {
            guard !Task.isCancelled else { return nil }
            publishAccessibilitySelectionError(selectionError)
            return nil
        } catch {
            guard !Self.isCancellation(error), !Task.isCancelled else { return nil }
            publishAccessibilitySelectionError(.selectionSafetyUnavailable)
            return nil
        }
    }

    func setSelectionClipboardFallbackEnabled(_ isEnabled: Bool) {
        selectionClipboardFallbackIsEnabled = isEnabled
        selectionPreferenceUserDefaults?.set(
            isEnabled,
            forKey: Self.selectionClipboardFallbackUserDefaultsKey
        )
    }

    func accessibilityAccessIsGranted(promptIfNeeded: Bool = false) async -> Bool {
        await accessibilitySelectionService.isTrusted(promptIfNeeded: promptIfNeeded)
    }

    private func prepareNativeSelectionDraft(
        from snapshot: AccessibilitySelectionSnapshot
    ) -> AccessibilitySelectionSnapshot? {
        guard !Task.isCancelled else { return nil }
        let boundedCharacterCount = snapshot.text.unicodeScalars
            .prefix(Self.maximumSelectedTextLength + 1)
            .count
        guard boundedCharacterCount <= Self.maximumSelectedTextLength else {
            publishAccessibilitySelectionError(.selectionTooLong)
            return nil
        }
        guard canPrepareNewQuickCapture() else { return nil }

        invalidateScreenshotExtraction()
        quickCaptureDraft = QuickCaptureDraft(
            selectedText: snapshot.text,
            sourceApplication: snapshot.sourceApplication.map {
                Self.prefixUnicodeScalars(
                    $0,
                    limit: Self.maximumSourceApplicationLength
                )
            },
            kind: .selection,
            selectionCaptureMethod: snapshot.captureMethod
        )
        attemptedQuickCaptureRequest = nil
        quickCaptureError = nil
        accessibilitySelectionError = nil
        screenshotPreviewData = nil
        screenshotExtractionSummary = nil
        screenshotMediaType = "image/png"
        return snapshot
    }

    private func publishAccessibilitySelectionError(
        _ selectionError: AccessibilitySelectionError
    ) {
        clearQuickCapture()
        accessibilitySelectionError = selectionError
        quickCaptureError = selectionError.localizedDescription
        notice = AppNotice(style: .warning, message: selectionError.localizedDescription)
    }

    @discardableResult
    func prepareScreenshotCapture() async -> Bool {
        guard !isPreparingScreenshot, !isPreparingAccessibilitySelection else { return false }
        guard canPrepareNewQuickCapture() else { return false }
        isPreparingScreenshot = true
        defer { isPreparingScreenshot = false }
        do {
            let snapshot = try await screenshotCaptureService.captureInteractive()
            guard !Task.isCancelled else { return false }
            invalidateScreenshotExtraction()
            quickCaptureDraft = QuickCaptureDraft(
                selectedText: "",
                sourceApplication: snapshot.sourceApplication.map {
                    Self.prefixUnicodeScalars(
                        $0,
                        limit: Self.maximumSourceApplicationLength
                    )
                },
                kind: .screenshot
            )
            screenshotPreviewData = snapshot.imageData
            screenshotMediaType = snapshot.mediaType
            screenshotExtractionMode = .gpt
            screenshotNoteKind = .text
            screenshotImageAnalysisIsEnabled = imageAnalysisIsEnabled
            screenshotExtractionSummary = nil
            attemptedQuickCaptureRequest = nil
            quickCaptureError = nil
            accessibilitySelectionError = nil
            return true
        } catch ScreenshotCaptureError.cancelled {
            clearQuickCapture()
            return false
        } catch {
            clearQuickCapture()
            quickCaptureError = error.recallUserMessage
            notice = AppNotice(style: .warning, message: error.recallUserMessage)
            return false
        }
    }

    func extractScreenshotText() async -> Bool {
        guard let draft = quickCaptureDraft,
              draft.kind == .screenshot,
              let screenshotPreviewData else {
            return false
        }
        guard !isExtractingScreenshot else { return false }

        // Calling extraction is an explicit request for the legacy text-note
        // path. The screenshot UI already selects this mode before invoking it,
        // while this assignment keeps programmatic callers unambiguous.
        screenshotNoteKind = .text

        let extractionID = UUID()
        let draftID = draft.clientCaptureID
        let extractionMode = screenshotExtractionMode
        let mediaType = screenshotMediaType
        activeScreenshotExtractionID = extractionID
        isExtractingScreenshot = true
        quickCaptureError = nil
        defer {
            if activeScreenshotExtractionID == extractionID {
                activeScreenshotExtractionID = nil
                isExtractingScreenshot = false
            }
        }

        do {
            let text: String
            let summary: String
            switch extractionMode {
            case .gpt:
                let response = try await client.extractScreenshotText(
                    ScreenshotOCRRequest(
                        mediaType: mediaType,
                        imageBase64: screenshotPreviewData.base64EncodedString()
                    )
                )
                text = response.text
                summary = "\(response.model) · Cloud extraction"
            case .appleVision:
                text = try await localScreenshotExtractor.extractText(
                    from: screenshotPreviewData
                )
                summary = "Apple Vision · Processed on this Mac"
            }

            guard activeScreenshotExtractionID == extractionID,
                  !Task.isCancelled,
                  quickCaptureDraft?.clientCaptureID == draftID else {
                return false
            }
            guard let normalized = text.nonEmptyTrimmed else {
                throw ScreenshotTextExtractionError.noText
            }
            let extractedCount = normalized.unicodeScalars.count
            guard extractedCount <= Self.maximumSelectedTextLength else {
                quickCaptureError = "The screenshot contains \(extractedCount.formatted()) characters. Select a smaller region so it fits the \(Self.maximumSelectedTextLength.formatted())-character source limit."
                return false
            }

            guard var currentDraft = quickCaptureDraft,
                  currentDraft.clientCaptureID == draftID,
                  currentDraft.kind == .screenshot else {
                return false
            }
            currentDraft.selectedText = normalized
            quickCaptureDraft = currentDraft
            screenshotExtractionSummary = summary
            return true
        } catch {
            guard activeScreenshotExtractionID == extractionID,
                  quickCaptureDraft?.clientCaptureID == draftID,
                  !Self.isCancellation(error) else {
                return false
            }
            quickCaptureError = error.recallUserMessage
            updateConnectionState(after: error)
            return false
        }
    }

    func submitQuickCapture() async -> Bool {
        guard let draft = quickCaptureDraft else { return false }
        guard !isSubmittingCapture else { return false }
        guard !isExtractingScreenshot else {
            quickCaptureError = "Wait for screenshot text extraction to finish, or cancel it before saving."
            return false
        }

        guard draft.characterCount <= Self.maximumSelectedTextLength else {
            quickCaptureError = "The selection is \(draft.characterCount.formatted()) characters. Recall can save up to \(Self.maximumSelectedTextLength.formatted()) characters without losing the original text."
            return false
        }

        guard draft.noteCharacterCount <= Self.maximumUserNoteLength else {
            quickCaptureError = "The note is \(draft.noteCharacterCount.formatted()) characters. Recall can save notes up to \(Self.maximumUserNoteLength.formatted()) characters. Your draft has not been changed."
            return false
        }

        let note = draft.userNote.nonEmptyTrimmed == nil ? nil : draft.userNote
        let currentRequest: PendingQuickCaptureRequest
        switch draft.kind {
        case .selection:
            currentRequest = .text(
                .clipboard(
                    clientCaptureID: draft.clientCaptureID,
                    capturedAt: draft.capturedAt,
                    text: draft.selectedText,
                    sourceApp: draft.sourceApplication,
                    userNote: note
                )
            )
        case .clipboard:
            currentRequest = .text(
                .clipboard(
                    clientCaptureID: draft.clientCaptureID,
                    capturedAt: draft.capturedAt,
                    text: draft.selectedText,
                    sourceApp: draft.sourceApplication,
                    userNote: note
                )
            )
        case .screenshot:
            if screenshotNoteKind == .image {
                guard let screenshotPreviewData else {
                    quickCaptureError = "The selected screenshot is no longer available. Capture the region again."
                    return false
                }
                currentRequest = .image(
                    ImageCaptureUploadRequest(
                        metadata: ImageCaptureCreateMetadata(
                            clientCaptureID: draft.clientCaptureID,
                            sourceApp: draft.sourceApplication,
                            userNote: note,
                            capturedAt: draft.capturedAt,
                            analyzeImage: screenshotImageAnalysisWillRun
                        ),
                        imageData: screenshotPreviewData,
                        mediaType: screenshotMediaType
                    )
                )
            } else {
                guard draft.characterCount > 0 else {
                    quickCaptureError = "Extract the screenshot text before saving a text note."
                    return false
                }
                currentRequest = .text(
                    .screenshot(
                        clientCaptureID: draft.clientCaptureID,
                        capturedAt: draft.capturedAt,
                        text: draft.selectedText,
                        sourceApp: draft.sourceApplication,
                        userNote: note
                    )
                )
            }
        }

        let request: PendingQuickCaptureRequest
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
            let capture: Capture
            switch request {
            case let .text(textRequest):
                capture = try await client.createCapture(textRequest)
            case let .image(imageRequest):
                capture = try await client.createImageCapture(imageRequest)
            }
            query = ""
            upsert(capture, insertAtFront: true)
            selectedCaptureID = capture.id
            connectionState = connectedStatePreservingAIConfiguration()
            switch capture.status {
            case .processing:
                notice = AppNotice(
                    style: .information,
                    message: "Saved. Recall is processing this memory.",
                    scope: .processing(capture.id),
                    lifetime: .untilStateChanges
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
        invalidateScreenshotExtraction()
        quickCaptureDraft = nil
        attemptedQuickCaptureRequest = nil
        quickCaptureError = nil
        accessibilitySelectionError = nil
        screenshotPreviewData = nil
        screenshotExtractionSummary = nil
        screenshotMediaType = "image/png"
        screenshotNoteKind = .text
    }

    func dismissQuickCapturePresentation() {
        invalidateScreenshotExtraction()
        screenshotPreviewData = nil
        screenshotExtractionSummary = nil
        screenshotMediaType = "image/png"
        if !isSubmittingCapture {
            clearQuickCapture()
        }
    }

    private func canPrepareNewQuickCapture() -> Bool {
        if isSubmittingCapture {
            let message = "Wait for the current save to finish before starting another Capture."
            quickCaptureError = message
            notice = AppNotice(style: .information, message: message)
            return false
        }
        if attemptedQuickCaptureRequest != nil, quickCaptureDraft != nil {
            let message = "A previous save may already exist. Reopen this draft and retry it, or cancel it before starting another Capture."
            quickCaptureError = message
            notice = AppNotice(style: .warning, message: message)
            return false
        }
        if quickCaptureDraft != nil {
            let message = "Finish or cancel the current Capture before starting another one."
            quickCaptureError = message
            notice = AppNotice(style: .information, message: message)
            return false
        }
        return true
    }

    private func invalidateScreenshotExtraction() {
        activeScreenshotExtractionID = nil
        isExtractingScreenshot = false
    }

    func retryEnrichment(id: String) async {
        do {
            let capture = try await client.enrich(id: id)
            upsert(capture)
            notice = AppNotice(
                style: .information,
                message: "AI processing restarted.",
                scope: .processing(id),
                lifetime: .untilStateChanges
            )
            beginPolling(captureID: id)
        } catch let error as RecallAPIError where error.code == "capture_already_processing" {
            notice = AppNotice(
                style: .information,
                message: error.localizedDescription,
                scope: .processing(id),
                lifetime: .untilStateChanges
            )
            beginPolling(captureID: id)
        } catch let error as RecallAPIError where error.code == "openai_not_configured" {
            notice = AppNotice(style: .warning, message: error.localizedDescription)
        } catch {
            guard !Self.isCancellation(error) else { return }
            updateConnectionState(after: error)
            notice = stateAwareErrorNotice(for: error)
        }
    }

    func loadAttachmentImage(_ attachment: CaptureAttachment) async {
        guard attachmentImageData[attachment.id] == nil,
              !loadingAttachmentIDs.contains(attachment.id) else {
            return
        }
        loadingAttachmentIDs.insert(attachment.id)
        defer { loadingAttachmentIDs.remove(attachment.id) }
        do {
            let data = try await client.attachmentData(
                contentPath: attachment.contentPath
            )
            guard !Task.isCancelled else { return }
            attachmentImageData[attachment.id] = data
        } catch {
            guard !Self.isCancellation(error) else { return }
            updateConnectionState(after: error)
        }
    }

    func deleteCapture(id: String) async -> Bool {
        let attachments = (
            libraryCaptures.first(where: { $0.id == id })
                ?? captures.first(where: { $0.id == id })
        )?.attachments ?? []
        do {
            try await client.deleteCapture(id: id)
        } catch let error as RecallAPIError where error.code == "capture_not_found" {
            // The desired state is already true; remove the stale local row.
        } catch {
            guard !Self.isCancellation(error) else { return false }
            updateConnectionState(after: error)
            notice = stateAwareErrorNotice(for: error)
            return false
        }

        pollingTasks[id]?.cancel()
        pollingTasks[id] = nil
        pollingGenerations[id] = nil
        for attachment in attachments {
            attachmentImageData[attachment.id] = nil
            loadingAttachmentIDs.remove(attachment.id)
        }
        removeCapture(id: id)
        notice = AppNotice(style: .information, message: "Memory deleted.")
        return true
    }

    func updateCapture(id: String, request: CaptureUpdateRequest) async -> Bool {
        guard !isUpdatingCapture else { return false }
        isUpdatingCapture = true
        captureUpdateError = nil
        defer { isUpdatingCapture = false }
        do {
            let capture = try await client.updateCapture(id: id, request: request)
            upsert(capture)
            connectionState = connectedStatePreservingAIConfiguration()
            notice = AppNotice(
                style: capture.aiContentStale ? .warning : .information,
                message: capture.aiContentStale
                    ? "Memory updated. The earlier AI interpretation is hidden until you refresh it."
                    : "Memory updated."
            )
            return true
        } catch {
            guard !Self.isCancellation(error) else { return false }
            captureUpdateError = error.recallUserMessage
            updateConnectionState(after: error)
            notice = AppNotice(
                style: error is URLError ? .error : .warning,
                message: error.recallUserMessage,
                scope: error is URLError ? .connection : .general,
                lifetime: error is URLError ? .untilStateChanges : nil
            )
            return false
        }
    }

    func requestSearchFocus() {
        searchFocusToken = UUID()
    }

    func dismissNotice() {
        notice = nil
    }

    private func dismissNotice(scope: AppNotice.Scope) {
        guard notice?.scope == scope else { return }
        notice = nil
    }

    private func stateAwareErrorNotice(for error: Error) -> AppNotice {
        AppNotice(
            style: .error,
            message: error.recallUserMessage,
            scope: error is URLError ? .connection : .general,
            lifetime: error is URLError ? .untilStateChanges : .persistent
        )
    }

    private func scheduleNoticeDismissal() {
        noticeDismissalTask?.cancel()
        noticeDismissalTask = nil
        guard let notice,
              case let .timed(defaultNanoseconds) = notice.lifetime else {
            return
        }
        let nanoseconds = noticeTimeoutOverrideNanoseconds ?? defaultNanoseconds
        let noticeID = notice.id
        noticeDismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self, self.notice?.id == noticeID else { return }
            self.notice = nil
        }
    }

    private func resolveProcessingNotice(
        captureID: String,
        status: CaptureStatus
    ) {
        guard notice?.scope == .processing(captureID) else { return }
        switch status {
        case .ready:
            notice = AppNotice(
                style: .information,
                message: "AI interpretation is ready."
            )
        case .error:
            notice = AppNotice(
                style: .warning,
                message: "AI processing needs attention. Your memory is still safe."
            )
        case .captured, .processing:
            break
        }
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
                        self.resolveProcessingNotice(
                            captureID: captureID,
                            status: capture.status
                        )
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
                message: "This memory is still processing. Its original content is safely saved; refresh later for updates.",
                scope: .processing(captureID),
                lifetime: .untilStateChanges
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
        sortLibraryCaptures()

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

    private func sortLibraryCaptures() {
        libraryCaptures.sort { left, right in
            let leftDate = left.listDate(for: sortOrder) ?? .distantPast
            let rightDate = right.listDate(for: sortOrder) ?? .distantPast
            if leftDate == rightDate {
                return left.id < right.id
            }
            switch sortOrder {
            case .createdNewest, .editedNewest:
                return leftDate > rightDate
            case .createdOldest, .editedOldest:
                return leftDate < rightDate
            }
        }
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
                capture.displayProblem,
                capture.displayKeyInsight,
                capture.displayWhySaved,
                capture.userNote,
                capture.selectedText,
                capture.surroundingContext,
                capture.displayTags.joined(separator: " "),
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
