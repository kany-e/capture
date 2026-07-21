import AppKit
import XCTest

@testable import Mema

final class AppleVisionScreenshotTextExtractorTests: XCTestCase {
    func testProductionExtractorReadsHighContrastScreenshotText() async throws {
        let image = NSImage(size: NSSize(width: 1200, height: 360))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 112, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        NSString(string: "Mema 2026").draw(
            at: NSPoint(x: 80, y: 110),
            withAttributes: attributes
        )
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(
            bitmap.representation(using: .png, properties: [:])
        )

        let text = try await AppleVisionScreenshotTextExtractor()
            .extractText(from: pngData)

        XCTAssertTrue(text.localizedCaseInsensitiveContains("Mema"))
        XCTAssertTrue(text.contains("2026"))
    }

    func testProductionExtractorRejectsInvalidImageData() async {
        do {
            _ = try await AppleVisionScreenshotTextExtractor()
                .extractText(from: Data([0, 1, 2]))
            XCTFail("Expected invalid image data to fail")
        } catch let error as ScreenshotTextExtractionError {
            XCTAssertEqual(error, .invalidImage)
        } catch {
            XCTFail("Expected ScreenshotTextExtractionError, got \(error)")
        }
    }
}
