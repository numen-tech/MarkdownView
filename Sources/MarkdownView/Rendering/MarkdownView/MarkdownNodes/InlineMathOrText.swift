//
//  InlineMathOrText.swift
//  MarkdownView
//
//  Created by LiYanan2004 on 2025/2/24.
//

import SwiftUI

@preconcurrency
@MainActor
struct InlineMathOrText {
    var text: String
    /// numen fork: the highlight and the part of `text` it covers (both nil when none).
    var highlight: MarkdownResolvedHighlight? = nil
    var highlightedRange: Range<String.Index>? = nil

    private func textNode(_ bounds: Range<String.Index>) -> MarkdownNodeView {
        guard let highlight else { return MarkdownNodeView(String(text[bounds])) }
        return MarkdownNodeView(
            highlight.attributed(text, bounds: bounds, highlightedRange: highlightedRange)
        )
    }

    @preconcurrency
    @MainActor
    func makeBody(mathContext: MarkdownMathContext?) -> MarkdownNodeView {
        #if ENABLE_MATH_RENDERING
        let mathSegments = self.mathSegments(mathContext: mathContext)

        guard !mathSegments.isEmpty else {
            return textNode(text.startIndex..<text.endIndex)
        }

        var nodeViews: [MarkdownNodeView] = []
        var processingIndex = text.startIndex

        for mathSegment in mathSegments {
            if processingIndex < mathSegment.range.lowerBound {
                nodeViews.append(textNode(processingIndex..<mathSegment.range.lowerBound))
            }

            switch mathSegment.kind {
            case .inline:
                if let highlight, let highlightedRange,
                   highlightedRange.overlaps(mathSegment.range) {
                    nodeViews.append(MarkdownNodeView {
                        InlineMath(latexText: mathSegment.latexText)
                            .background(highlight.color)
                    })
                } else {
                    nodeViews.append(MarkdownNodeView {
                        InlineMath(latexText: mathSegment.latexText)
                    })
                }
            case .display:
                if let identifier = mathSegment.identifier {
                    nodeViews.append(MarkdownNodeView {
                        MarkdownDisplayMathView(mathIdentifier: identifier)
                            .id(identifier)
                    })
                }
            }

            processingIndex = mathSegment.range.upperBound
        }

        if processingIndex < text.endIndex {
            nodeViews.append(textNode(processingIndex..<text.endIndex))
        }

        return MarkdownNodeView(nodeViews)
        #else
        return textNode(text.startIndex..<text.endIndex)
        #endif
    }
}

#if ENABLE_MATH_RENDERING
fileprivate extension InlineMathOrText {
    struct MathSegment {
        var kind: MarkdownMathPreprocessor.PlaceholderKind
        var range: Range<String.Index>
        var latexText: String
        var identifier: UUID?
    }

    func mathSegments(mathContext: MarkdownMathContext?) -> [MathSegment] {
        let placeholderSegments = mathPlaceholderSegments(mathContext: mathContext)
        let parsedSegments = MathParser(text: text)
            .mathRepresentations
            .lazy
            .map {
                MathSegment(
                    kind: .inline,
                    range: $0.range,
                    latexText: String(text[$0.range]),
                    identifier: nil
                )
            }
            .filter { parsedSegment in
                !placeholderSegments.contains { placeholderSegment in
                    parsedSegment.range.overlaps(placeholderSegment.range)
                }
            }

        return (placeholderSegments + parsedSegments)
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    func mathPlaceholderSegments(mathContext: MarkdownMathContext?) -> [MathSegment] {
        MarkdownMathPreprocessor.placeholderSegments(in: text).compactMap { placeholderSegment in
            switch placeholderSegment.match.kind {
            case .inline:
                guard let latexText = mathContext?.inlineMathStorage[placeholderSegment.match.identifier] else {
                    return nil
                }

                return MathSegment(
                    kind: .inline,
                    range: placeholderSegment.range,
                    latexText: latexText,
                    identifier: placeholderSegment.match.identifier
                )
            case .display:
                guard let latexText = mathContext?.displayMathStorage[placeholderSegment.match.identifier] else {
                    return nil
                }

                return MathSegment(
                    kind: .display,
                    range: placeholderSegment.range,
                    latexText: latexText,
                    identifier: placeholderSegment.match.identifier
                )
            }
        }
    }
}
#endif
