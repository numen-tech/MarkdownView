//
//  MarkdownView.swift
//  MarkdownView
//

import SwiftUI
import Markdown

/// A view that renders markdown content.
public struct MarkdownView: View {
    private var content: MarkdownContent
    
    @Environment(\.markdownRendererConfiguration) private var configuration
    @Environment(\.markdownMathContext) private var mathContext
    @Environment(\.markdownElementRenderers) private var elementRenderers
    @Environment(\.markdownFontGroup) private var fonts
    /// numen fork: a highlight step re-runs `body` with the same text; skip the re-parse.
    @State private var parseCache = MarkdownParseCache()

    /// Creates a view that renders given markdown string.
    /// 
    /// - Parameter text: The markdown source to render.
    public init(_ text: String) {
        self.content = .rawText(text)
    }

    /// Creates a view that renders a parsed markdown result.
    ///
    /// - Parameter parseResult: The parsed markdown result to render.
    public init(_ parseResult: MarkdownParseResult) {
        self.content = .parsedDocument(parseResult)
    }
    
    public var body: some View {
        let parseResult = parseCache.parse(
            content,
            with: MarkdownDocumentParsingOptions(
                mathContext: mathContext,
                elementRenderers: elementRenderers
            )
        )
        
        MarkdownViewRenderer(
            configuration: configuration.resolvingHighlight(against: parseResult),
            mathContext: parseResult.mathContext,
            elementRenderers: elementRenderers
        )
        .makeBody(for: parseResult.document)
        .font(fonts.body._swiftUIFont)
    }
}

/// numen fork: the last raw-text parse of one `MarkdownView`, reused while its text and parsing
/// options stay the same (a highlighted-span step changes only the renderer configuration).
@MainActor
final class MarkdownParseCache {
    private var sourceText: String?
    private var options: MarkdownDocumentParsingOptions = []
    private var result: MarkdownParseResult?

    func parse(
        _ content: MarkdownContent,
        with options: MarkdownDocumentParsingOptions
    ) -> MarkdownParseResult {
        guard case .rawText(let text) = content else { return content.parse(with: options) }
        // Byte equality, not `==`: canonically equivalent strings differ in UTF-8 offsets.
        if let result, let sourceText, sourceText.utf8.elementsEqual(text.utf8),
           self.options == options {
            return result
        }
        let parsed = content.parse(with: options)
        sourceText = text
        self.options = options
        result = parsed
        return parsed
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
#Preview {
    ScrollView {
        MarkdownView(
            """
            # MarkdownView

            A view-based markdown renderer for SwiftUI.

            > Block quotes are useful for callouts and quoted prose.

            ## Features

            - Emphasis with **bold** and *italic* text
            - Links such as [MarkdownView](https://github.com/liyanan2004/MarkdownView)
            - Inline code like `MarkdownText("Hello")`

            ```swift
            MarkdownView("Hello **World**")
            ```
            """
        )
        .padding()
    }
    .markdownLinksUnderlined()
    .scrollBounceBehavior(.basedOnSize)
    #if os(macOS) || os(iOS)
    .textSelection(.enabled)
    #endif
}
