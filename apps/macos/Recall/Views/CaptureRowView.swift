import SwiftUI

struct CaptureRowView: View {
    let capture: Capture

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                sourceIcon
                VStack(alignment: .leading, spacing: 5) {
                    Text(capture.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    if let summary = capture.displaySummary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
            }

            if !capture.tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(capture.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.primary.opacity(0.06), in: Capsule())
                    }
                    if capture.tags.count > 3 {
                        Text("+\(capture.tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                CaptureStatusBadge(status: capture.status)
                Text(capture.sourceLabel)
                    .lineLimit(1)
                Spacer()
                if let createdDate = capture.createdDate {
                    Text(createdDate, style: .relative)
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var sourceIcon: some View {
        Image(systemName: capture.sourceType == .web ? "globe" : "doc.on.clipboard")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 30, height: 30)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
