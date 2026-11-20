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

    @Test("Text blocks merge only while their directions agree", .tags(.rendering))
    func mergeRule() {
        let english = MarkdownNodeView("One.").withDirection(.leftToRight)
        let neutral = MarkdownNodeView("42").withDirection(nil)
        let arabic = MarkdownNodeView("مرحبا").withDirection(.rightToLeft)

        let same = MarkdownNodeView([english, neutral, english], layoutPolicy: .linebreak)
        #expect(same.contentType == .text)
        #expect(same.direction == .leftToRight)
        #expect(same.asAttributedString.map { String($0.characters) } == "One.\n\n42\n\nOne.")

        let rtlFirstNeutral = MarkdownNodeView([neutral, arabic], layoutPolicy: .linebreak)
        #expect(rtlFirstNeutral.contentType == .text)
        #expect(rtlFirstNeutral.direction == .rightToLeft)

        let mixed = MarkdownNodeView([english, arabic], layoutPolicy: .linebreak)
        #expect(mixed.contentType == .view)

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
