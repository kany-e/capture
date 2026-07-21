import SwiftUI

struct CaptureListView: View {
    @EnvironmentObject private var store: MemaStore
    @EnvironmentObject private var captureCoordinator: GlobalCaptureCoordinator
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
                    Text("Mema")
                        .font(.title2.weight(.bold))
                    BackendConnectionPill(state: store.connectionState)
                }
                Spacer()
                Menu {
                    Button("Capture Clipboard", systemImage: "doc.on.clipboard") {
                        captureCoordinator.prepareClipboardCapture()
                    }
                    Button("Capture Screenshot Note", systemImage: "viewfinder") {
                        beginScreenshotCapture()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("New Capture")
                .accessibilityLabel("New Capture")

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

            HStack {
                if store.query.nonEmptyTrimmed == nil {
                    Menu {
                        ForEach(CaptureSortOrder.allCases) { order in
                            Button {
                                Task { await store.setSortOrder(order) }
                            } label: {
                                if order == store.sortOrder {
                                    Label(order.label, systemImage: "checkmark")
                                } else {
                                    Text(order.label)
                                }
                            }
                        }
                    } label: {
                        Label(store.sortOrder.label, systemImage: "arrow.up.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Sort memories")
                } else {
                    Label("Search results · relevance", systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.caption)

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
                Label("Mema is offline", systemImage: "bolt.horizontal.circle")
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
                         ? "Copy something useful, then capture it from Mema's menu bar."
                         : "Try a different phrase or clear the search.")
                } actions: {
                    if store.query.nonEmptyTrimmed == nil {
                        HStack {
                            Button("Capture Clipboard") {
                                captureCoordinator.prepareClipboardCapture()
                            }
                            Button("Screenshot Note") {
                                beginScreenshotCapture()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List(store.captures, selection: $store.selectedCaptureID) { capture in
                    CaptureRowView(capture: capture, sortOrder: store.sortOrder)
                        .tag(capture.id)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func beginScreenshotCapture() {
        captureCoordinator.prepareScreenshotCapture()
    }
}
