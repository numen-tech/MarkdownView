//
//  HighlightedSpanModifier.swift
//  MarkdownView (numen-tech fork)
//

import SwiftUI

/// A span of the markdown source whose rendered text draws a background colour.
///
/// `range` holds UTF-8 byte offsets into the markdown string the ``MarkdownView`` was given
/// (`MarkdownView(_:)`'s `text`, or the source text of the parse result it renders), lower bound
/// inclusive, upper bound exclusive. The view maps it through its own math preprocessing, so the
/// offsets always refer to the string as written.
///
/// Text runs inside the span get `color` as their background. A text node whose source holds
/// backslash escapes or entities, an inline code span and an inline math formula that the span
/// touches are highlighted whole. Block structure (code blocks, display math, images) is never
/// highlighted. A span that covers no text node draws nothing.
public struct MarkdownHighlightedSpan: Hashable, Sendable {
    /// UTF-8 byte offsets into the markdown source.
    public var range: Range<Int>
    /// The background drawn behind the highlighted runs.
    public var color: Color

    public init(range: Range<Int>, color: Color = .yellow.opacity(0.4)) {
        self.range = range
        self.color = color
    }
}

extension View {
    /// Highlights the text runs that render `span` of the markdown source; `nil` clears it.
    ///
    /// Applies to every ``MarkdownView`` in the subtree, each against its own source text.
    nonisolated public func markdownHighlightedSpan(_ span: MarkdownHighlightedSpan?) -> some View {
        transformEnvironment(\.markdownRendererConfiguration) { configuration in
            configuration.highlightedSpan = span
        }
    }
}
