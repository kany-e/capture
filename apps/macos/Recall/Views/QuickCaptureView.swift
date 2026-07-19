import SwiftUI

struct QuickCaptureView: View {
    @EnvironmentObject private var store: RecallStore
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusState private var noteIsFocused: Bool

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
        .onAppear {
            noteIsFocused = true
        }
        .onExitCommand {
            cancel()
        }
    }

    private func captureForm(_ draft: QuickCaptureDraft) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capture Clipboard")
                        .font(.title2.weight(.bold))
                    Label(draft.sourceApplication ?? "Clipboard", systemImage: "app.dashed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SELECTION")
                        .font(.caption.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(draft.characterCount.formatted()) / \(RecallStore.maximumSelectedTextLength.formatted())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(draft.characterCount > RecallStore.maximumSelectedTextLength ? .red : .secondary)
                }
                ScrollView {
                    Text(draft.selectedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
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
                Text("Your source is saved before AI processing begins.")
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
                        || draft.characterCount > RecallStore.maximumSelectedTextLength
                        || draft.noteCharacterCount > RecallStore.maximumUserNoteLength
                )
            }
        }
        .padding(24)
    }

    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Nothing to capture")
                .font(.title2.weight(.bold))
            Text(store.quickCaptureError ?? "Copy some text in any app, then choose Capture Clipboard again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
            Button("Close", action: cancel)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(36)
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
        Task {
            guard await store.submitQuickCapture() else { return }
            dismissWindow(id: RecallWindowID.quickCapture)
            store.clearQuickCapture()
        }
    }

    private func cancel() {
        guard !store.isSubmittingCapture else { return }
        dismissWindow(id: RecallWindowID.quickCapture)
        store.clearQuickCapture()
    }
}
