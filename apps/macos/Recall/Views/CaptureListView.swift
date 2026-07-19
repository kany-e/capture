import SwiftUI

struct CaptureListView: View {
    @EnvironmentObject private var store: RecallStore
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(.regularMaterial)
        .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 430)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recall")
                        .font(.title2.weight(.bold))
                    BackendConnectionPill(state: store.connectionState)
                }
                Spacer()
                Button {
                    _ = store.prepareClipboardCapture()
                    NotificationCenter.default.post(name: .openQuickCapture, object: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Capture Clipboard")
                .accessibilityLabel("Capture Clipboard")

                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .accessibilityLabel("Refresh")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search your memories", text: $store.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search your memories")
                if store.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !store.query.isEmpty {
                    Button {
                        store.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }

            if let searchError = store.searchError {
                Label(searchError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading your memories…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Recall is offline", systemImage: "bolt.horizontal.circle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .loaded:
            if store.captures.isEmpty {
                ContentUnavailableView {
                    Label(
                        store.query.nonEmptyTrimmed == nil ? "No memories yet" : "No matches",
                        systemImage: store.query.nonEmptyTrimmed == nil ? "sparkles" : "magnifyingglass"
                    )
                } description: {
                    Text(store.query.nonEmptyTrimmed == nil
                         ? "Copy something useful, then capture it from Recall's menu bar."
                         : "Try a different phrase or clear the search.")
                } actions: {
                    if store.query.nonEmptyTrimmed == nil {
                        Button("Capture Clipboard") {
                            _ = store.prepareClipboardCapture()
                            NotificationCenter.default.post(name: .openQuickCapture, object: nil)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List(store.captures, selection: $store.selectedCaptureID) { capture in
                    CaptureRowView(capture: capture)
                        .tag(capture.id)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

extension Notification.Name {
    static let openQuickCapture = Notification.Name("Recall.openQuickCapture")
}
