import Markdown
import SwiftUI

extension Markdown.Table.Cell {
    public var horizontalAlignment: HorizontalAlignment {
        cellAlignment.horizontalAlignment
    }

    public var textAlignment: TextAlignment {
        cellAlignment.textAlignment
    }

    /// numen fork (gemma4-qat#1765): the alignment in a table laid out in `tableDirection`. A
    /// column marked `:---` or `---:` stays on the physical left or right, as GFM and HTML mean
    /// it; `leading` and `trailing` mirror in a right-to-left table, so those two swap there.
    func horizontalAlignment(tableDirection: LayoutDirection?) -> HorizontalAlignment {
        let both = directionalAlignments
        return tableDirection == .rightToLeft ? both.rightToLeft.horizontal : both.leftToRight.horizontal
    }

    func textAlignment(tableDirection: LayoutDirection?) -> TextAlignment {
        let both = directionalAlignments
        return tableDirection == .rightToLeft ? both.rightToLeft.text : both.leftToRight.text
    }

    /// The cell's alignment in a left-to-right and in a right-to-left table, from one read of its
    /// column's parsed alignment.
    var directionalAlignments: (
        leftToRight: (horizontal: HorizontalAlignment, text: TextAlignment),
        rightToLeft: (horizontal: HorizontalAlignment, text: TextAlignment)
    ) {
        let column = columnAlignment
        let leftToRight: CellAlignment = switch column {
        case .center: .center
        case .right: .trailing
        case .left, .none: .leading
        }
        let rightToLeft: CellAlignment = switch column {
        case .left: .trailing
        case .right: .leading
        case .center, .none: leftToRight
        }
        return ((leftToRight.horizontalAlignment, leftToRight.textAlignment), (rightToLeft.horizontalAlignment, rightToLeft.textAlignment))
    }

    /// The parsed alignment of the cell's column, nil when unmarked or outside a table.
    private var columnAlignment: Markdown.Table.ColumnAlignment? {
        guard parent is any TableCellContainer else { return nil }
        var element = parent
        while let current = element {
            if let table = current as? Markdown.Table {
                return indexInParent < table.columnAlignments.count ? table.columnAlignments[indexInParent] : nil
            }
            element = current.parent
        }
        return nil
    }
}

private extension Markdown.Table.Cell {
    var cellAlignment: CellAlignment {
        guard parent is any TableCellContainer else { return .leading }

        let columnIndex = indexInParent
        var currentElement = parent

        while currentElement != nil {
            if let table = currentElement as? Markdown.Table {
                let alignment = table.columnAlignments[columnIndex]
                switch alignment {
                case .center:
                    return .center
                case .left:
                    return .leading
                case .right:
                    return .trailing
                case .none:
                    return .leading
                }
            }

            currentElement = currentElement?.parent
        }

        return .leading
    }

    enum CellAlignment {
        case leading
        case center
        case trailing


        var textAlignment: TextAlignment {
            switch self {
            case .leading:
                .leading
            case .center:
                .center
            case .trailing:
                .trailing
            }
        }

        var horizontalAlignment: HorizontalAlignment {
            switch self {
            case .leading:
                .leading
            case .center:
                .center
            case .trailing:
                .trailing
            }
        }
    }
}
