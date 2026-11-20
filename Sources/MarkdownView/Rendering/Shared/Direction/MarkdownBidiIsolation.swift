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
        var tagged: [Range<Int>] = []
        for (value, range) in text.runs[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self]
        where value == true {
            let lower = text.characters.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.characters.distance(from: text.startIndex, to: range.upperBound)
            tagged.append(lower..<upper)
        }
        var spans = tagged
        for run in leftToRightRuns(in: string) {
            let span = string.distance(from: string.startIndex, to: run.range.lowerBound)..<string.distance(from: string.startIndex, to: run.range.upperBound)
            if run.isURL, tagged.contains(where: { $0.overlaps(span) }) { continue }
            spans.append(span)
        }
        let merged = merge(spans)
        guard !merged.isEmpty else { return text }
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
            // A paragraph written left to right (a merged text's English paragraph beside a Hebrew
            // one) needs no isolate, and selecting it should copy its exact characters.
            if text[start..<text.characters.index(after: start)].runs.first?.writingDirection == .leftToRight { continue }
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

    /// The URLs, dates and grouped numbers in `string`, which read left to right as units. A
    /// number run that overlaps a date gives way to it, so two dates side by side stay two while a
    /// phone number keeps its country code (`+1 212-555-0123`).
    static func leftToRightRuns(in string: String) -> [(range: Range<String.Index>, isURL: Bool)] {
        guard string.contains(where: { $0.isNumber || $0 == "/" || $0 == "." }) else { return [] }
        let whole = NSRange(string.startIndex..., in: string)
        func ranges(_ expression: NSRegularExpression) -> [Range<String.Index>] {
            expression.matches(in: string, range: whole).compactMap { Range($0.range, in: string) }
        }
        let urls = string.contains("://") || string.contains("www.") ? ranges(url) : []
        let dates = ranges(date)
        let numbers = ranges(number).filter { range in
            string[range].filter({ $0.wholeNumberValue != nil }).count >= 6
                && !dates.contains(where: { $0.overlaps(range) })
        }
        return urls.map { ($0, true) } + (dates + numbers).map { ($0, false) }
    }

    /// The bare URLs in `string` (`MarkdownContentDirection` skips them as it skips autolinks).
    static func urlRanges(in string: String) -> [Range<String.Index>] {
        guard string.contains("://") || string.contains("www.") else { return [] }
        return url.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap { Range($0.range, in: string) }
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
        pattern: #"(?:[a-zA-Z][a-zA-Z0-9+.\-]*://|www\.)[^\s<>"،؛؟]*[^\s<>".,:;!?'’”)\]،؛؟]"#
    )

    /// An ISO date, `2026-11-17`, in ASCII or Arabic-Indic digits.
    private static let date = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])[0-9\x{0660}-\x{0669}\x{06F0}-\x{06F9}]{4}-[0-9\x{0660}-\x{0669}\x{06F0}-\x{06F9}]{2}-[0-9\x{0660}-\x{0669}\x{06F0}-\x{06F9}]{2}(?![\p{L}\p{N}])"#
    )

    /// Digits in three or more groups split by single spaces, no-break spaces, dots or hyphens,
    /// optionally after a `+`, six digits or more: phone numbers and grouped thousands. A range
    /// written `10 - 20` is not one.
    private static let number = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])\+?[0-9\x{0660}-\x{0669}\x{06F0}-\x{06F9}]{1,4}(?:[ \x{00A0}.\-][0-9\x{0660}-\x{0669}\x{06F0}-\x{06F9}]{1,6}){2,}(?![\p{L}\p{N}])"#
    )
}
