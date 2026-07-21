import Foundation

protocol RecallAPIClient: Sendable {
    func health() async throws -> HealthResponse
    func createCapture(_ request: CaptureCreateRequest) async throws -> Capture
    func createImageCapture(_ request: ImageCaptureUploadRequest) async throws -> Capture
    func listCaptures(limit: Int, offset: Int) async throws -> CaptureListEnvelope
    func listCaptures(
        limit: Int,
        offset: Int,
        sort: CaptureSortOrder
    ) async throws -> CaptureListEnvelope
    func getCapture(id: String) async throws -> Capture
    func updateCapture(id: String, request: CaptureUpdateRequest) async throws -> Capture
    func attachmentData(contentPath: String) async throws -> Data
    func deleteCapture(id: String) async throws
    func search(query: String, limit: Int) async throws -> SearchResponse
    func enrich(id: String) async throws -> Capture
    func extractScreenshotText(_ request: ScreenshotOCRRequest) async throws -> ScreenshotOCRResponse
}

extension RecallAPIClient {
    func listCaptures(
        limit: Int,
        offset: Int,
        sort: CaptureSortOrder
    ) async throws -> CaptureListEnvelope {
        try await listCaptures(limit: limit, offset: offset)
    }

    func updateCapture(id: String, request: CaptureUpdateRequest) async throws -> Capture {
        throw RecallAPIError.http(
            statusCode: 501,
            code: "capture_update_unavailable",
            message: "Capture editing is not available in this client."
        )
    }

    func createImageCapture(_ request: ImageCaptureUploadRequest) async throws -> Capture {
        throw RecallAPIError.http(
            statusCode: 501,
            code: "image_capture_unavailable",
            message: "Image capture is not available in this client."
        )
    }

    func attachmentData(contentPath: String) async throws -> Data {
        throw RecallAPIError.http(
            statusCode: 501,
            code: "attachment_content_unavailable",
            message: "Image attachment content is not available in this client."
        )
    }

    func deleteCapture(id: String) async throws {
        throw RecallAPIError.http(
            statusCode: 501,
            code: "capture_delete_unavailable",
            message: "Capture deletion is not available in this client."
        )
    }

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
        try await send(path: ["health"], expectedStatusCodes: [200, 503])
    }

    func createCapture(_ request: CaptureCreateRequest) async throws -> Capture {
        try await send(
            path: ["v1", "captures"],
            method: "POST",
            body: request,
            expectedStatusCodes: [202]
        )
    }

    func createImageCapture(_ request: ImageCaptureUploadRequest) async throws -> Capture {
        let boundary = "RecallBoundary-\(UUID().uuidString)"
        let body = try multipartBody(for: request, boundary: boundary)
        return try await send(
            path: ["v1", "image-captures"],
            method: "POST",
            queryItems: [],
            bodyData: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            expectedStatusCodes: [202],
            timeoutInterval: 30
        )
    }

    func listCaptures(limit: Int, offset: Int) async throws -> CaptureListEnvelope {
        try await listCaptures(limit: limit, offset: offset, sort: .createdNewest)
    }

    func listCaptures(
        limit: Int,
        offset: Int,
        sort: CaptureSortOrder
    ) async throws -> CaptureListEnvelope {
        try await send(
            path: ["v1", "captures"],
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "sort", value: sort.rawValue),
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

    func updateCapture(id: String, request: CaptureUpdateRequest) async throws -> Capture {
        try await send(
            path: ["v1", "captures", id],
            method: "PATCH",
            body: request,
            expectedStatusCodes: [200]
        )
    }

    func attachmentData(contentPath: String) async throws -> Data {
        let components = contentPath.split(separator: "/").map(String.init)
        guard components.count == 4,
              components[0] == "v1",
              components[1] == "attachments",
              UUID(uuidString: components[2]) != nil,
              components[3] == "content" else {
            throw RecallAPIError.invalidResponse
        }
        return try await performRequest(
            path: components,
            method: "GET",
            queryItems: [],
            bodyData: nil,
            contentType: nil,
            accept: "image/png, image/jpeg",
            expectedStatusCodes: [200],
            timeoutInterval: 30
        )
    }

    func deleteCapture(id: String) async throws {
        _ = try await performRequest(
            path: ["v1", "captures", id],
            method: "DELETE",
            queryItems: [],
            bodyData: nil,
            contentType: nil,
            accept: "application/json",
            expectedStatusCodes: [204],
            timeoutInterval: 15
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

    func extractScreenshotText(_ request: ScreenshotOCRRequest) async throws -> ScreenshotOCRResponse {
        try await send(
            path: ["v1", "ocr"],
            method: "POST",
            body: request,
            expectedStatusCodes: [200],
            timeoutInterval: 50
        )
    }

    private func send<Response: Decodable>(
        path: [String],
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        expectedStatusCodes: Set<Int>,
        timeoutInterval: TimeInterval = 15
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: nil,
            contentType: nil,
            expectedStatusCodes: expectedStatusCodes,
            timeoutInterval: timeoutInterval
        )
    }

    private func send<Request: Encodable, Response: Decodable>(
        path: [String],
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Request,
        expectedStatusCodes: Set<Int>,
        timeoutInterval: TimeInterval = 15
    ) async throws -> Response {
        let encoder = JSONEncoder()
        let data = try encoder.encode(body)
        return try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: data,
            contentType: "application/json",
            expectedStatusCodes: expectedStatusCodes,
            timeoutInterval: timeoutInterval
        )
    }

    private func send<Response: Decodable>(
        path: [String],
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        contentType: String?,
        expectedStatusCodes: Set<Int>,
        timeoutInterval: TimeInterval
    ) async throws -> Response {
        let data = try await performRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData,
            contentType: contentType,
            accept: "application/json",
            expectedStatusCodes: expectedStatusCodes,
            timeoutInterval: timeoutInterval
        )
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw RecallAPIError.decoding(error.localizedDescription)
        }
    }

    private func performRequest(
        path: [String],
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?,
        contentType: String?,
        accept: String,
        expectedStatusCodes: Set<Int>,
        timeoutInterval: TimeInterval
    ) async throws -> Data {
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
        request.timeoutInterval = timeoutInterval
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecallAPIError.invalidResponse
        }

        guard expectedStatusCodes.contains(httpResponse.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            let fallback = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw RecallAPIError.http(
                statusCode: httpResponse.statusCode,
                code: envelope?.error.code,
                message: envelope?.error.message ?? "Local service returned \(httpResponse.statusCode): \(fallback)."
            )
        }

        return data
    }

    private func multipartBody(
        for request: ImageCaptureUploadRequest,
        boundary: String
    ) throws -> Data {
        var body = Data()
        func append(_ value: String) {
            body.append(Data(value.utf8))
        }

        let metadata = try JSONEncoder().encode(request.metadata)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"metadata\"\r\n")
        append("Content-Type: application/json\r\n\r\n")
        body.append(metadata)
        append("\r\n")

        let filename = request.mediaType == "image/jpeg" ? "capture.jpg" : "capture.png"
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(request.mediaType)\r\n\r\n")
        body.append(request.imageData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
