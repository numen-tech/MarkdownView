//
//  InlineMath.swift
//  MarkdownView
//
//  Created by Yanan Li on 2026/6/17.
//

#if ENABLE_MATH_RENDERING
import SwiftUI

struct InlineMath: View {
    var latexText: String
    @Environment(\.markdownFontGroup.inlineMath) private var font

    init(latexText: String) {
        self.latexText = latexText
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            SwiftMathView(
                latex: latexText,
                font: font,
                labelMode: .text,
                textAlignment: .left
            )
            ScrollView(.horizontal) {
                SwiftMathView(
                    latex: latexText,
                    font: font,
                    labelMode: .text,
                    textAlignment: .left
                )
            }
            // LaTeX reads left to right in any UI: keep the overflow scroll at its start under a
            // right-to-left layout, as the code block does (numen-tech/gemma4-qat#1746).
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

#endif
