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
        physicalAlignment(tableDirection: tableDirection).horizontalAlignment
    }

    func textAlignment(tableDirection: LayoutDirection?) -> TextAlignment {
        physicalAlignment(tableDirection: tableDirection).textAlignment
    }

    private func physicalAlignment(tableDirection: LayoutDirection?) -> CellAlignment {
        guard tableDirection == .rightToLeft, parent is any TableCellContainer,
              let alignments = table?.columnAlignments, indexInParent < alignments.count
        else { return cellAlignment }
        switch alignments[indexInParent] {
        case .left: return .trailing
        case .right: return .leading
        default: return cellAlignment
        }
    }

    /// The table this cell belongs to.
    var table: Markdown.Table? {
        var element = parent
        while let current = element {
            if let table = current as? Markdown.Table { return table }
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
