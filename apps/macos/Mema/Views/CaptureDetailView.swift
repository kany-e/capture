import AppKit
import SwiftUI

struct CaptureDetailView: View {
    @EnvironmentObject private var store: MemaStore
    let capture: Capture
    private let surroundingContextPreview: SurroundingContextPreview?
    @State private var isSurroundingContextExpanded = false
    @State private var showsDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showsEditSheet = false

    init(capture: Capture) {
        self.capture = capture
        surroundingContextPreview = SurroundingContextPreview(
            context: capture.surroundingContext
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                if let attachment = capture.primaryImageAttachment {
                    MemaSection("Original image", icon: "photo") {
                        AttachmentImageView(attachment: attachment, style: .detail)
                    }
                }

                if capture.status != .processing, capture.aiContentStale {
                    staleAISection
                } else if capture.aiInterpretationHidden,
                          capture.aiSummary?.nonEmptyTrimmed != nil {
                    hiddenAISection
                }

                if !capture.aiInterpretationHidden,
                   let summary = capture.aiSummary?.nonEmptyTrimmed {
                    MemaSection("AI interpretation", icon: "sparkles") {
                        Text(summary)
                            .font(.title3)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                } else if capture.status == .processing {
                    processingSection
                }

                if let userNote = capture.userNote?.nonEmptyTrimmed {
                    MemaSection("Your note", icon: "person.crop.circle") {
                        Text(userNote)
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                }

                if capture.selectedText.nonEmptyTrimmed != nil
                    || capture.primaryImageAttachment == nil {
                    MemaSection(
                        capture.primaryImageAttachment != nil
                            ? "Text found in image"
                            : capture.sourceType == .screenshot
                                ? "Extracted source text"
                                : "Original selection",
                        icon: capture.sourceType == .screenshot
                            ? "text.viewfinder"
                            : "quote.opening"
                    ) {
                        Text(capture.selectedText.nonEmptyTrimmed ?? "No text was selected.")
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .foregroundStyle(capture.selectedText.nonEmptyTrimmed == nil ? .secondary : .primary)
                    }
                }

                if let surroundingContextPreview {
                    surroundingContextSection(surroundingContextPreview)
                }

                interpretationDetails

                if !capture.displayTags.isEmpty {
                    MemaSection("Tags", icon: "tag") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(capture.displayTags, id: \.self) { tag in
                                    TagPill(text: tag)
                                }
                            }
                        }
                    }
                }

                sourceSection

                if capture.status == .error {
                    errorSection
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
        .navigationTitle(capture.displayTitle)
        .toolbar {
            Button {
                showsEditSheet = true
            } label: {
                Label("Edit memory", systemImage: "pencil")
            }
            .disabled(isDeleting || capture.status == .processing)

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("Delete memory", systemImage: "trash")
            }
            .disabled(isDeleting)
        }
        .sheet(isPresented: $showsEditSheet) {
            CaptureEditView(capture: capture)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Delete this memory?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Memory", role: .destructive) {
                isDeleting = true
                Task {
                    _ = await store.deleteCapture(id: capture.id)
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                capture.primaryImageAttachment == nil
                    ? "This removes the saved memory."
                    : "This removes the saved memory, its image, and its AI index."
            )
        }
    }

    private func surroundingContextSection(
        _ preview: SurroundingContextPreview
    ) -> some View {
        MemaSection("Surrounding context", icon: "text.alignleft") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            "\(preview.totalCharacterCount.formatted()) \(preview.totalCharacterCount == 1 ? "character" : "characters") captured"
                        )
                            .font(.callout.weight(.medium))
                        Text("Hidden by default to keep this memory responsive.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button(isSurroundingContextExpanded ? "Hide" : "Show") {
                        isSurroundingContextExpanded.toggle()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(
                        isSurroundingContextExpanded
                            ? "Hide surrounding context"
                            : "Show surrounding context"
                    )
                }

                if isSurroundingContextExpanded {
                    Divider()
                    Text(preview.text)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)

                    if preview.isDisplayLimited {
                        Label(
                            "Previewing the first \(preview.displayedCharacterCount.formatted()) of \(preview.totalCharacterCount.formatted()) \(preview.totalCharacterCount == 1 ? "character" : "characters") across \(preview.displayedLineCount.formatted()) \(preview.displayedLineCount == 1 ? "line" : "lines"). The full context remains saved for search and AI.",
                            systemImage: "text.badge.ellipsis"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if capture.contextTruncated {
                    Label("Context was shortened during capture", systemImage: "scissors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CaptureStatusBadge(status: capture.status)
                Text(capture.sourceLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if let createdDate = capture.createdDate {
                    Text("Created \(createdDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let editedDate = capture.userEditedDate {
                    Text("Edited \(editedDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(capture.displayTitle)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .textSelection(.enabled)
            if let sourceTitle = capture.sourceTitle?.nonEmptyTrimmed,
               sourceTitle != capture.displayTitle {
                Text(sourceTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var processingSection: some View {
        MemaSection("AI interpretation", icon: "sparkles") {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Building a contextual memory…")
                        .font(.headline)
                    Text(
                        capture.primaryImageAttachment == nil
                            ? "Your original selection and note are already saved."
                            : "The original image and your note are already saved. OCR and visual indexing continue in the background."
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var interpretationDetails: some View {
        let details: [(String, String, String)] = [
            ("Problem", "questionmark.circle", capture.displayProblem ?? ""),
            ("Key insight", "lightbulb", capture.displayKeyInsight ?? ""),
            ("Why it mattered", "bookmark", capture.displayWhySaved ?? ""),
        ].filter { $0.2.nonEmptyTrimmed != nil }

        if !details.isEmpty || !capture.displayCaveats.isEmpty {
            MemaSection("Memory details", icon: "square.grid.2x2") {
                VStack(alignment: .leading, spacing: 16) {
                    if capture.hasUserOrganizationOverrides {
                        Label("Organized by you", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(details, id: \.0) { detail in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(detail.0)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(detail.2)
                                    .textSelection(.enabled)
                            }
                        } icon: {
                            Image(systemName: detail.1)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if !capture.displayCaveats.isEmpty {
                        Divider()
                        Label {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Caveats")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(capture.displayCaveats, id: \.self) { caveat in
                                    Text("• \(caveat)")
                                        .textSelection(.enabled)
                                }
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private var sourceSection: some View {
        MemaSection("Source", icon: capture.sourceType.systemImageName) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(capture.sourceLabel)
                        .font(.headline)
                    if let url = capture.sourceURLValue {
                        Text(url.host() ?? url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let url = capture.sourceURLValue {
                    Button("Open Source", systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var staleAISection: some View {
        MemaSection("AI interpretation", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    capture.aiInterpretationHidden
                        ? "Hidden because the source or your note changed"
                        : "Based on an earlier version of this memory",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.headline)
                Text(
                    "Mema keeps the previous AI layer separate instead of silently rewriting it. Refresh AI when you want a new interpretation based on the edited memory."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Button("Refresh AI", systemImage: "arrow.clockwise") {
                    Task { await store.retryEnrichment(id: capture.id) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var hiddenAISection: some View {
        MemaSection("AI interpretation", icon: "sparkles") {
            HStack(spacing: 12) {
                Label("Hidden for this memory", systemImage: "eye.slash")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Edit visibility") {
                    showsEditSheet = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var errorSection: some View {
        MemaSection("Processing error", icon: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 12) {
                Text(capture.errorMessage?.nonEmptyTrimmed ?? "AI processing did not complete.")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Text(
                    capture.primaryImageAttachment == nil
                        ? "The source and your note remain available and searchable."
                        : "The original image and your note remain saved. Retry to rebuild its searchable AI index."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Retry AI", systemImage: "arrow.clockwise") {
                    Task { await store.retryEnrichment(id: capture.id) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct CaptureEditView: View {
    @EnvironmentObject private var store: MemaStore
    @Environment(\.dismiss) private var dismiss
    let capture: Capture
    @State private var draft: CaptureEditDraft

    init(capture: Capture) {
        self.capture = capture
        _draft = State(initialValue: CaptureEditDraft(capture: capture))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit Memory")
                        .font(.title2.weight(.bold))
                    Text("Captured source, your edits, and AI output remain separate.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)

            Divider()

            Form {
                Section("Title and note") {
                    TextField("Memory title", text: $draft.title)
                    Text("Leave blank to use the current AI or source title.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        "Your note",
                        text: $draft.userNote,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                }

                Section(
                    capture.primaryImageAttachment == nil
                        ? "Selected content"
                        : "Text found in image"
                ) {
                    TextEditor(text: $draft.selectedText)
                        .font(.body)
                        .frame(minHeight: 120)
                    Text(
                        "\(draft.selectedText.unicodeScalars.count.formatted()) / \(MemaStore.maximumSelectedTextLength.formatted())"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        draft.selectedText.unicodeScalars.count
                            > MemaStore.maximumSelectedTextLength ? .red : .secondary
                    )
                }

                Section("Source") {
                    TextField("Application", text: $draft.sourceApp)
                    TextField("Source title", text: $draft.sourceTitle)
                    TextField("URL", text: $draft.sourceURL)
                }

                Section("AI interpretation") {
                    Toggle("Show AI interpretation", isOn: $draft.showAIInterpretation)
                    Text(
                        capture.aiContentStale
                            ? "This interpretation is already based on an earlier version. Use Refresh AI from the detail view to rebuild it."
                            : "Changing selected content, your note, or source marks the existing AI interpretation as out of date and hides it. Mema never regenerates automatically."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Memory details · organized by you") {
                    TextField("Problem", text: $draft.problem, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Key insight", text: $draft.keyInsight, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Why it mattered", text: $draft.whySaved, axis: .vertical)
                        .lineLimit(1...4)
                    EditableLineList(
                        title: "Caveats",
                        placeholder: "Add a caveat",
                        values: $draft.caveats
                    )
                }

                Section("Tags") {
                    EditableTagList(tags: $draft.tags)
                }

                if let message = validationMessage ?? store.captureUpdateError {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text("Saving updates the user-edited time; creation time never changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.isUpdatingCapture)
                Button {
                    save()
                } label: {
                    if store.isUpdatingCapture {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 64)
                    } else {
                        Text("Save Changes")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil || store.isUpdatingCapture)
            }
            .padding(18)
        }
        .frame(width: 660, height: 720)
    }

    private var validationMessage: String? {
        if draft.selectedText.unicodeScalars.count > MemaStore.maximumSelectedTextLength {
            return "Selected content is too long."
        }
        if draft.userNote.unicodeScalars.count > MemaStore.maximumUserNoteLength {
            return "Your note is too long."
        }
        if draft.sourceApp.unicodeScalars.count > MemaStore.maximumSourceApplicationLength {
            return "The source application can use up to 200 characters."
        }
        if draft.sourceTitle.unicodeScalars.count > MemaStore.maximumSourceTitleLength {
            return "The source title can use up to 500 characters."
        }
        if draft.sourceURL.unicodeScalars.count > MemaStore.maximumSourceURLLength {
            return "The source URL can use up to 2,048 characters."
        }
        if draft.title.unicodeScalars.count > 200 {
            return "The memory title can use up to 200 characters."
        }
        if [draft.problem, draft.keyInsight, draft.whySaved].contains(
            where: { $0.unicodeScalars.count > 2_000 }
        ) {
            return "Each memory detail can use up to 2,000 characters."
        }
        if draft.tags.count > 20 || draft.caveats.count > 20 {
            return "Tags and caveats can each contain up to 20 items."
        }
        if (draft.tags + draft.caveats).contains(
            where: { $0.unicodeScalars.count > 300 }
        ) {
            return "Each tag or caveat can use up to 300 characters."
        }
        if let url = draft.sourceURL.nonEmptyTrimmed {
            guard let parsed = URL(string: url),
                  let scheme = parsed.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  parsed.host?.nonEmptyTrimmed != nil else {
                return "Source URL must begin with http:// or https://."
            }
        }
        if capture.primaryImageAttachment == nil,
           draft.selectedText.nonEmptyTrimmed == nil,
           draft.sourceTitle.nonEmptyTrimmed == nil,
           draft.title.nonEmptyTrimmed == nil {
            return "Keep at least a title, source title, or selected content."
        }
        return nil
    }

    private func save() {
        guard validationMessage == nil else { return }
        let request = CaptureUpdateRequest(
            selectedText: sourceOverride(
                currentOverride: capture.userSelectedText,
                effectiveValue: capture.selectedText,
                editedValue: draft.selectedText
            ),
            userNote: draft.userNote.nonEmptyTrimmed,
            sourceApp: sourceOverride(
                currentOverride: capture.userSourceApp,
                effectiveValue: capture.sourceApp ?? "",
                editedValue: draft.sourceApp
            ),
            sourceTitle: sourceOverride(
                currentOverride: capture.userSourceTitle,
                effectiveValue: capture.sourceTitle ?? "",
                editedValue: draft.sourceTitle
            ),
            sourceURL: sourceOverride(
                currentOverride: capture.userSourceURL,
                effectiveValue: capture.sourceURL ?? "",
                editedValue: draft.sourceURL
            ),
            userTitle: draft.title.nonEmptyTrimmed,
            userProblem: manualText(draft.problem, aiValue: capture.problem),
            userKeyInsight: manualText(
                draft.keyInsight,
                aiValue: capture.keyInsight
            ),
            userWhySaved: manualText(draft.whySaved, aiValue: capture.whySaved),
            userCaveats: manualList(draft.caveats, aiValues: capture.caveats),
            userTags: manualList(draft.tags, aiValues: capture.tags),
            showAIInterpretation: draft.showAIInterpretation
        )
        Task {
            if await store.updateCapture(id: capture.id, request: request) {
                dismiss()
            }
        }
    }

    private func normalized(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            guard let trimmed = value.nonEmptyTrimmed else { return nil }
            let key = trimmed.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            return seen.insert(key).inserted ? trimmed : nil
        }
    }

    private func manualText(_ value: String, aiValue: String?) -> String? {
        let edited = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = aiValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return edited == generated ? nil : edited
    }

    private func sourceOverride(
        currentOverride: String?,
        effectiveValue: String,
        editedValue: String
    ) -> String? {
        if currentOverride == nil, editedValue == effectiveValue {
            return nil
        }
        return editedValue
    }

    private func manualList(_ values: [String], aiValues: [String]) -> [String]? {
        let edited = normalized(values)
        return edited == aiValues ? nil : edited
    }
}

private struct CaptureEditDraft {
    var title: String
    var userNote: String
    var selectedText: String
    var sourceApp: String
    var sourceTitle: String
    var sourceURL: String
    var showAIInterpretation: Bool
    var problem: String
    var keyInsight: String
    var whySaved: String
    var caveats: [String]
    var tags: [String]

    init(capture: Capture) {
        title = capture.userTitle ?? ""
        userNote = capture.userNote ?? ""
        selectedText = capture.selectedText
        sourceApp = capture.sourceApp ?? ""
        sourceTitle = capture.sourceTitle ?? ""
        sourceURL = capture.sourceURL ?? ""
        showAIInterpretation = !capture.aiInterpretationHidden
        problem = capture.userProblem ?? capture.problem ?? ""
        keyInsight = capture.userKeyInsight ?? capture.keyInsight ?? ""
        whySaved = capture.userWhySaved ?? capture.whySaved ?? ""
        caveats = capture.userCaveats ?? capture.caveats
        tags = capture.userTags ?? capture.tags
    }
}

private struct EditableTagList: View {
    @Binding var tags: [String]
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                        HStack(spacing: 5) {
                            Text(tag)
                            Button {
                                tags.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove tag \(tag)")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.leading, 9)
                        .padding(.trailing, 6)
                        .padding(.vertical, 5)
                        .foregroundStyle(Color.accentColor)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                    }
                }
            }

            HStack {
                TextField("New tag", text: $newTag)
                    .onSubmit(addTag)
                Button("Add", systemImage: "plus", action: addTag)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.secondary.opacity(0.6),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    }
                    .disabled(newTag.nonEmptyTrimmed == nil || tags.count >= 20)
            }
        }
    }

    private func addTag() {
        guard let value = newTag.nonEmptyTrimmed,
              !tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }),
              tags.count < 20 else { return }
        tags.append(value)
        newTag = ""
    }
}

private struct EditableLineList: View {
    let title: String
    let placeholder: String
    @Binding var values: [String]
    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(values.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField(placeholder, text: $values[index], axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        values.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove caveat")
                }
            }
            HStack {
                TextField(placeholder, text: $newValue)
                    .onSubmit(addValue)
                Button("Add", systemImage: "plus", action: addValue)
                    .disabled(newValue.nonEmptyTrimmed == nil || values.count >= 20)
            }
        }
    }

    private func addValue() {
        guard let value = newValue.nonEmptyTrimmed, values.count < 20 else { return }
        values.append(value)
        newValue = ""
    }
}
