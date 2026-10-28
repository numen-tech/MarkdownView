import Markdown
import SwiftUI
import Testing

@testable import MarkdownView

/// numen fork: `markdownHighlightedSpan(_:)` puts a background on exactly the text runs a UTF-8
/// source span covers.
@MainActor
@Suite("Markdown Highlighted Span")
struct MarkdownHighlightedSpanTests {
    static let color = Color.red

    @Test("A span across **bold** highlights the runs inside it", .tags(.rendering))
    func boldSpan() throws {
        let markdown = "Plain **bold** text. Next sentence."
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "**bold** text.", in: markdown))
        // Adjacent highlighted runs are joined (`highlightedRuns`); the style split is checked below.
        #expect(runs == ["bold text."])
    }

    @Test("The highlighted runs keep their inline styles", .tags(.rendering))
    func keepsInlineIntent() throws {
        let markdown = "Plain **bold** text."
        let paragraph = try #require(document(markdown).child(at: 0))
        let attributed = try #require(
            renderer(markdown, span: Self.bytes(of: "bold** text", in: markdown))
                .visitNode(paragraph).asAttributedString
        )
        let boldRun = try #require(attributed.runs.first { String(attributed[$0.range].characters) == "bold" })
        #expect(boldRun.backgroundColor == Self.color)
        #expect(boldRun.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
    }

    @Test("A span that cuts a word highlights from that character", .tags(.rendering))
    func partialWord() throws {
        let markdown = "Hello world."
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "lo wor", in: markdown))
        #expect(runs == ["lo wor"])
    }

    @Test("Byte offsets count UTF-8, not UTF-16 or characters", .tags(.rendering))
    func multibyteOffsets() throws {
        let markdown = "Café ☕️ and 👩🏽‍💻 are *here*. Then more."
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "👩🏽‍💻 are *here*.", in: markdown))
        #expect(runs == ["👩🏽‍💻 are here."])
    }

    @Test("A bound inside a grapheme widens to the whole character", .tags(.rendering))
    func boundInsideGrapheme() throws {
        let markdown = "A 👩🏽‍💻 b"
        let emoji = Self.bytes(of: "👩🏽‍💻", in: markdown)
        let runs = try highlightedRuns(markdown, span: (emoji.lowerBound + 1)..<(emoji.upperBound - 1))
        #expect(runs == ["👩🏽‍💻"])
    }

    @Test("A span across a soft line break highlights the joining space", .tags(.rendering))
    func softBreak() throws {
        let markdown = "First line\nsecond line."
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "line\nsecond", in: markdown))
        #expect(runs == ["line second"])
    }

    @Test("A span ending at a line end leaves the soft break plain", .tags(.rendering))
    func softBreakAtSentenceEnd() throws {
        let markdown = "First line.\nSecond line."
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "First line.", in: markdown))
        #expect(runs == ["First line."])
    }

    @Test("CRLF line endings map columns on later lines", .tags(.rendering))
    func crlf() throws {
        let markdown = "One.\r\n\r\nTwo **three** four."
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "three** four", in: markdown), block: 1)
        #expect(runs == ["three four"])
    }

    @Test("A block quote's continuation line maps past its marker", .tags(.rendering))
    func blockQuoteContinuation() throws {
        let markdown = "> quoted line one\n> continues **here** now."
        let highlight = try #require(resolved(markdown, span: Self.bytes(of: "continues **here**", in: markdown)))
        #expect(Self.highlightedText(in: document(markdown), highlight: highlight) == "continues here")
    }

    @Test("Links inside emphasis inside the span are highlighted", .tags(.rendering, .links))
    func nestedInlineContainers() throws {
        let markdown = "Before *see [the **docs**](https://example.com) now* after."
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "*see [the **docs**](https://example.com) now*", in: markdown))
        #expect(runs == ["see the docs now"])
    }

    @Test("A span starting inside a link highlights only its tail", .tags(.rendering, .links))
    func spanStartsInsideLink() throws {
        let markdown = "Read [the full guide](https://example.com) today."
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "full guide](https://example.com) today.", in: markdown))
        #expect(runs == ["full guide today."])
    }

    @Test("Backslash escapes fall back to the whole node", .tags(.rendering))
    func escapesFallBack() throws {
        // swift-markdown merges `\*` into one text node whose source is two bytes longer than its
        // text, so columns past the escape no longer line up.
        let markdown = #"Use \*stars\* here. And plain."#
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "here.", in: markdown))
        #expect(runs == ["Use *stars* here. And plain."])
    }

    @Test("A text node before a hard break maps exactly despite its trailing spaces", .tags(.rendering))
    func hardBreak() throws {
        // cmark's range covers "Line one  "; the text "Line one" still sits at its start.
        let markdown = "Line one  \nline two."
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "one", in: markdown))
        #expect(runs == ["one"])
    }

    @Test("Entities fall back to the whole node", .tags(.rendering))
    func entitiesFallBack() throws {
        let markdown = "Fish &amp; chips taste good. Next."
        let runs = try highlightedRuns(markdown, span: Self.bytes(of: "good.", in: markdown))
        #expect(runs == ["Fish & chips taste good. Next."])
    }

    @Test("Inline code the span touches is highlighted whole", .tags(.rendering))
    func inlineCode() throws {
        let markdown = "Run `make test` now. Then rest."
        let whole = try highlightedRuns(markdown, span: Self.bytes(of: "Run `make test` now.", in: markdown))
        #expect(whole == ["Run make test now."])
        let partial = try highlightedRuns(markdown, span: Self.bytes(of: "test", in: markdown))
        #expect(partial == ["make test"])
    }

    @Test("Inline code outside the span keeps its own background", .tags(.rendering))
    func inlineCodeOutsideSpan() throws {
        let markdown = "Run `make` now. Then rest."
        let paragraph = try #require(document(markdown).child(at: 0))
        let attributed = try #require(
            renderer(markdown, span: Self.bytes(of: "Then rest.", in: markdown))
                .visitNode(paragraph).asAttributedString
        )
        let codeRun = try #require(attributed.runs.first { String(attributed[$0.range].characters) == "make" })
        #expect(codeRun.backgroundColor != Self.color)
    }

    @Test(
        "Math earlier on the line shifts nothing",
        .tags(.rendering, .math),
        arguments: [
            "Let $x = 1$ and then **bold** text. Done.",
            "Let \\(x = 1\\) and then **bold** text. Done.",
            "$$\na = b\n$$\n\nThen **bold** text. Done.",
            "Some $y$ first.\n\nLet $x^2 + y^2 = z^2$ and then **bold** text. Done.",
        ]
    )
    func mathColumnMapping(markdown: String) throws {
        let highlight = try #require(
            resolved(markdown, span: Self.bytes(of: "**bold** text.", in: markdown), math: true)
        )
        #expect(Self.highlightedText(in: document(markdown, math: true), highlight: highlight) == "bold text.")
    }

    @Test("A span over inline math highlights the text around it", .tags(.rendering, .math))
    func spanOverMath() throws {
        let markdown = "Area is $\\pi r^2$ for a circle. Next."
        let highlight = try #require(
            resolved(markdown, span: Self.bytes(of: "is $\\pi r^2$ for a circle.", in: markdown), math: true)
        )
        let text = Self.highlightedText(in: document(markdown, math: true), highlight: highlight)
        #expect(text.hasPrefix("is markdownview-math(inline:"))
        #expect(text.hasSuffix(") for a circle."))
    }

    @Test("A bound inside a formula snaps to the formula's edge", .tags(.rendering, .math))
    func boundInsideMath() throws {
        let markdown = "Take $a + b$ then go."
        let processed = try #require(
            resolved(markdown, span: Self.bytes(of: "b$ then", in: markdown), math: true)
        )
        let processedText = processed.processedText
        let placeholderStart = try #require(processedText.range(of: "markdownview-math("))
        let lower = processedText.utf8.distance(from: processedText.startIndex, to: placeholderStart.lowerBound)
        #expect(processed.range.lowerBound == lower)
    }

    @Test("A span over a code block or past the end highlights nothing", .tags(.rendering))
    func spanOutsideText() throws {
        let markdown = "```swift\nlet x = 1\n```\n\nAfter the code."
        #expect(try highlightedRuns(markdown, span: Self.bytes(of: "let x = 1", in: markdown), block: 1) == [])
        #expect(resolved(markdown, span: 500..<900) == nil)
        #expect(resolved(markdown, span: 3..<3) == nil)
        #expect(try highlightedRuns(markdown, span: -20..<5, block: 1) == [])
    }

    @Test("Every paragraph outside the span stays plain", .tags(.rendering))
    func otherParagraphsUntouched() throws {
        let markdown = "First paragraph.\n\nSecond paragraph.\n\n- item one\n- item two"
        let span = Self.bytes(of: "Second paragraph.", in: markdown)
        #expect(try highlightedRuns(markdown, span: span, block: 0) == [])
        #expect(try highlightedRuns(markdown, span: span, block: 1) == ["Second paragraph."])
        let items = try #require(document(markdown).child(at: 2))
        let highlight = try #require(resolved(markdown, span: span))
        #expect(Self.highlightedText(in: items, highlight: highlight) == "")
    }

    @Test("A list item's paragraph highlights through the nested renderer", .tags(.rendering, .lists))
    func listItem() throws {
        let markdown = "Intro.\n\n- first item\n- second **item** here\n"
        let highlight = try #require(resolved(markdown, span: Self.bytes(of: "second **item**", in: markdown)))
        let list = try #require(document(markdown).child(at: 1))
        #expect(Self.highlightedText(in: list, highlight: highlight) == "second item")
    }

    @Test("A span on a parse result's source applies to MarkdownView(parseResult)", .tags(.rendering))
    func resolvesAgainstSourceSnapshot() throws {
        let markdown = "Alpha $x$ beta **gamma**."
        let parseResult = MarkdownDocumentParser.parse(
            MarkdownParseRequest(sourceText: markdown, mathContext: MarkdownMathContext(), elementRenderers: [])
        )
        var configuration = MarkdownRendererConfiguration()
        configuration.highlightedSpan = MarkdownHighlightedSpan(
            range: Self.bytes(of: "gamma", in: markdown), color: Self.color
        )
        let resolvedConfiguration = configuration.resolvingHighlight(against: parseResult)
        #expect(resolvedConfiguration.highlightedSpan == nil)
        let highlight = try #require(resolvedConfiguration.resolvedHighlight)
        #expect(Self.highlightedText(in: parseResult.document, highlight: highlight) == "gamma")
    }

    @Test("A span on part of an escape or entity still takes the whole node", .tags(.rendering))
    func partialEscapeAndEntity() throws {
        let entity = "Fish &amp; chips."
        #expect(try highlightedRuns(entity, span: Self.bytes(of: "amp", in: entity)) == ["Fish & chips."])
        let escape = #"\*stars\* here."#
        #expect(try highlightedRuns(escape, span: 0..<1) == ["*stars* here."])
    }

    @Test("The line after a backslash hard break is highlighted", .tags(.rendering))
    func backslashHardBreak() throws {
        let markdown = "a\\\nb"
        let highlight = try #require(resolved(markdown, span: 3..<4))
        #expect(Self.highlightedText(in: document(markdown), highlight: highlight).contains("b"))
    }

    @Test(
        "A lazy continuation line, whose columns cmark misreports, does not crash",
        .tags(.rendering),
        arguments: ["> first\nsecond line here.", "> first\nsecond line here.\n\nAfter.", "> first\n*a* a"]
    )
    func lazyContinuation(markdown: String) throws {
        // Known limitation: cmark shifts the columns of a lazy continuation line, so its nodes
        // fall back to whole-node highlights at the reported position (README, numen fork).
        let highlight = try #require(resolved(markdown, span: Self.bytes(of: "first", in: markdown)))
        #expect(Self.highlightedText(in: document(markdown), highlight: highlight) == "first")
        for offset in 0..<markdown.utf8.count {
            if let highlight = resolved(markdown, span: offset..<(offset + 1)) {
                _ = Self.highlightedText(in: document(markdown), highlight: highlight)
            }
        }
    }

    @Test("An empty span inside a formula stays empty", .tags(.rendering, .math))
    func emptySpanInsideMath() {
        #expect(resolved("Take $x$ now.", span: 6..<6, math: true) == nil)
    }

    @Test("The parse cache compares bytes, not canonical equivalence", .tags(.parsing))
    func parseCacheIsByteExact() {
        let cache = MarkdownParseCache()
        let composed = "\u{E9} abc"
        let decomposed = "e\u{301} abc"
        #expect(composed == decomposed)
        _ = cache.parse(.rawText(composed), with: [])
        #expect(cache.parse(.rawText(decomposed), with: []).sourceSnapshot.text.utf8.count == 7)
    }

    @Test("A highlight step keeps converted HTML instead of flashing raw tags", .tags(.rendering))
    func htmlKeepsConversionAcrossHighlightSteps() {
        var input = AttributedString("Hello ")
        input += AttributedString("<b>world</b>", attributes: AttributeContainer().isHTML(true))
        var highlighted = input
        highlighted[highlighted.startIndex..<highlighted.index(highlighted.startIndex, offsetByCharacters: 5)]
            .backgroundColor = Self.color
        let rendered = _MarkdownText.RenderedState(input: input, output: AttributedString("Hello world"))
        #expect(_MarkdownText.visibleText(input: highlighted, rendered: rendered) == rendered.output)
        let changed = AttributedString("Bye <b>x</b>")
        #expect(_MarkdownText.visibleText(input: changed, rendered: rendered) == changed)
    }

    @Test("A highlight step reuses the view's parse of unchanged text", .tags(.parsing))
    func parseCache() {
        let cache = MarkdownParseCache()
        let options: MarkdownDocumentParsingOptions = [.rendersMath]
        let first = cache.parse(.rawText("Some $x$ text."), with: options)
        #expect(cache.parse(.rawText("Some $x$ text."), with: options).document.isIdentical(to: first.document))
        #expect(!cache.parse(.rawText("Some $x$ text."), with: []).document.isIdentical(to: first.document))
        #expect(cache.parse(.rawText("Other text."), with: []).sourceSnapshot.text == "Other text.")
    }

    // MARK: - Helpers

    func document(_ markdown: String, math: Bool = false) -> Markdown.Document {
        MarkdownDocumentParser.parse(
            MarkdownParseRequest(
                sourceText: markdown,
                mathContext: math ? MarkdownMathContext() : nil,
                elementRenderers: []
            )
        ).document
    }

    func resolved(_ markdown: String, span: Range<Int>, math: Bool = false) -> MarkdownResolvedHighlight? {
        let parseResult = MarkdownDocumentParser.parse(
            MarkdownParseRequest(
                sourceText: markdown,
                mathContext: math ? MarkdownMathContext() : nil,
                elementRenderers: []
            )
        )
        return MarkdownResolvedHighlight(
            MarkdownHighlightedSpan(range: span, color: Self.color),
            parseResult: parseResult
        )
    }

    func renderer(_ markdown: String, span: Range<Int>) -> MarkdownViewRenderer {
        var configuration = MarkdownRendererConfiguration()
        configuration.resolvedHighlight = resolved(markdown, span: span)
        return MarkdownViewRenderer(configuration: configuration, mathContext: nil, elementRenderers: [])
    }

    /// The highlighted runs of block `block`'s rendered attributed string, adjacent runs joined.
    func highlightedRuns(_ markdown: String, span: Range<Int>, block: Int = 0) throws -> [String] {
        let node = try #require(document(markdown).child(at: block))
        let rendered = renderer(markdown, span: span).visitNode(node)
        guard let attributed = rendered.asAttributedString else { return [] }
        var runs: [String] = []
        var previousHighlighted = false
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            let highlighted = run.backgroundColor == Self.color
            if highlighted, previousHighlighted, let last = runs.popLast() {
                runs.append(last + text)
            } else if highlighted {
                runs.append(text)
            }
            previousHighlighted = highlighted
        }
        // Style boundaries split runs; report the visible highlighted stretches.
        return runs
    }

    static func texts(in markup: any Markup) -> [Markdown.Text] {
        if let text = markup as? Markdown.Text { return [text] }
        return markup.children.flatMap { texts(in: $0) }
    }

    static func highlightedText(in markup: any Markup, highlight: MarkdownResolvedHighlight) -> String {
        texts(in: markup).compactMap { text in
            highlight.highlightedRange(in: text.plainText, nodeRange: text.range).map {
                String(text.plainText[$0])
            }
        }.joined()
    }

    /// The UTF-8 offsets of the first occurrence of `needle` in `markdown`.
    static func bytes(of needle: String, in markdown: String) -> Range<Int> {
        guard let range = markdown.range(of: needle) else {
            Issue.record("\(needle) not in \(markdown)")
            return 0..<0
        }
        let utf8 = markdown.utf8
        return utf8.distance(from: utf8.startIndex, to: range.lowerBound)
            ..< utf8.distance(from: utf8.startIndex, to: range.upperBound)
    }
}

private extension MarkdownViewRenderer {
    func visitNode(_ markup: any Markup) -> MarkdownNodeView {
        var renderer = self
        return renderer.visit(markup)
    }
}
