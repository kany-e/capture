import Foundation

protocol RecallAPIClient: Sendable {
    func health() async throws -> HealthResponse
    func createCapture(_ request: CaptureCreateRequest) async throws -> Capture
    func listCaptures(limit: Int, offset: Int) async throws -> CaptureListEnvelope
    func getCapture(id: String) async throws -> Capture
    func search(query: String, limit: Int) async throws -> SearchResponse
    func enrich(id: String) async throws -> Capture
}

extension RecallAPIClient {
    func listCaptures() async throws -> CaptureListEnvelope {
        try await listCaptures(limit: 50, offset: 0)
    }

    func search(query: String) async throws -> SearchResponse {
        try await search(query: query, limit: 20)
    }
}

struct LiveRecallAPIClient: RecallAPIClient, Sendable {
    let baseURL: URL
    let session: URLSession

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:8765")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func health() async throws -> HealthResponse {
        try await send(path: ["health"], expectedStatusCodes: [200])
    }

    func createCapture(_ request: CaptureCreateRequest) async throws -> Capture {
        try await send(
            path: ["v1", "captures"],
            method: "POST",
            body: request,
            expectedStatusCodes: [202]
        )
    }

    func listCaptures(limit: Int, offset: Int) async throws -> CaptureListEnvelope {
        try await send(
            path: ["v1", "captures"],
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ],
            expectedStatusCodes: [200]
        )
    }

    func getCapture(id: String) async throws -> Capture {
        try await send(
            path: ["v1", "captures", id],
            expectedStatusCodes: [200]
        )
    }

    func search(query: String, limit: Int) async throws -> SearchResponse {
        try await send(
            path: ["v1", "search"],
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            expectedStatusCodes: [200]
        )
    }

    func enrich(id: String) async throws -> Capture {
        try await send(
            path: ["v1", "captures", id, "enrich"],
            method: "POST",
            expectedStatusCodes: [202]
        )
    }

    private func send<Response: Decodable>(
        path: [String],
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        expectedStatusCodes: Set<Int>
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: nil,
            expectedStatusCodes: expectedStatusCodes
        )
    }

    private func send<Request: Encodable, Response: Decodable>(
        path: [String],
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Request,
        expectedStatusCodes: Set<Int>
    ) async throws -> Response {
        let encoder = JSONEncoder()
        let data = try encoder.encode(body)
        return try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: data,
            expectedStatusCodes: expectedStatusCodes
        )
    }

    private func send<Response: Decodable>(
        path: [String],
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        expectedStatusCodes: Set<Int>
    ) async throws -> Response {
        var url = baseURL
        for component in path {
            url.appendPathComponent(component)
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw RecallAPIError.invalidResponse
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let requestURL = components.url else {
            throw RecallAPIError.invalidResponse
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.httpBody = bodyData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecallAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        guard expectedStatusCodes.contains(httpResponse.statusCode) else {
            let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
            let fallback = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw RecallAPIError.http(
                statusCode: httpResponse.statusCode,
                code: envelope?.error.code,
                message: envelope?.error.message ?? "Local service returned \(httpResponse.statusCode): \(fallback)."
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw RecallAPIError.decoding(error.localizedDescription)
        }
    }
}
