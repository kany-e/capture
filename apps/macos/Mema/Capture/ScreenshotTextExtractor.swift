import Foundation
import ImageIO
@preconcurrency import Vision

enum ScreenshotTextExtractionError: Error, LocalizedError, Equatable {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Apple Vision could not read this screenshot image."
        case .noText:
            return "Apple Vision found no text. Try selecting a clearer or larger region."
        }
    }
}

protocol LocalScreenshotTextExtracting: Sendable {
    func extractText(from imageData: Data) async throws -> String
}

struct AppleVisionScreenshotTextExtractor: LocalScreenshotTextExtracting {
    func extractText(from imageData: Data) async throws -> String {
        let extractionTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw ScreenshotTextExtractionError.invalidImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            try Task.checkCancellation()

            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ScreenshotTextExtractionError.noText
            }
            return text
        }
        return try await withTaskCancellationHandler {
            try await extractionTask.value
        } onCancel: {
            extractionTask.cancel()
        }
    }
}
