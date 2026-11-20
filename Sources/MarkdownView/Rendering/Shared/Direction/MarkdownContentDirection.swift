//
//  MarkdownContentDirection.swift
//  MarkdownView (numen-tech fork)
//

import SwiftUI
import Markdown

/// numen fork (gemma4-qat#1765): the reading direction of content, from its first strong
/// character, as HTML's `dir="auto"` and UAX #9's rule P2 decide a paragraph's. Each block
/// (paragraph, heading, list, list item, table, block quote) lays out in the direction of its own
/// text rather than the UI's, so an Arabic reply in an English UI reads right to left and an
/// English one in an Arabic UI left to right.
///
/// "Strong" is approximated without the Unicode bidi tables, which Swift does not expose: a letter
/// (`isAlphabetic`) in a right-to-left script block (Hebrew, Arabic, Syriac, Thaana, NKo,
/// Samaritan, Mandaic, their presentation forms and the supplementary RTL blocks) is
/// right-to-left, any other letter left-to-right, and the marks LRM, RLM and ALM count. Digits,
/// punctuation, symbols, spaces and emoji are neutral.
public enum MarkdownContentDirection {
    /// The direction of the first strong character of `text`, or nil when it has none.
    public static func firstStrong(in text: some StringProtocol) -> LayoutDirection? {
        for scalar in text.unicodeScalars {
            if let direction = strongDirection(of: scalar) { return direction }
        }
        return nil
    }

    /// Whether `text` holds any right-to-left letter.
    public static func containsRightToLeft(_ text: some StringProtocol) -> Bool {
        text.unicodeScalars.contains { strongDirection(of: $0) == .rightToLeft }
    }

    static func strongDirection(of scalar: Unicode.Scalar) -> LayoutDirection? {
        switch scalar.value {
        case 0x200E: return .leftToRight  // LEFT-TO-RIGHT MARK
        case 0x200F, 0x061C: return .rightToLeft  // RIGHT-TO-LEFT MARK, ARABIC LETTER MARK
        default: break
        }
        guard scalar.properties.isAlphabetic else { return nil }
        return isRightToLeftBlock(scalar.value) ? .rightToLeft : .leftToRight
    }

    private static func isRightToLeftBlock(_ value: UInt32) -> Bool {
        switch value {
        case 0x0590...0x08FF,  // Hebrew, Arabic, Syriac, Arabic Supplement, Thaana, NKo, Samaritan, Mandaic, Arabic Extended
             0xFB1D...0xFDFF,  // Hebrew and Arabic presentation forms A
             0xFE70...0xFEFF,  // Arabic presentation forms B
             0x10800...0x10FFF,  // supplementary RTL scripts (Phoenician, Kharoshthi, Old South Arabian, ...)
             0x1E800...0x1EFFF:  // Mende Kikakui, Adlam, Arabic mathematical alphabetic symbols
            return true
        default:
            return false
        }
    }

    // MARK: Blocks

    /// The direction of a block: its first strong character outside inline code, math, HTML,
    /// images and bare links (a URL written as its own label), or nil when it has none.
    static func of(_ markup: any Markup, skipsMath: Bool) -> LayoutDirection? {
        switch markup {
        case let text as Markdown.Text:
            return firstStrong(inText: text.string, skipsMath: skipsMath)
        case is InlineCode, is CodeBlock, is InlineHTML, is HTMLBlock, is Markdown.Image, is SymbolLink:
            return nil
        case let link as Markdown.Link:
            if let destination = link.destination, link.plainText == destination { return nil }
        default:
            break
        }
        for child in markup.children {
            if let direction = of(child, skipsMath: skipsMath) { return direction }
        }
        return nil
    }

    /// The first strong character of a text node's string, past any math in it (the parser's
    /// placeholders and `$...$`-style spans: a formula's letters are not prose).
    static func firstStrong(inText text: String, skipsMath: Bool) -> LayoutDirection? {
        guard skipsMath, text.contains(where: { $0 == "$" || $0 == "\\" || $0 == "(" }) else {
            return firstStrong(in: text)
        }
        let math = MarkdownMathPreprocessor.placeholderSegments(in: text).map(\.range)
            + MathParser(text: text).mathRepresentations.map(\.range)
        guard !math.isEmpty else { return firstStrong(in: text) }
        var index = text.startIndex
        for range in math.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if index < range.lowerBound, let direction = firstStrong(in: text[index..<range.lowerBound]) {
                return direction
            }
            index = max(index, range.upperBound)
        }
        return index < text.endIndex ? firstStrong(in: text[index...]) : nil
    }
}
