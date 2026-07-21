import Foundation

enum GlobalCaptureIntent: Sendable {
    case clipboard
    case screenshot
}

@MainActor
final class GlobalCaptureCoordinator: ObservableObject {
    @Published private(set) var quickCapturePresentationRequest = 0

    private let store: RecallStore
    private var screenshotPreparationTask: Task<Void, Never>?

    init(store: RecallStore) {
        self.store = store
    }

    func handle(_ intent: GlobalCaptureIntent) {
        switch intent {
        case .clipboard:
            prepareClipboardCapture()
        case .screenshot:
            prepareScreenshotCapture()
        }
    }

    func prepareClipboardCapture() {
        guard !store.isPreparingScreenshot else { return }
        let prepared = store.prepareClipboardCapture()
        if prepared || store.quickCaptureDraft != nil || store.quickCaptureError != nil {
            requestQuickCapturePresentation()
        }
    }

    func prepareScreenshotCapture() {
        guard screenshotPreparationTask == nil else { return }
        screenshotPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { screenshotPreparationTask = nil }
            await Task.yield()
            let prepared = await store.prepareScreenshotCapture()
            guard !Task.isCancelled else { return }
            if prepared || store.quickCaptureDraft != nil || store.quickCaptureError != nil {
                requestQuickCapturePresentation()
            }
        }
    }

    func requestQuickCapturePresentation() {
        quickCapturePresentationRequest &+= 1
    }

    func cancelPendingCapture() {
        screenshotPreparationTask?.cancel()
    }

    func cancelPendingCaptureAndWait() async {
        let task = screenshotPreparationTask
        task?.cancel()
        await task?.value
    }
}
