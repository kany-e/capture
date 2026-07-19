import Foundation

enum CaptureStatus: String, Codable, CaseIterable, Sendable {
    case captured
    case processing
    case ready
    case error
}

enum CaptureSourceType: String, Codable, Sendable {
    case web
    case clipboard
}

struct Capture: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let clientCaptureID: String?
    let createdAt: String
    let updatedAt: String
    let capturedAt: String
    let status: CaptureStatus
    let sourceType: CaptureSourceType
    let sourceApp: String?
    let sourceTitle: String?
    let sourceURL: String?
    let selectedText: String
    let surroundingContext: String?
    let contextTruncated: Bool
    let userNote: String?
    let aiTitle: String?
    let aiSummary: String?
    let problem: String?
    let keyInsight: String?
    let whySaved: String?
    let caveats: [String]
    let tags: [String]
    let entities: [String]
    let searchAliases: [String]
    let errorMessage: String?
    let enrichmentVersion: Int

    enum CodingKeys: String, CodingKey {
        case id
        case clientCaptureID = "client_capture_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case capturedAt = "captured_at"
        case status
        case sourceType = "source_type"
        case sourceApp = "source_app"
        case sourceTitle = "source_title"
        case sourceURL = "source_url"
        case selectedText = "selected_text"
        case surroundingContext = "surrounding_context"
        case contextTruncated = "context_truncated"
        case userNote = "user_note"
        case aiTitle = "ai_title"
        case aiSummary = "ai_summary"
        case problem
        case keyInsight = "key_insight"
        case whySaved = "why_saved"
        case caveats
        case tags
        case entities
        case searchAliases = "search_aliases"
        case errorMessage = "error_message"
        case enrichmentVersion = "enrichment_version"
    }

    var displayTitle: String {
        if let aiTitle = aiTitle?.nonEmptyTrimmed {
            return aiTitle
        }
        if let sourceTitle = sourceTitle?.nonEmptyTrimmed {
            return sourceTitle
        }
        if let firstLine = selectedText
            .split(whereSeparator: \Character.isNewline)
            .first
            .map(String.init)?
            .nonEmptyTrimmed {
            return firstLine.truncated(to: 72)
        }
        return "Untitled memory"
    }

    var displaySummary: String? {
        aiSummary?.nonEmptyTrimmed
            ?? userNote?.nonEmptyTrimmed
            ?? selectedText.nonEmptyTrimmed?.truncated(to: 180)
    }

    var sourceLabel: String {
        sourceApp?.nonEmptyTrimmed
            ?? (sourceType == .web ? "Web" : "Clipboard")
    }

    var sourceURLValue: URL? {
        guard let sourceURL,
              let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    var createdDate: Date? {
        RecallDateParser.date(from: createdAt)
    }
}

enum RecallDateParser {
    static func date(from value: String) -> Date? {
        if let parsed = try? Date.ISO8601FormatStyle(
            includingFractionalSeconds: true
        ).parse(value) {
            return parsed
        }

        if let parsed = try? Date.ISO8601FormatStyle().parse(value) {
            return parsed
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

extension String {
    var nonEmptyTrimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func truncated(to limit: Int) -> String {
        guard count > limit else { return self }
        return String(prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
