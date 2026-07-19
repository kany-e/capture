import Foundation

struct CaptureCreateRequest: Codable, Equatable, Sendable {
    let clientCaptureID: String?
    let sourceType: CaptureSourceType
    let sourceApp: String?
    let sourceTitle: String?
    let sourceURL: String?
    let selectedText: String
    let surroundingContext: String?
    let contextTruncated: Bool
    let userNote: String?
    let capturedAt: String

    enum CodingKeys: String, CodingKey {
        case clientCaptureID = "client_capture_id"
        case sourceType = "source_type"
        case sourceApp = "source_app"
        case sourceTitle = "source_title"
        case sourceURL = "source_url"
        case selectedText = "selected_text"
        case surroundingContext = "surrounding_context"
        case contextTruncated = "context_truncated"
        case userNote = "user_note"
        case capturedAt = "captured_at"
    }

    static func clipboard(
        clientCaptureID: String,
        capturedAt: String,
        text: String,
        sourceApp: String?,
        userNote: String?
    ) -> CaptureCreateRequest {
        return CaptureCreateRequest(
            clientCaptureID: clientCaptureID,
            sourceType: .clipboard,
            sourceApp: sourceApp,
            sourceTitle: nil,
            sourceURL: nil,
            selectedText: text,
            surroundingContext: nil,
            contextTruncated: false,
            userNote: userNote,
            capturedAt: capturedAt
        )
    }

    static func currentTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
