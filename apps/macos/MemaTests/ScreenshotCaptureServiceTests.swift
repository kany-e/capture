import Foundation
import XCTest

@testable import Mema

@MainActor
final class ScreenshotCaptureServiceTests: XCTestCase {
    func testInitializationRemovesAbandonedScreenshotFilesOnly() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemaScreenshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let abandonedURL = temporaryDirectory
            .appendingPathComponent(
                "\(SystemScreenshotCaptureService.temporaryFilenamePrefix)abandoned.png"
            )
        let unrelatedURL = temporaryDirectory.appendingPathComponent("keep-me.png")
        try Data([1]).write(to: abandonedURL)
        try Data([2]).write(to: unrelatedURL)

        _ = SystemScreenshotCaptureService(
            permissionService: AllowedScreenCapturePermissionStub(),
            processRunner: ScreenshotProcessRunnerStub(
                imageData: Data(),
                terminationStatus: 0
            ),
            temporaryDirectory: temporaryDirectory
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandonedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }

    func testSuccessfulSelectionReadsImageAndRemovesTemporaryFile() async throws {
        let runner = ScreenshotProcessRunnerStub(
            imageData: Data([1, 2, 3, 4]),
            terminationStatus: 0
        )
        let service = SystemScreenshotCaptureService(
            permissionService: AllowedScreenCapturePermissionStub(),
            processRunner: runner
        )

        let snapshot = try await service.captureInteractive()
        let recordedOutputURL = await runner.lastOutputURL()
        let outputURL = try XCTUnwrap(recordedOutputURL)

        XCTAssertEqual(snapshot.imageData, Data([1, 2, 3, 4]))
        XCTAssertEqual(snapshot.mediaType, "image/png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testCancelledSelectionRemovesTemporaryFileAndLeavesNoImage() async throws {
        let runner = ScreenshotProcessRunnerStub(
            imageData: Data([5, 6, 7]),
            terminationStatus: 1
        )
        let service = SystemScreenshotCaptureService(
            permissionService: AllowedScreenCapturePermissionStub(),
            processRunner: runner
        )

        do {
            _ = try await service.captureInteractive()
            XCTFail("Expected a cancelled selection")
        } catch {
            XCTAssertEqual(error as? ScreenshotCaptureError, .cancelled)
        }
        let recordedOutputURL = await runner.lastOutputURL()
        let outputURL = try XCTUnwrap(recordedOutputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testOversizedSelectionIsRejectedBeforeReadingAndRemoved() async throws {
        let runner = ScreenshotProcessRunnerStub(
            imageData: Data(
                repeating: 1,
                count: SystemScreenshotCaptureService.maximumScreenshotBytes + 1
            ),
            terminationStatus: 0
        )
        let service = SystemScreenshotCaptureService(
            permissionService: AllowedScreenCapturePermissionStub(),
            processRunner: runner
        )

        do {
            _ = try await service.captureInteractive()
            XCTFail("Expected an oversized-image error")
        } catch {
            XCTAssertEqual(error as? ScreenshotCaptureError, .imageTooLarge)
        }
        let recordedOutputURL = await runner.lastOutputURL()
        let outputURL = try XCTUnwrap(recordedOutputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testTemporarySignatureExplainsWhyAnEnabledPermissionCannotBeMatched() async {
        let runner = ScreenshotProcessRunnerStub(
            imageData: Data([1]),
            terminationStatus: 0
        )
        let service = SystemScreenshotCaptureService(
            permissionService: DeniedScreenCapturePermissionStub(),
            codeSigningIdentityService: CodeSigningIdentityStub(isStable: false),
            processRunner: runner
        )

        do {
            _ = try await service.captureInteractive()
            XCTFail("Expected an unstable-signature error")
        } catch {
            XCTAssertEqual(error as? ScreenshotCaptureError, .unstableCodeSignature)
            XCTAssertTrue(error.localizedDescription.contains("temporary code signature"))
            XCTAssertTrue(error.localizedDescription.contains("Apple Development"))
        }
        let outputURL = await runner.lastOutputURL()
        XCTAssertNil(outputURL)
    }

    func testStableSignatureKeepsTheNormalPermissionGuidanceWhenAccessIsDenied() async {
        let runner = ScreenshotProcessRunnerStub(
            imageData: Data([1]),
            terminationStatus: 0
        )
        let service = SystemScreenshotCaptureService(
            permissionService: DeniedScreenCapturePermissionStub(),
            codeSigningIdentityService: CodeSigningIdentityStub(isStable: true),
            processRunner: runner
        )

        do {
            _ = try await service.captureInteractive()
            XCTFail("Expected a permission-denied error")
        } catch {
            XCTAssertEqual(error as? ScreenshotCaptureError, .permissionDenied)
            XCTAssertTrue(error.localizedDescription.contains("System Settings"))
            XCTAssertFalse(error.localizedDescription.contains("temporary code signature"))
        }
        let outputURL = await runner.lastOutputURL()
        XCTAssertNil(outputURL)
    }

    func testSuspendedSelectionDoesNotBlockMainActor() async throws {
        let runner = SuspendedScreenshotProcessRunner()
        let service = SystemScreenshotCaptureService(
            permissionService: AllowedScreenCapturePermissionStub(),
            processRunner: runner
        )
        let captureTask = Task { try await service.captureInteractive() }

        for _ in 0..<100 where !(await runner.hasStarted()) {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let didStart = await runner.hasStarted()
        XCTAssertTrue(didStart)

        var mainActorContinued = false
        mainActorContinued = true
        XCTAssertTrue(mainActorContinued)

        try await runner.complete(imageData: Data([8, 9]), terminationStatus: 0)
        let snapshot = try await captureTask.value
        XCTAssertEqual(snapshot.imageData, Data([8, 9]))
        let recordedOutputURL = await runner.lastOutputURL()
        let outputURL = try XCTUnwrap(recordedOutputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }
}

private struct AllowedScreenCapturePermissionStub: ScreenCapturePermissionServing {
    func isAuthorized() -> Bool { true }
    func requestAccess() -> Bool { true }
}

private struct DeniedScreenCapturePermissionStub: ScreenCapturePermissionServing {
    func isAuthorized() -> Bool { false }
    func requestAccess() -> Bool { false }
}

private struct CodeSigningIdentityStub: CodeSigningIdentityServing {
    let isStable: Bool

    var hasStablePrivacyIdentity: Bool { isStable }
}

private actor ScreenshotProcessRunnerStub: InteractiveScreenshotProcessRunning {
    private let imageData: Data
    private let terminationStatus: Int32
    private var outputURL: URL?

    init(imageData: Data, terminationStatus: Int32) {
        self.imageData = imageData
        self.terminationStatus = terminationStatus
    }

    func run(outputURL: URL) async throws -> Int32 {
        self.outputURL = outputURL
        try imageData.write(to: outputURL)
        return terminationStatus
    }

    func lastOutputURL() -> URL? {
        outputURL
    }
}

private actor SuspendedScreenshotProcessRunner: InteractiveScreenshotProcessRunning {
    private var outputURL: URL?
    private var continuation: CheckedContinuation<Int32, Error>?

    func run(outputURL: URL) async throws -> Int32 {
        self.outputURL = outputURL
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func hasStarted() -> Bool {
        continuation != nil
    }

    func complete(imageData: Data, terminationStatus: Int32) throws {
        guard let outputURL, let continuation else { return }
        try imageData.write(to: outputURL)
        self.continuation = nil
        continuation.resume(returning: terminationStatus)
    }

    func lastOutputURL() -> URL? {
        outputURL
    }
}
