import SwiftUI
import Markdown

struct MarkdownTable: View {
    var table: MarkdownTableStyleConfiguration.Table
    @Environment(\.markdownTableStyle) private var tableStyle
    @Environment(\.layoutDirection) private var layoutDirection

    init(table: MarkdownTableStyleConfiguration.Table) {
        self.table = table
    }
    
    var body: some View {
        let configuration = MarkdownTableStyleConfiguration(
            table: table
        )
        tableStyle
            .makeBody(configuration: configuration)
            .erasedToAnyView()
            .markdownTableCellStyleApplied()
            .coordinateSpace(name: MarkdownTable.CoordinateSpaceName)
            // numen fork (gemma4-qat#1765): every row places its cells in the grid's columns by
            // the table's direction, even a row a custom style lays out in another.
            .environment(\.markdownTableLayoutDirection, layoutDirection)
    }
}

extension EnvironmentValues {
    /// numen fork (gemma4-qat#1765): the direction the table lays out in, set by `MarkdownTable`.
    /// Nil for a row rendered outside one.
    @Entry var markdownTableLayoutDirection: LayoutDirection? = nil
}

extension MarkdownTable {
    static let CoordinateSpaceName: String = "markdownview-table"
}

// MARK: - Auxiliary

fileprivate extension View {
    nonisolated func markdownTableCellStyleApplied() -> some View {
        modifier(MarkdownTableCellStylingViewModifier())
    }
}

fileprivate struct MarkdownTableCellStylingViewModifier: ViewModifier {
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(
                MarkdownTableRowStyleCollectionPreference.self
            ) { styleCollection in
                if styleCollection.values.contains(where: { $0.backgroundStyle != nil }) {
                    ZStack(alignment: .topLeading) {
                        ForEach(styleCollection.rows) { row in
                            if let backgroundStyle = row.backgroundStyle {
                                resolveShape(row.backgroundShape, style: backgroundStyle)
                                    .environment(\.layoutDirection, layoutDirection)
                                    .offset(styleCollection.offset(for: row.position))
                                    .frame(height: styleCollection.heights[row.position.row])
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // numen fork (gemma4-qat#1765): the cell frames are physical points, and
                    // `.offset` mirrors under right-to-left; place the layers left to right.
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
            .backgroundPreferenceValue(
                MarkdownTableCellStyleCollectionPreference.self
            ) { styleCollection in
                if styleCollection.cells.contains(where: { $0.backgroundStyle != nil }) {
                    ZStack(alignment: .topLeading) {
                        ForEach(styleCollection.cells) { cell in
                            if let backgroundStyle = cell.backgroundStyle {
                                resolveShape(cell.backgroundShape, style: backgroundStyle)
                                    .environment(\.layoutDirection, layoutDirection)
                                    .offset(styleCollection.offset(for: cell.position))
                                    .frame(
                                        width: styleCollection.widths[cell.position.column],
                                        height: styleCollection.heights[cell.position.row]
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // numen fork (gemma4-qat#1765): the cell frames are physical points, and
                    // `.offset` mirrors under right-to-left; place the layers left to right.
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
            .overlayPreferenceValue(
                MarkdownTableCellStyleCollectionPreference.self
            ) { styleCollection in
                if styleCollection.cells.contains(where: { $0.overlayContent != nil }) {
                    ZStack(alignment: .topLeading) {
                        ForEach(styleCollection.cells) { cell in
                            if let overlayContent = cell.overlayContent {
                                overlayContent
                                    // The caller's overlay lays out in the table's direction; only
                                    // its placement is physical.
                                    .environment(\.layoutDirection, layoutDirection)
                                    .offset(styleCollection.offset(for: cell.position))
                                    .frame(
                                        width: styleCollection.widths[cell.position.column],
                                        height: styleCollection.heights[cell.position.row]
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // numen fork (gemma4-qat#1765): the cell frames are physical points, and
                    // `.offset` mirrors under right-to-left; place the layers left to right.
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
    }
    
    func resolveShape(_ shape: any Shape, style: some ShapeStyle) -> AnyView {
        func cast(_ shape: some Shape) -> AnyView {
            AnyView(shape.fill(style))
        }
        return _openExistential(shape, do: cast(_:))
    }
}

extension View {
    nonisolated func _markdownTableStylesIgnored(_ ignored: Bool = true) -> some View {
        transformEnvironment(\.self) { environmentValues in
            if ignored {
                environmentValues.markdownTableCellPadding = .zero
                environmentValues.markdownTableCellBackgroundStyle = nil
                environmentValues.markdownTableCellOverlayContent = nil
                environmentValues.markdownTableRowBackgroundStyle = nil
            }
        }
    }
}
