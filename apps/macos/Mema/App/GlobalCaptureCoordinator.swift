import AppKit
import Foundation

enum GlobalCaptureIntent: Sendable {
    case selection
    case clipboard
    case screenshot
}

@MainActor
final class GlobalCaptureCoordinator: ObservableObject {
    @Published private(set) var quickCapturePresentationRequest = 0
    @Published private(set) var quickCapturePresentationContext: QuickCapturePresentationContext?

    private let store: MemaStore
    private var selectionPreparationTask: Task<Void, Never>?
    private var screenshotPreparationTask: Task<Void, Never>?

    init(store: MemaStore) {
        self.store = store
    }

    func handle(_ intent: GlobalCaptureIntent) {
        switch intent {
        case .selection:
            prepareAccessibilitySelectionCapture()
        case .clipboard:
            prepareClipboardCapture()
        case .screenshot:
            prepareScreenshotCapture()
        }
    }

    func prepareAccessibilitySelectionCapture() {
        guard selectionPreparationTask == nil else { return }
        let fallbackPoint = NSEvent.mouseLocation
        selectionPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { selectionPreparationTask = nil }
            let snapshot = await store.prepareAccessibilitySelectionCapture()
            guard !Task.isCancelled else { return }
            if snapshot != nil
                || store.quickCaptureDraft != nil
                || store.quickCaptureError != nil {
                requestQuickCapturePresentation(
                    context: QuickCapturePresentationContext(
                        selectionBoundsInAXScreenCoordinates: snapshot?
                            .selectionBoundsInAXScreenCoordinates,
                        fallbackPointInAppKitScreenCoordinates: fallbackPoint
                    )
                )
            }
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

    func requestQuickCapturePresentation(
        context: QuickCapturePresentationContext? = nil
    ) {
        quickCapturePresentationContext = context ?? QuickCapturePresentationContext(
            selectionBoundsInAXScreenCoordinates: nil,
            fallbackPointInAppKitScreenCoordinates: NSEvent.mouseLocation
        )
        quickCapturePresentationRequest &+= 1
    }

    func cancelPendingCapture() {
        selectionPreparationTask?.cancel()
        screenshotPreparationTask?.cancel()
    }

    func cancelPendingCaptureAndWait() async {
        let selectionTask = selectionPreparationTask
        let screenshotTask = screenshotPreparationTask
        selectionTask?.cancel()
        screenshotTask?.cancel()
        await selectionTask?.value
        await screenshotTask?.value
    }
}
