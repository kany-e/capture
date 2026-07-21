import Foundation
import XCTest

@testable import Recall

final class LiveRecallAPIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testHealthDecodesHealthy200Response() async throws {
        let recorder = RequestRecorder()
        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 200,
                data: Data(
                    #"{"status":"ok","database":"ok","openai_configured":true}"#.utf8
                )
            )
        }

        let response = try await makeClient().health()

        XCTAssertEqual(
            response,
            HealthResponse(status: "ok", database: "ok", openAIConfigured: true)
        )
        XCTAssertEqual(recorder.request?.httpMethod, "GET")
        XCTAssertEqual(recorder.request?.url?.path, "/health")
    }

    func testHealthDecodesDegraded503Response() async throws {
        let recorder = RequestRecorder()
        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 503,
                data: Data(
                    #"{"status":"degraded","database":"error","openai_configured":false}"#.utf8
                )
            )
        }

        let response = try await makeClient().health()

        XCTAssertEqual(
            response,
            HealthResponse(
                status: "degraded",
                database: "error",
                openAIConfigured: false
            )
        )
        XCTAssertEqual(recorder.request?.httpMethod, "GET")
        XCTAssertEqual(recorder.request?.url?.path, "/health")
    }

    func testListCapturesDecodesItemsEnvelopeAndPagination() async throws {
        let recorder = RequestRecorder()
        let captureObject = try ContractFixtures.readyCaptureJSONObject()
        let responseData = try JSONSerialization.data(
            withJSONObject: [
                "items": [captureObject],
                "limit": 17,
                "offset": 3,
            ]
        )
        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 200,
                data: responseData
            )
        }

        let envelope = try await makeClient().listCaptures(limit: 17, offset: 3)

        XCTAssertEqual(envelope.limit, 17)
        XCTAssertEqual(envelope.offset, 3)
        XCTAssertEqual(envelope.items.count, 1)
        XCTAssertEqual(envelope.items.first?.status, .ready)
        XCTAssertEqual(
            envelope.items.first?.id,
            "4b3a30b7-55d9-4ef8-93ef-34281c826e52"
        )

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/captures")
        let queryItems = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) }),
            ["limit": "17", "offset": "3", "sort": "created_desc"]
        )
    }

    func testUpdateCaptureSendsUserLayerPatchAndDecodesEditingMetadata() async throws {
        let recorder = RequestRecorder()
        var captureObject = try ContractFixtures.readyCaptureJSONObject()
        captureObject["user_edited_at"] = "2026-07-21T20:00:00Z"
        captureObject["user_title"] = "My title"
        captureObject["user_tags"] = ["manual"]
        captureObject["ai_content_stale"] = true
        captureObject["ai_interpretation_hidden"] = true
        let responseData = try JSONSerialization.data(withJSONObject: captureObject)
        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 200,
                data: responseData
            )
        }
        let update = CaptureUpdateRequest(
            selectedText: "Corrected source",
            userNote: "Updated note",
            sourceApp: nil,
            sourceTitle: nil,
            sourceURL: nil,
            userTitle: "My title",
            userProblem: nil,
            userKeyInsight: nil,
            userWhySaved: nil,
            userCaveats: nil,
            userTags: ["manual"],
            showAIInterpretation: true
        )

        let capture = try await makeClient().updateCapture(
            id: "4b3a30b7-55d9-4ef8-93ef-34281c826e52",
            request: update
        )

        XCTAssertEqual(capture.userTitle, "My title")
        XCTAssertEqual(capture.displayTags, ["manual"])
        XCTAssertTrue(capture.aiContentStale)
        XCTAssertTrue(capture.aiInterpretationHidden)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(
            request.url?.path,
            "/v1/captures/4b3a30b7-55d9-4ef8-93ef-34281c826e52"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try requestBodyData(from: request))
                as? [String: Any]
        )
        XCTAssertEqual(object["selected_text"] as? String, "Corrected source")
        XCTAssertEqual(object["user_title"] as? String, "My title")
        XCTAssertEqual(object["user_tags"] as? [String], ["manual"])
        XCTAssertEqual(object["show_ai_interpretation"] as? Bool, true)
        XCTAssertTrue(object["source_app"] is NSNull)
        XCTAssertTrue(object["user_note"] as? String == "Updated note")
        XCTAssertTrue(object["user_problem"] is NSNull)
    }

    func testCreateCaptureSendsJSONPostAndAccepts202() async throws {
        let requestBody = CaptureCreateRequest(
            clientCaptureID: "ca1ad8ce-196d-48af-ad2f-b4a9b79f71f9",
            sourceType: .clipboard,
            sourceApp: "Xcode",
            sourceTitle: nil,
            sourceURL: nil,
            selectedText: "Captured locally",
            surroundingContext: nil,
            contextTruncated: false,
            userNote: "Keep this for later.",
            capturedAt: "2026-07-18T17:20:01.123456Z"
        )
        let recorder = RequestRecorder()
        var captureObject = try ContractFixtures.readyCaptureJSONObject()
        captureObject["client_capture_id"] = requestBody.clientCaptureID
        captureObject["status"] = "processing"
        captureObject["source_type"] = "clipboard"
        captureObject["source_app"] = "Xcode"
        captureObject["source_title"] = NSNull()
        captureObject["source_url"] = NSNull()
        captureObject["selected_text"] = requestBody.selectedText
        captureObject["surrounding_context"] = NSNull()
        captureObject["user_note"] = requestBody.userNote
        captureObject["captured_at"] = requestBody.capturedAt
        captureObject["ai_title"] = NSNull()
        captureObject["ai_summary"] = NSNull()
        captureObject["problem"] = NSNull()
        captureObject["key_insight"] = NSNull()
        captureObject["why_saved"] = NSNull()
        captureObject["caveats"] = []
        captureObject["tags"] = []
        captureObject["entities"] = []
        captureObject["search_aliases"] = []
        captureObject["enrichment_version"] = 0
        let responseData = try JSONSerialization.data(withJSONObject: captureObject)
        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 202,
                data: responseData
            )
        }

        let capture = try await makeClient().createCapture(requestBody)

        XCTAssertEqual(capture.status, .processing)
        XCTAssertEqual(capture.selectedText, requestBody.selectedText)
        XCTAssertEqual(capture.clientCaptureID, requestBody.clientCaptureID)

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/captures")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let encodedBody = try requestBodyData(from: request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedBody) as? [String: Any]
        )
        XCTAssertEqual(object["client_capture_id"] as? String, requestBody.clientCaptureID)
        XCTAssertEqual(object["source_type"] as? String, "clipboard")
        XCTAssertEqual(object["selected_text"] as? String, requestBody.selectedText)
        XCTAssertNil(object["source_url"])
    }

    func testCreateImageCaptureSendsMultipartImageAndMetadata() async throws {
        let recorder = RequestRecorder()
        let attachmentID = "4cfe5742-43e0-4bf4-9f79-bec7ef9954c2"
        var captureObject = try ContractFixtures.readyCaptureJSONObject()
        captureObject["status"] = "processing"
        captureObject["source_type"] = "screenshot"
        captureObject["selected_text"] = ""
        captureObject["attachments"] = [[
            "id": attachmentID,
            "kind": "image",
            "media_type": "image/png",
            "byte_size": 4,
            "pixel_width": 10,
            "pixel_height": 8,
            "sha256": String(repeating: "a", count: 64),
            "content_path": "/v1/attachments/\(attachmentID)/content",
        ]]
        let responseData = try JSONSerialization.data(withJSONObject: captureObject)
        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 202,
                data: responseData
            )
        }
        let upload = ImageCaptureUploadRequest(
            metadata: ImageCaptureCreateMetadata(
                clientCaptureID: "ca1ad8ce-196d-48af-ad2f-b4a9b79f71f9",
                sourceApp: "Preview",
                userNote: "Search this diagram later.",
                capturedAt: "2026-07-21T10:30:00-07:00",
                analyzeImage: true
            ),
            imageData: Data([0, 1, 2, 255]),
            mediaType: "image/png"
        )

        let capture = try await makeClient().createImageCapture(upload)

        XCTAssertEqual(capture.primaryImageAttachment?.id, attachmentID)
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/image-captures")
        let contentType = try XCTUnwrap(
            request.value(forHTTPHeaderField: "Content-Type")
        )
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = try requestBodyData(from: request)
        XCTAssertNotNil(body.range(of: upload.imageData))
        let bodyText = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(bodyText.contains("name=\"metadata\""))
        XCTAssertTrue(bodyText.contains("name=\"image\"; filename=\"capture.png\""))
        XCTAssertTrue(bodyText.contains("\"analyze_image\":true"))
        XCTAssertTrue(bodyText.contains("Search this diagram later."))
    }

    func testAttachmentDownloadAndCaptureDeleteUseBoundedPaths() async throws {
        let recorder = RequestRecorder()
        let attachmentID = "4cfe5742-43e0-4bf4-9f79-bec7ef9954c2"
        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 200,
                data: Data([9, 8, 7])
            )
        }

        let data = try await makeClient().attachmentData(
            contentPath: "/v1/attachments/\(attachmentID)/content"
        )

        XCTAssertEqual(data, Data([9, 8, 7]))
        XCTAssertEqual(recorder.request?.httpMethod, "GET")
        XCTAssertEqual(
            recorder.request?.url?.path,
            "/v1/attachments/\(attachmentID)/content"
        )

        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 204,
                data: Data()
            )
        }
        try await makeClient().deleteCapture(
            id: "4b3a30b7-55d9-4ef8-93ef-34281c826e52"
        )
        XCTAssertEqual(recorder.request?.httpMethod, "DELETE")
        XCTAssertEqual(
            recorder.request?.url?.path,
            "/v1/captures/4b3a30b7-55d9-4ef8-93ef-34281c826e52"
        )
    }

    func testScreenshotOCRSendsBoundedJSONPostAndDecodesProviderMetadata() async throws {
        let recorder = RequestRecorder()
        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 200,
                data: Data(
                    #"{"text":"Exact OCR text","provider":"openai","processing_location":"cloud","model":"gpt-5.6"}"#.utf8
                )
            )
        }
        let request = ScreenshotOCRRequest(
            mediaType: "image/png",
            imageBase64: Data([1, 2, 3]).base64EncodedString()
        )

        let response = try await makeClient().extractScreenshotText(request)

        XCTAssertEqual(response.text, "Exact OCR text")
        XCTAssertEqual(response.processingLocation, .cloud)
        XCTAssertEqual(response.provider, .openai)
        XCTAssertEqual(response.model, "gpt-5.6")
        let sent = try XCTUnwrap(recorder.request)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.path, "/v1/ocr")
        XCTAssertEqual(sent.timeoutInterval, 50)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try requestBodyData(from: sent))
                as? [String: Any]
        )
        XCTAssertEqual(object["media_type"] as? String, "image/png")
        XCTAssertEqual(object["image_base64"] as? String, request.imageBase64)
    }

    func testStableErrorEnvelopePreservesStatusCodeCodeAndMessage() async throws {
        let recorder = RequestRecorder()
        let responseData = Data(
            """
            {
              "error": {
                "code": "capture_not_found",
                "message": "Capture was not found.",
                "details": null,
                "request_id": "8a12890b-6c51-4cb9-896a-78659ef08758"
              }
            }
            """.utf8
        )
        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 404,
                data: responseData
            )
        }

        do {
            _ = try await makeClient().getCapture(
                id: "4b3a30b7-55d9-4ef8-93ef-34281c826e52"
            )
            XCTFail("Expected a structured API error")
        } catch let error as RecallAPIError {
            XCTAssertEqual(
                error,
                .http(
                    statusCode: 404,
                    code: "capture_not_found",
                    message: "Capture was not found."
                )
            )
            XCTAssertEqual(error.statusCode, 404)
            XCTAssertEqual(error.code, "capture_not_found")
            XCTAssertEqual(error.localizedDescription, "Capture was not found.")
        } catch {
            XCTFail("Expected RecallAPIError, got \(error)")
        }

        XCTAssertEqual(recorder.request?.url?.path, "/v1/captures/4b3a30b7-55d9-4ef8-93ef-34281c826e52")
    }

    func testPlain404FromUnimplementedRouteUsesFallbackHTTPError() async throws {
        let recorder = RequestRecorder()
        URLProtocolStub.install { request in
            recorder.record(request)
            return try stubbedResponse(
                for: request,
                statusCode: 404,
                data: Data(#"{"detail":"Not Found"}"#.utf8)
            )
        }

        do {
            _ = try await makeClient().enrich(
                id: "4b3a30b7-55d9-4ef8-93ef-34281c826e52"
            )
            XCTFail("Expected the unimplemented route to return an HTTP error")
        } catch let error as RecallAPIError {
            XCTAssertEqual(error.statusCode, 404)
            XCTAssertNil(error.code)
            XCTAssertEqual(
                error,
                .http(
                    statusCode: 404,
                    code: nil,
                    message: "Local service returned 404: not found."
                )
            )
        } catch {
            XCTFail("Expected RecallAPIError, got \(error)")
        }

        XCTAssertEqual(recorder.request?.httpMethod, "POST")
        XCTAssertEqual(
            recorder.request?.url?.path,
            "/v1/captures/4b3a30b7-55d9-4ef8-93ef-34281c826e52/enrich"
        )
    }

    private func makeClient() -> LiveRecallAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        addTeardownBlock {
            session.invalidateAndCancel()
        }
        return LiveRecallAPIClient(
            baseURL: URL(string: "https://recall.test")!,
            session: session
        )
    }

    private func requestBodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw try XCTUnwrap(stream.streamError)
            }
            if count == 0 {
                break
            }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }
}

private struct StubbedResponse {
    let response: HTTPURLResponse
    let data: Data
}

private enum StubError: Error {
    case missingHandler
    case invalidRequestURL
    case invalidHTTPResponse
}

private func stubbedResponse(
    for request: URLRequest,
    statusCode: Int,
    data: Data
) throws -> StubbedResponse {
    guard let url = request.url else {
        throw StubError.invalidRequestURL
    }
    guard let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    ) else {
        throw StubError.invalidHTTPResponse
    }
    return StubbedResponse(response: response, data: data)
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequest = request
    }
}

private final class URLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> StubbedResponse

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func install(_ handler: @escaping Handler) {
            lock.lock()
            defer { lock.unlock() }
            self.handler = handler
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            handler = nil
        }

        func currentHandler() -> Handler? {
            lock.lock()
            defer { lock.unlock() }
            return handler
        }
    }

    private static let storage = Storage()

    static func install(_ handler: @escaping Handler) {
        storage.install(handler)
    }

    static func reset() {
        storage.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.storage.currentHandler() else {
            client?.urlProtocol(self, didFailWithError: StubError.missingHandler)
            return
        }

        do {
            let result = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: result.response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
