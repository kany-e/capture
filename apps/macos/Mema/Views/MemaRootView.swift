import SwiftUI

struct MemaRootView: View {
    @EnvironmentObject private var store: MemaStore
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let notice = store.notice {
                NoticeBanner(notice: notice, dismiss: store.dismissNotice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            NavigationSplitView {
                CaptureListView(isSearchFocused: $isSearchFocused)
            } detail: {
                if let capture = store.selectedCapture {
                    CaptureDetailView(capture: capture)
                        .id(capture.id)
                } else {
                    ContentUnavailableView(
                        "Select a memory",
                        systemImage: "rectangle.stack",
                        description: Text("Choose a capture to see its source, your note, and the AI interpretation.")
                    )
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
        .frame(minWidth: 820, minHeight: 560)
        .animation(.easeOut(duration: 0.18), value: store.notice)
        .task {
            await store.start()
        }
        .task {
            await store.runForegroundRefreshLoop()
        }
        .task(id: store.query) {
            if store.loadState == .loaded || store.query.nonEmptyTrimmed != nil {
                await store.search()
            }
        }
        .task(id: store.selectedCaptureID) {
            await store.refreshSelectedCapture()
        }
        .onChange(of: store.searchFocusToken) {
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refresh() }
        }
    }
}
