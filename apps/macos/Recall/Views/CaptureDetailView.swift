import AppKit
import SwiftUI

struct CaptureDetailView: View {
    @EnvironmentObject private var store: RecallStore
    let capture: Capture

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                if let summary = capture.aiSummary?.nonEmptyTrimmed {
                    RecallSection("AI interpretation", icon: "sparkles") {
                        Text(summary)
                            .font(.title3)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                } else if capture.status == .processing {
                    processingSection
                }

                if let userNote = capture.userNote?.nonEmptyTrimmed {
                    RecallSection("Your note", icon: "person.crop.circle") {
                        Text(userNote)
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                }

                RecallSection("Original selection", icon: "quote.opening") {
                    Text(capture.selectedText.nonEmptyTrimmed ?? "No text was selected.")
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .foregroundStyle(capture.selectedText.nonEmptyTrimmed == nil ? .secondary : .primary)
                }

                if let context = capture.surroundingContext?.nonEmptyTrimmed {
                    RecallSection("Surrounding context", icon: "text.alignleft") {
                        Text(context)
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                        if capture.contextTruncated {
                            Label("Context was shortened during capture", systemImage: "scissors")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                interpretationDetails

                if !capture.tags.isEmpty {
                    RecallSection("Tags", icon: "tag") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(capture.tags, id: \.self) { tag in
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
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CaptureStatusBadge(status: capture.status)
                Text(capture.sourceLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if let createdDate = capture.createdDate {
                    Text(createdDate.formatted(date: .abbreviated, time: .shortened))
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
        RecallSection("AI interpretation", icon: "sparkles") {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Building a contextual memory…")
                        .font(.headline)
                    Text("Your original selection and note are already saved.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var interpretationDetails: some View {
        let details: [(String, String, String)] = [
            ("Problem", "questionmark.circle", capture.problem ?? ""),
            ("Key insight", "lightbulb", capture.keyInsight ?? ""),
            ("Why it mattered", "bookmark", capture.whySaved ?? ""),
        ].filter { $0.2.nonEmptyTrimmed != nil }

        if !details.isEmpty || !capture.caveats.isEmpty {
            RecallSection("Memory details", icon: "square.grid.2x2") {
                VStack(alignment: .leading, spacing: 16) {
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
                    if !capture.caveats.isEmpty {
                        Divider()
                        Label {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Caveats")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(capture.caveats, id: \.self) { caveat in
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
        RecallSection("Source", icon: capture.sourceType == .web ? "globe" : "doc.on.clipboard") {
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

    private var errorSection: some View {
        RecallSection("Processing error", icon: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 12) {
                Text(capture.errorMessage?.nonEmptyTrimmed ?? "AI processing did not complete.")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Text("The source and your note remain available and searchable.")
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
