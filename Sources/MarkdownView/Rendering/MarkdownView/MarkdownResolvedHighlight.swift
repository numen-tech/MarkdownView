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
    /// Exact when the node's source bytes are `plainText` verbatim; otherwise (escapes, entities,
    /// or a source position that does not point at the text) the whole node.
    func highlightedRange(in plainText: String, nodeRange: SourceRange?) -> Range<String.Index>? {
        guard !plainText.isEmpty, let nodeBytes = byteRange(of: nodeRange) else { return nil }
        let lower = max(nodeBytes.lowerBound, range.lowerBound)
        let upper = min(nodeBytes.upperBound, range.upperBound)
        guard lower < upper else { return nil }

        let utf8 = processedText.utf8
        let nodeStart = utf8.index(utf8.startIndex, offsetBy: nodeBytes.lowerBound)
        let nodeEnd = utf8.index(utf8.startIndex, offsetBy: nodeBytes.upperBound)
        guard utf8[nodeStart..<nodeEnd].elementsEqual(plainText.utf8) else {
            return plainText.startIndex..<plainText.endIndex
        }
        let start = Self.characterBoundary(
            in: plainText, utf8Offset: lower - nodeBytes.lowerBound, roundingUp: false
        )
        let end = Self.characterBoundary(
            in: plainText, utf8Offset: upper - nodeBytes.lowerBound, roundingUp: true
        )
        return start < end ? start..<end : nil
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
        guard sourceText != processedText, let mathContext else {
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
