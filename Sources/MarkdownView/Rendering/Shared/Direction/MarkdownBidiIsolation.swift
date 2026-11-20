//
//  MarkdownBidiIsolation.swift
//  MarkdownView (numen-tech fork)
//

import Foundation
import SwiftUI

/// numen fork (gemma4-qat#1765): left-to-right isolates (U+2066 LRI ... U+2069 PDI) around the
/// runs of a displayed text that must read left to right as one unit inside right-to-left prose:
/// inline code (`--update-refs`, `python3 fib.py --n 40`), URLs and bare links, and phone or
/// digit-grouped numbers (`+966 50 123 4567`, whose groups the bidi algorithm would otherwise
/// reverse). Without an isolate their neutral characters (`-`, `.`, `/`, spaces) take the
/// paragraph's direction and the run splits and reorders.
///
/// Applied only to the text handed to `Text` (`_MarkdownText`), never to the markdown, so a
/// copy of the reply, Read Aloud, export and the stored history keep the model's bytes. Selecting
/// and copying the displayed text does carry the (invisible) isolates. Left alone when the text
/// holds no right-to-left letter and lays out left to right: there an isolate changes nothing.
enum MarkdownBidiIsolation {
    static let isolateStart: Character = "\u{2066}"
    static let isolateEnd: Character = "\u{2069}"

    static func isolated(_ text: AttributedString, layoutDirection: LayoutDirection) -> AttributedString {
        let string = String(text.characters)
        guard layoutDirection == .rightToLeft || MarkdownContentDirection.containsRightToLeft(string) else {
            return text
        }
        // Character offsets of the runs to isolate: the renderer's (inline code, autolinks), then
        // URLs and grouped numbers found in the text. A found URL that overlaps a rendered run is
        // dropped (the parser's link boundary wins); a number joins an inline-code group in it.
        let taggedRanges = text.runs[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self]
            .filter { $0.0 == true }.map(\.1)
        var tagged = characterOffsets(of: taggedRanges, in: text.characters)
        tagged.sort { $0.lowerBound < $1.lowerBound }
        var spans = tagged
        var next = 0
        let runs = leftToRightRuns(in: string).sorted { $0.range.lowerBound < $1.range.lowerBound }
        for (run, span) in zip(runs, characterOffsets(of: runs.map(\.range), in: string)) {
            if run.isURL {
                // Found runs come in order, so one cursor walks the tagged ones.
                while next < tagged.count, tagged[next].upperBound <= span.lowerBound { next += 1 }
                if next < tagged.count, tagged[next].overlaps(span) { continue }
            }
            spans.append(span)
        }
        let merged = merge(spans)
        guard !merged.isEmpty else { return text }
        let paragraphs = paragraphRanges(in: string)
        let isolating = isolatingParagraphs(paragraphs, of: text, string: string, layoutDirection: layoutDirection)
        var paragraph = 0
        // Built from slices of the input, whose indices stay valid: each LRI takes the attributes
        // of the character it opens, each PDI those of the character it closes (a highlight's
        // background runs on unbroken).
        var result = AttributedString()
        var index = text.startIndex
        var cursor = (index: text.startIndex, offset: 0)
        func advance(to target: Int) -> AttributedString.Index {
            cursor = (text.characters.index(cursor.index, offsetBy: target - cursor.offset), target)
            return cursor.index
        }
        for span in merged {
            let start = advance(to: span.lowerBound)
            // A paragraph that reads left to right and holds no right-to-left letter (a merged
            // text's English paragraph beside a Hebrew one) needs no isolate, and selecting it
            // should copy its exact characters.
            while paragraph < paragraphs.count - 1, paragraphs[paragraph].upperBound <= span.lowerBound { paragraph += 1 }
            if !isolating[paragraph] { continue }
            result += text[index..<start]
            let end = advance(to: span.upperBound)
            let last = text.characters.index(before: end)
            result += AttributedString(String(isolateStart), attributes: text[start..<text.characters.index(after: start)].runs.first?.attributes ?? AttributeContainer())
            result += text[start..<end]
            result += AttributedString(String(isolateEnd), attributes: text[last..<end].runs.first?.attributes ?? AttributeContainer())
            index = end
        }
        result += text[index...]
        return result
    }

    /// The character offsets of `ranges` in `collection`, found in one forward walk over its
    /// bounds. A distance from the start for each range would make a long reply with many runs
    /// quadratic, on the main actor, on every streaming update.
    static func characterOffsets<C: Collection>(of ranges: [Range<C.Index>], in collection: C) -> [Range<Int>] {
        let bounds = ranges.flatMap { [$0.lowerBound, $0.upperBound] }
        let order = bounds.indices.sorted { bounds[$0] < bounds[$1] }
        var offsets = [Int](repeating: 0, count: bounds.count)
        var index = collection.startIndex
        var offset = 0
        for slot in order {
            offset += collection.distance(from: index, to: bounds[slot])
            index = bounds[slot]
            offsets[slot] = offset
        }
        return ranges.indices.map { offsets[2 * $0]..<offsets[2 * $0 + 1] }
    }

    /// The URLs, dates and grouped numbers in `string`, which read left to right as units. A
    /// number run that overlaps a date gives way to it, so two dates side by side stay two while a
    /// phone number keeps its country code (`+1 212-555-0123`).
    static func leftToRightRuns(in string: String) -> [(range: Range<String.Index>, isURL: Bool)] {
        guard string.contains(where: { $0.isNumber || $0 == "/" || $0 == "." }) else { return [] }
        let whole = NSRange(string.startIndex..., in: string)
        func ranges(_ expression: NSRegularExpression) -> [Range<String.Index>] {
            expression.matches(in: string, range: whole).compactMap { Range($0.range, in: string) }
        }
        let urls = urlRanges(in: string)
        let dates = ranges(date)
        // Numbers are found with the dates masked out, so a phone number next to a date keeps its
        // own run (each masked character is one UTF-16 unit, as the digits and hyphens it replaces).
        var masked = string
        for range in dates.reversed() {
            masked.replaceSubrange(range, with: String(repeating: "x", count: string[range].count))
        }
        let numbers = number.matches(in: masked, range: NSRange(masked.startIndex..., in: masked)).compactMap { match -> Range<String.Index>? in
            guard let range = Range(match.range, in: string) else { return nil }
            return string[range].filter({ $0.isASCII && $0.isNumber }).count >= 6 ? range : nil
        }
        return urls.map { ($0, true) } + (dates + numbers).map { ($0, false) }
    }

    /// The bare URLs in `string` (`MarkdownContentDirection` skips them as it skips autolinks).
    static func urlRanges(in string: String) -> [Range<String.Index>] {
        guard string.contains("://") || string.contains("www.") else { return [] }
        return url.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap { match in
            guard var range = Range(match.range, in: string) else { return nil }
            // A closing parenthesis that balances one in the URL belongs to it
            // (`https://en.wikipedia.org/wiki/Swift_(programming_language)`).
            while range.upperBound < string.endIndex, string[range.upperBound] == ")",
                  string[range].filter({ $0 == "(" }).count > string[range].filter({ $0 == ")" }).count {
                range = range.lowerBound..<string.index(after: range.upperBound)
            }
            return range
        }
    }

    /// Character offsets of the paragraphs of `string` (split at newlines, CRLF included).
    static func paragraphRanges(in string: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        var offset = 0
        for character in string {
            if character.isNewline {
                ranges.append(start..<offset)
                start = offset + 1
            }
            offset += 1
        }
        ranges.append(start..<offset)
        return ranges
    }

    /// For each paragraph of `string` (`paragraphRanges`), whether it needs isolates: it reads
    /// right to left (its own writing direction, else the layout's) or holds a right-to-left
    /// letter. One pass, with cursors into both views.
    private static func isolatingParagraphs(
        _ paragraphs: [Range<Int>], of text: AttributedString, string: String, layoutDirection: LayoutDirection
    ) -> [Bool] {
        var stringCursor = (index: string.startIndex, offset: 0)
        var textCursor = (index: text.startIndex, offset: 0)
        return paragraphs.map { paragraph in
            let lower = string.index(stringCursor.index, offsetBy: paragraph.lowerBound - stringCursor.offset)
            let upper = string.index(lower, offsetBy: paragraph.count)
            stringCursor = (upper, paragraph.upperBound)
            if MarkdownContentDirection.containsRightToLeft(string[lower..<upper]) { return true }
            guard !paragraph.isEmpty else { return layoutDirection == .rightToLeft }
            let start = text.characters.index(textCursor.index, offsetBy: paragraph.lowerBound - textCursor.offset)
            textCursor = (start, paragraph.lowerBound)
            switch text[start..<text.characters.index(after: start)].runs.first?.writingDirection {
            case .some(.leftToRight): return false
            case .some(.rightToLeft): return true
            default: return layoutDirection == .rightToLeft
            }
        }
    }

    /// Spans sorted and overlapping ones joined (an inline-code group inside a phone number
    /// isolates the whole number); empty ones dropped.
    static func merge(_ spans: [Range<Int>]) -> [Range<Int>] {
        var merged: [Range<Int>] = []
        for span in spans.filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, last.overlaps(span) {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// A URL with a scheme or `www.`, without the sentence punctuation after it.
    private static let url = try! NSRegularExpression(
        pattern: #"(?:[a-zA-Z][a-zA-Z0-9+.\-]*://|www\.)[^\s<>"،؛؟\x{200E}\x{200F}\x{2066}-\x{2069}]*[^\s<>".,:;!?'’”)\]،؛؟\x{200E}\x{200F}\x{2066}-\x{2069}]"#
    )

    /// An ISO date, `2026-11-17`. (ASCII digits only here and in `number`: Arabic-Indic digit
    /// groups reorder inside an isolate too, since rule N1 treats them as right-to-left, so an
    /// isolate would not fix them.)
    private static let date = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])[0-9]{4}-[0-9]{2}-[0-9]{2}(?![\p{L}\p{N}])"#
    )

    /// Digits in three or more groups split by single spaces, no-break spaces, dots or hyphens,
    /// optionally after a `+`, six digits or more: phone numbers and grouped thousands. A range
    /// written `10 - 20` is not one.
    private static let number = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])\+?[0-9]{1,4}(?:[ \x{00A0}.\-][0-9]{1,6}){2,}(?![\p{L}\p{N}])"#
    )
}
