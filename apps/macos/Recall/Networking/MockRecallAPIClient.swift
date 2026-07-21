import Foundation

actor MockRecallAPIClient: RecallAPIClient {
    private var captures: [Capture]

    init(captures: [Capture] = Capture.previewSamples) {
        self.captures = captures
    }

    func health() async throws -> HealthResponse {
        HealthResponse(
            status: "ok",
            database: "ok",
            attachments: "ok",
            openAIConfigured: true
        )
    }

    func createImageCapture(_ request: ImageCaptureUploadRequest) async throws -> Capture {
        let now = ISO8601DateFormatter().string(from: Date())
        let attachmentID = UUID().uuidString.lowercased()
        let capture = Capture(
            id: UUID().uuidString.lowercased(),
            clientCaptureID: request.metadata.clientCaptureID,
            createdAt: now,
            updatedAt: now,
            capturedAt: request.metadata.capturedAt,
            status: request.metadata.analyzeImage ? .processing : .ready,
            sourceType: .screenshot,
            sourceApp: request.metadata.sourceApp,
            sourceTitle: nil,
            sourceURL: nil,
            selectedText: "",
            surroundingContext: nil,
            contextTruncated: false,
            userNote: request.metadata.userNote,
            aiTitle: nil,
            aiSummary: nil,
            problem: nil,
            keyInsight: nil,
            whySaved: nil,
            caveats: [],
            tags: [],
            entities: [],
            searchAliases: [],
            errorMessage: nil,
            enrichmentVersion: 1,
            attachments: [
                CaptureAttachment(
                    id: attachmentID,
                    kind: "image",
                    mediaType: request.mediaType,
                    byteSize: request.imageData.count,
                    pixelWidth: 1,
                    pixelHeight: 1,
                    sha256: String(repeating: "0", count: 64),
                    contentPath: "/v1/attachments/\(attachmentID)/content"
                )
            ]
        )
        captures.insert(capture, at: 0)
        return capture
    }

    func createCapture(_ request: CaptureCreateRequest) async throws -> Capture {
        let now = ISO8601DateFormatter().string(from: Date())
        let capture = Capture(
            id: UUID().uuidString.lowercased(),
            clientCaptureID: request.clientCaptureID,
            createdAt: now,
            updatedAt: now,
            capturedAt: request.capturedAt,
            status: .processing,
            sourceType: request.sourceType,
            sourceApp: request.sourceApp,
            sourceTitle: request.sourceTitle,
            sourceURL: request.sourceURL,
            selectedText: request.selectedText,
            surroundingContext: request.surroundingContext,
            contextTruncated: request.contextTruncated,
            userNote: request.userNote,
            aiTitle: nil,
            aiSummary: nil,
            problem: nil,
            keyInsight: nil,
            whySaved: nil,
            caveats: [],
            tags: [],
            entities: [],
            searchAliases: [],
            errorMessage: nil,
            enrichmentVersion: 1
        )
        captures.insert(capture, at: 0)
        return capture
    }

    func listCaptures(limit: Int, offset: Int) async throws -> CaptureListEnvelope {
        try await listCaptures(limit: limit, offset: offset, sort: .createdNewest)
    }

    func listCaptures(
        limit: Int,
        offset: Int,
        sort: CaptureSortOrder
    ) async throws -> CaptureListEnvelope {
        let ordered = captures.sorted { left, right in
            let leftDate = left.listDate(for: sort) ?? .distantPast
            let rightDate = right.listDate(for: sort) ?? .distantPast
            switch sort {
            case .createdNewest, .editedNewest: return leftDate > rightDate
            case .createdOldest, .editedOldest: return leftDate < rightDate
            }
        }
        let start = min(offset, ordered.count)
        let end = min(start + limit, ordered.count)
        return CaptureListEnvelope(
            items: Array(ordered[start..<end]),
            limit: limit,
            offset: offset
        )
    }

    func getCapture(id: String) async throws -> Capture {
        guard let capture = captures.first(where: { $0.id == id }) else {
            throw RecallAPIError.http(
                statusCode: 404,
                code: "capture_not_found",
                message: "Capture was not found."
            )
        }
        return capture
    }

    func attachmentData(contentPath: String) async throws -> Data {
        guard captures.contains(where: {
            $0.attachments.contains(where: { $0.contentPath == contentPath })
        }) else {
            throw RecallAPIError.http(
                statusCode: 404,
                code: "attachment_not_found",
                message: "Image attachment was not found."
            )
        }
        return Data()
    }

    func deleteCapture(id: String) async throws {
        guard captures.contains(where: { $0.id == id }) else {
            throw RecallAPIError.http(
                statusCode: 404,
                code: "capture_not_found",
                message: "Capture was not found."
            )
        }
        captures.removeAll(where: { $0.id == id })
    }

    func search(query: String, limit: Int) async throws -> SearchResponse {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        let matches = captures.filter { capture in
            let haystack = [
                capture.displayTitle,
                capture.aiSummary,
                capture.userNote,
                capture.selectedText,
                capture.displayTags.joined(separator: " "),
            ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            return terms.allSatisfy(haystack.contains)
        }
        return SearchResponse(
            query: query,
            results: matches.prefix(limit).map {
                SearchResult(capture: $0, score: 1, keywordScore: 1, semanticScore: nil)
            }
        )
    }

    func enrich(id: String) async throws -> Capture {
        try await getCapture(id: id)
    }

    func extractScreenshotText(_ request: ScreenshotOCRRequest) async throws -> ScreenshotOCRResponse {
        guard Data(base64Encoded: request.imageBase64) != nil else {
            throw RecallAPIError.decoding("Invalid screenshot data")
        }
        return ScreenshotOCRResponse(
            text: "Text extracted from the screenshot.",
            provider: .openai,
            processingLocation: .cloud,
            model: "gpt-5.6"
        )
    }
}

extension Capture {
    static let previewSamples: [Capture] = [
        Capture(
            id: "4b3a30b7-55d9-4ef8-93ef-34281c826e52",
            clientCaptureID: nil,
            createdAt: "2026-07-18T17:20:04.123456Z",
            updatedAt: "2026-07-18T17:20:04.123456Z",
            capturedAt: "2026-07-18T10:20:00-07:00",
            status: .ready,
            sourceType: .web,
            sourceApp: "Google Chrome",
            sourceTitle: "Nginx serves 502 after moving a FastAPI service",
            sourceURL: "https://example.com/questions/fastapi-nginx-502",
            selectedText: "Set WorkingDirectory to the project directory and restart the service.",
            surroundingContext: "The application worked manually but failed through Nginx under systemd.",
            contextTruncated: false,
            userNote: "Every common fix failed. This was the only thing that worked on my VPS.",
            aiTitle: "The systemd working-directory fix for a VPS 502",
            aiSummary: "A FastAPI service worked manually but failed behind Nginx because systemd started it from the wrong directory.",
            problem: "A FastAPI application returned HTTP 502 through Nginx and systemd.",
            keyInsight: "The service process used the wrong working directory.",
            whySaved: "It was the only fix that worked after common suggestions failed.",
            caveats: ["Verify the deployment path before editing the service."],
            tags: ["FastAPI", "Nginx", "VPS"],
            entities: ["FastAPI", "Nginx", "systemd"],
            searchAliases: ["surprising VPS fix", "502 after common fixes failed"],
            errorMessage: nil,
            enrichmentVersion: 1
        ),
        Capture(
            id: "b355db9e-4791-4d52-a35b-058bc76e4361",
            clientCaptureID: nil,
            createdAt: "2026-07-18T16:10:00Z",
            updatedAt: "2026-07-18T16:10:00Z",
            capturedAt: "2026-07-18T09:10:00-07:00",
            status: .processing,
            sourceType: .clipboard,
            sourceApp: "Preview",
            sourceTitle: nil,
            sourceURL: nil,
            selectedText: "Memory is strongest when an idea remains connected to the situation in which it mattered.",
            surroundingContext: nil,
            contextTruncated: false,
            userNote: "Useful framing for the project introduction.",
            aiTitle: nil,
            aiSummary: nil,
            problem: nil,
            keyInsight: nil,
            whySaved: nil,
            caveats: [],
            tags: [],
            entities: [],
            searchAliases: [],
            errorMessage: nil,
            enrichmentVersion: 1
        ),
    ]
}
