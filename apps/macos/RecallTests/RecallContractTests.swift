import Foundation
import XCTest

@testable import Recall

final class RecallContractTests: XCTestCase {
    func testReadyCaptureFixtureDecodesCompleteCapture() throws {
        let capture = try JSONDecoder().decode(
            Capture.self,
            from: ContractFixtures.readyCaptureData()
        )

        XCTAssertEqual(capture.id, "4b3a30b7-55d9-4ef8-93ef-34281c826e52")
        XCTAssertEqual(capture.clientCaptureID, "149f51e1-8c18-42d4-9778-3f3b062527a2")
        XCTAssertEqual(capture.status, .ready)
        XCTAssertEqual(capture.sourceType, .web)
        XCTAssertEqual(capture.sourceApp, "Google Chrome")
        XCTAssertEqual(capture.aiTitle, "VPS 上 FastAPI 502 的 systemd 工作目录修复")
        XCTAssertEqual(capture.tags, ["FastAPI", "Nginx", "systemd", "VPS", "Deployment"])
        XCTAssertEqual(capture.caveats.count, 2)
        XCTAssertNil(capture.errorMessage)
        XCTAssertEqual(capture.enrichmentVersion, 1)
    }

    func testDateParserAcceptsMicrosecondTimestamp() throws {
        let wholeSecond = try XCTUnwrap(
            RecallDateParser.date(from: "2026-07-18T17:20:01Z")
        )
        let microsecondDate = try XCTUnwrap(
            RecallDateParser.date(from: "2026-07-18T17:20:01.123456Z")
        )

        XCTAssertEqual(
            microsecondDate.timeIntervalSince(wholeSecond),
            0.123456,
            accuracy: 0.000001
        )
    }

    func testCreateRequestEncodesAllFieldsWithSnakeCaseKeys() throws {
        let request = CaptureCreateRequest(
            clientCaptureID: "149f51e1-8c18-42d4-9778-3f3b062527a2",
            sourceType: .web,
            sourceApp: "Google Chrome",
            sourceTitle: "A useful answer",
            sourceURL: "https://example.com/answer",
            selectedText: "Set WorkingDirectory before restarting the service.",
            surroundingContext: "The service worked when launched manually.",
            contextTruncated: true,
            userNote: "This was the only fix that worked.",
            capturedAt: "2026-07-18T10:20:00-07:00"
        )

        let object = try jsonObject(from: JSONEncoder().encode(request))

        XCTAssertEqual(
            Set(object.keys),
            [
                "client_capture_id",
                "source_type",
                "source_app",
                "source_title",
                "source_url",
                "selected_text",
                "surrounding_context",
                "context_truncated",
                "user_note",
                "captured_at",
            ]
        )
        XCTAssertEqual(object["client_capture_id"] as? String, request.clientCaptureID)
        XCTAssertEqual(object["source_type"] as? String, "web")
        XCTAssertEqual(object["source_url"] as? String, request.sourceURL)
        XCTAssertEqual(object["selected_text"] as? String, request.selectedText)
        XCTAssertEqual(object["context_truncated"] as? Bool, true)
        XCTAssertNil(object["clientCaptureID"])
        XCTAssertNil(object["sourceType"])
        XCTAssertNil(object["capturedAt"])
    }

    func testCreateRequestOmitsNilOptionalFields() throws {
        let request = CaptureCreateRequest(
            clientCaptureID: nil,
            sourceType: .clipboard,
            sourceApp: nil,
            sourceTitle: nil,
            sourceURL: nil,
            selectedText: "A local selection",
            surroundingContext: nil,
            contextTruncated: false,
            userNote: nil,
            capturedAt: "2026-07-18T17:20:01.123456Z"
        )

        let object = try jsonObject(from: JSONEncoder().encode(request))

        XCTAssertEqual(
            Set(object.keys),
            ["source_type", "selected_text", "context_truncated", "captured_at"]
        )
        XCTAssertEqual(object["source_type"] as? String, "clipboard")
        XCTAssertEqual(object["selected_text"] as? String, "A local selection")
        XCTAssertEqual(object["context_truncated"] as? Bool, false)
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}

enum ContractFixtures {
    static func readyCaptureData() throws -> Data {
        try Data(contentsOf: readyCaptureURL)
    }

    static func readyCaptureJSONObject() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: readyCaptureData()) as? [String: Any]
        )
    }

    private static let readyCaptureURL: URL = {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return repositoryRoot
            .appendingPathComponent("contracts", isDirectory: true)
            .appendingPathComponent("examples", isDirectory: true)
            .appendingPathComponent("capture-ready-response.json")
    }()
}
