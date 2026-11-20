//
//  MarkdownTableStyleConfiguration.Row.swift
//  MarkdownView
//
//  Created by LiYanan2004 on 2025/4/21.
//

import SwiftUI

extension MarkdownTableStyleConfiguration {
    /// A type-erased view of a table.
    ///
    /// Access `header` and `rows` properties for further customization.
    @preconcurrency
    @MainActor
    public struct Table {
        var headerCells: [Cell]
        var bodyRows: [Row]

        init(headerCells: [Cell], bodyRows: [Row]) {
            self.headerCells = headerCells
            self.bodyRows = bodyRows
        }

        /// The header row of a table.
        public var header: MarkdownTableStyleConfiguration.Table.Header {
            MarkdownTableStyleConfiguration.Table.Header(cells: headerCells)
        }
        /// The body rows of a table.
        public var rows: [MarkdownTableStyleConfiguration.Table.Row] {
            bodyRows
        }
        
        typealias Fallback = EmptyView
        /// An empty fallback view kept for source compatibility.
        @available(*, deprecated, message: "MarkdownView 3 does not use fallback any more.")
        public var fallback: EmptyView {
            EmptyView()
        }
    }
}

extension MarkdownTableStyleConfiguration.Table {
    struct Cell {
        var horizontalAlignment: HorizontalAlignment
        var textAlignment: TextAlignment
        /// numen fork (gemma4-qat#1765): the alignment in a right-to-left table, where an explicit
        /// `:---` / `---:` column keeps its physical side. The row picks by the direction the
        /// table actually lays out in, its own or the one it inherits (a numeric table in an
        /// Arabic block quote), which only the view knows.
        var rightToLeftHorizontalAlignment: HorizontalAlignment
        var rightToLeftTextAlignment: TextAlignment
        var colspan: Int
        var content: AnyView

        init(
            horizontalAlignment: HorizontalAlignment,
            textAlignment: TextAlignment,
            rightToLeftHorizontalAlignment: HorizontalAlignment? = nil,
            rightToLeftTextAlignment: TextAlignment? = nil,
            colspan: Int,
            content: some View
        ) {
            self.horizontalAlignment = horizontalAlignment
            self.textAlignment = textAlignment
            self.rightToLeftHorizontalAlignment = rightToLeftHorizontalAlignment ?? horizontalAlignment
            self.rightToLeftTextAlignment = rightToLeftTextAlignment ?? textAlignment
            self.colspan = colspan
            self.content = AnyView(content)
        }

        func horizontalAlignment(in direction: LayoutDirection) -> HorizontalAlignment {
            direction == .rightToLeft ? rightToLeftHorizontalAlignment : horizontalAlignment
        }

        func textAlignment(in direction: LayoutDirection) -> TextAlignment {
            direction == .rightToLeft ? rightToLeftTextAlignment : textAlignment
        }
    }
}

extension MarkdownTableStyleConfiguration.Table: View {
    @_documentation(visibility: internal)
    public var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            header
            ForEach(Array(rows.enumerated()), id: \.offset) { (_, row) in
                row
            }
        }
    }
}
