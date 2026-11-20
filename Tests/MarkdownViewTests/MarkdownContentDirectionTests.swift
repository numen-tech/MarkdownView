import Markdown
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
        #expect(shown.contains("\u{2066}+966 50 123 4567\u{2069}."))
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
        #expect(shown == "قيمة \u{2066}a\u{2069} و \u{2066}+966 50 123 4567\u{2069} ثم")
    }

    @Test("Sentence punctuation stays outside a URL; two dates are two runs", .tags(.rendering))
    func urlAndDateEdges() {
        let url = String(MarkdownBidiIsolation.isolated(AttributedString("راجع https://example.com؟"), layoutDirection: .rightToLeft).characters)
        #expect(url == "راجع \u{2066}https://example.com\u{2069}؟")
        let dates = String(MarkdownBidiIsolation.isolated(AttributedString("من 2024-05-01 2025-06-01"), layoutDirection: .rightToLeft).characters)
        #expect(dates == "من \u{2066}2024-05-01\u{2069} \u{2066}2025-06-01\u{2069}")
        let phone = String(MarkdownBidiIsolation.isolated(AttributedString("اتصل +1 212-555-0123"), layoutDirection: .rightToLeft).characters)
        #expect(phone == "اتصل \u{2066}+1 212-555-0123\u{2069}")
        let comma = String(MarkdownBidiIsolation.isolated(AttributedString("راجع https://example.com،ثم"), layoutDirection: .rightToLeft).characters)
        #expect(comma == "راجع \u{2066}https://example.com\u{2069}،ثم")
    }

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
        #expect(both == "اتصل \u{2066}+1 212-555-0123\u{2069} \u{2066}2026-11-17\u{2069}")
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
