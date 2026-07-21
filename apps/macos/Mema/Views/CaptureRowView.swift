import SwiftUI

struct CaptureRowView: View {
    let capture: Capture
    var sortOrder: CaptureSortOrder = .createdNewest

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
                if let attachment = capture.primaryImageAttachment {
                    AttachmentImageView(attachment: attachment, style: .thumbnail)
                }
            }

            if !capture.displayTags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(capture.displayTags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.primary.opacity(0.06), in: Capsule())
                    }
                    if capture.displayTags.count > 3 {
                        Text("+\(capture.displayTags.count - 3)")
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
                if let date = capture.listDate(for: sortOrder) {
                    Text(
                        date.formatted(
                            date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated,
                            time: .shortened
                        )
                    )
                    .monospacedDigit()
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
        Image(systemName: capture.sourceType.systemImageName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 30, height: 30)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
