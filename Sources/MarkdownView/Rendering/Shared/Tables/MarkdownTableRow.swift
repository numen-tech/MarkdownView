//
//  MarkdownTableHeader.swift
//  MarkdownView
//
//  Created by LiYanan2004 on 2025/4/21.
//

import SwiftUI
import Markdown

struct MarkdownTableRow: View {
    private var rowIndex: Int
    private var cells: [MarkdownTableStyleConfiguration.Table.Cell]
    @Environment(\.markdownTableCellPadding) private var padding
    /// numen fork (gemma4-qat#1765): the direction the table lays out in, its own or inherited,
    /// for the grid's column alignment (one per column, shared by every row); the row's own
    /// direction for the alignment of the text inside a cell.
    @Environment(\.markdownTableLayoutDirection) private var tableLayoutDirection
    @Environment(\.layoutDirection) private var layoutDirection
    
    init(
        rowIndex: Int,
        cells: [MarkdownTableStyleConfiguration.Table.Cell]
    ) {
        self.rowIndex = rowIndex
        self.cells = cells
    }
    
    var body: some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { (index, cell) in
                cell.content
                    .multilineTextAlignment(cell.textAlignment(in: layoutDirection))
                    .gridColumnAlignment(cell.horizontalAlignment(in: tableLayoutDirection ?? layoutDirection))
                    .gridCellColumns(cell.colspan)
                    ._markdownCellPadding(padding)
                    .modifier(
                        MarkdownTableStylePreferenceSynchronizer(
                            row: rowIndex,
                            column: index
                        )
                    )
            }
        }
    }
}
