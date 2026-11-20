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
        // Character offsets of the runs to isolate, in order and not overlapping.
        var spans: [Range<Int>] = []
        for (value, range) in text.runs[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self]
        where value == true {
            let lower = text.characters.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.characters.distance(from: text.startIndex, to: range.upperBound)
            spans.append(lower..<upper)
        }
        let whole = NSRange(string.startIndex..., in: string)
        for (expression, isNumber) in [(url, false), (number, true)] {
            for match in expression.matches(in: string, range: whole) {
                guard let range = Range(match.range, in: string) else { continue }
                if isNumber, string[range].filter({ $0.isASCII && $0.isNumber }).count < 6 { continue }
                let lower = string.distance(from: string.startIndex, to: range.lowerBound)
                let upper = string.distance(from: string.startIndex, to: range.upperBound)
                let span = lower..<upper
                if !spans.contains(where: { $0.overlaps(span) }) { spans.append(span) }
            }
        }
        guard !spans.isEmpty else { return text }
        var result = text
        // From the end, so earlier offsets stay valid. Each mark takes the attributes of the run it
        // opens (a highlight's background runs on unbroken).
        for span in spans.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            let end = result.characters.index(result.startIndex, offsetBy: span.upperBound)
            let start = result.characters.index(result.startIndex, offsetBy: span.lowerBound)
            let attributes = result[start..<result.characters.index(after: start)].runs.first?.attributes ?? AttributeContainer()
            result.insert(AttributedString(String(isolateEnd), attributes: attributes), at: end)
            result.insert(AttributedString(String(isolateStart), attributes: attributes), at: start)
        }
        return result
    }

    /// A URL with a scheme or `www.`, without the sentence punctuation after it.
    private static let url = try! NSRegularExpression(
        pattern: #"(?:[a-zA-Z][a-zA-Z0-9+.\-]*://|www\.)[^\s<>"]*[^\s<>".,:;!?'’”)\]]"#
    )

    /// Digits in three or more groups split by single spaces, no-break spaces, dots or hyphens,
    /// optionally after a `+`, six digits or more: phone numbers, grouped thousands, ISO dates.
    /// A range written `10 - 20` is not one.
    private static let number = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])\+?[0-9]{1,4}(?:[ \x{00A0}.\-][0-9]{1,6}){2,}(?![\p{L}\p{N}])"#
    )
}
