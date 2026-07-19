import Foundation

struct APIErrorEnvelope: Decodable, Sendable {
    let error: APIErrorBody
}

struct APIErrorBody: Decodable, Sendable {
    let code: String
    let message: String
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case requestID = "request_id"
    }
}

enum RecallAPIError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse
    case http(statusCode: Int, code: String?, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Recall received an invalid response from the local service."
        case let .http(_, _, message):
            return message
        case .decoding:
            return "Recall could not understand data returned by the local service."
        }
    }

    var code: String? {
        guard case let .http(_, code, _) = self else { return nil }
        return code
    }

    var statusCode: Int? {
        guard case let .http(statusCode, _, _) = self else { return nil }
        return statusCode
    }
}

extension Error {
    var recallUserMessage: String {
        if let apiError = self as? RecallAPIError {
            return apiError.localizedDescription
        }

        if let urlError = self as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return "Recall's local service is not running. Start the backend and try again."
            case .timedOut:
                return "The local service took too long to respond."
            case .cancelled:
                return "The request was cancelled."
            default:
                return urlError.localizedDescription
            }
        }

        return localizedDescription
    }
}
