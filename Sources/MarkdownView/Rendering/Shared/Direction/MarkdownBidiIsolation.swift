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
/// A number with Latin words after it (`1 ms`, `2 GB RAM`) is isolated too, and inside a found
/// number, date or measure the spaces show as no-break spaces, so a line never breaks inside one
/// (gemma4-qat#1986: `+966 50 123` ended one line and `4567` began the next). A number, date or
/// measure after a left-to-right letter is not isolated: rule W7 already reads it with that letter's
/// phrase (`value 1 234 567`), and an isolate would set it apart; a number keeps its no-break spaces.
/// Inside an isolate the text writes itself (FSI, LRI, RLI) nothing is isolated but numbers and
/// dates, which hold no strong letter: an inner isolate around a URL or code would hide the letters
/// an FSI resolves from.
///
/// Applied only to the text handed to `Text` (`_MarkdownText`), never to the markdown, so a
/// copy of the reply, Read Aloud, export and the stored history keep the model's bytes. Selecting
/// and copying the displayed text does carry the (invisible) isolates and those no-break spaces. Left alone when the text
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
        // Text that writes its own isolate (FSI, LRI, RLI) is left as written inside it: an FSI
        // resolves from its first strong letter, which an inner isolate around a URL or code would
        // hide (`abc FSI https://example.com שלום PDI` reads left to right).
        let written = writtenIsolates(in: string)
        var spans = tagged.filter { !starts($0, inside: written) }
        // The found numbers and dates, and each measure's number and first word (`1 ms`), whose
        // spaces show as no-break spaces, so a line never breaks inside one (gemma4-qat#1986).
        var found: [Range<Int>] = []
        var numberRuns: [Range<Int>] = []
        var opaque = tagged
        var next = 0
        let runs = leftToRightRuns(in: string).sorted { $0.range.lowerBound < $1.range.lowerBound }
        for (run, span) in zip(runs, characterOffsets(of: runs.map(\.range), in: string)) {
            if run.isURL {
                // Found runs come in order, so one cursor walks the tagged ones.
                while next < tagged.count, tagged[next].upperBound <= span.lowerBound { next += 1 }
                if next < tagged.count, tagged[next].overlaps(span) { continue }
                opaque.append(span)
                if !starts(span, inside: written) { spans.append(span) }
            } else {
                found.append(span)
                numberRuns.append(span)
            }
        }
        // A number or date after a left-to-right letter already reads with it (rule W7 gives its
        // digits the letter's direction, `value 1 234 567`), and an isolate would set it apart
        // from that phrase, so it keeps only its no-break spaces; any other one is isolated. The
        // same rule as a measure's (`acceptedMeasures`).
        let leading = precedingStrong(before: numberRuns.map(\.lowerBound), in: string, isolated: merge(spans))
        var keptOnly: [Range<Int>] = []
        for (span, strong) in zip(numberRuns, leading) {
            if strong == .leftToRight { keptOnly.append(span) } else { spans.append(span) }
        }
        for measure in acceptedMeasures(in: string, isolated: merge(spans), numbers: found, opaque: merge(opaque)) {
            spans.append(measure.whole)
            found += measure.units
        }
        // A measure's isolate hides its letters from W7 too (`خلال 1 ms، 2026-11-17`: the date
        // follows Arabic once `1 ms` is isolated), so the kept-only numbers are judged again. An
        // isolate only hides letters, so none goes the other way.
        if !keptOnly.isEmpty, !spans.isEmpty {
            let again = precedingStrong(before: keptOnly.map(\.lowerBound), in: string, isolated: merge(spans))
            var stillKept: [Range<Int>] = []
            for (span, strong) in zip(keptOnly, again) {
                if strong == .leftToRight { stillKept.append(span) } else { spans.append(span) }
            }
            keptOnly = stillKept
        }
        let unbroken = subtracting(merge(tagged), from: found.sorted { $0.lowerBound < $1.lowerBound })
        var unbrokenCursor = 0
        let isolates = merge(spans)
        // The part of a kept-only number an isolate covers (a measure's, inline code inside it) is
        // that isolate's; the rest keeps its no-break spaces.
        let unisolated = subtracting(isolates, from: keptOnly)
        let merged = (isolates.map { ($0, true) } + unisolated.map { ($0, false) }).sorted { $0.0.lowerBound < $1.0.lowerBound }
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
        for (span, isolates) in merged {
            let start = advance(to: span.lowerBound)
            // A paragraph that reads left to right and holds no right-to-left letter (a merged
            // text's English paragraph beside a Hebrew one) needs no isolate, and selecting it
            // should copy its exact characters.
            while paragraph < paragraphs.count - 1, paragraphs[paragraph].upperBound <= span.lowerBound { paragraph += 1 }
            if !isolating[paragraph] { continue }
            result += text[index..<start]
            let end = advance(to: span.upperBound)
            let last = text.characters.index(before: end)
            if isolates {
                result += AttributedString(String(isolateStart), attributes: text[start..<text.characters.index(after: start)].runs.first?.attributes ?? AttributeContainer())
            }
            result += keptTogether(text[start..<end], from: span.lowerBound, unbroken: unbroken, cursor: &unbrokenCursor)
            if isolates {
                result += AttributedString(String(isolateEnd), attributes: text[last..<end].runs.first?.attributes ?? AttributeContainer())
            }
            index = end
        }
        result += text[index...]
        return result
    }

    /// `slice` (starting at character offset `offset`), with each space inside an `unbroken` range
    /// replaced by a no-break space of the same attributes: one character for one, so the offsets
    /// after it hold. `unbroken` is sorted and `cursor` walks it across calls made in order.
    static func keptTogether(
        _ slice: AttributedSubstring, from offset: Int, unbroken: [Range<Int>], cursor: inout Int
    ) -> AttributedString {
        // One forward pass: the text between replaced spaces is copied as slices, so a long
        // grouped number costs one walk, not one walk per space.
        var piece = AttributedString()
        let characters = slice.characters
        var copied = slice.startIndex
        var index = slice.startIndex
        var at = offset
        while index < slice.endIndex {
            let after = characters.index(after: index)
            if characters[index] == " " {
                while cursor < unbroken.count, unbroken[cursor].upperBound <= at { cursor += 1 }
                if cursor < unbroken.count, unbroken[cursor].contains(at) {
                    piece += slice[copied..<index]
                    let attributes = slice[index..<after].runs.first?.attributes ?? AttributeContainer()
                    piece += AttributedString(String(noBreakSpace), attributes: attributes)
                    copied = after
                }
            }
            index = after
            at += 1
        }
        piece += slice[copied..<slice.endIndex]
        return piece
    }

    /// `ranges` (sorted) with the parts inside `within` (sorted, disjoint) cut out: inline code keeps
    /// its own spaces, a phone number that crosses a code span's edge keeps the rest together.
    static func subtracting(_ within: [Range<Int>], from ranges: [Range<Int>]) -> [Range<Int>] {
        guard !within.isEmpty else { return ranges }
        var result: [Range<Int>] = []
        var cursor = 0
        for range in ranges {
            while cursor < within.count, within[cursor].upperBound <= range.lowerBound { cursor += 1 }
            var start = range.lowerBound
            var index = cursor
            while index < within.count, within[index].lowerBound < range.upperBound {
                if within[index].lowerBound > start { result.append(start..<within[index].lowerBound) }
                start = max(start, within[index].upperBound)
                index += 1
            }
            if start < range.upperBound { result.append(start..<range.upperBound) }
        }
        return result.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// The measures of `string` (`measure`) that get an isolate, as character offsets: the whole
    /// match, and each number with the word after it (`pair`), which never break. One forward walk
    /// keeps the last strong direction outside the runs already isolated (`isolated`, sorted and
    /// merged, and the measures taken so far), reset at each paragraph separator and restored after an isolate
    /// written in the text, inside which no measure is taken. A measure after a left-to-right letter is left alone: there rule W7
    /// already gives the number the word's direction and the phrase is one run, which an isolate
    /// would split (`the value 10 GB`). The regex runs between inline code and URLs; a found
    /// grouped number ending where a measure's number ends takes the unit into its isolate
    /// (`1 234 567 MB`).
    static func acceptedMeasures(
        in string: String, isolated: [Range<Int>], numbers: [Range<Int>], opaque: [Range<Int>]
    ) -> [(whole: Range<Int>, units: [Range<Int>])] {
        guard string.contains(where: { $0.isASCII && $0.isNumber }) else { return [] }
        // The regex runs on the gaps between the opaque runs (`opaque`, sorted and merged: inline
        // code, autolinks, URLs), each gap's edges taken as boundaries, so a match neither starts in
        // one nor runs through one.
        var gaps: [Range<String.Index>] = []
        var gapStart = string.startIndex
        var opaqueCursor = 0
        var inOpaque = false
        for (offset, index) in string.indices.enumerated() {
            while opaqueCursor < opaque.count, opaque[opaqueCursor].upperBound <= offset { opaqueCursor += 1 }
            let opaqueHere = opaqueCursor < opaque.count && opaque[opaqueCursor].contains(offset)
            if opaqueHere, !inOpaque { gaps.append(gapStart..<index) }
            if !opaqueHere, inOpaque { gapStart = index }
            inOpaque = opaqueHere
        }
        if !inOpaque { gaps.append(gapStart..<string.endIndex) }
        let matches = gaps.filter { !$0.isEmpty }.flatMap { gap in
            measure.matches(in: string, range: NSRange(gap, in: string)).compactMap { match -> [Range<String.Index>]? in
                guard let range = Range(match.range, in: string), let number = Range(match.range(at: 1), in: string) else { return nil }
                let pairs = pair.matches(in: string, range: match.range).compactMap { Range($0.range, in: string) }
                return [range, number] + pairs
            }
        }
        guard !matches.isEmpty else { return [] }
        let offsets = characterOffsets(of: matches.flatMap { $0 }, in: string)
        var candidates: [(whole: Range<Int>, number: Range<Int>, units: [Range<Int>], unitLike: Bool)] = []
        var next = 0
        for match in matches {
            // A capitalised word of four letters or more is a name or starts a clause (`2024 Apple`)
            // and reads after the number unisolated; a unit is one case or short (`ms`, `GB`, `GiB`,
            // `Hz`, `kWh`, `dB`), and a few longer ones are named.
            let word = String(string[match[1].upperBound..<match[0].upperBound].dropFirst().prefix { $0.isLetter })
            let unitLike = !isCapitalisedWord(word) || titleCaseUnits.contains(word)
            candidates.append((offsets[next], offsets[next + 1], Array(offsets[(next + 2)..<(next + match.count)]), unitLike))
            next += match.count
        }
        var accepted: [(whole: Range<Int>, units: [Range<Int>])] = []
        var lastStrong: LayoutDirection?
        var saved: [LayoutDirection?] = []
        var skip = 0
        var number = 0
        var candidate = 0
        var acceptedEnd = 0
        for (offset, character) in string.enumerated() {
            while skip < isolated.count, isolated[skip].upperBound <= offset { skip += 1 }
            let insideIsolated = skip < isolated.count && isolated[skip].contains(offset)
            while number < numbers.count, numbers[number].upperBound <= offset { number += 1 }
            while candidate < candidates.count, candidates[candidate].whole.lowerBound <= offset {
                let measure = candidates[candidate]
                candidate += 1
                // Text that writes its own isolates is left as it reads (an FSI resolves from its
                // first strong letter, which an inner isolate would hide).
                guard measure.whole.lowerBound == offset, offset >= acceptedEnd, saved.isEmpty,
                      lastStrong != .leftToRight, measure.unitLike else { continue }
                if !insideIsolated {
                    accepted.append((measure.whole, measure.units))
                } else if number < numbers.count, numbers[number].contains(offset),
                          numbers[number].upperBound == measure.number.upperBound {
                    accepted.append((numbers[number].lowerBound..<measure.whole.upperBound, measure.units))
                } else {
                    continue
                }
                acceptedEnd = measure.whole.upperBound
            }
            if character.unicodeScalars.contains(where: MarkdownContentDirection.isParagraphSeparator) {
                lastStrong = nil
                saved.removeAll()
            } else if character == isolateEnd {
                if let outer = saved.popLast() { lastStrong = outer }
            } else if character == isolateStart || character == "\u{2067}" || character == "\u{2068}" {
                saved.append(lastStrong)
                lastStrong = nil
            } else if !insideIsolated, offset >= acceptedEnd,
                      let direction = character.unicodeScalars.lazy.compactMap(MarkdownContentDirection.strongDirection(of:)).first {
                lastStrong = direction
            }
        }
        return accepted
    }

    /// The character offsets inside an isolate the text writes itself (U+2066 LRI, U+2067 RLI,
    /// U+2068 FSI, up to its PDI), nested ones included, sorted and disjoint. A paragraph separator
    /// (bidi class B) ends every open one; a line separator (U+2028) does not.
    static func writtenIsolates(in string: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var depth = 0
        var start = 0
        for (offset, character) in string.enumerated() {
            if character.unicodeScalars.contains(where: MarkdownContentDirection.isParagraphSeparator) {
                if depth > 0 { ranges.append(start..<offset) }
                depth = 0
            } else if character == isolateStart || character == "\u{2067}" || character == "\u{2068}" {
                if depth == 0 { start = offset + 1 }
                depth += 1
            } else if character == isolateEnd, depth > 0 {
                depth -= 1
                if depth == 0 { ranges.append(start..<offset) }
            }
        }
        if depth > 0 { ranges.append(start..<string.count) }
        return ranges.filter { !$0.isEmpty }
    }

    /// Whether `span` starts inside one of `ranges` (sorted, disjoint).
    static func starts(_ span: Range<Int>, inside ranges: [Range<Int>]) -> Bool {
        var low = 0
        var high = ranges.count
        while low < high {
            let middle = (low + high) / 2
            if ranges[middle].upperBound <= span.lowerBound { low = middle + 1 } else { high = middle }
        }
        return low < ranges.count && ranges[low].contains(span.lowerBound)
    }

    /// For each offset of `offsets` (sorted), the last strong direction before it as rule W7 sees
    /// it: letters inside `isolated` (sorted, merged) or inside an isolate the text writes are
    /// skipped, and a paragraph separator resets it. `nil` where there is none.
    static func precedingStrong(before offsets: [Int], in string: String, isolated: [Range<Int>]) -> [LayoutDirection?] {
        guard !offsets.isEmpty else { return [] }
        var result: [LayoutDirection?] = []
        result.reserveCapacity(offsets.count)
        var lastStrong: LayoutDirection?
        var saved: [LayoutDirection?] = []
        var skip = 0
        var next = 0
        for (offset, character) in string.enumerated() {
            while next < offsets.count, offsets[next] <= offset {
                result.append(lastStrong)
                next += 1
            }
            if next == offsets.count { break }
            while skip < isolated.count, isolated[skip].upperBound <= offset { skip += 1 }
            if character.unicodeScalars.contains(where: MarkdownContentDirection.isParagraphSeparator) {
                lastStrong = nil
                saved.removeAll()
            } else if character == isolateEnd {
                if let outer = saved.popLast() { lastStrong = outer }
            } else if character == isolateStart || character == "\u{2067}" || character == "\u{2068}" {
                saved.append(lastStrong)
                lastStrong = nil
            } else if !(skip < isolated.count && isolated[skip].contains(offset)),
                      let direction = character.unicodeScalars.lazy.compactMap(MarkdownContentDirection.strongDirection(of:)).first {
                lastStrong = direction
            }
        }
        while result.count < offsets.count { result.append(lastStrong) }
        return result
    }

    /// `Word`: an uppercase letter, then three or more letters, all lowercase.
    static func isCapitalisedWord(_ word: String) -> Bool {
        guard word.count >= 4, let first = word.first, first.isUppercase else { return false }
        return word.dropFirst().allSatisfy { $0.isLetter && $0.isLowercase }
    }

    /// Units written capitalised and four letters or longer.
    static let titleCaseUnits: Set<String> = ["Mbps", "Kbps", "Gbps", "Tbps", "Mbit", "Gbit", "Kbit"]

    static let noBreakSpace: Character = "\u{00A0}"

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
            guard var range = Range(match.range(at: 1), in: string) else { return nil }
            // A closing parenthesis that balances one in the URL belongs to it
            // (`https://en.wikipedia.org/wiki/Swift_(programming_language)`). Counted once, then
            // kept up to date, so a run of them is one walk.
            guard range.upperBound < string.endIndex, string[range.upperBound] == ")" else { return range }
            var open = string[range].reduce(0) { $0 + ($1 == "(" ? 1 : $1 == ")" ? -1 : 0) }
            while open > 0, range.upperBound < string.endIndex, string[range.upperBound] == ")" {
                range = range.lowerBound..<string.index(after: range.upperBound)
                open -= 1
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
    /// A URL never runs across a paragraph separator (bidi class B: `\s` misses U+001C-U+001E),
    /// so matching resumes after one at the next URL. The scheme is tried once per word, from its
    /// first letter (`2https://...` gives `https://...`, as before): the lookbehind holds the
    /// attempt to a word's start, and the digits or signs before the letter are skipped
    /// possessively. Retried from every letter, a long word cost time quadratic in its length.
    /// Group 1 is the URL.
    private static let url = try! NSRegularExpression(
        pattern: #"(?:(?<![a-zA-Z0-9+.\-])[0-9+.\-]*+(?=[a-zA-Z])|(?=www\.))((?:[a-zA-Z][a-zA-Z0-9+.\-]*://|www\.)[^\s<>"،؛؟\x{200E}\x{200F}\x{2066}-\x{2069}\x{0A}\x{0D}\x{1C}-\x{1E}\x{85}\x{2029}]*[^\s<>".,:;!?'’”)\]،؛؟\x{200E}\x{200F}\x{2066}-\x{2069}\x{0A}\x{0D}\x{1C}-\x{1E}\x{85}\x{2029}])"#
    )

    /// An ISO date, `2026-11-17`. (ASCII digits only here and in `number`: Arabic-Indic digit
    /// groups reorder inside an isolate too, since rule N1 treats them as right-to-left, so an
    /// isolate would not fix them.)
    private static let date = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])[0-9]{4}-[0-9]{2}-[0-9]{2}(?![\p{L}\p{N}])"#
    )

    /// A measure: a whole ASCII number, signed, decimal, a time, a fraction or a range too (`-5`,
    /// `12.5`, `12:30`, `1/2`, `5-10`; a number grouped by spaces is found as a number first), then one or more Latin words
    /// (accented ones too), each after one space or no-break space; numbers may follow among the
    /// words: `1 ms`, `2 GB RAM`, `40 km/h`, `-5 ms to +5 ms`, `3 files in the folder`. Between the
    /// number and the word a space takes the paragraph's direction and the two swap
    /// (gemma4-qat#1986). Group 1 is the first number. A number with no space before its unit
    /// (`5GB`) is one run already, and a sentence's full stop stays outside (`1 ms.`).
    private static let measure = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(?<![0-9][.,:/\-\x{2013}])("# + Measure.number + ")" + Measure.space + Measure.word
            + "(?:" + Measure.space + "(?:" + Measure.word + "|" + Measure.number + "))*" + #"(?![\p{L}\p{N}\p{M}])"#
    )

    /// A number and the word after it, inside a measure: the part that never breaks.
    private static let pair = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])"# + Measure.number + Measure.space + Measure.word
    )

    private enum Measure {
        static let number = #"(?:\+|-|\x{2212})?[0-9]+(?:[.,:/\-\x{2013}][0-9]+)*"#
        static let word = #"\p{Latin}[\p{Latin}\p{M}0-9]*(?:/\p{Latin}+)?"#
        static let space = #"[ \x{00A0}]"#
    }

    /// Digits in three or more groups split by single spaces, no-break spaces, dots or hyphens,
    /// optionally after a `+`, six digits or more: phone numbers and grouped thousands. A range
    /// written `10 - 20` is not one.
    private static let number = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])\+?[0-9]{1,4}(?:[ \x{00A0}.\-][0-9]{1,6}){2,}(?![\p{L}\p{N}])"#
    )
}
