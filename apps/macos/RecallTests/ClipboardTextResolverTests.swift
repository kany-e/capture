import AppKit
import Foundation
import XCTest

@testable import Recall

@MainActor
final class ClipboardTextResolverTests: XCTestCase {
    func testPlainTextRemainsByteForByteAuthoritativeWithoutEquivalentStructure() {
        let plainText = "  Heading Equation $e$ Conclusion  \r\n"

        let resolved = ClipboardTextResolver.preferredText(
            plainText: plainText,
            structuredCandidates: ["Heading\nEquation e\nConclusion"]
        )

        XCTAssertEqual(resolved, plainText)
    }

    func testEquivalentStructuredTextRestoresLineBoundaries() {
        let plainText = "  Heading Equation $e$ Conclusion  "

        let resolved = ClipboardTextResolver.preferredText(
            plainText: plainText,
            structuredCandidates: ["Heading\nEquation $e$\nConclusion"]
        )

        XCTAssertEqual(resolved, "  Heading\nEquation $e$\nConclusion  ")
    }

    func testStructuredBreakCannotMoveToAPlainTextNonWhitespaceBoundary() {
        let plainText = "ab c"

        let resolved = ClipboardTextResolver.preferredText(
            plainText: plainText,
            structuredCandidates: ["a\nbc"]
        )

        XCTAssertEqual(resolved, plainText)
    }

    func testResolverChoosesAProjectableCandidateInsteadOfAnInvalidRicherOne() {
        let resolved = ClipboardTextResolver.preferredText(
            plainText: "ab cd",
            structuredCandidates: ["a\nb c\nd", "ab\ncd"]
        )

        XCTAssertEqual(resolved, "ab\ncd")
    }

    func testProjectedBreakPreservesAdditionalPlainIndentation() {
        let resolved = ClipboardTextResolver.preferredText(
            plainText: "Heading    indented",
            structuredCandidates: ["Heading\nindented"]
        )

        XCTAssertEqual(resolved, "Heading\n   indented")
    }

    func testWhitespaceOnlyPlainTextCannotBeReplacedByRichContent() {
        XCTAssertEqual(
            ClipboardTextResolver.preferredText(
                plainText: " \t\n",
                structuredCandidates: ["secret"]
            ),
            " \t\n"
        )
    }

    func testStructuredOnlyContentIsNotAcceptedWithoutPlainText() {
        let html = ClipboardTextRepresentation(
            typeRawValue: NSPasteboard.PasteboardType.html.rawValue,
            data: Data("<p>visible</p><p hidden=\"\">secret</p>".utf8)
        )

        XCTAssertNil(ClipboardTextResolver.resolve(
            plainText: nil,
            representations: [html]
        ))
    }

    func testPasteboardItemsAreResolvedWithoutCrossItemPairing() {
        let plain = ClipboardTextRepresentation(
            typeRawValue: NSPasteboard.PasteboardType.string.rawValue,
            data: Data("ab c".utf8)
        )
        let unrelatedHTML = ClipboardTextRepresentation(
            typeRawValue: NSPasteboard.PasteboardType.html.rawValue,
            data: Data("<p>a</p><p>bc</p>".utf8)
        )

        XCTAssertEqual(
            ClipboardTextResolver.resolve(items: [
                ClipboardTextItem(plainText: nil, representations: [plain]),
                ClipboardTextItem(plainText: nil, representations: [unrelatedHTML]),
            ]),
            "ab c"
        )
    }

    func testPasteboardItemsPairWithinEachItemAndJoinWithNewlines() {
        func plain(_ value: String) -> ClipboardTextRepresentation {
            ClipboardTextRepresentation(
                typeRawValue: NSPasteboard.PasteboardType.string.rawValue,
                data: Data(value.utf8)
            )
        }
        func html(_ value: String) -> ClipboardTextRepresentation {
            ClipboardTextRepresentation(
                typeRawValue: NSPasteboard.PasteboardType.html.rawValue,
                data: Data(value.utf8)
            )
        }

        XCTAssertEqual(
            ClipboardTextResolver.resolve(items: [
                ClipboardTextItem(
                    plainText: nil,
                    representations: [plain("First item"), html("<p>First</p><p>item</p>")]
                ),
                ClipboardTextItem(
                    plainText: nil,
                    representations: [plain("Second item"), html("<p>Second item</p>")]
                ),
            ]),
            "First\nitem\nSecond item"
        )
    }

    func testHTMLRestoresBlocksWithoutExecutingOrIncludingHiddenContent() {
        let html = """
        <html>
          <head><script>ignored()</script></head>
          <body>
            <h1>Heading</h1>
            <p>Equation $e$ &amp; symbols</p>
            <p hidden>secret</p>
            <p>Conclusion</p>
          </body>
        </html>
        """
        let plainText = "Heading Equation $e$ & symbols Conclusion"
        let representation = ClipboardTextRepresentation(
            typeRawValue: NSPasteboard.PasteboardType.html.rawValue,
            data: Data(html.utf8)
        )

        let resolved = ClipboardTextResolver.resolve(
            plainText: plainText,
            representations: [representation]
        )

        XCTAssertEqual(resolved, "Heading\nEquation $e$ & symbols\nConclusion")
        XCTAssertFalse(resolved?.contains("ignored") == true)
        XCTAssertFalse(resolved?.contains("secret") == true)
    }

    func testGeminiSemanticMathRestoresTexAndBlockBoundaries() {
        let html = #"""
        <p>
          Intro <span class="math-inline" data-math="\ln">
            <span aria-hidden="true">rendered ln</span>
          </span> explanation.
        </p>
        <div class="math-block" data-math="\frac{dy}{dt} = rt + C_1 - y">
          <span aria-hidden="true">rendered fraction</span>
        </div>
        <h3>Conclusion</h3>
        """#
        let plainText = "Intro $\\ln$ explanation. $$\\frac{dy}{dt} = rt + C_1 - y$$ Conclusion"
        let representation = ClipboardTextRepresentation(
            typeRawValue: NSPasteboard.PasteboardType.html.rawValue,
            data: Data(html.utf8)
        )

        let resolved = ClipboardTextResolver.resolve(
            plainText: plainText,
            representations: [representation]
        )

        XCTAssertEqual(
            resolved,
            "Intro $\\ln$ explanation.\n$$\\frac{dy}{dt} = rt + C_1 - y$$\nConclusion"
        )
    }

    func testSemanticMathCannotAddTexMissingFromPlainText() {
        let html = #"<p>Intro <span class="math-inline" data-math="\ln">ln</span></p>"#
        let representation = ClipboardTextRepresentation(
            typeRawValue: NSPasteboard.PasteboardType.html.rawValue,
            data: Data(html.utf8)
        )

        XCTAssertEqual(
            ClipboardTextResolver.resolve(
                plainText: "Intro ln",
                representations: [representation]
            ),
            "Intro ln"
        )
    }

    func testRenderedHTMLCanRestoreLinesAroundPreservedMarkdownDecoration() {
        let html = """
        <p>Intro <strong>important</strong>. <em>Careful</em>.</p>
        <h3>Derivation</h3>
        <ul><li>First item</li><li>Second item</li></ul>
        """
        let plainText = "Intro **important**. *Careful*. ### Derivation * First item * Second item"
        let representation = ClipboardTextRepresentation(
            typeRawValue: NSPasteboard.PasteboardType.html.rawValue,
            data: Data(html.utf8)
        )

        let resolved = ClipboardTextResolver.resolve(
            plainText: plainText,
            representations: [representation]
        )

        XCTAssertEqual(
            resolved,
            "Intro **important**. *Careful*.\n### Derivation\n* First item\n* Second item"
        )
    }

    func testUnpairedMarkdownLikeOperatorCannotAuthorizeRichReshaping() {
        let representation = ClipboardTextRepresentation(
            typeRawValue: NSPasteboard.PasteboardType.html.rawValue,
            data: Data("<p>Value 2</p><p>3</p>".utf8)
        )

        XCTAssertEqual(
            ClipboardTextResolver.resolve(
                plainText: "Value 2 ** 3",
                representations: [representation]
            ),
            "Value 2 ** 3"
        )
    }

    func testRTFRestoresParagraphsWhenCharactersMatchPlainText() throws {
        let rtf = #"{\rtf1\ansi Heading\par Equation $e$\par Conclusion}"#
        let representation = ClipboardTextRepresentation(
            typeRawValue: NSPasteboard.PasteboardType.rtf.rawValue,
            data: Data(rtf.utf8)
        )

        let resolved = ClipboardTextResolver.resolve(
            plainText: "Heading Equation $e$ Conclusion",
            representations: [representation]
        )

        XCTAssertEqual(resolved, "Heading\nEquation $e$\nConclusion")
    }

    func testOversizedStructuredRepresentationIsIgnored() {
        let oversized = Data(
            repeating: 0x20,
            count: ClipboardTextResolver.maximumStructuredRepresentationBytes + 1
        )
        let representation = ClipboardTextRepresentation(
            typeRawValue: NSPasteboard.PasteboardType.html.rawValue,
            data: oversized
        )

        let resolved = ClipboardTextResolver.resolve(
            plainText: "Keep exact plain text",
            representations: [representation]
        )

        XCTAssertEqual(resolved, "Keep exact plain text")
    }

    func testMalformedRTFLeavesPlainTextUnchanged() {
        let representation = ClipboardTextRepresentation(
            typeRawValue: "text/rtf",
            data: Data([0x00, 0xFF, 0x01, 0x02])
        )

        XCTAssertEqual(
            ClipboardTextResolver.resolve(
                plainText: "Keep plain",
                representations: [representation]
            ),
            "Keep plain"
        )
    }

    func testUTF16PlainRepresentationIsDecodedWithinItsOwnItem() {
        let representation = ClipboardTextRepresentation(
            typeRawValue: "public.utf16-plain-text",
            data: "Heading $e$".data(using: .utf16LittleEndian)!
        )

        XCTAssertEqual(
            ClipboardTextResolver.resolve(items: [
                ClipboardTextItem(plainText: nil, representations: [representation]),
            ]),
            "Heading $e$"
        )
    }

    func testClipboardCaptureUsesEquivalentHTMLLineStructure() throws {
        let item = NSPasteboardItem()
        XCTAssertTrue(
            item.setString(
                "Heading Equation $e$ Conclusion",
                forType: .string
            )
        )
        XCTAssertTrue(
            item.setData(
                Data("<h1>Heading</h1><p>Equation $e$</p><p>Conclusion</p>".utf8),
                forType: .html
            )
        )
        let pasteboard = ClipboardPasteboardStub(
            plainText: "Heading Equation $e$ Conclusion",
            items: [item]
        )
        let service = SystemClipboardCaptureService(pasteboard: pasteboard)

        let snapshot = try service.readSnapshot()

        XCTAssertEqual(snapshot.text, "Heading\nEquation $e$\nConclusion")
    }

    func testClipboardCaptureDoesNotPairPlainAndHTMLAcrossItems() throws {
        let plainItem = NSPasteboardItem()
        XCTAssertTrue(plainItem.setString("ab c", forType: .string))
        let htmlItem = NSPasteboardItem()
        XCTAssertTrue(htmlItem.setData(
            Data("<p>a</p><p>bc</p>".utf8),
            forType: .html
        ))
        let pasteboard = ClipboardPasteboardStub(
            plainText: "ab c",
            items: [plainItem, htmlItem]
        )

        XCTAssertEqual(
            try SystemClipboardCaptureService(pasteboard: pasteboard).readSnapshot().text,
            "ab c"
        )
    }

    func testClipboardCaptureJoinsMultiplePlainItems() throws {
        let first = NSPasteboardItem()
        XCTAssertTrue(first.setString("first", forType: .string))
        let second = NSPasteboardItem()
        XCTAssertTrue(second.setString("second", forType: .string))
        let service = SystemClipboardCaptureService(
            pasteboard: ClipboardPasteboardStub(
                plainText: "first\nsecond",
                items: [first, second]
            )
        )

        XCTAssertEqual(try service.readSnapshot().text, "first\nsecond")
    }

    func testClipboardCaptureRejectsAConcurrentClipboardChange() {
        let pasteboard = ClipboardPasteboardStub(
            plainText: "candidate",
            items: nil,
            types: [.string]
        )
        pasteboard.changeCountAfterStringRead = 2
        let service = SystemClipboardCaptureService(pasteboard: pasteboard)

        XCTAssertThrowsError(try service.readSnapshot()) { error in
            guard case ClipboardCaptureError.changedDuringRead = error else {
                return XCTFail("Expected changedDuringRead, got \(error)")
            }
        }
    }

    func testClipboardCaptureTopLevelTypesFallbackRestoresHTMLLines() throws {
        let pasteboard = ClipboardPasteboardStub(
            plainText: "Heading Conclusion",
            items: nil,
            types: [.string, .html],
            dataByType: [
                NSPasteboard.PasteboardType.html.rawValue:
                    Data("<h1>Heading</h1><p>Conclusion</p>".utf8),
            ]
        )

        XCTAssertEqual(
            try SystemClipboardCaptureService(pasteboard: pasteboard).readSnapshot().text,
            "Heading\nConclusion"
        )
    }

    func testClipboardCaptureRejectsHTMLWithoutPlainText() {
        let pasteboard = ClipboardPasteboardStub(
            plainText: nil,
            items: nil,
            types: [.html],
            dataByType: [
                NSPasteboard.PasteboardType.html.rawValue: Data("<p>secret</p>".utf8),
            ]
        )
        let service = SystemClipboardCaptureService(pasteboard: pasteboard)

        XCTAssertThrowsError(try service.readSnapshot()) { error in
            guard case ClipboardCaptureError.noText = error else {
                return XCTFail("Expected noText, got \(error)")
            }
        }
    }

    func testClipboardCaptureRejectsWhitespaceOnlyPlainText() {
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString(" \t\n", forType: .string))
        let service = SystemClipboardCaptureService(
            pasteboard: ClipboardPasteboardStub(plainText: " \t\n", items: [item])
        )

        XCTAssertThrowsError(try service.readSnapshot()) { error in
            guard case ClipboardCaptureError.emptyText = error else {
                return XCTFail("Expected emptyText, got \(error)")
            }
        }
    }

    func testClipboardCaptureBoundsTypeInspectionAndKeepsPlainText() throws {
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString("Keep plain", forType: .string))
        XCTAssertTrue(item.setData(
            Data("<p>Keep</p><p>plain</p>".utf8),
            forType: .html
        ))
        for index in 0..<31 {
            XCTAssertTrue(item.setData(
                Data([UInt8(index)]),
                forType: NSPasteboard.PasteboardType(
                    rawValue: "dev.recall.test.type-\(index)"
                )
            ))
        }
        XCTAssertGreaterThan(item.types.count, 32)
        let service = SystemClipboardCaptureService(
            pasteboard: ClipboardPasteboardStub(plainText: "Keep plain", items: [item])
        )

        XCTAssertEqual(try service.readSnapshot().text, "Keep plain")
    }

    func testClipboardCaptureBoundsItemInspectionByFallingBackToSystemPlainText() throws {
        var items: [NSPasteboardItem] = []
        for index in 0..<16 {
            let item = NSPasteboardItem()
            XCTAssertTrue(item.setData(
                Data("<p>rich-only \(index)</p>".utf8),
                forType: .html
            ))
            items.append(item)
        }
        let beyondLimit = NSPasteboardItem()
        XCTAssertTrue(beyondLimit.setString("too late", forType: .string))
        items.append(beyondLimit)
        let service = SystemClipboardCaptureService(
            pasteboard: ClipboardPasteboardStub(plainText: "too late", items: items)
        )

        XCTAssertEqual(try service.readSnapshot().text, "too late")
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("RecallTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        return pasteboard
    }
}

@MainActor
private final class ClipboardPasteboardStub: ClipboardPasteboardReading {
    var changeCount = 1
    var changeCountAfterStringRead: Int?
    let pasteboardItems: [NSPasteboardItem]?
    let types: [NSPasteboard.PasteboardType]?
    private let plainText: String?
    private let dataByType: [String: Data]

    init(
        plainText: String?,
        items: [NSPasteboardItem]?,
        types: [NSPasteboard.PasteboardType]? = nil,
        dataByType: [String: Data] = [:]
    ) {
        self.plainText = plainText
        self.dataByType = dataByType
        pasteboardItems = items
        self.types = types ?? items.map { Array(Set($0.flatMap(\.types))) }
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        defer {
            if let changeCountAfterStringRead {
                changeCount = changeCountAfterStringRead
            }
        }
        return dataType == .string ? plainText : nil
    }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
        dataByType[dataType.rawValue]
            ?? pasteboardItems?.lazy.compactMap { $0.data(forType: dataType) }.first
    }
}
