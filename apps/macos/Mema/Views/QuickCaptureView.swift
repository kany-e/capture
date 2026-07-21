import AppKit
import SwiftUI

struct QuickCaptureView: View {
    @EnvironmentObject private var store: MemaStore
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
                || store.screenshotNoteKind == .image
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
                Image("MemaMarkTemplate")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }

            if draft.kind == .screenshot {
                screenshotSection
            }

            if draft.kind != .screenshot || store.screenshotNoteKind == .text {
                VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(draft.kind == .screenshot ? "EXTRACTED SOURCE TEXT" : "SELECTION")
                        .font(.caption.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(draft.characterCount.formatted()) / \(MemaStore.maximumSelectedTextLength.formatted())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(draft.characterCount > MemaStore.maximumSelectedTextLength ? .red : .secondary)
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
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Why does this matter to you?")
                        .font(.headline)
                    Spacer()
                    Text("\(draft.noteCharacterCount.formatted()) / \(MemaStore.maximumUserNoteLength.formatted())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            draft.noteCharacterCount > MemaStore.maximumUserNoteLength
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
                .disabled(store.isQuickCaptureRetryLocked)
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
                Text(captureFooter(for: draft))
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
                        || !store.quickCaptureCanSubmit
                )
            }
        }
        .padding(24)
    }

    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data = store.screenshotPreviewData,
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .accessibilityLabel("Selected screenshot preview")
            }

            Picker("Save as", selection: $store.screenshotNoteKind) {
                ForEach(ScreenshotNoteKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.isExtractingScreenshot || store.isQuickCaptureRetryLocked)

            if store.screenshotNoteKind == .image {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Build a searchable AI index")
                            .font(.headline)
                        Text(
                            !store.imageAnalysisIsEnabled
                                ? "AI image analysis is blocked by the master privacy control in Settings. This image will stay local."
                                : store.screenshotImageAnalysisWillRun
                                    ? "Save immediately, then send the image to GPT in the background for OCR and visual understanding. Provider data policies apply."
                                    : "Keep this image as a local attachment without OCR or visual analysis."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .frame(height: 32, alignment: .topLeading)
                    }
                    Spacer(minLength: 12)
                    Toggle(
                        "Build a searchable AI index",
                        isOn: $store.screenshotImageAnalysisIsEnabled
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                    .padding(.top, 1)
                    .disabled(
                        !store.imageAnalysisIsEnabled || store.isQuickCaptureRetryLocked
                    )
                }
                .frame(minHeight: 54, alignment: .top)

                Label(
                    "The original image is stored locally; AI annotations remain separate and can fail without losing it.",
                    systemImage: "photo.badge.checkmark"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
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
                if store.accessibilitySelectionError == .selectionUnavailable,
                   !store.selectionClipboardFallbackIsEnabled {
                    SettingsLink {
                        Text("Open Selection Settings")
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
        case .screenshot: "Capture Screenshot"
        }
    }

    private func sourceFallback(for kind: QuickCaptureDraft.Kind) -> String {
        switch kind {
        case .selection: "Selected text"
        case .clipboard: "Clipboard"
        case .screenshot: "Screenshot"
        }
    }

    private func captureFooter(for draft: QuickCaptureDraft) -> String {
        switch draft.kind {
        case .selection:
            if draft.selectionCaptureMethod == .clipboardFallback {
                return "This app required two matching temporary Copies. Mema restored the "
                    + "previous clipboard on a best-effort basis; clipboard history apps may "
                    + "still record the selection."
            }
            return "Mema saves only this source selection and your optional note before AI processing begins."
        case .clipboard:
            return "Your clipboard text and optional note are saved before AI processing begins."
        case .screenshot:
            if store.screenshotNoteKind == .image {
                return store.screenshotImageAnalysisWillRun
                    ? "The image and note are saved first; OCR and visual indexing continue in the background."
                    : "The image and optional note are saved locally without AI analysis."
            }
            return "Mema saves only the extracted source text and optional note; the temporary image is discarded."
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
                if newValue.unicodeScalars.count <= MemaStore.maximumUserNoteLength {
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
            dismissWindow(id: MemaWindowID.quickCapture)
            store.clearQuickCapture()
        }
    }

    private func cancel() {
        guard !store.isSubmittingCapture else { return }
        screenshotExtractionTask?.cancel()
        screenshotExtractionTask = nil
        dismissWindow(id: MemaWindowID.quickCapture)
        store.clearQuickCapture()
    }
}
