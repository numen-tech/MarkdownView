//
//  MarkdownResolvedHighlight.swift
//  MarkdownView (numen-tech fork)
//

import SwiftUI
import Markdown

/// A ``MarkdownHighlightedSpan`` resolved against one parse result: the span as UTF-8 offsets
/// into the text the document was parsed from (the math-preprocessed text, where `$…$` became a
/// placeholder), plus that text's line starts, so a node's `SourceRange` (1-based line, 1-based
/// UTF-8 column) converts to the same offsets.
struct MarkdownResolvedHighlight: Hashable, Sendable {
    /// UTF-8 offsets into `processedText`.
    var range: Range<Int>
    var color: Color
    var processedText: String
    /// The UTF-8 offset where each line of `processedText` starts; index 0 is line 1.
    var lineStarts: [Int]

    init?(_ span: MarkdownHighlightedSpan, parseResult: MarkdownParseResult) {
        let processedText = parseResult.processedSnapshot.text
        guard let range = Self.processedRange(
            for: span.range,
            sourceText: parseResult.sourceSnapshot.text,
            processedText: processedText,
            mathContext: parseResult.mathContext
        ), !range.isEmpty else { return nil }
        self.range = range
        self.color = span.color
        self.processedText = processedText
        self.lineStarts = Self.lineStarts(of: processedText)
    }

    // MARK: Nodes

    /// The UTF-8 offsets a node's source range covers in `processedText`.
    func byteRange(of sourceRange: SourceRange?) -> Range<Int>? {
        guard let sourceRange,
              let lower = offset(of: sourceRange.lowerBound),
              let upper = offset(of: sourceRange.upperBound),
              lower <= upper
        else { return nil }
        return lower..<upper
    }

    /// Whether the span shares at least one byte with the node.
    func overlaps(_ sourceRange: SourceRange?) -> Bool {
        guard let nodeRange = byteRange(of: sourceRange) else { return false }
        return nodeRange.overlaps(range)
    }

    /// The part of a text node's `plainText` the span covers, or nil when it covers none.
    ///
    /// Exact when the node's reported source range holds its text verbatim (`verbatim`);
    /// otherwise (escapes, entities, a column cmark misreports) the whole node, when its
    /// reported source range overlaps the span.
    func highlightedRange(in plainText: String, nodeRange: SourceRange?) -> Range<String.Index>? {
        guard !plainText.isEmpty, let reported = byteRange(of: nodeRange), reported.overlaps(range)
        else { return nil }
        guard let nodeBytes = verbatim(plainText, in: reported) else {
            if let range = smartPunctuationRange(in: plainText, reported: reported) { return range }
            return plainText.startIndex..<plainText.endIndex
        }
        let lower = max(nodeBytes.lowerBound, range.lowerBound)
        let upper = min(nodeBytes.upperBound, range.upperBound)
        guard lower < upper else { return nil }
        let start = Self.characterBoundary(
            in: plainText, utf8Offset: lower - nodeBytes.lowerBound, roundingUp: false
        )
        let end = Self.characterBoundary(
            in: plainText, utf8Offset: upper - nodeBytes.lowerBound, roundingUp: true
        )
        return start < end ? start..<end : nil
    }

    /// The part of `plainText` the span covers when the node differs from its source only by
    /// cmark's smart punctuation (`'` and `"` curled, `--` and `---` as dashes, `...` as an
    /// ellipsis), which is on in `MarkdownView`'s parse: each character is matched to the source
    /// bytes it came from, so a sentence in a paragraph with an apostrophe is still exact instead of
    /// the whole node. Nil when the node differs in any other way (escapes, entities, a column
    /// cmark misreports): the caller takes the whole node.
    func smartPunctuationRange(in plainText: String, reported: Range<Int>) -> Range<String.Index>? {
        let utf8 = processedText.utf8
        guard reported.upperBound <= utf8.count else { return nil }
        let source = Array(utf8[utf8.index(utf8.startIndex, offsetBy: reported.lowerBound)..<utf8.index(utf8.startIndex, offsetBy: reported.upperBound)])
        var cursor = 0
        var first: String.Index?
        var last: String.Index?
        for index in plainText.indices {
            let character = plainText[index]
            let start = reported.lowerBound + cursor
            let literal = Array(String(character).utf8)
            var matched: Int?
            if source.count - cursor >= literal.count, source[cursor..<(cursor + literal.count)].elementsEqual(literal) {
                matched = literal.count
            } else if let candidates = Self.smartPunctuation[character] {
                matched = candidates.first { candidate in
                    source.count - cursor >= candidate.count
                        && source[cursor..<(cursor + candidate.count)].elementsEqual(candidate)
                }?.count
            }
            guard let matched else { return nil }
            cursor += matched
            if start < range.upperBound, reported.lowerBound + cursor > range.lowerBound {
                if first == nil { first = index }
                last = plainText.index(after: index)
            }
        }
        // Only a hard break's trailing spaces may follow the text.
        guard source[cursor...].allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }) else { return nil }
        guard let first, let last, first < last else { return nil }
        return first..<last
    }

    /// What cmark's smart punctuation writes for the ASCII it replaces.
    private static let smartPunctuation: [Character: [[UInt8]]] = [
        "\u{2018}": [Array("'".utf8)],
        "\u{2019}": [Array("'".utf8)],
        "\u{201C}": [Array("\"".utf8)],
        "\u{201D}": [Array("\"".utf8)],
        "\u{2013}": [Array("--".utf8)],
        "\u{2014}": [Array("---".utf8)],
        "\u{2026}": [Array("...".utf8)],
    ]

    /// The bytes of `reported` that hold `plainText`: all of them when they are the text, or
    /// their start when only spaces and tabs follow it (cmark's range of the text before a hard
    /// break covers the break's trailing spaces). Nil otherwise: escapes and entities, whose
    /// source is longer than their text, and a column cmark misreports (a lazy continuation
    /// line, `> a\nb`; the line after a backslash hard break), which this does not search for.
    func verbatim(_ plainText: String, in reported: Range<Int>) -> Range<Int>? {
        let needle = plainText.utf8
        let count = needle.count
        guard count <= reported.count else { return nil }
        let utf8 = processedText.utf8
        let lower = utf8.index(utf8.startIndex, offsetBy: reported.lowerBound)
        let textEnd = utf8.index(lower, offsetBy: count)
        let upper = utf8.index(lower, offsetBy: reported.count)
        guard utf8[lower..<textEnd].elementsEqual(needle),
              utf8[textEnd..<upper].allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") })
        else { return nil }
        return reported.lowerBound..<(reported.lowerBound + count)
    }

    /// `text` with ``color`` as the background of `highlightedRange` clamped to `bounds`.
    func attributed(
        _ text: String,
        bounds: Range<String.Index>? = nil,
        highlightedRange: Range<String.Index>?
    ) -> AttributedString {
        let bounds = bounds ?? text.startIndex..<text.endIndex
        var attributed = AttributedString(text[bounds])
        guard let highlightedRange,
              highlightedRange.overlaps(bounds) else { return attributed }
        let lower = max(highlightedRange.lowerBound, bounds.lowerBound)
        let upper = min(highlightedRange.upperBound, bounds.upperBound)
        let characters = attributed.characters
        let start = characters.index(
            characters.startIndex, offsetBy: text[bounds.lowerBound..<lower].count
        )
        let end = characters.index(start, offsetBy: text[lower..<upper].count)
        attributed[start..<end].backgroundColor = color
        return attributed
    }

    // MARK: Coordinates

    /// A 1-based line and 1-based UTF-8 column as an offset into `processedText`.
    func offset(of location: SourceLocation) -> Int? {
        guard location.line >= 1, location.column >= 1,
              location.line <= lineStarts.count
        else { return nil }
        let offset = lineStarts[location.line - 1] + location.column - 1
        return offset <= processedText.utf8.count ? offset : nil
    }

    /// Line starts as cmark counts lines: after `\n`, `\r\n` or a lone `\r`.
    static func lineStarts(of text: String) -> [Int] {
        var starts = [0]
        var previousWasCR = false
        var offset = 0
        for byte in text.utf8 {
            offset += 1
            if byte == UInt8(ascii: "\n") {
                if previousWasCR { starts[starts.count - 1] = offset } else { starts.append(offset) }
                previousWasCR = false
            } else if byte == UInt8(ascii: "\r") {
                starts.append(offset)
                previousWasCR = true
            } else {
                previousWasCR = false
            }
        }
        return starts
    }

    /// Maps UTF-8 offsets into the source text onto the processed text. Unchanged stretches map
    /// 1:1; a bound inside a math replacement snaps outward to its placeholder. Returns nil when
    /// the placeholders do not line up with the source (never expected).
    static func processedRange(
        for sourceRange: Range<Int>,
        sourceText: String,
        processedText: String,
        mathContext: MarkdownMathContext?
    ) -> Range<Int>? {
        let sourceUTF8 = sourceText.utf8
        let processedUTF8 = processedText.utf8
        let lowerBound = min(max(sourceRange.lowerBound, 0), sourceUTF8.count)
        let upperBound = min(max(sourceRange.upperBound, lowerBound), sourceUTF8.count)
        // An empty span stays empty: snapping bounds out to a formula would grow it.
        guard lowerBound < upperBound else { return lowerBound..<lowerBound }
        guard !sourceUTF8.elementsEqual(processedUTF8), let mathContext else {
            return lowerBound..<upperBound
        }

        var sourceCursor = 0
        var processedCursor = 0
        var lower: Int?
        var upper: Int?
        for segment in MarkdownMathPreprocessor.placeholderSegments(in: processedText) {
            let match = segment.match
            let storage = match.kind == .inline
                ? mathContext.inlineMathStorage
                : mathContext.displayMathStorage
            // Text that merely looks like a placeholder was in the source verbatim.
            guard let matchedText = storage[match.identifier] else { continue }

            let placeholderStart = processedUTF8.distance(
                from: processedUTF8.startIndex, to: segment.range.lowerBound
            )
            let placeholderEnd = processedUTF8.distance(
                from: processedUTF8.startIndex, to: segment.range.upperBound
            )
            let mathStart = sourceCursor + (placeholderStart - processedCursor)
            let mathEnd = mathStart + matchedText.utf8.count
            guard placeholderStart >= processedCursor, mathEnd <= sourceUTF8.count else {
                return nil
            }
            let mathStartIndex = sourceUTF8.index(sourceUTF8.startIndex, offsetBy: mathStart)
            let mathEndIndex = sourceUTF8.index(sourceUTF8.startIndex, offsetBy: mathEnd)
            guard sourceUTF8[mathStartIndex..<mathEndIndex].elementsEqual(matchedText.utf8) else {
                return nil
            }

            if lower == nil, lowerBound < mathEnd {
                lower = lowerBound <= mathStart
                    ? processedCursor + (lowerBound - sourceCursor)
                    : placeholderStart
            }
            if upper == nil, upperBound <= mathEnd {
                upper = upperBound <= mathStart
                    ? processedCursor + (upperBound - sourceCursor)
                    : placeholderEnd
            }
            if lower != nil, upper != nil { break }
            sourceCursor = mathEnd
            processedCursor = placeholderEnd
        }
        let resolvedLower = lower ?? processedCursor + (lowerBound - sourceCursor)
        let resolvedUpper = upper ?? processedCursor + (upperBound - sourceCursor)
        guard resolvedLower <= resolvedUpper, resolvedUpper <= processedUTF8.count else {
            return nil
        }
        return resolvedLower..<resolvedUpper
    }

    /// The `Character` boundary at or before (or, rounding up, at or after) a UTF-8 offset.
    static func characterBoundary(
        in text: String,
        utf8Offset: Int,
        roundingUp: Bool
    ) -> String.Index {
        let utf8 = text.utf8
        guard utf8Offset < utf8.count else { return text.endIndex }
        let target = utf8.index(utf8.startIndex, offsetBy: max(utf8Offset, 0))
        var boundary = text.startIndex
        while boundary < text.endIndex {
            let next = text.index(after: boundary)
            if next > target { break }
            boundary = next
        }
        if boundary == target || !roundingUp { return boundary }
        return text.index(after: boundary)
    }
}

extension View {
    /// Hands the resolved highlight to nested renderers (lists, headings), which read the
    /// configuration from the environment. Only the highlight fields change, so styling a custom
    /// style set inside the content survives; the source span is cleared so a `MarkdownView`
    /// nested in the content does not apply it to its own, different source.
    func markdownResolvedHighlight(_ highlight: MarkdownResolvedHighlight?) -> some View {
        transformEnvironment(\.markdownRendererConfiguration) { configuration in
            configuration.resolvedHighlight = highlight
            configuration.highlightedSpan = nil
        }
    }
}

extension MarkdownRendererConfiguration {
    /// The configuration a `MarkdownView` renders `parseResult` with: its highlighted span
    /// resolved against that document, and the source span cleared so a `MarkdownView` nested in
    /// the content (inside a custom renderer) does not apply it to its own, different source.
    func resolvingHighlight(against parseResult: MarkdownParseResult) -> Self {
        var configuration = self
        configuration.resolvedHighlight = highlightedSpan.flatMap {
            MarkdownResolvedHighlight($0, parseResult: parseResult)
        }
        configuration.highlightedSpan = nil
        return configuration
    }
}
