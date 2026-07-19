import Foundation

struct HealthResponse: Codable, Equatable, Sendable {
    let status: String
    let database: String
    let openAIConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case database
        case openAIConfigured = "openai_configured"
    }
}

struct CaptureListEnvelope: Codable, Equatable, Sendable {
    let items: [Capture]
    let limit: Int
    let offset: Int
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
