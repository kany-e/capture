import AppKit
import SwiftUI

struct QuickCaptureView: View {
    @EnvironmentObject private var store: RecallStore
    @EnvironmentObject private var captureCoordinator: GlobalCaptureCoordinator
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusState private var noteIsFocused: Bool
    @State private var screenshotExtractionTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let draft = store.quickCaptureDraft {
                captureForm(draft)
            } else {
                unavailableState
            }
        }
        .frame(width: 500)
        .background(.regularMaterial)
        .background {
            QuickCaptureWindowAccessor(
                requestID: captureCoordinator.quickCapturePresentationRequest,
                context: captureCoordinator.quickCapturePresentationContext
            )
            .frame(width: 0, height: 0)
        }
        .onAppear {
            noteIsFocused = store.quickCaptureDraft?.kind != .screenshot
        }
        .onExitCommand {
            cancel()
        }
        .onDisappear {
            screenshotExtractionTask?.cancel()
            screenshotExtractionTask = nil
            store.dismissQuickCapturePresentation()
        }
    }

    private func captureForm(_ draft: QuickCaptureDraft) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(captureTitle(for: draft.kind))
                        .font(.title2.weight(.bold))
                    Label(
                        draft.sourceApplication ?? sourceFallback(for: draft.kind),
                        systemImage: "app.dashed"
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
            }

            if draft.kind == .screenshot {
                screenshotExtractionSection
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(draft.kind == .screenshot ? "EXTRACTED SOURCE TEXT" : "SELECTION")
                        .font(.caption.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(draft.characterCount.formatted()) / \(RecallStore.maximumSelectedTextLength.formatted())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(draft.characterCount > RecallStore.maximumSelectedTextLength ? .red : .secondary)
                }
                ScrollView {
                    Text(
                        draft.selectedText.nonEmptyTrimmed
                            ?? "Choose an extractor, then extract the screenshot's source text."
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .foregroundStyle(
                            draft.selectedText.nonEmptyTrimmed == nil ? .secondary : .primary
                        )
                }
                .frame(height: 132)
                .padding(12)
                .background(.background.opacity(0.68), in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(.primary.opacity(0.08), lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Why does this matter to you?")
                        .font(.headline)
                    Spacer()
                    Text("\(draft.noteCharacterCount.formatted()) / \(RecallStore.maximumUserNoteLength.formatted())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            draft.noteCharacterCount > RecallStore.maximumUserNoteLength
                                ? .red
                                : .secondary
                        )
                }
                TextField(
                    "Optional note — the context only you know",
                    text: noteBinding,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .focused($noteIsFocused)
                .disabled(
                    store.isQuickCaptureRetryLocked
                        || (draft.kind == .screenshot && draft.selectedText.isEmpty)
                )
                .onSubmit {
                    save()
                }
                if store.isQuickCaptureRetryLocked {
                    Text("A previous save may have reached the backend. Retry uses the original note; cancel and capture again to edit it safely.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = store.quickCaptureError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(captureFooter(for: draft.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.isSubmittingCapture)
                Button {
                    save()
                } label: {
                    if store.isSubmittingCapture {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 48)
                    } else {
                        Text(store.isQuickCaptureRetryLocked ? "Retry" : "Save")
                            .frame(minWidth: 48)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    store.isSubmittingCapture
                        || store.isExtractingScreenshot
                        || draft.characterCount == 0
                        || draft.characterCount > RecallStore.maximumSelectedTextLength
                        || draft.noteCharacterCount > RecallStore.maximumUserNoteLength
                )
            }
        }
        .padding(24)
    }

    private var screenshotExtractionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data = store.screenshotPreviewData,
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 150)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .accessibilityLabel("Selected screenshot preview")
            }

            Picker("Text extractor", selection: $store.screenshotExtractionMode) {
                ForEach(ScreenshotExtractionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.isExtractingScreenshot || store.isQuickCaptureRetryLocked)

            HStack {
                Label(
                    store.screenshotExtractionMode == .gpt
                        ? "Image is sent to GPT for this extraction only"
                        : "Image stays on this Mac",
                    systemImage: store.screenshotExtractionMode == .gpt
                        ? "cloud"
                        : "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    screenshotExtractionTask?.cancel()
                    screenshotExtractionTask = Task { @MainActor in
                        defer { screenshotExtractionTask = nil }
                        if await store.extractScreenshotText() {
                            noteIsFocused = true
                        }
                    }
                } label: {
                    if store.isExtractingScreenshot {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 150)
                    } else {
                        Text(
                            store.screenshotExtractionSummary == nil
                                ? "Extract source text"
                                : "Re-extract source text"
                        )
                        .frame(minWidth: 150)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isExtractingScreenshot || store.isQuickCaptureRetryLocked)
            }

            if let summary = store.screenshotExtractionSummary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(
                systemName: store.quickCaptureError == nil
                    ? "doc.on.clipboard"
                    : "exclamationmark.triangle"
            )
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(store.quickCaptureError == nil ? "Nothing to capture" : "Capture unavailable")
                .font(.title2.weight(.bold))
            Text(store.quickCaptureError ?? "Copy some text in any app, then choose Capture Clipboard again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
            HStack {
                if store.accessibilitySelectionError == .permissionRequired {
                    Button("Open Accessibility Settings") {
                        openAccessibilitySettings()
                    }
                }
                if store.accessibilitySelectionError != nil {
                    Button("Capture Current Clipboard") {
                        captureCoordinator.prepareClipboardCapture()
                    }
                }
                Button("Close", action: cancel)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(36)
    }

    private func captureTitle(for kind: QuickCaptureDraft.Kind) -> String {
        switch kind {
        case .selection: "Capture Selection"
        case .clipboard: "Capture Clipboard"
        case .screenshot: "Capture Screenshot Note"
        }
    }

    private func sourceFallback(for kind: QuickCaptureDraft.Kind) -> String {
        switch kind {
        case .selection: "Selected text"
        case .clipboard: "Clipboard"
        case .screenshot: "Screenshot"
        }
    }

    private func captureFooter(for kind: QuickCaptureDraft.Kind) -> String {
        switch kind {
        case .selection:
            "Recall saves only this source selection and your optional note before AI processing begins."
        case .clipboard:
            "Your clipboard text and optional note are saved before AI processing begins."
        case .screenshot:
            "Recall saves only the extracted source text and your optional note; closing clears the temporary image."
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { store.quickCaptureDraft?.userNote ?? "" },
            set: { newValue in
                store.quickCaptureDraft?.userNote = newValue
                if newValue.unicodeScalars.count <= RecallStore.maximumUserNoteLength {
                    store.quickCaptureError = nil
                }
            }
        )
    }

    private func save() {
        guard let clientCaptureID = store.quickCaptureDraft?.clientCaptureID else { return }
        Task {
            guard await store.submitQuickCapture() else { return }
            guard store.quickCaptureDraft?.clientCaptureID == clientCaptureID else {
                return
            }
            dismissWindow(id: RecallWindowID.quickCapture)
            store.clearQuickCapture()
        }
    }

    private func cancel() {
        guard !store.isSubmittingCapture else { return }
        screenshotExtractionTask?.cancel()
        screenshotExtractionTask = nil
        dismissWindow(id: RecallWindowID.quickCapture)
        store.clearQuickCapture()
    }
}
