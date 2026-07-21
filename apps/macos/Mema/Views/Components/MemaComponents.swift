import AppKit
import SwiftUI

struct AttachmentImageView: View {
    enum Style {
        case thumbnail
        case detail
    }

    @EnvironmentObject private var store: MemaStore
    let attachment: CaptureAttachment
    let style: Style

    var body: some View {
        Group {
            if let data = store.attachmentImageData[attachment.id],
               let image = NSImage(data: data) {
                switch style {
                case .thumbnail:
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 56)
                        .clipped()
                case .detail:
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 560)
                }
            } else if store.attachmentImageErrors.contains(attachment.id) {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(style == .thumbnail ? .title3 : .largeTitle)
                        .foregroundStyle(.secondary)
                    if style == .detail {
                        Text("Image unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Retry") {
                        Task { await store.loadAttachmentImage(attachment) }
                    }
                    .buttonStyle(.borderless)
                }
                .frame(
                    width: style == .thumbnail ? 72 : nil,
                    height: style == .thumbnail ? 56 : 220
                )
            } else {
                ZStack {
                    Color.primary.opacity(0.045)
                    Image(systemName: "photo")
                        .font(style == .thumbnail ? .title3 : .largeTitle)
                        .foregroundStyle(.tertiary)
                }
                .frame(
                    width: style == .thumbnail ? 72 : nil,
                    height: style == .thumbnail ? 56 : 220
                )
            }
        }
        .background(.black.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: style == .thumbnail ? 9 : 13))
        .overlay {
            RoundedRectangle(cornerRadius: style == .thumbnail ? 9 : 13)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
        .task(id: attachment.id) {
            await store.loadAttachmentImage(attachment)
        }
        .accessibilityLabel("Saved image attachment")
    }
}

struct CaptureStatusBadge: View {
    let status: CaptureStatus

    var body: some View {
        HStack(spacing: 5) {
            if status == .processing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.11), in: Capsule())
        .accessibilityLabel("Status: \(label)")
    }

    private var label: String {
        switch status {
        case .captured: "Captured"
        case .processing: "Processing"
        case .ready: "Ready"
        case .error: "Needs attention"
        }
    }

    private var iconName: String {
        switch status {
        case .captured: "tray.and.arrow.down.fill"
        case .processing: "sparkles"
        case .ready: "checkmark"
        case .error: "exclamationmark"
        }
    }

    private var color: Color {
        switch status {
        case .captured: .secondary
        case .processing: .orange
        case .ready: .green
        case .error: .red
        }
    }
}

struct BackendConnectionPill: View {
    let state: BackendConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var label: String {
        switch state {
        case .checking: "Connecting"
        case .connected: "Connected"
        case .degraded: "Storage unavailable"
        case .disconnected: "Offline"
        }
    }

    private var helpText: String {
        switch state {
        case .checking:
            "Checking the local Mema service"
        case let .connected(openAIConfigured):
            openAIConfigured
                ? "Local service connected; AI is configured"
                : "Local service connected; AI is not configured"
        case .degraded:
            "The local Mema service is running, but its database or attachment storage is unavailable"
        case .disconnected:
            "The local Mema service is not available"
        }
    }

    private var color: Color {
        switch state {
        case .checking: .orange
        case .connected: .green
        case .degraded: .red
        case .disconnected: .red
        }
    }
}

struct MemaSection<Content: View>: View {
    let eyebrow: String
    let icon: String
    @ViewBuilder let content: Content

    init(
        _ eyebrow: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(eyebrow.uppercased(), systemImage: icon)
                .font(.caption.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.10), in: Capsule())
    }
}

struct NoticeBanner: View {
    let notice: AppNotice
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(notice.message)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 12)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(color.opacity(0.09))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var icon: String {
        switch notice.style {
        case .information: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch notice.style {
        case .information: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }
}
