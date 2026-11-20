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
/// "Strong" is approximated without the Unicode bidi tables, which Swift does not expose: a
/// character in a right-to-left script block (Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan,
/// Mandaic, their presentation forms and the supplementary RTL blocks) other than its marks,
/// digits and few weak or neutral signs is right-to-left (letters, and punctuation such as `؟`),
/// any other letter left-to-right, and the marks LRM, RLM and ALM count. Digits,
/// punctuation, symbols, spaces and emoji are neutral.
public enum MarkdownContentDirection {
    /// The direction of the first strong character of `text`, or nil when it has none. As rule P2
    /// says, characters between an isolate initiator (LRI, RLI, FSI) and its PDI are skipped.
    public static func firstStrong(in text: some StringProtocol) -> LayoutDirection? {
        var isolates = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x2066...0x2068: isolates += 1
            case 0x000A, 0x000D, 0x001C...0x001E, 0x0085, 0x2029: isolates = 0  // paragraph separators (B)
            case 0x2069: isolates = max(isolates - 1, 0)
            default:
                if isolates == 0, let direction = strongDirection(of: scalar) { return direction }
            }
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
        if isRightToLeftBlock(scalar.value) {
            // Most of these blocks is strong R or AL, punctuation such as `؟` and `؛` included;
            // their marks, digits and the few weak or neutral signs are not.
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .spacingMark, .decimalNumber, .format, .spaceSeparator:
                return nil
            case .mathSymbol, .otherSymbol, .currencySymbol, .modifierSymbol:
                // Mostly ON or ES (`؆`, the Hebrew alternative plus sign, the bismillah ligature);
                // the Arabic ray, the afghani sign, the two Sindhi signs and the rial sign are AL.
                switch scalar.value {
                case 0x0608, 0x060B, 0x06FD, 0x06FE, 0xFDFC: return .rightToLeft
                default: return nil
                }
            default:
                break
            }
            switch scalar.value {
            case 0x0600...0x0605, 0x0609...0x060A, 0x060C, 0x060E...0x060F, 0x066A...0x066C, 0x06DD...0x06DE, 0x06E9,
                 0x08E2, 0xFD3E...0xFD3F:  // number signs, per-mille, comma, poetic marks, ornate parentheses
                return nil
            default:
                return .rightToLeft
            }
        }
        guard scalar.properties.isAlphabetic else { return nil }
        return .leftToRight
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
        var isolates = 0
        return of(markup, skipsMath: skipsMath, isolates: &isolates)
    }

    /// `isolates` is the isolate depth open at `markup`: it carries across the inline nodes of
    /// one block (`\u{2067}**مرحبا**\u{2069} hello` reads left to right), and each block starts
    /// at zero, as a paragraph ends every isolate.
    private static func of(_ markup: any Markup, skipsMath: Bool, isolates: inout Int) -> LayoutDirection? {
        switch markup {
        case let text as Markdown.Text:
            return firstStrong(inText: text.string, skipsMath: skipsMath, isolates: &isolates)
        case is InlineCode, is CodeBlock, is InlineHTML, is HTMLBlock, is Markdown.Image, is SymbolLink:
            // Skipped for direction, but a paragraph separator shown in it still ends every isolate.
            if containsParagraphSeparator(skippedText(of: markup)) { isolates = 0 }
            return nil
        case let link as Markdown.Link:
            if isAutolink(link) {
                if containsParagraphSeparator(link.plainText) { isolates = 0 }
                return nil
            }
        default:
            break
        }
        for child in markup.children {
            // A block, a table cell and a hard line break each end every isolate (the display
            // shows a cell as its own text and a hard break as a paragraph separator).
            if child is any BlockMarkup || child is Markdown.Table.Cell || child is LineBreak { isolates = 0 }
            if let direction = of(child, skipsMath: skipsMath, isolates: &isolates) { return direction }
        }
        return nil
    }

    /// The text a skipped node shows.
    private static func skippedText(of markup: any Markup) -> String {
        switch markup {
        case let code as InlineCode: return code.code
        case let html as InlineHTML:
            // The display converts inline HTML: a comment or a tag shows nothing (its source
            // newlines included), and only a line break tag shows a newline.
            return html.rawHTML.range(of: #"^<br(?:\s[^>]*)?/?>$"#, options: [.regularExpression, .caseInsensitive]) != nil ? "\n" : ""
        default: return ""
        }
    }

    /// A paragraph separator (bidi class B), which ends every isolate open before it.
    static func isParagraphSeparator(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x000A, 0x000D, 0x001C...0x001E, 0x0085, 0x2029: return true
        default: return false
        }
    }

    static func containsParagraphSeparator(_ text: some StringProtocol) -> Bool {
        text.unicodeScalars.contains(where: isParagraphSeparator)
    }

    /// The first strong character of a text node's string, past any math in it (the parser's
    /// placeholders and `$...$`-style spans: a formula's letters are not prose) and past bare URLs,
    /// which the display isolates as autolinks are.
    static func firstStrong(inText text: String, skipsMath: Bool) -> LayoutDirection? {
        var isolates = 0
        return firstStrong(inText: text, skipsMath: skipsMath, isolates: &isolates)
    }

    /// The same, starting at isolate depth `isolates` and leaving it at the depth after `text`.
    static func firstStrong(inText text: String, skipsMath: Bool, isolates: inout Int) -> LayoutDirection? {
        var skipped = MarkdownBidiIsolation.urlRanges(in: text)
        if skipsMath, text.contains(where: { $0 == "$" || $0 == "\\" || $0 == "(" }) {
            skipped += MarkdownMathPreprocessor.placeholderSegments(in: text).map(\.range)
                + MathParser(text: text).mathRepresentations.map(\.range)
        }
        // One scan, so an isolate's depth carries across a skipped range.
        let sorted = skipped.sorted { $0.lowerBound < $1.lowerBound }
        var next = 0
        var index = text.unicodeScalars.startIndex
        while index < text.unicodeScalars.endIndex {
            while next < sorted.count, sorted[next].upperBound <= index { next += 1 }
            if next < sorted.count, sorted[next].contains(index) {
                // A skipped math span's separator still ends every isolate.
                if text.unicodeScalars[index..<sorted[next].upperBound].contains(where: isParagraphSeparator) { isolates = 0 }
                index = sorted[next].upperBound
                continue
            }
            let scalar = text.unicodeScalars[index]
            switch scalar.value {
            case 0x2066...0x2068: isolates += 1
            case 0x000A, 0x000D, 0x001C...0x001E, 0x0085, 0x2029: isolates = 0  // paragraph separators (B)
            case 0x2069: isolates = max(isolates - 1, 0)
            default:
                if isolates == 0, let direction = strongDirection(of: scalar) { return direction }
            }
            index = text.unicodeScalars.index(after: index)
        }
        return nil
    }

    /// Whether `link` is an autolink, shown as its own address: `<https://...>`, or
    /// `<name@example.com>` with its `mailto:` destination. The renderer isolates these, and
    /// a block's direction skips them.
    static func isAutolink(_ link: Markdown.Link) -> Bool {
        guard let destination = link.destination else { return false }
        return link.plainText == destination || "mailto:" + link.plainText == destination
    }
}
