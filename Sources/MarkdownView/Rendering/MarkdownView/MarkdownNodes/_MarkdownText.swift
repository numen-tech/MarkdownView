//
//  _MarkdownText.swift
//  MarkdownView
//
//  Created by Yanan Li on 2025/10/20.
//

import SwiftUI

/// A view that displays parsed HTML asynchronously.
///
/// Convert HTML into  `AttributedString` asynchronously to avoid `AttributeGraph` crash.
struct _MarkdownText: View {
    var text: AttributedString
    @State private var attributedString: RenderedState?
    
    init(_ text: AttributedString) {
        self.text = text
    }

    var body: some View {
        Group {
            if let attributedString {
                Text(Self.visibleText(input: text, rendered: attributedString))
            } else {
                Text(text)
            }
        }
        .task(id: text) {
            var attributedString = text
            for run in text.runs.reversed() where (run.isHTML ?? false) {
                let range = run.range

                if let htmlAttrString = try? AttributedString(
                    NSAttributedString(
                        data: Data(String(text.characters[range]).utf8),
                        options: [
                            .documentType: NSAttributedString.DocumentType.html
                        ],
                        documentAttributes: nil
                    )
                ) {
                    attributedString.replaceSubrange(range, with: htmlAttrString)
                }
            }

            // Streaming updates can start a new render before an older render finishes.
            // Avoid committing work SwiftUI already cancelled for a superseded input.
            guard !Task.isCancelled else { return }
            self.attributedString = RenderedState(input: text, output: attributedString)
        }
    }

    static func visibleText(input: AttributedString, rendered: RenderedState) -> AttributedString {
        // `renderedState` is asynchronous cache state. During streaming, an older
        // partial input can finish after the latest input and briefly live in
        // `@State`. Only use the cached output when it was produced from the
        // exact input currently being displayed; otherwise fall back to `input`
        // so the visible text cannot regress while the next render catches up.
        guard rendered.input == input else {
            // numen fork: a highlighted-span step changes only backgrounds; keep the converted
            // HTML (with the old highlight) until the new conversion lands, rather than flash
            // the raw tags.
            if input.runs.contains(where: { $0.isHTML ?? false }),
               withoutBackgrounds(rendered.input) == withoutBackgrounds(input) {
                return rendered.output
            }
            return input
        }
        return rendered.output
    }

    private static func withoutBackgrounds(_ text: AttributedString) -> AttributedString {
        var text = text
        text.backgroundColor = nil
        return text
    }

    struct RenderedState {
        /// The source markdown text that produced `output`.
        var input: AttributedString

        /// The same content after asynchronous HTML runs have been converted.
        var output: AttributedString
    }
}
