import Foundation

struct HealthResponse: Codable, Equatable, Sendable {
    let status: String
    let database: String
    let attachments: String
    let openAIConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case database
        case attachments
        case openAIConfigured = "openai_configured"
    }

    init(
        status: String,
        database: String,
        attachments: String = "ok",
        openAIConfigured: Bool
    ) {
        self.status = status
        self.database = database
        self.attachments = attachments
        self.openAIConfigured = openAIConfigured
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        database = try container.decode(String.self, forKey: .database)
        attachments = try container.decodeIfPresent(
            String.self,
            forKey: .attachments
        ) ?? "ok"
        openAIConfigured = try container.decode(
            Bool.self,
            forKey: .openAIConfigured
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(database, forKey: .database)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(openAIConfigured, forKey: .openAIConfigured)
    }
}

struct ImageCaptureCreateMetadata: Codable, Equatable, Sendable {
    let clientCaptureID: String
    let sourceApp: String?
    let userNote: String?
    let capturedAt: String
    let analyzeImage: Bool

    enum CodingKeys: String, CodingKey {
        case clientCaptureID = "client_capture_id"
        case sourceApp = "source_app"
        case userNote = "user_note"
        case capturedAt = "captured_at"
        case analyzeImage = "analyze_image"
    }
}

struct ImageCaptureUploadRequest: Equatable, Sendable {
    let metadata: ImageCaptureCreateMetadata
    let imageData: Data
    let mediaType: String
}

struct CaptureListEnvelope: Codable, Equatable, Sendable {
    let items: [Capture]
    let limit: Int
    let offset: Int
}

struct CaptureUpdateRequest: Codable, Equatable, Sendable {
    let selectedText: String?
    let userNote: String?
    let sourceApp: String?
    let sourceTitle: String?
    let sourceURL: String?
    let userTitle: String?
    let userProblem: String?
    let userKeyInsight: String?
    let userWhySaved: String?
    let userCaveats: [String]?
    let userTags: [String]?
    let showAIInterpretation: Bool

    enum CodingKeys: String, CodingKey {
        case selectedText = "selected_text"
        case userNote = "user_note"
        case sourceApp = "source_app"
        case sourceTitle = "source_title"
        case sourceURL = "source_url"
        case userTitle = "user_title"
        case userProblem = "user_problem"
        case userKeyInsight = "user_key_insight"
        case userWhySaved = "user_why_saved"
        case userCaveats = "user_caveats"
        case userTags = "user_tags"
        case showAIInterpretation = "show_ai_interpretation"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullable(selectedText, forKey: .selectedText)
        try container.encodeNullable(userNote, forKey: .userNote)
        try container.encodeNullable(sourceApp, forKey: .sourceApp)
        try container.encodeNullable(sourceTitle, forKey: .sourceTitle)
        try container.encodeNullable(sourceURL, forKey: .sourceURL)
        try container.encodeNullable(userTitle, forKey: .userTitle)
        try container.encodeNullable(userProblem, forKey: .userProblem)
        try container.encodeNullable(userKeyInsight, forKey: .userKeyInsight)
        try container.encodeNullable(userWhySaved, forKey: .userWhySaved)
        try container.encodeNullable(userCaveats, forKey: .userCaveats)
        try container.encodeNullable(userTags, forKey: .userTags)
        try container.encode(showAIInterpretation, forKey: .showAIInterpretation)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNullable<T: Encodable>(
        _ value: T?,
        forKey key: Key
    ) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

struct SearchResponse: Codable, Equatable, Sendable {
    let query: String
    let results: [SearchResult]
}

struct SearchResult: Codable, Equatable, Sendable {
    let capture: Capture
    let score: Double
    let keywordScore: Double
    let semanticScore: Double?

    enum CodingKeys: String, CodingKey {
        case capture
        case score
        case keywordScore = "keyword_score"
        case semanticScore = "semantic_score"
    }
}

struct ScreenshotOCRRequest: Codable, Equatable, Sendable {
    let mediaType: String
    let imageBase64: String

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case imageBase64 = "image_base64"
    }
}

enum ScreenshotOCRProvider: String, Codable, Equatable, Sendable {
    case openai
}

enum ScreenshotOCRProcessingLocation: String, Codable, Equatable, Sendable {
    case cloud
}

struct ScreenshotOCRResponse: Codable, Equatable, Sendable {
    let text: String
    let provider: ScreenshotOCRProvider
    let processingLocation: ScreenshotOCRProcessingLocation
    let model: String

    enum CodingKeys: String, CodingKey {
        case text
        case provider
        case processingLocation = "processing_location"
        case model
    }
}
