@preconcurrency import AppKit
import CoreGraphics
import Foundation
import Security

struct ScreenshotSnapshot: Equatable, Sendable {
    let imageData: Data
    let mediaType: String
    let sourceApplication: String?
}

enum ScreenshotCaptureError: Error, LocalizedError, Equatable {
    case cancelled
    case permissionDenied
    case unstableCodeSignature
    case unavailable
    case emptyImage
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Screenshot selection was cancelled."
        case .permissionDenied:
            return "Mema needs Screen Recording permission. Open System Settings > "
                + "Privacy & Security > Screen & System Audio Recording, enable Mema, "
                + "then relaunch the app."
        case .unstableCodeSignature:
            return "This Mema build uses a temporary code signature, so macOS cannot "
                + "match it to the Screen Recording permission shown in System Settings. "
                + "Use an Apple Development-signed build, reset Mema’s Screen Recording "
                + "permission once, then relaunch the app."
        case .unavailable:
            return "Mema could not start macOS screenshot selection."
        case .emptyImage:
            return "The selected screenshot was empty. Try selecting the region again."
        case .imageTooLarge:
            return "The selected screenshot is larger than 8 MiB. Select a smaller region and try again."
        }
    }
}

protocol ScreenCapturePermissionServing {
    func isAuthorized() -> Bool
    func requestAccess() -> Bool
}

struct SystemScreenCapturePermissionService: ScreenCapturePermissionServing {
    func isAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

protocol CodeSigningIdentityServing {
    var hasStablePrivacyIdentity: Bool { get }
}

struct SystemCodeSigningIdentityService: CodeSigningIdentityServing {
    var hasStablePrivacyIdentity: Bool {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &dynamicCode) == errSecSuccess,
              let dynamicCode else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return false
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        else {
            return false
        }
        return teamIdentifier.nonEmptyTrimmed != nil
    }
}

@MainActor
protocol ScreenshotCaptureServing {
    func captureInteractive() async throws -> ScreenshotSnapshot
}

protocol InteractiveScreenshotProcessRunning: Sendable {
    func run(outputURL: URL) async throws -> Int32
}

struct SystemInteractiveScreenshotProcessRunner: InteractiveScreenshotProcessRunning {
    func run(outputURL: URL) async throws -> Int32 {
        let execution = ScreenshotProcessExecution(outputURL: outputURL)
        return try await execution.run()
    }
}

@MainActor
struct SystemScreenshotCaptureService: ScreenshotCaptureServing {
    static let temporaryFilenamePrefix = "mema-screenshot-"
    static let maximumScreenshotBytes = 8 * 1_024 * 1_024

    private let permissionService: any ScreenCapturePermissionServing
    private let codeSigningIdentityService: any CodeSigningIdentityServing
    private let processRunner: any InteractiveScreenshotProcessRunning
    private let fileManager: FileManager
    private let temporaryDirectory: URL

    init(
        permissionService: any ScreenCapturePermissionServing =
            SystemScreenCapturePermissionService(),
        codeSigningIdentityService: any CodeSigningIdentityServing =
            SystemCodeSigningIdentityService(),
        processRunner: any InteractiveScreenshotProcessRunning =
            SystemInteractiveScreenshotProcessRunner(),
        fileManager: FileManager = .default,
        temporaryDirectory: URL? = nil
    ) {
        self.permissionService = permissionService
        self.codeSigningIdentityService = codeSigningIdentityService
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory
        removeAbandonedScreenshots()
    }

    func captureInteractive() async throws -> ScreenshotSnapshot {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        guard permissionService.isAuthorized() || permissionService.requestAccess() else {
            guard codeSigningIdentityService.hasStablePrivacyIdentity else {
                throw ScreenshotCaptureError.unstableCodeSignature
            }
            throw ScreenshotCaptureError.permissionDenied
        }

        let sourceApplication = frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? nil
            : frontmostApplication?.localizedName
        let outputURL = temporaryDirectory
            .appendingPathComponent("\(Self.temporaryFilenamePrefix)\(UUID().uuidString.lowercased())")
            .appendingPathExtension("png")
        defer { try? fileManager.removeItem(at: outputURL) }

        let terminationStatus: Int32
        do {
            terminationStatus = try await processRunner.run(outputURL: outputURL)
        } catch is CancellationError {
            throw ScreenshotCaptureError.cancelled
        } catch {
            throw ScreenshotCaptureError.unavailable
        }

        guard !Task.isCancelled, terminationStatus == 0 else {
            throw ScreenshotCaptureError.cancelled
        }
        let fileSize = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let fileSize, fileSize > 0 else {
            throw ScreenshotCaptureError.emptyImage
        }
        guard fileSize <= Self.maximumScreenshotBytes else {
            throw ScreenshotCaptureError.imageTooLarge
        }
        let data = try? await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: outputURL, options: .mappedIfSafe)
        }.value
        guard let data, !data.isEmpty else {
            throw ScreenshotCaptureError.emptyImage
        }
        return ScreenshotSnapshot(
            imageData: data,
            mediaType: "image/png",
            sourceApplication: sourceApplication?.nonEmptyTrimmed ?? "Screenshot"
        )
    }

    private func removeAbandonedScreenshots() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls where url.lastPathComponent.hasPrefix(Self.temporaryFilenamePrefix)
                && url.pathExtension.lowercased() == "png" {
            try? fileManager.removeItem(at: url)
        }
    }
}

private final class ScreenshotProcessExecution: @unchecked Sendable {
    private let outputURL: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<Int32, Error>, Never>?
    private var process: Process?
    private var cancellationRequested = false
    private var completed = false

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func run() async throws -> Int32 {
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                start(continuation: continuation)
            }
        } onCancel: {
            cancel()
        }
        return try result.get()
    }

    private func start(
        continuation: CheckedContinuation<Result<Int32, Error>, Never>
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-t", "png", outputURL.path]
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            let result: Result<Int32, Error> = self.isCancellationRequested
                ? .failure(CancellationError())
                : .success(process.terminationStatus)
            self.finish(with: result)
        }

        lock.lock()
        self.continuation = continuation
        self.process = process
        let shouldCancelBeforeLaunch = cancellationRequested
        lock.unlock()

        guard !shouldCancelBeforeLaunch else {
            finish(with: .failure(CancellationError()))
            return
        }

        do {
            try process.run()
        } catch {
            finish(with: .failure(error))
            return
        }

        if isCancellationRequested, process.isRunning {
            process.terminate()
        }
    }

    private var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    private func cancel() {
        lock.lock()
        cancellationRequested = true
        let process = process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func finish(with result: Result<Int32, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = continuation
        self.continuation = nil
        process = nil
        lock.unlock()

        continuation?.resume(returning: result)
    }
}
