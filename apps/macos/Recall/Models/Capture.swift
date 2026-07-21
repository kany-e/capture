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
    case screenshot

    var systemImageName: String {
        switch self {
        case .web: return "globe"
        case .clipboard: return "doc.on.clipboard"
        case .screenshot: return "camera.viewfinder"
        }
    }
}

enum CaptureSortOrder: String, CaseIterable, Identifiable, Sendable {
    case createdNewest = "created_desc"
    case createdOldest = "created_asc"
    case editedNewest = "edited_desc"
    case editedOldest = "edited_asc"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .createdNewest: "Created · newest first"
        case .createdOldest: "Created · oldest first"
        case .editedNewest: "Last edited · newest first"
        case .editedOldest: "Last edited · oldest first"
        }
    }

    var shortLabel: String {
        switch self {
        case .createdNewest, .createdOldest: "Created"
        case .editedNewest, .editedOldest: "Edited"
        }
    }

    var usesEditedTime: Bool {
        switch self {
        case .createdNewest, .createdOldest: false
        case .editedNewest, .editedOldest: true
        }
    }
}

struct CaptureAttachment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: String
    let mediaType: String
    let byteSize: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let sha256: String
    let contentPath: String

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case mediaType = "media_type"
        case byteSize = "byte_size"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
        case sha256
        case contentPath = "content_path"
    }
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
    var userEditedAt: String? = nil
    var userSelectedText: String? = nil
    var userSourceApp: String? = nil
    var userSourceTitle: String? = nil
    var userSourceURL: String? = nil
    var userTitle: String? = nil
    var userProblem: String? = nil
    var userKeyInsight: String? = nil
    var userWhySaved: String? = nil
    var userCaveats: [String]? = nil
    var userTags: [String]? = nil
    var aiInterpretationHidden = false
    var aiContentStale = false
    var attachments: [CaptureAttachment] = []

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
        case userEditedAt = "user_edited_at"
        case userSelectedText = "user_selected_text"
        case userSourceApp = "user_source_app"
        case userSourceTitle = "user_source_title"
        case userSourceURL = "user_source_url"
        case userTitle = "user_title"
        case userProblem = "user_problem"
        case userKeyInsight = "user_key_insight"
        case userWhySaved = "user_why_saved"
        case userCaveats = "user_caveats"
        case userTags = "user_tags"
        case aiInterpretationHidden = "ai_interpretation_hidden"
        case aiContentStale = "ai_content_stale"
        case attachments
    }

    var displayTitle: String {
        if let userTitle = userTitle?.nonEmptyTrimmed {
            return userTitle
        }
        if !aiInterpretationHidden, let aiTitle = aiTitle?.nonEmptyTrimmed {
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
        return attachments.isEmpty ? "Untitled memory" : "Image note"
    }

    var displaySummary: String? {
        (!aiInterpretationHidden ? aiSummary?.nonEmptyTrimmed : nil)
            ?? userNote?.nonEmptyTrimmed
            ?? selectedText.nonEmptyTrimmed?.truncated(to: 180)
    }

    var displayProblem: String? {
        effectiveText(userProblem, fallback: problem)
    }

    var displayKeyInsight: String? {
        effectiveText(userKeyInsight, fallback: keyInsight)
    }

    var displayWhySaved: String? {
        effectiveText(userWhySaved, fallback: whySaved)
    }

    var displayCaveats: [String] {
        userCaveats ?? (aiInterpretationHidden ? [] : caveats)
    }

    var displayTags: [String] {
        userTags ?? (aiInterpretationHidden ? [] : tags)
    }

    var hasUserOrganizationOverrides: Bool {
        userTitle != nil
            || userProblem != nil
            || userKeyInsight != nil
            || userWhySaved != nil
            || userCaveats != nil
            || userTags != nil
    }

    var primaryImageAttachment: CaptureAttachment? {
        attachments.first(where: { $0.kind == "image" })
    }

    var sourceLabel: String {
        if let sourceApp = sourceApp?.nonEmptyTrimmed {
            return sourceApp
        }
        switch sourceType {
        case .web: return "Web"
        case .clipboard: return "Clipboard"
        case .screenshot: return "Screenshot"
        }
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

    var userEditedDate: Date? {
        userEditedAt.flatMap(RecallDateParser.date(from:))
    }

    func listDate(for sortOrder: CaptureSortOrder) -> Date? {
        if sortOrder.usesEditedTime {
            return userEditedDate ?? createdDate
        }
        return createdDate
    }

    private func effectiveText(_ userValue: String?, fallback: String?) -> String? {
        if let userValue {
            return userValue.nonEmptyTrimmed
        }
        return aiInterpretationHidden ? nil : fallback?.nonEmptyTrimmed
    }
}

extension Capture {
    /// Keeps a newer app compatible with a backend from before image attachments.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        clientCaptureID = try container.decodeIfPresent(String.self, forKey: .clientCaptureID)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        capturedAt = try container.decode(String.self, forKey: .capturedAt)
        status = try container.decode(CaptureStatus.self, forKey: .status)
        sourceType = try container.decode(CaptureSourceType.self, forKey: .sourceType)
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        selectedText = try container.decode(String.self, forKey: .selectedText)
        surroundingContext = try container.decodeIfPresent(String.self, forKey: .surroundingContext)
        contextTruncated = try container.decode(Bool.self, forKey: .contextTruncated)
        userNote = try container.decodeIfPresent(String.self, forKey: .userNote)
        aiTitle = try container.decodeIfPresent(String.self, forKey: .aiTitle)
        aiSummary = try container.decodeIfPresent(String.self, forKey: .aiSummary)
        problem = try container.decodeIfPresent(String.self, forKey: .problem)
        keyInsight = try container.decodeIfPresent(String.self, forKey: .keyInsight)
        whySaved = try container.decodeIfPresent(String.self, forKey: .whySaved)
        caveats = try container.decode([String].self, forKey: .caveats)
        tags = try container.decode([String].self, forKey: .tags)
        entities = try container.decode([String].self, forKey: .entities)
        searchAliases = try container.decode([String].self, forKey: .searchAliases)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        enrichmentVersion = try container.decode(Int.self, forKey: .enrichmentVersion)
        userEditedAt = try container.decodeIfPresent(String.self, forKey: .userEditedAt)
        userSelectedText = try container.decodeIfPresent(String.self, forKey: .userSelectedText)
        userSourceApp = try container.decodeIfPresent(String.self, forKey: .userSourceApp)
        userSourceTitle = try container.decodeIfPresent(String.self, forKey: .userSourceTitle)
        userSourceURL = try container.decodeIfPresent(String.self, forKey: .userSourceURL)
        userTitle = try container.decodeIfPresent(String.self, forKey: .userTitle)
        userProblem = try container.decodeIfPresent(String.self, forKey: .userProblem)
        userKeyInsight = try container.decodeIfPresent(String.self, forKey: .userKeyInsight)
        userWhySaved = try container.decodeIfPresent(String.self, forKey: .userWhySaved)
        userCaveats = try container.decodeIfPresent([String].self, forKey: .userCaveats)
        userTags = try container.decodeIfPresent([String].self, forKey: .userTags)
        aiInterpretationHidden = try container.decodeIfPresent(
            Bool.self,
            forKey: .aiInterpretationHidden
        ) ?? false
        aiContentStale = try container.decodeIfPresent(
            Bool.self,
            forKey: .aiContentStale
        ) ?? false
        attachments = try container.decodeIfPresent(
            [CaptureAttachment].self,
            forKey: .attachments
        ) ?? []
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

/// A bounded, display-only projection of surrounding context.
///
/// The complete value remains on `Capture` for search and AI processing. Keeping
/// this projection small prevents SwiftUI's selectable `Text` from laying out a
/// whole web page when a browser capture contains unusually broad context.
struct SurroundingContextPreview: Equatable, Sendable {
    static let defaultCharacterLimit = 2_000
    static let defaultLineLimit = 60

    let text: String
    let totalCharacterCount: Int
    let displayedCharacterCount: Int
    let displayedLineCount: Int

    var omittedCharacterCount: Int {
        totalCharacterCount - displayedCharacterCount
    }

    var isDisplayLimited: Bool {
        omittedCharacterCount > 0
    }

    init?(
        context: String?,
        characterLimit: Int = SurroundingContextPreview.defaultCharacterLimit,
        lineLimit: Int = SurroundingContextPreview.defaultLineLimit
    ) {
        guard characterLimit > 0,
              lineLimit > 0,
              let context,
              let firstContentIndex = context.firstIndex(where: { !$0.isWhitespace }),
              let lastContentIndex = context.lastIndex(where: { !$0.isWhitespace }) else {
            return nil
        }

        let trimmedContext = context[firstContentIndex...lastContentIndex]
        let characterCount = trimmedContext.count
        var displayEnd = trimmedContext.index(
            trimmedContext.startIndex,
            offsetBy: min(characterCount, characterLimit)
        )
        var currentIndex = trimmedContext.startIndex
        var lineBreakCount = 0

        while currentIndex < displayEnd {
            if trimmedContext[currentIndex].isNewline {
                lineBreakCount += 1
                if lineBreakCount >= lineLimit {
                    displayEnd = currentIndex
                    break
                }
            }
            currentIndex = trimmedContext.index(after: currentIndex)
        }

        let displayedText = String(trimmedContext[..<displayEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        text = displayedText
        totalCharacterCount = characterCount
        displayedCharacterCount = displayedText.count
        displayedLineCount = displayedText.reduce(into: 1) { count, character in
            if character.isNewline {
                count += 1
            }
        }
    }
}
