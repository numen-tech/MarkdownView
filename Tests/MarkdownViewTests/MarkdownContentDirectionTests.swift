import Markdown
#if canImport(AppKit)
import AppKit
import CoreText
#endif
import SwiftUI
import Testing

@testable import MarkdownView

/// numen fork (gemma4-qat#1765): blocks lay out in their content's direction, and left-to-right
/// runs inside right-to-left prose are isolated for display.
@MainActor
@Suite("Markdown Content Direction")
struct MarkdownContentDirectionTests {
    @Test("The first strong character decides", .tags(.rendering), arguments: [
        ("Hello world", LayoutDirection.leftToRight),
        ("שלום עולם", .rightToLeft),
        ("مرحبا بالعالم", .rightToLeft),
        ("123, 456: مرحبا", .rightToLeft),
        ("٣ apples", .leftToRight),
        ("\u{200F}abc", .rightToLeft),
        ("\u{200E}مرحبا", .leftToRight),
        ("\u{2066}git\u{2069} مرحبا", .rightToLeft),
        ("؟ Git", .rightToLeft),
        ("\u{2067}ع https://x.org abc\u{2069} مرحبا", .rightToLeft),
        ("\u{05B0}\u{0651} ok", .leftToRight),
        ("\u{2067}مرحبا\u{2069} hello", .leftToRight),
        ("日本語", .leftToRight),
    ])
    func firstStrong(text: String, expected: LayoutDirection) {
        #expect(MarkdownContentDirection.firstStrong(in: text) == expected)
    }

    @Test("Isolate depth carries across a skipped URL", .tags(.rendering))
    func depthAcrossSkips() {
        #expect(MarkdownContentDirection.firstStrong(inText: "\u{2067}ع https://x.org abc\u{2069} مرحبا", skipsMath: false) == .rightToLeft)
        #expect(MarkdownContentDirection.firstStrong(inText: "https://x.org abc", skipsMath: false) == .leftToRight)
    }

    @Test("Digits, punctuation and emoji are neutral", .tags(.rendering), arguments: ["", "42", "-- 3.14 --", "🙂 ✅", "٣٤٥"])
    func neutral(text: String) {
        #expect(MarkdownContentDirection.firstStrong(in: text) == nil)
    }

    @Test("A block skips inline code, math and bare links", .tags(.rendering), arguments: [
        ("`git rebase` يعيد كتابة السجل.", LayoutDirection.rightToLeft, false),
        ("$x^2$ هو المربع.", .rightToLeft, true),
        ("<https://git-scm.com> هو الموقع.", .rightToLeft, false),
        ("[الوثائق](https://git-scm.com) here", .rightToLeft, false),
        ("**Note:** مرحبا", .leftToRight, false),
        ("1. שלום\n2. world", .rightToLeft, false),
        ("| Name | الاسم |\n|---|---|\n| a | b |", .leftToRight, false),
        ("| الاسم | Name |\n|---|---|\n| a | b |", .rightToLeft, false),
        ("> اقتباس\n> quote", .rightToLeft, false),
        ("https://example.com مرحبا", .rightToLeft, false),
        ("<https://example.com> مرحبا", .rightToLeft, false),
        ("<name@example.com> مرحبا", .rightToLeft, false),
        ("[docs](https://example.com) مرحبا", .leftToRight, false),
    ])
    func block(markdown: String, expected: LayoutDirection, math: Bool) throws {
        let block = try #require(document(markdown, math: math).child(at: 0))
        #expect(MarkdownContentDirection.of(block, skipsMath: math) == expected)
    }

    @Test("Renderer nodes carry their block's direction", .tags(.rendering))
    func nodeDirection() throws {
        let markdown = "# عنوان\n\nEnglish paragraph.\n\n- بند\n\n> quote"
        let document = document(markdown)
        let renderer = MarkdownViewRenderer(configuration: MarkdownRendererConfiguration(), mathContext: nil, elementRenderers: [])
        let directions = document.children.map { child -> LayoutDirection? in
            var renderer = renderer
            return renderer.visit(child).direction
        }
        #expect(directions == [.rightToLeft, .leftToRight, .rightToLeft, .leftToRight])
    }

    @Test("Text blocks of different directions keep theirs as paragraph attributes", .tags(.rendering))
    func mergeRule() throws {
        let english = MarkdownNodeView("One.").withDirection(.leftToRight)
        let neutral = MarkdownNodeView("42").withDirection(nil)
        let arabic = MarkdownNodeView("مرحبا").withDirection(.rightToLeft)

        let same = MarkdownNodeView([english, english], layoutPolicy: .linebreak)
        #expect(same.contentType == .text)
        #expect(same.direction == .leftToRight)
        #expect(same.asAttributedString.map { String($0.characters) } == "One.\n\nOne.")

        // A block with no strong character follows the container: the merged text takes no
        // direction, and the directed paragraphs keep theirs.
        let withNeutral = MarkdownNodeView([english, neutral, english], layoutPolicy: .linebreak)
        #expect(withNeutral.asAttributedString.map { String($0.characters) } == "One.\n\n42\n\nOne.")
        #expect(withNeutral.direction == nil)
        let rtlAfterNeutral = MarkdownNodeView([neutral, arabic], layoutPolicy: .linebreak)
        #expect(rtlAfterNeutral.contentType == .text)
        #expect(rtlAfterNeutral.direction == nil)
        let neutralRun = try #require(rtlAfterNeutral.asAttributedString?.runs.first)
        #expect(neutralRun.alignment == nil)

        // Mixed directions stay one text (the blank line between them unchanged), each paragraph
        // carrying its own direction and alignment.
        let mixed = MarkdownNodeView([english, arabic], layoutPolicy: .linebreak)
        let text = try #require(mixed.asAttributedString)
        #expect(String(text.characters) == "One.\n\nمرحبا")
        #expect(mixed.direction == nil)
        let arabicRun = try #require(text.runs.first { String(text[$0.range].characters).contains("مرحبا") })
        #expect(arabicRun.writingDirection == .rightToLeft)
        #expect(arabicRun.alignment == .right)
        let englishRun = try #require(text.runs.first { String(text[$0.range].characters).contains("One.") })
        #expect(englishRun.alignment == .left)

        // Agreeing blocks get no paragraph attributes: they lay out exactly as before.
        #expect(same.asAttributedString?.runs.allSatisfy { $0.alignment == nil } == true)
        #expect(MarkdownNodeView([neutral, neutral], layoutPolicy: .linebreak).direction == nil)

        // Inline pieces of one paragraph keep merging whatever they hold.
        let inline = MarkdownNodeView([MarkdownNodeView("abc "), MarkdownNodeView("مرحبا")])
        #expect(inline.contentType == .text)
    }

    // The scan counter is a DEBUG-only seam, so a Release test build compiles without this test.
    #if DEBUG
    @Test("A table's cells take its resolved direction instead of rescanning it", .tags(.rendering))
    func tableDirectionOncePerTable() throws {
        let rows = (1...40).map { "| \($0) | \($0 * 7) | \($0 * 13) |" }.joined(separator: "\n")
        let markdown = "| a1 | b2 | c3 |\n|:---|---:|:---:|\n" + rows + "\n| | | مرحبا |"
        let table = try #require(document(markdown).child(at: 0) as? Markdown.Table)
        var renderer = MarkdownViewRenderer(configuration: MarkdownRendererConfiguration(), mathContext: nil, elementRenderers: [])
        let before = MarkdownViewRenderer.tableDirectionScans
        _ = renderer.visit(table)
        #expect(MarkdownViewRenderer.tableDirectionScans == before)
        // A cell visited alone still finds its table's direction.
        let cell = try #require(table.head.child(at: 0))
        var lone = MarkdownViewRenderer(configuration: MarkdownRendererConfiguration(), mathContext: nil, elementRenderers: [])
        _ = lone.visit(cell)
        #expect(MarkdownViewRenderer.tableDirectionScans == before + 1)
    }
    #endif

    @Test("Isolate depth carries across inline markup within a block, and resets per block", .tags(.rendering), arguments: [
        ("\u{2067}**مرحبا**\u{2069} hello", LayoutDirection.leftToRight),
        ("\u{2067}*مرحبا* [رابط](https://x.org)\u{2069} hello", .leftToRight),
        ("**مرحبا** hello", .rightToLeft),
        ("\u{2067}**abc**\u{2069} مرحبا", .rightToLeft),
    ])
    func depthAcrossInline(markdown: String, expected: LayoutDirection) throws {
        let block = try #require(document(markdown).child(at: 0))
        #expect(MarkdownContentDirection.of(block, skipsMath: false) == expected)
    }

    @Test("An isolate left open in a table cell or before a hard line break ends there", .tags(.rendering))
    func depthResetsPerCellAndHardBreak() throws {
        let table = try #require(document("| \u{2067}abc | مرحبا |\n|---|---|\n| 1 | 2 |").child(at: 0))
        #expect(MarkdownContentDirection.of(table, skipsMath: false) == .rightToLeft)
        let paragraph = try #require(document("\u{2067}**abc**\\\nمرحبا").child(at: 0))
        #expect(MarkdownContentDirection.of(paragraph, skipsMath: false) == .rightToLeft)
        // A soft break is a space on screen: the isolate carries across it.
        let soft = try #require(document("\u{2067}**abc**\nمرحبا").child(at: 0))
        #expect(MarkdownContentDirection.of(soft, skipsMath: false) == nil)
        #expect(MarkdownContentDirection.firstStrong(in: "\u{2067}abc\u{2029}مرحبا") == .rightToLeft)
    }

    @Test("A paragraph separator inside skipped inline code or after a bare URL ends an isolate", .tags(.rendering))
    func separatorInSkippedText() throws {
        let code = try #require(document("\u{2067}abc `x\u{2029}y` שלום").child(at: 0))
        #expect(MarkdownContentDirection.of(code, skipsMath: false) == .rightToLeft)
        let url = try #require(document("\u{2067}abc https://x.org/a\u{001C}שלום").child(at: 0))
        #expect(MarkdownContentDirection.of(url, skipsMath: false) == .rightToLeft)
        let twoURLs = try #require(document("https://a.example\u{001C}https://b.example שלום").child(at: 0))
        #expect(MarkdownContentDirection.of(twoURLs, skipsMath: false) == .rightToLeft)
        let comment = try #require(document("\u{2067}abc <!--a\nb--> שלום\u{2069} English").child(at: 0))
        #expect(MarkdownContentDirection.of(comment, skipsMath: false) == .leftToRight)
        for tag in ["<br/>", "<BR>", "<br id=\"x\">", "<br class='a' />", "<br title=\"a>b\">", "<br data-x='>'/>"] {
            let lineBreakTag = try #require(document("\u{2067}abc " + tag + " שלום").child(at: 0))
            #expect(MarkdownContentDirection.of(lineBreakTag, skipsMath: false) == .rightToLeft, "\(tag)")
        }
        // Not a line break: a tag that only starts with br.
        let brand = try #require(document("\u{2067}abc <brand> שלום\u{2069} English").child(at: 0))
        #expect(MarkdownContentDirection.of(brand, skipsMath: false) == .leftToRight)
        let found = MarkdownBidiIsolation.urlRanges(in: "https://x.org/a\u{2029}b")
        #expect(found.map { "https://x.org/a\u{2029}b"[$0] } == ["https://x.org/a"])
        // Renderer level: the paragraph node takes the right-to-left direction.
        var renderer = MarkdownViewRenderer(configuration: MarkdownRendererConfiguration(), mathContext: nil, elementRenderers: [])
        #expect(renderer.visit(code).direction == .rightToLeft)
        #expect(renderer.visit(url).direction == .rightToLeft)
    }

    @Test("An isolate left open in one block does not reach the next", .tags(.rendering))
    func depthResetsPerBlock() throws {
        let quote = try #require(document("> \u{2067}abc\n>\n> مرحبا").child(at: 0))
        #expect(MarkdownContentDirection.of(quote, skipsMath: false) == .rightToLeft)
    }

    @Test("Character offsets of unordered, overlapping ranges in one walk", .tags(.rendering))
    func characterOffsetsCursor() {
        let string = "ab👍🏽cd https://x.org 2026-11-17"
        let ranges = [string.range(of: "2026-11-17")!, string.range(of: "cd")!, string.range(of: "b👍🏽c")!]
        let offsets = MarkdownBidiIsolation.characterOffsets(of: ranges, in: string)
        let expected = ranges.map { string.distance(from: string.startIndex, to: $0.lowerBound)..<string.distance(from: string.startIndex, to: $0.upperBound) }
        #expect(offsets == expected)
    }

    // MARK: Isolates

    @Test("Inline code, URLs and grouped numbers are isolated in right-to-left text", .tags(.rendering))
    func isolates() throws {
        let markdown = "استخدم `--update-refs` أو https://git-scm.com/docs/git-rebase واتصل على +966 50 123 4567."
        let paragraph = try #require(document(markdown).child(at: 0))
        var renderer = MarkdownViewRenderer(configuration: MarkdownRendererConfiguration(), mathContext: nil, elementRenderers: [])
        let attributed = try #require(renderer.visit(paragraph).asAttributedString)
        let shown = String(MarkdownBidiIsolation.isolated(attributed, layoutDirection: .leftToRight).characters)
        #expect(shown.contains("\u{2066}--update-refs\u{2069}"))
        #expect(shown.contains("\u{2066}https://git-scm.com/docs/git-rebase\u{2069}"))
        #expect(shown.contains("\u{2066}+966\u{00A0}50\u{00A0}123\u{00A0}4567\u{2069}."))
        // The isolates are display-only: the rendered node itself holds none.
        #expect(!String(attributed.characters).contains("\u{2066}"))
    }

    @Test("Several isolates in one text, and overlapping runs joined", .tags(.rendering))
    func severalIsolates() {
        var code = AttributedString("50")
        code[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        var first = AttributedString("a")
        first[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        let text = AttributedString("قيمة ") + first + AttributedString(" و +966 ") + code + AttributedString(" 123 4567 ثم")
        let shown = String(MarkdownBidiIsolation.isolated(text, layoutDirection: .rightToLeft).characters)
        #expect(shown == "قيمة \u{2066}a\u{2069} و \u{2066}+966\u{00A0}50\u{00A0}123\u{00A0}4567\u{2069} ثم")
    }

    @Test("Sentence punctuation stays outside a URL; two dates are two runs", .tags(.rendering))
    func urlAndDateEdges() {
        let url = String(MarkdownBidiIsolation.isolated(AttributedString("راجع https://example.com؟"), layoutDirection: .rightToLeft).characters)
        #expect(url == "راجع \u{2066}https://example.com\u{2069}؟")
        let dates = String(MarkdownBidiIsolation.isolated(AttributedString("من 2024-05-01 2025-06-01"), layoutDirection: .rightToLeft).characters)
        #expect(dates == "من \u{2066}2024-05-01\u{2069} \u{2066}2025-06-01\u{2069}")
        let phone = String(MarkdownBidiIsolation.isolated(AttributedString("اتصل +1 212-555-0123"), layoutDirection: .rightToLeft).characters)
        #expect(phone == "اتصل \u{2066}+1\u{00A0}212-555-0123\u{2069}")
        let comma = String(MarkdownBidiIsolation.isolated(AttributedString("راجع https://example.com،ثم"), layoutDirection: .rightToLeft).characters)
        #expect(comma == "راجع \u{2066}https://example.com\u{2069}،ثم")
    }


    // MARK: Numbers kept whole (gemma4-qat#1986)

    @Test("A number with Latin words after it is isolated; one after a Latin word is not", .tags(.rendering))
    func measures() {
        func shown(_ text: String) -> String {
            String(MarkdownBidiIsolation.isolated(AttributedString(text), layoutDirection: .rightToLeft).characters)
        }
        #expect(shown("خلال أقل من 1 ms.") == "خلال أقل من \u{2066}1\u{00A0}ms\u{2069}.")
        #expect(shown("ذاكرة 2 GB RAM فقط") == "ذاكرة \u{2066}2\u{00A0}GB RAM\u{2069} فقط")
        #expect(shown("السرعة 40 km/h و 12.5 GB") == "السرعة \u{2066}40\u{00A0}km/h\u{2069} و \u{2066}12.5\u{00A0}GB\u{2069}")
        // A whole number: a time or a fraction is not cut at its `:` or `/`.
        #expect(shown("الموعد 12:30 UTC") == "الموعد \u{2066}12:30\u{00A0}UTC\u{2069}")
        #expect(shown("أضف 1/2 cup") == "أضف \u{2066}1/2\u{00A0}cup\u{2069}")
        // Only the number and its first word are kept together; the clause still wraps.
        #expect(shown("נמצאו 3 files in the current directory") == "נמצאו \u{2066}3\u{00A0}files in the current directory\u{2069}")
        // After a Latin word the number already reads with it (rule W7): no isolate to split them.
        #expect(shown("القيمة value 10 GB هنا") == "القيمة value 10 GB هنا")
        // A Latin letter inside an isolate is invisible to W7, so it does not count as one.
        #expect(shown("خلال 1 ms، 2 GB") == "خلال \u{2066}1\u{00A0}ms\u{2069}، \u{2066}2\u{00A0}GB\u{2069}")
        #expect(shown("راجع https://example.com/v 2 ok") == "راجع \u{2066}https://example.com/v\u{2069} \u{2066}2\u{00A0}ok\u{2069}")
        // A URL ends at a paragraph separator, and the next paragraph's measure is its own.
        let separated = shown("راجع https://x.org\u{2029}خلال 1 ms")
        #expect(separated == "راجع \u{2066}https://x.org\u{2069}\u{2029}خلال \u{2066}1\u{00A0}ms\u{2069}")
        // No space, no swap: `5GB` is one run already.
        #expect(shown("حجم 5GB فقط") == "حجم 5GB فقط")
        // A sign, a range, a label's colon, an accented unit, a grouped number's unit.
        #expect(shown("التأخير -5 ms") == "التأخير \u{2066}-5\u{00A0}ms\u{2069}")
        #expect(shown("بين 5-10 ms") == "بين \u{2066}5-10\u{00A0}ms\u{2069}")
        #expect(shown("المدة:12 ms") == "المدة:\u{2066}12\u{00A0}ms\u{2069}")
        #expect(shown("المسافة 2 mètres") == "المسافة \u{2066}2\u{00A0}mètres\u{2069}")
        #expect(shown("גודל 1 234 567 MB") == "גודל \u{2066}1\u{00A0}234\u{00A0}567\u{00A0}MB\u{2069}")
        // One phrase, one isolate: the two measures keep their English order.
        #expect(shown("من 2 GB to 4 GB") == "من \u{2066}2\u{00A0}GB to 4\u{00A0}GB\u{2069}")
        #expect(shown("من -5 ms to +5 ms") == "من \u{2066}-5\u{00A0}ms to +5\u{00A0}ms\u{2069}")
        // A capitalised word after the number is a name or a clause, not a unit.
        #expect(shown("في عام 2024 Apple أعلنت") == "في عام 2024 Apple أعلنت")
        // Mixed-case and short units are units.
        for unit in ["GiB", "Hz", "MHz", "kWh", "dB", "Mbps", "Pa"] {
            #expect(shown("السعة 2 \(unit) فقط") == "السعة \u{2066}2\u{00A0}\(unit)\u{2069} فقط", "\(unit)")
        }
        // Two groups are two numbers: the floor stays out of the files' isolate.
        #expect(shown("في الطابق 3 100 files") == "في الطابق 3 \u{2066}100\u{00A0}files\u{2069}")
        // Text that writes its own isolates is left as written inside them, and W7 resumes after.
        #expect(shown("abc \u{2068}2 GB שלום\u{2069}") == "abc \u{2068}2 GB שלום\u{2069}")
        #expect(shown("שלום \u{2066}abc\u{2069} 2 GB") == "שלום \u{2066}abc\u{2069} \u{2066}2\u{00A0}GB\u{2069}")
        // An isolate written in the text hides its letters from W7 too.
        #expect(shown("שלום \u{2066}abc\u{2069} 2 GB") == "שלום \u{2066}abc\u{2069} \u{2066}2\u{00A0}GB\u{2069}")
    }

    @Test("A grouped number or date after a Latin word stays in its phrase", .tags(.rendering))
    func numberAfterLatinWord() {
        func shown(_ text: String) -> String {
            String(MarkdownBidiIsolation.isolated(AttributedString(text), layoutDirection: .rightToLeft).characters)
        }
        // Rule W7 gives the digits the word's direction, so `value 1 234 567` is one run; an
        // isolate would set the number apart. It keeps its no-break spaces.
        #expect(shown("قيمة value 1 234 567 الآن") == "قيمة value 1\u{00A0}234\u{00A0}567 الآن")
        #expect(shown("تاريخ release 2026-11-17 هنا") == "تاريخ release 2026-11-17 هنا")
        #expect(shown("اتصل call +966 50 123 4567") == "اتصل call +966\u{00A0}50\u{00A0}123\u{00A0}4567")
        // After a right-to-left word, or a Latin one inside an isolate, it is isolated as before.
        #expect(shown("قيمة 1 234 567 الآن") == "قيمة \u{2066}1\u{00A0}234\u{00A0}567\u{2069} الآن")
        #expect(shown("راجع https://x.org 1 234 567") == "راجع \u{2066}https://x.org\u{2069} \u{2066}1\u{00A0}234\u{00A0}567\u{2069}")
        #expect(shown("שלום \u{2066}abc\u{2069} 2026-11-17") == "שלום \u{2066}abc\u{2069} \u{2066}2026-11-17\u{2069}")
        // A newline ends the Latin word's reach.
        #expect(shown("value\nقيمة 1 234 567") == "value\nقيمة \u{2066}1\u{00A0}234\u{00A0}567\u{2069}")
        // A measure that takes the number still isolates the whole phrase (`1 ms 1 234 567`).
        #expect(shown("خلال 1 ms 1 234 567") == "خلال \u{2066}1\u{00A0}ms 1\u{00A0}234\u{00A0}567\u{2069}")
        // A measure's letters are inside its isolate, so the date after it follows Arabic.
        #expect(shown("خلال 1 ms، 2026-11-17") == "خلال \u{2066}1\u{00A0}ms\u{2069}، \u{2066}2026-11-17\u{2069}")
        // Inline code inside the number is isolated; the rest of the number keeps its no-break spaces.
        var code = AttributedString("234")
        code[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        let split = AttributedString("قيمة value 1 ") + code + AttributedString(" 567 الآن")
        #expect(String(MarkdownBidiIsolation.isolated(split, layoutDirection: .rightToLeft).characters)
            == "قيمة value 1\u{00A0}\u{2066}234\u{2069}\u{00A0}567 الآن")
    }

    @Test("Inside an isolate the text writes, URLs and inline code get none", .tags(.rendering))
    func writtenIsolatesKeepTheirRuns() {
        func shown(_ text: AttributedString) -> String {
            String(MarkdownBidiIsolation.isolated(text, layoutDirection: .rightToLeft).characters)
        }
        // The FSI resolves from its first strong letter, the URL's `h`: left to right, as written.
        let fsi = "abc \u{2068}https://example.com שלום\u{2069}"
        #expect(shown(AttributedString(fsi)) == fsi)
        for opener in ["\u{2066}", "\u{2067}"] {
            let text = "שלום \(opener)https://x.org abc\u{2069}"
            #expect(shown(AttributedString(text)) == text)
        }
        var code = AttributedString("ls -la")
        code[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        #expect(shown(AttributedString("abc \u{2068}") + code + AttributedString(" שלום\u{2069}")) == "abc \u{2068}ls -la שלום\u{2069}")
        // A line separator (U+2028) is no paragraph separator: the FSI stays open across it.
        let lineSeparated = "abc \u{2068}\u{2028}https://x.org שלום\u{2069}"
        #expect(shown(AttributedString(lineSeparated)) == lineSeparated)
        // Nested: still inside the outer one after the inner PDI.
        let nested = "abc \u{2068}\u{2067}x\u{2069} https://x.org שלום\u{2069}"
        #expect(shown(AttributedString(nested)) == nested)
        // Once the written isolate closes, or at a newline, a URL and code are isolated again.
        #expect(shown(AttributedString("abc \u{2068}x\u{2069} https://example.com שלום"))
            == "abc \u{2068}x\u{2069} \u{2066}https://example.com\u{2069} שלום")
        #expect(shown(AttributedString("abc \u{2068}x\nשלום https://example.com"))
            == "abc \u{2068}x\nשלום \u{2066}https://example.com\u{2069}")
        #expect(shown(AttributedString("abc \u{2068}x\u{2069} ") + code + AttributedString(" שלום"))
            == "abc \u{2068}x\u{2069} \u{2066}ls -la\u{2069} שלום")
    }

    @Test("Inline code keeps its own spaces", .tags(.rendering))
    func codeKeepsSpaces() {
        var code = AttributedString("x = 1 in items")
        code[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        var phone = AttributedString("+966 50 123 4567")
        phone[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        let text = AttributedString("שלום ") + code + AttributedString(" ו ") + phone
        let shown = String(MarkdownBidiIsolation.isolated(text, layoutDirection: .rightToLeft).characters)
        #expect(shown == "שלום \u{2066}x = 1 in items\u{2069} ו \u{2066}+966 50 123 4567\u{2069}")
        // A phone number that crosses a code span keeps the code's space and joins the rest.
        var middle = AttributedString("50 123")
        middle[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        let crossing = AttributedString("שלום +966 ") + middle + AttributedString(" 4567")
        let crossed = String(MarkdownBidiIsolation.isolated(crossing, layoutDirection: .rightToLeft).characters)
        #expect(crossed == "שלום \u{2066}+966\u{00A0}50 123\u{00A0}4567\u{2069}")
        // A measure in code does not hide the one after it.
        var unit = AttributedString("1 ms")
        unit[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        let after = String(MarkdownBidiIsolation.isolated(AttributedString("המדה ") + unit + AttributedString(" 2 GB"), layoutDirection: .rightToLeft).characters)
        #expect(after == "המדה \u{2066}1 ms\u{2069} \u{2066}2\u{00A0}GB\u{2069}")
        // A date inside code stays the code's.
        var version = AttributedString("v2/2024-05-01")
        version[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        let dated = String(MarkdownBidiIsolation.isolated(AttributedString("גרסה ") + version + AttributedString(" results"), layoutDirection: .rightToLeft).characters)
        #expect(dated == "גרסה \u{2066}v2/2024-05-01\u{2069} results")
        var released = AttributedString("on 2024-05-01")
        released[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        let ended = String(MarkdownBidiIsolation.isolated(AttributedString("גרסה ") + released + AttributedString(" results"), layoutDirection: .rightToLeft).characters)
        #expect(ended == "גרסה \u{2066}on 2024-05-01\u{2069} results")
    }

    @Test("Left-to-right text is unchanged, measures and phone numbers included", .tags(.rendering))
    func leftToRightUnchangedWithMeasures() {
        let english = AttributedString("Call +1 212 555 0123 within 1 ms, or 2 GB RAM on 2026-11-17.")
        #expect(MarkdownBidiIsolation.isolated(english, layoutDirection: .leftToRight) == english)
        // An English paragraph beside a Hebrew one keeps its spaces too.
        let mixed = AttributedString("Call +1 212 555 0123 in 1 ms.\nשלום")
        let shown = String(MarkdownBidiIsolation.isolated(mixed, layoutDirection: .leftToRight).characters)
        #expect(shown == "Call +1 212 555 0123 in 1 ms.\nשלום")
    }

    @Test("The rendered node keeps the markdown's characters: no isolate and no no-break space", .tags(.rendering))
    func renderedNodeUnchanged() throws {
        let markdown = "السعر 12.50 دولار، والهاتف +966 50 123 4567، خلال أقل من 1 ms."
        let paragraph = try #require(document(markdown).child(at: 0))
        var renderer = MarkdownViewRenderer(configuration: MarkdownRendererConfiguration(), mathContext: nil, elementRenderers: [])
        let attributed = try #require(renderer.visit(paragraph).asAttributedString)
        #expect(String(attributed.characters) == markdown)
        let shown = String(MarkdownBidiIsolation.isolated(attributed, layoutDirection: .rightToLeft).characters)
        #expect(shown.contains("\u{2066}+966\u{00A0}50\u{00A0}123\u{00A0}4567\u{2069}،"))
        #expect(shown.hasSuffix("\u{2066}1\u{00A0}ms\u{2069}."))
        // Dropping the display characters gives the markdown back.
        let stripped = String(shown.filter { $0 != MarkdownBidiIsolation.isolateStart && $0 != MarkdownBidiIsolation.isolateEnd })
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        #expect(stripped == markdown)
    }

    #if canImport(AppKit)
    @Test("Laid out right to left, the phone number never breaks and both cases read in order", .tags(.rendering))
    func laidOutInOrder() throws {
        let sentence = "السعر 12.50 دولار، والهاتف +966 50 123 4567، والتاريخ 2026-11-17. خلال أقل من 1 ms."
        let shown = String(MarkdownBidiIsolation.isolated(AttributedString(sentence), layoutDirection: .rightToLeft).characters)
        var brokeInsideWithoutTheFix = false
        // From a column the number (about 135 pt with its comma) fits in; a narrower one must break it.
        for width in stride(from: 180.0, through: 420.0, by: 4.0) {
            let lines = Self.layout(shown, width: width)
            let phone = try #require(Self.utf16Range(of: "+966\u{00A0}50\u{00A0}123\u{00A0}4567", in: shown))
            let holding = lines.filter { NSIntersectionRange($0.range, phone).length > 0 }
            #expect(holding.count == 1, "width \(width): the number is on one line")
            // In that line its characters run left to right.
            if let line = holding.first {
                let xs = (phone.location..<NSMaxRange(phone)).map { CTLineGetOffsetForStringIndex(line.line, $0, nil) }
                #expect(xs == xs.sorted(), "width \(width): +966 50 123 4567 in order")
            }
            let unit = try #require(Self.utf16Range(of: "1\u{00A0}ms", in: shown))
            do {
                let line = try #require(lines.first { NSIntersectionRange($0.range, unit) == unit }, "width \(width): 1 ms on one line")
                let one = CTLineGetOffsetForStringIndex(line.line, unit.location, nil)
                let m = CTLineGetOffsetForStringIndex(line.line, unit.location + 2, nil)
                #expect(one < m, "width \(width): 1 ms, not ms 1")
            }
            // The control: the same isolates with plain spaces do break inside the number somewhere.
            let plain = shown.replacingOccurrences(of: "\u{00A0}", with: " ")
            let plainPhone = try #require(Self.utf16Range(of: "+966 50 123 4567", in: plain))
            if Self.layout(plain, width: width).filter({ NSIntersectionRange($0.range, plainPhone).length > 0 }).count > 1 {
                brokeInsideWithoutTheFix = true
            }
        }
        #expect(brokeInsideWithoutTheFix, "the widths swept include one that broke the number before the fix")
        // The control for the unit: unisolated, `1 ms` lays out as `ms 1`.
        let raw = try #require(Self.utf16Range(of: "1 ms", in: sentence))
        let rawLine = try #require(Self.layout(sentence, width: 420).first { NSIntersectionRange($0.range, raw) == raw })
        #expect(CTLineGetOffsetForStringIndex(rawLine.line, raw.location, nil) > CTLineGetOffsetForStringIndex(rawLine.line, raw.location + 2, nil))
    }

    private static func utf16Range(of needle: String, in string: String) -> NSRange? {
        let range = (string as NSString).range(of: needle)
        return range.location == NSNotFound ? nil : range
    }

    /// `string` laid out by Core Text in a right-to-left paragraph `width` points wide.
    private static func layout(_ string: String, width: CGFloat) -> [(line: CTLine, range: NSRange)] {
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection = .rightToLeft
        style.alignment = .natural
        let attributed = NSAttributedString(
            string: string, attributes: [.font: NSFont.systemFont(ofSize: 17), .paragraphStyle: style])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        return lines.map { line in
            let range = CTLineGetStringRange(line)
            return (line, NSRange(location: range.location, length: range.length))
        }
    }
    #endif

    #if ENABLE_MATH_RENDERING
    @Test("A \\(...\\) formula is skipped too", .tags(.rendering))
    func parenthesizedMath() throws {
        let block = try #require(document("\\(E = mc^2\\) היא הנוסחה.", math: true).child(at: 0))
        #expect(MarkdownContentDirection.of(block, skipsMath: true) == .rightToLeft)
    }
    #endif

    @Test("Arabic-Indic digit groups are left alone (an isolate would not fix their order)", .tags(.rendering))
    func arabicIndicNumber() {
        let text = AttributedString("الهاتف +٩٦٦ ٥٠ ١٢٣ ٤٥٦٧ الآن")
        #expect(MarkdownBidiIsolation.isolated(text, layoutDirection: .rightToLeft) == text)
    }

    @Test("A phone number beside a date, a URL with parentheses, a URL before a PDI", .tags(.rendering))
    func runBoundaries() {
        let both = String(MarkdownBidiIsolation.isolated(AttributedString("اتصل +1 212-555-0123 2026-11-17"), layoutDirection: .rightToLeft).characters)
        #expect(both == "اتصل \u{2066}+1\u{00A0}212-555-0123\u{2069} \u{2066}2026-11-17\u{2069}")
        let parens = String(MarkdownBidiIsolation.isolated(AttributedString("راجع https://en.wikipedia.org/wiki/Swift_(language)"), layoutDirection: .rightToLeft).characters)
        #expect(parens == "راجع \u{2066}https://en.wikipedia.org/wiki/Swift_(language)\u{2069}")
        #expect(MarkdownContentDirection.firstStrong(inText: "\u{2066}https://x.org\u{2069} שלום", skipsMath: false) == .rightToLeft)
    }

    @Test("Symbols in right-to-left blocks are neutral, AL ones aside", .tags(.rendering))
    func rightToLeftBlockSymbols() {
        #expect(MarkdownContentDirection.firstStrong(in: "\u{0606} 8 equals two") == .leftToRight)
        #expect(MarkdownContentDirection.firstStrong(in: "\u{FDFD} Chapter") == .leftToRight)
        #expect(MarkdownContentDirection.firstStrong(in: "\u{FB29} plus") == .leftToRight)
        #expect(MarkdownContentDirection.firstStrong(in: "\u{060B} 50") == .rightToLeft)
    }

    @Test("Isolation is decided per paragraph", .tags(.rendering))
    func perParagraphIsolation() {
        var code = AttributedString("git status")
        code[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        var hebrewCode = AttributedString("-1")
        hebrewCode[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        // An English paragraph with no Hebrew in it: untouched. One with Hebrew words around code:
        // isolated, even though it reads left to right.
        let text = AttributedString("Run ") + code + AttributedString(".\n\nAuthor שלום ") + hebrewCode + AttributedString(" עולם")
        let shown = String(MarkdownBidiIsolation.isolated(text, layoutDirection: .leftToRight).characters)
        #expect(shown == "Run git status.\n\nAuthor שלום \u{2066}-1\u{2069} עולם")
    }

    @Test("A paragraph written left to right in a mixed text gets no isolates", .tags(.rendering))
    func leftToRightParagraphUnisolated() throws {
        var code = AttributedString("status")
        code[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        let english = MarkdownNodeView(AttributedString("Run git ") + code + AttributedString(".")).withDirection(.leftToRight)
        let hebrew = MarkdownNodeView("שלום").withDirection(.rightToLeft)
        let merged = try #require(MarkdownNodeView([english, hebrew], layoutPolicy: .linebreak).asAttributedString)
        let shown = String(MarkdownBidiIsolation.isolated(merged, layoutDirection: .leftToRight).characters)
        #expect(shown == "Run git status.\n\nשלום")
    }

    @Test("Explicit left and right columns stay physical in a right-to-left table", .tags(.rendering))
    func physicalColumnAlignment() throws {
        let table = try #require(document("| الاسم | العدد | ملاحظة |\n|:---|---:|---|\n| a | 1 | x |").child(at: 0) as? Markdown.Table)
        let cells = Array(table.head.cells)
        #expect(cells[0].horizontalAlignment(tableDirection: .rightToLeft) == .trailing)
        #expect(cells[1].horizontalAlignment(tableDirection: .rightToLeft) == .leading)
        #expect(cells[2].horizontalAlignment(tableDirection: .rightToLeft) == .leading)
        #expect(cells[0].horizontalAlignment(tableDirection: .leftToRight) == .leading)
        #expect(cells[1].horizontalAlignment(tableDirection: nil) == .trailing)
    }

    @Test("Spans merge sorted, overlapping ones joined", .tags(.rendering))
    func mergeSpans() {
        #expect(MarkdownBidiIsolation.merge([5..<9, 0..<2, 7..<12, 3..<3]) == [0..<2, 5..<12])
    }

    @Test("Left-to-right text is left alone", .tags(.rendering))
    func leftToRightUnchanged() {
        let text = AttributedString("Run `ls` or call +1 555 123 4567, see https://example.com.")
        #expect(MarkdownBidiIsolation.isolated(text, layoutDirection: .leftToRight) == text)
    }

    @Test("A range and a short number stay unisolated", .tags(.rendering))
    func notNumbers() {
        let text = AttributedString("من 10 - 20 صفحة، و 3.14 و 2026")
        let shown = String(MarkdownBidiIsolation.isolated(text, layoutDirection: .rightToLeft).characters)
        #expect(!shown.contains("\u{2066}"))
    }

    @Test("An isolate keeps the run's highlight", .tags(.rendering))
    func isolateKeepsAttributes() throws {
        var code = AttributedString("x = 1")
        code.backgroundColor = .red
        code[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        let text = AttributedString("قيمة ") + code
        let shown = MarkdownBidiIsolation.isolated(text, layoutDirection: .rightToLeft)
        let first = try #require(shown.characters.firstIndex(of: "\u{2066}"))
        let isolate = shown[first..<shown.characters.index(after: first)]
        #expect(isolate.runs.first?.backgroundColor == .red)
        #expect(String(shown.characters).hasSuffix("\u{2066}x = 1\u{2069}"))
    }

    // MARK: Helpers

    func document(_ markdown: String, math: Bool = false) -> Markdown.Document {
        MarkdownDocumentParser.parse(
            MarkdownParseRequest(
                sourceText: markdown,
                mathContext: math ? MarkdownMathContext() : nil,
                elementRenderers: []
            )
        ).document
    }
}
