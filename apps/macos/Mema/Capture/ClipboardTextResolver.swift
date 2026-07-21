@preconcurrency import AppKit
import Foundation

/// A detached pasteboard representation that is safe to move across actor boundaries.
struct ClipboardTextRepresentation: Equatable, Sendable {
    let typeRawValue: String
    let data: Data
}

struct ClipboardTextItem: Equatable, Sendable {
    let plainText: String?
    let representations: [ClipboardTextRepresentation]
}

/// Resolves a clipboard item's text without treating its markup as trusted display content.
///
/// Plain text is required and owns the content. HTML and RTF are used only to replace an
/// existing plain-text whitespace separator with a richer logical line boundary. This keeps
/// Markdown and TeX delimiters from disappearing merely because a rich representation renders
/// them differently, and prevents representations from separate pasteboard items being paired.
enum ClipboardTextResolver {
    private struct WhitespaceLayout {
        let content: [Character]
        let gaps: [[Character]]
    }

    static let maximumStructuredRepresentationBytes = 2 * 1_024 * 1_024

    private static let plainTextTypes = Set([
        NSPasteboard.PasteboardType.string.rawValue,
        "public.plain-text",
        "public.utf16-plain-text",
        "public.utf16-external-plain-text",
        "NSStringPboardType",
        "text/plain",
    ])

    private static let htmlTypes = Set([
        NSPasteboard.PasteboardType.html.rawValue,
        "text/html",
    ])

    private static let rtfTypes = Set([
        NSPasteboard.PasteboardType.rtf.rawValue,
        "text/rtf",
        "application/rtf",
    ])

    static func isSupportedRepresentationType(_ typeRawValue: String) -> Bool {
        plainTextTypes.contains(typeRawValue)
            || htmlTypes.contains(typeRawValue)
            || rtfTypes.contains(typeRawValue)
    }

    static func resolve(
        plainText: String?,
        representations: [ClipboardTextRepresentation]
    ) -> String? {
        let decodedPlainText = plainText ?? representations.lazy.compactMap(decodePlainText).first
        let structuredCandidates = representations.compactMap(decodeStructuredText)
        return preferredText(
            plainText: decodedPlainText,
            structuredCandidates: structuredCandidates
        )
    }

    static func resolve(items: [ClipboardTextItem]) -> String? {
        var resolvedItems: [String] = []
        for item in items {
            let decodedPlainText = item.plainText
                ?? item.representations.lazy.compactMap(decodePlainText).first
            guard let decodedPlainText else { continue }
            guard let resolvedItem = preferredText(
                plainText: decodedPlainText,
                structuredCandidates: item.representations.compactMap(decodeStructuredText)
            ) else {
                continue
            }
            resolvedItems.append(resolvedItem)
        }
        return resolvedItems.isEmpty ? nil : resolvedItems.joined(separator: "\n")
    }

    static func preferredText(
        plainText: String?,
        structuredCandidates: [String]
    ) -> String? {
        guard let plainText else { return nil }
        guard plainText.nonEmptyTrimmed != nil else { return plainText }

        let candidates = structuredCandidates.compactMap(cleanStructuredCandidate)

        let projectedCandidates = candidates.compactMap { candidate -> String? in
            guard logicalLineBreakCount(candidate) > logicalLineBreakCount(plainText) else {
                return nil
            }
            return projectLineStructure(from: candidate, onto: plainText)
        }
        return projectedCandidates.max(by: isLessStructured) ?? plainText
    }

    private static func decodePlainText(
        _ representation: ClipboardTextRepresentation
    ) -> String? {
        guard plainTextTypes.contains(representation.typeRawValue) else { return nil }

        let encodings: [String.Encoding]
        if representation.typeRawValue.contains("utf16") {
            if representation.data.starts(with: [0xFE, 0xFF]) {
                encodings = [.utf16BigEndian, .utf16]
            } else if representation.data.starts(with: [0xFF, 0xFE]) {
                encodings = [.utf16LittleEndian, .utf16]
            } else {
                // public.utf16-plain-text is native-endian when it has no BOM.
                // All supported macOS deployment targets are little-endian.
                encodings = [.utf16LittleEndian, .utf16BigEndian, .utf8]
            }
        } else {
            encodings = [.utf8, .utf16, .unicode]
        }
        return encodings.lazy.compactMap {
            String(data: representation.data, encoding: $0)
        }.first
    }

    private static func decodeStructuredText(
        _ representation: ClipboardTextRepresentation
    ) -> String? {
        guard !representation.data.isEmpty,
              representation.data.count <= maximumStructuredRepresentationBytes else {
            return nil
        }

        if htmlTypes.contains(representation.typeRawValue) {
            return InertHTMLTextDecoder.decode(representation.data)
        }
        if rtfTypes.contains(representation.typeRawValue) {
            return try? NSAttributedString(
                data: representation.data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ).string
        }
        return nil
    }

    private static func cleanStructuredCandidate(_ candidate: String) -> String? {
        let normalized = candidate
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.nonEmptyTrimmed
    }

    private static func projectLineStructure(
        from structuredText: String,
        onto plainText: String
    ) -> String? {
        let plainLayout = projectionLayout(
            of: plainText,
            ignoringPlainMarkdownDecoration: true
        )
        let structuredLayout = projectionLayout(
            of: structuredText,
            ignoringPlainMarkdownDecoration: false
        )
        guard plainLayout.content == structuredLayout.content,
              plainLayout.gaps.count == structuredLayout.gaps.count else {
            return nil
        }

        var result = ""
        var projectedAnyBoundary = false
        result.append(contentsOf: plainLayout.gaps[0])
        for index in plainLayout.content.indices {
            result.append(plainLayout.content[index])
            let plainGap = plainLayout.gaps[index + 1]

            // Leading and trailing whitespace belong entirely to the plain source.
            // Between visible characters, take only a strictly richer line boundary;
            // otherwise keep the original whitespace byte-for-byte.
            guard index + 1 < plainLayout.content.count else {
                result.append(contentsOf: plainGap)
                continue
            }
            let structuredGap = structuredLayout.gaps[index + 1]
            if plainGap.contains(where: \Character.isWhitespace),
               logicalLineBreakCount(structuredGap) > logicalLineBreakCount(plainGap) {
                result.append(contentsOf: projectedGap(
                    plainGap,
                    lineBreakCount: logicalLineBreakCount(structuredGap)
                ))
                projectedAnyBoundary = true
            } else {
                result.append(contentsOf: plainGap)
            }
        }
        return projectedAnyBoundary ? result : nil
    }

    private static func projectionLayout(
        of text: String,
        ignoringPlainMarkdownDecoration: Bool
    ) -> WhitespaceLayout {
        let characters = Array(text)
        let ignoredIndices = ignoringPlainMarkdownDecoration
            ? markdownDecorationIndices(in: characters)
            : []
        var content: [Character] = []
        var gaps: [[Character]] = []
        var currentGap: [Character] = []

        for (index, character) in characters.enumerated() {
            if character.isWhitespace || ignoredIndices.contains(index) {
                currentGap.append(character)
            } else {
                gaps.append(currentGap)
                currentGap = []
                content.append(character)
            }
        }
        gaps.append(currentGap)
        return WhitespaceLayout(content: content, gaps: gaps)
    }

    /// Rich HTML renders a small set of Markdown presentation delimiters that
    /// remain literal in Gemini's plain-text representation. Treating verified
    /// delimiter runs as gap material lets block boundaries be projected while
    /// still returning every original character unchanged. Structured content
    /// must match all remaining anchors in order, so this never authorizes rich
    /// data to add or remove source text.
    private static func markdownDecorationIndices(
        in characters: [Character]
    ) -> Set<Int> {
        var ignored: Set<Int> = []
        var pairedRuns: [String: [[Int]]] = [:]
        var index = 0

        func hasWhitespaceBefore(_ position: Int) -> Bool {
            position == 0 || characters[position - 1].isWhitespace
        }

        while index < characters.count {
            let character = characters[index]

            if character == "#", hasWhitespaceBefore(index) {
                var end = index
                while end < characters.count, characters[end] == "#" {
                    end += 1
                }
                let length = end - index
                if (1...6).contains(length),
                   end < characters.count,
                   characters[end].isWhitespace {
                    ignored.formUnion(index..<end)
                }
                index = end
                continue
            }

            if character == "*",
               hasWhitespaceBefore(index),
               index + 1 < characters.count,
               characters[index + 1].isWhitespace {
                ignored.insert(index)
                index += 1
                continue
            }

            if character == "*" || character == "_"
                || character == "~" || character == "`" {
                var end = index
                while end < characters.count, characters[end] == character {
                    end += 1
                }
                let length = end - index
                let isSupportedRun: Bool
                if character == "*" {
                    isSupportedRun = (1...3).contains(length)
                } else if character == "_" {
                    isSupportedRun = (2...3).contains(length)
                } else if character == "~" {
                    isSupportedRun = length == 2
                } else {
                    isSupportedRun = (1...3).contains(length)
                }
                if isSupportedRun {
                    let key = String(repeating: String(character), count: length)
                    pairedRuns[key, default: []].append(Array(index..<end))
                }
                index = end
                continue
            }

            index += 1
        }

        for runs in pairedRuns.values {
            var runIndex = 0
            while runIndex + 1 < runs.count {
                ignored.formUnion(runs[runIndex])
                ignored.formUnion(runs[runIndex + 1])
                runIndex += 2
            }
        }
        return ignored
    }

    private static func projectedGap(
        _ plainGap: [Character],
        lineBreakCount: Int
    ) -> String {
        let replacement = String(repeating: "\n", count: lineBreakCount)
        let existingBreakCount = logicalLineBreakCount(plainGap)

        if existingBreakCount == 0 {
            // Replace exactly one existing separator. Markdown presentation
            // delimiters may also occupy this gap and must remain byte-for-byte.
            var result = ""
            var replacedSeparator = false
            for character in plainGap {
                if !replacedSeparator, character.isWhitespace {
                    result.append(contentsOf: replacement)
                    replacedSeparator = true
                } else {
                    result.append(character)
                }
            }
            return result
        }

        var result = ""
        var insertedReplacement = false
        for character in plainGap {
            if character.isNewline {
                if !insertedReplacement {
                    result.append(contentsOf: replacement)
                    insertedReplacement = true
                }
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func logicalLineBreakCount(_ text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if character.isNewline {
                count += 1
            }
        }
    }

    private static func logicalLineBreakCount(_ characters: [Character]) -> Int {
        characters.reduce(into: 0) { count, character in
            if character.isNewline {
                count += 1
            }
        }
    }

    private static func isLessStructured(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBreaks = logicalLineBreakCount(lhs)
        let rhsBreaks = logicalLineBreakCount(rhs)
        if lhsBreaks != rhsBreaks {
            return lhsBreaks < rhsBreaks
        }
        // With equal line structure, prefer the candidate with less formatting whitespace.
        return lhs.count > rhs.count
    }
}

/// A deliberately small, inert HTML-to-text decoder for clipboard fragments.
/// It never creates a web view, resolves URLs, runs scripts, or loads remote resources.
private enum InertHTMLTextDecoder {
    private struct OpenElement {
        let name: String
        let suppressesText: Bool
        let preservesWhitespace: Bool
    }

    private static let blockElements = Set([
        "address", "article", "aside", "blockquote", "dd", "div", "dl", "dt",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5",
        "h6", "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section",
        "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul",
    ])

    private static let voidElements = Set([
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr",
    ])

    private static let alwaysSuppressedElements = Set([
        "head", "noscript", "script", "style", "svg", "template",
    ])

    private static let maximumElementDepth = 128
    private static let maximumTagCharacterCount = 16_384

    static func decode(_ data: Data) -> String? {
        guard let html = decodeString(data) else { return nil }

        var output = ""
        var stack: [OpenElement] = []
        var index = html.startIndex
        var pendingSpace = false

        func textIsSuppressed() -> Bool {
            stack.last?.suppressesText ?? false
        }

        func whitespaceIsPreserved() -> Bool {
            stack.last?.preservesWhitespace ?? false
        }

        func appendBreak() {
            pendingSpace = false
            guard !output.isEmpty, output.last != "\n" else { return }
            output.append("\n")
        }

        func appendText(_ rawText: Substring) {
            guard !textIsSuppressed() else { return }
            let decoded = decodeEntities(String(rawText))
            if whitespaceIsPreserved() {
                if pendingSpace, output.last?.isWhitespace == false {
                    output.append(" ")
                }
                pendingSpace = false
                output.append(contentsOf: decoded)
                return
            }

            for character in decoded {
                if character.isWhitespace {
                    pendingSpace = true
                    continue
                }
                if pendingSpace,
                   !output.isEmpty,
                   output.last?.isWhitespace == false {
                    output.append(" ")
                }
                pendingSpace = false
                output.append(character)
            }
        }

        func appendSemanticText(_ text: String) {
            guard !textIsSuppressed() else { return }
            if pendingSpace,
               !output.isEmpty,
               output.last?.isWhitespace == false {
                output.append(" ")
            }
            pendingSpace = false
            output.append(contentsOf: text)
        }

        while index < html.endIndex {
            guard html[index] == "<" else {
                let nextTag = html[index...].firstIndex(of: "<") ?? html.endIndex
                appendText(html[index..<nextTag])
                index = nextTag
                continue
            }

            if html[index...].hasPrefix("<!--") {
                if let end = html[index...].range(of: "-->")?.upperBound {
                    index = end
                } else {
                    break
                }
                continue
            }

            guard let tagEnd = html[index...].firstIndex(of: ">") else {
                appendText(html[index...])
                break
            }

            let contentStart = html.index(after: index)
            let rawTag = String(html[contentStart..<tagEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            index = html.index(after: tagEnd)

            guard rawTag.count <= maximumTagCharacterCount else { return nil }
            guard !rawTag.isEmpty,
                  !rawTag.hasPrefix("!"),
                  !rawTag.hasPrefix("?") else {
                continue
            }

            let isClosing = rawTag.hasPrefix("/")
            let tagBody = isClosing ? rawTag.dropFirst() : Substring(rawTag)
            let name = tagBody.prefix { character in
                !character.isWhitespace && character != "/"
            }.lowercased()
            guard !name.isEmpty else { continue }

            if isClosing {
                let wasSuppressed = textIsSuppressed()
                if let matchIndex = stack.lastIndex(where: { $0.name == name }) {
                    stack.removeSubrange(matchIndex...)
                }
                if blockElements.contains(name), !wasSuppressed {
                    appendBreak()
                }
                continue
            }

            let parentSuppressesText = textIsSuppressed()
            let lowercasedTag = rawTag.lowercased()
            let hidden = alwaysSuppressedElements.contains(name)
                || containsHiddenAttribute(lowercasedTag)
            let semanticMath = parentSuppressesText || hidden
                ? nil
                : semanticMathText(in: rawTag)
            let suppressesText = parentSuppressesText
                || hidden
                || semanticMath != nil
            let preservesWhitespace = (stack.last?.preservesWhitespace ?? false) || name == "pre"

            if name == "br" || name == "hr" {
                if !suppressesText {
                    appendBreak()
                }
            } else if blockElements.contains(name), !suppressesText {
                appendBreak()
            }

            if let semanticMath {
                if semanticMath.isBlock {
                    appendBreak()
                }
                appendSemanticText(semanticMath.text)
                if semanticMath.isBlock {
                    appendBreak()
                }
            }

            let isSelfClosing = rawTag.hasSuffix("/") || voidElements.contains(name)
            if !isSelfClosing {
                guard stack.count < maximumElementDepth else { return nil }
                stack.append(
                    OpenElement(
                        name: name,
                        suppressesText: suppressesText,
                        preservesWhitespace: preservesWhitespace
                    )
                )
            }
        }

        let result = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.nonEmptyTrimmed
    }

    private static func semanticMathText(
        in rawTag: String
    ) -> (text: String, isBlock: Bool)? {
        guard let classValue = attributeValue(named: "class", in: rawTag),
              let mathValue = attributeValue(named: "data-math", in: rawTag) else {
            return nil
        }
        let classes = Set(
            classValue
                .split(whereSeparator: \Character.isWhitespace)
                .map { $0.lowercased() }
        )
        if classes.contains("math-inline") {
            return ("$\(decodeEntities(mathValue))$", false)
        }
        if classes.contains("math-block") {
            return ("$$\(decodeEntities(mathValue))$$", true)
        }
        return nil
    }

    private static func attributeValue(
        named expectedName: String,
        in rawTag: String
    ) -> String? {
        var index = rawTag.startIndex

        while index < rawTag.endIndex,
              !rawTag[index].isWhitespace,
              rawTag[index] != "/" {
            index = rawTag.index(after: index)
        }

        while index < rawTag.endIndex {
            while index < rawTag.endIndex, rawTag[index].isWhitespace {
                index = rawTag.index(after: index)
            }
            guard index < rawTag.endIndex, rawTag[index] != "/" else { break }

            let nameStart = index
            while index < rawTag.endIndex,
                  !rawTag[index].isWhitespace,
                  rawTag[index] != "=",
                  rawTag[index] != "/" {
                index = rawTag.index(after: index)
            }
            let name = String(rawTag[nameStart..<index])

            while index < rawTag.endIndex, rawTag[index].isWhitespace {
                index = rawTag.index(after: index)
            }
            guard index < rawTag.endIndex, rawTag[index] == "=" else {
                continue
            }
            index = rawTag.index(after: index)
            while index < rawTag.endIndex, rawTag[index].isWhitespace {
                index = rawTag.index(after: index)
            }
            guard index < rawTag.endIndex else { break }

            let value: String
            if rawTag[index] == "\"" || rawTag[index] == "'" {
                let quote = rawTag[index]
                index = rawTag.index(after: index)
                let valueStart = index
                while index < rawTag.endIndex, rawTag[index] != quote {
                    index = rawTag.index(after: index)
                }
                value = String(rawTag[valueStart..<index])
                if index < rawTag.endIndex {
                    index = rawTag.index(after: index)
                }
            } else {
                let valueStart = index
                while index < rawTag.endIndex,
                      !rawTag[index].isWhitespace,
                      rawTag[index] != "/" {
                    index = rawTag.index(after: index)
                }
                value = String(rawTag[valueStart..<index])
            }

            if name.caseInsensitiveCompare(expectedName) == .orderedSame {
                return value
            }
        }
        return nil
    }

    private static func decodeString(_ data: Data) -> String? {
        for encoding in [
            String.Encoding.utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1,
        ] {
            if let value = String(data: data, encoding: encoding) {
                return value
            }
        }
        return nil
    }

    private static func containsHiddenAttribute(_ lowercasedTag: String) -> Bool {
        let tokens = lowercasedTag.split(whereSeparator: \Character.isWhitespace)
        let compact = lowercasedTag.filter { !$0.isWhitespace }
        return tokens.dropFirst().contains {
            $0 == "hidden" || $0.hasPrefix("hidden=")
        }
            || compact.contains("aria-hidden=\"true\"")
            || compact.contains("aria-hidden='true'")
            || compact.contains("aria-hidden=true")
            || compact.contains("display:none")
            || compact.contains("visibility:hidden")
    }

    private static func decodeEntities(_ source: String) -> String {
        var output = ""
        var index = source.startIndex

        while index < source.endIndex {
            guard source[index] == "&",
                  let semicolon = source[index...].prefix(34).firstIndex(of: ";") else {
                output.append(source[index])
                index = source.index(after: index)
                continue
            }

            let entityStart = source.index(after: index)
            let entity = String(source[entityStart..<semicolon])
            if let decoded = decodeEntity(entity) {
                output.append(decoded)
                index = source.index(after: semicolon)
            } else {
                output.append(source[index])
                index = source.index(after: index)
            }
        }
        return output
    }

    private static func decodeEntity(_ entity: String) -> Character? {
        let named: [String: Character] = [
            "amp": "&", "apos": "'", "gt": ">", "lt": "<", "nbsp": " ",
            "quot": "\"", "ensp": " ", "emsp": " ", "thinsp": " ",
            "ndash": "–", "mdash": "—", "hellip": "…", "middot": "·",
            "times": "×", "divide": "÷", "plusmn": "±",
        ]
        if let value = named[entity.lowercased()] {
            return value
        }

        let scalarValue: UInt32?
        if entity.lowercased().hasPrefix("#x") {
            scalarValue = UInt32(entity.dropFirst(2), radix: 16)
        } else if entity.hasPrefix("#") {
            scalarValue = UInt32(entity.dropFirst(), radix: 10)
        } else {
            scalarValue = nil
        }
        guard let scalarValue,
              let scalar = UnicodeScalar(scalarValue) else {
            return nil
        }
        return Character(String(scalar))
    }
}
