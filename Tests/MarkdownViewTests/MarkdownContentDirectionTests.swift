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
        ("\u{2067}مرحبا\u{2069} hello", .leftToRight),
        ("日本語", .leftToRight),
    ])
    func firstStrong(text: String, expected: LayoutDirection) {
        #expect(MarkdownContentDirection.firstStrong(in: text) == expected)
    }

    @Test("Digits, punctuation and emoji are neutral", .tags(.rendering), arguments: ["", "42", "-- 3.14 --", "🙂 ✅", "٣٤٥"])
    func neutral(text: String) {
        #expect(MarkdownContentDirection.firstStrong(in: text) == nil)
    }

    @Test("A block skips inline code, math and bare links", .tags(.rendering), arguments: [
        ("`git rebase` يعيد كتابة السجل.", LayoutDirection.rightToLeft, false),
        ("$x^2$ هو المربع.", .rightToLeft, true),
        ("\\(E = mc^2\\) היא הנוסחה.", .rightToLeft, true),
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
