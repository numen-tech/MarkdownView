//
//  MarkdownViewRenderer.swift
//  MarkdownView
//
//  Created by Yanan Li on 2025/4/12.
//

import SwiftUI
import Markdown

@MainActor
@preconcurrency
struct MarkdownViewRenderer: @preconcurrency MarkupVisitor {
    var configuration: MarkdownRendererConfiguration
    var mathContext: MarkdownMathContext?
    var elementRenderers: [MarkdownElementRendererRegistration]
    private var activeInlineIntent: InlinePresentationIntent = []
    
    init(
        configuration: MarkdownRendererConfiguration,
        mathContext: MarkdownMathContext?,
        elementRenderers: [MarkdownElementRendererRegistration]
    ) {
        self.configuration = configuration
        self.mathContext = mathContext
        self.elementRenderers = elementRenderers
    }
    
    func makeBody(for markup: any Markup) -> some View {
        var visitor = self
        return visitor
            .visit(markup)
            .environment(\.markdownMathContext, mathContext)
            .environment(\.markdownElementRenderers, elementRenderers)
            .markdownResolvedHighlight(configuration.resolvedHighlight)
    }

    func makeBody(forChildrenOf markup: any Markup) -> some View {
        self
            .descendInto(markup)
            .environment(\.markdownMathContext, mathContext)
            .environment(\.markdownElementRenderers, elementRenderers)
            .markdownResolvedHighlight(configuration.resolvedHighlight)
    }

    /// numen fork (gemma4-qat#1765): `markup`'s child blocks in a column, each in its own
    /// content direction (a block quote's, a list item's).
    func makeBlockStack(forChildrenOf markup: any Markup, spacing: CGFloat) -> some View {
        let blocks = markup.children.map { child in
            var renderer = self
            return renderer.visit(child)
        }
        return MarkdownBlockStack(blocks: blocks, spacing: spacing)
            .environment(\.markdownMathContext, mathContext)
            .environment(\.markdownElementRenderers, elementRenderers)
            .markdownResolvedHighlight(configuration.resolvedHighlight)
    }

    /// numen fork (gemma4-qat#1765): the content direction of a block.
    func contentDirection(of markup: any Markup) -> LayoutDirection? {
        MarkdownContentDirection.of(markup, skipsMath: mathContext != nil)
    }

    func visitDocument(_ document: Markdown.Document) -> MarkdownNodeView {
        var renderer = self
        let nodeViews = document.children.map {
            renderer.visit($0)
        }
        return MarkdownNodeView(nodeViews, layoutPolicy: .linebreak)
    }
    
    func defaultVisit(_ markup: Markdown.Markup) -> MarkdownNodeView {
        descendInto(markup)
    }
    
    func descendInto(_ markup: any Markup) -> MarkdownNodeView {
        var nodeViews = [MarkdownNodeView]()
        for child in markup.children {
            var renderer = self
            let nodeView = renderer.visit(child)
            nodeViews.append(nodeView)
        }
        return MarkdownNodeView(nodeViews)
    }
    
    func visitText(_ text: Markdown.Text) -> MarkdownNodeView {
        if mathContext != nil,
           let mathIdentifier = MarkdownMathPreprocessor.displayPlaceholderIdentifier(
               in: text.plainText
           ) {
            return MarkdownNodeView {
                MarkdownDisplayMathView(mathIdentifier: mathIdentifier)
                    .id(mathIdentifier)
            }
        }

        // numen fork: the runs inside the highlighted span get its background.
        let highlight = configuration.resolvedHighlight
        let highlightedRange = highlight?.highlightedRange(in: text.plainText, nodeRange: text.range)

        if mathContext != nil {
            return InlineMathOrText(
                text: text.plainText,
                highlight: highlightedRange == nil ? nil : highlight,
                highlightedRange: highlightedRange
            )
            .makeBody(mathContext: mathContext)
        }

        if let highlight, let highlightedRange {
            return MarkdownNodeView(
                highlight.attributed(text.plainText, highlightedRange: highlightedRange)
            )
        }
        return MarkdownNodeView(text.plainText)
    }
    
    func visitBlockDirective(_ blockDirective: BlockDirective) -> MarkdownNodeView {
        let fallbackContent = descendInto(blockDirective)
        return MarkdownNodeView {
            MarkdownBlockDirective(
                blockDirective: blockDirective,
                fallbackContent: fallbackContent
            )
        }
    }
    
    func visitBlockQuote(_ blockQuote: BlockQuote) -> MarkdownNodeView {
        let content = MarkdownBlockQuoteStyleConfiguration.Content {
            MarkdownViewRenderer(
                configuration: configuration,
                mathContext: mathContext,
                elementRenderers: elementRenderers
            )
            .makeBlockStack(forChildrenOf: blockQuote, spacing: configuration.componentSpacing)
        }
        return MarkdownNodeView {
            MarkdownBlockQuote(content: content)
                .tint(configuration.tintColors[.blockQuote, default: .accentColor])
        }
        .withDirection(contentDirection(of: blockQuote))
    }
    
    func visitSoftBreak(_ softBreak: SoftBreak) -> MarkdownNodeView {
        // numen fork: a span running across the line break keeps its highlight unbroken.
        // swift-markdown gives a soft break no range, so its neighbours bound it.
        if let highlight = configuration.resolvedHighlight,
           let parent = softBreak.parent, softBreak.indexInParent > 0,
           let before = highlight.byteRange(of: parent.child(at: softBreak.indexInParent - 1)?.range),
           let after = highlight.byteRange(of: parent.child(at: softBreak.indexInParent + 1)?.range),
           highlight.range.lowerBound <= before.upperBound,
           highlight.range.upperBound > after.lowerBound {
            var space = AttributedString(" ")
            space.backgroundColor = highlight.color
            return MarkdownNodeView(space)
        }
        return MarkdownNodeView(" ")
    }
    
    func visitThematicBreak(_ thematicBreak: ThematicBreak) -> MarkdownNodeView {
        MarkdownNodeView {
            Divider()
        }
    }
    
    func visitLineBreak(_ lineBreak: LineBreak) -> MarkdownNodeView {
        MarkdownNodeView("\n")
    }
    
    func visitInlineCode(_ inlineCode: InlineCode) -> MarkdownNodeView {
        let tintColor = configuration.tintColors[.inlineCodeBlock, default: .accentColor]
        var attributedString = AttributedString(stringLiteral: inlineCode.code)
        attributedString.foregroundColor = tintColor
        attributedString.backgroundColor = tintColor.opacity(0.1)
        // numen fork (gemma4-qat#1765): code reads left to right inside right-to-left prose.
        attributedString[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
        // numen fork: an inline code span the highlighted span touches is highlighted whole.
        if let highlight = configuration.resolvedHighlight, highlight.overlaps(inlineCode.range) {
            attributedString.backgroundColor = highlight.color
        }
        return MarkdownNodeView(attributedString)
    }
    
    func visitInlineHTML(_ inlineHTML: InlineHTML) -> MarkdownNodeView {
        MarkdownNodeView(
            AttributedString(
                inlineHTML.rawHTML,
                attributes: AttributeContainer().isHTML(true)
            )
        )
    }
    
    func visitImage(_ image: Markdown.Image) -> MarkdownNodeView {
        MarkdownNodeView {
            MarkdownImage(image: image)
        }
    }
    
    func visitCodeBlock(_ codeBlock: CodeBlock) -> MarkdownNodeView {
        MarkdownNodeView {
            MarkdownStyledCodeBlock(
                configuration: MarkdownCodeBlockStyleConfiguration(
                    language: codeBlock.language,
                    code: codeBlock.code.trimmingCharacters(in: .newlines)
                )
            )
        }
    }
    
    func visitHTMLBlock(_ html: HTMLBlock) -> MarkdownNodeView {
        MarkdownNodeView {
            HTMLBlockView(html: html.rawHTML)
        }
    }
    
    func visitListItem(_ listItem: ListItem) -> MarkdownNodeView {
        MarkdownNodeView {
            MarkdownListItem(listItem: listItem)
        }
    }
    
    func visitOrderedList(_ orderedList: OrderedList) -> MarkdownNodeView {
        MarkdownNodeView {
            MarkdownList(listItemsContainer: orderedList)
        }
        .withDirection(contentDirection(of: orderedList))
    }
    
    func visitUnorderedList(_ unorderedList: UnorderedList) -> MarkdownNodeView {
        MarkdownNodeView {
            MarkdownList(listItemsContainer: unorderedList)
        }
        .withDirection(contentDirection(of: unorderedList))
    }
    
    func visitTable(_ table: Markdown.Table) -> MarkdownNodeView {
        let renderedTable = renderedTable(for: table)
        return MarkdownNodeView {
            MarkdownTable(table: renderedTable)
        }
        .withDirection(contentDirection(of: table))
    }
    
    func visitTableHead(_ head: Markdown.Table.Head) -> MarkdownNodeView {
        MarkdownNodeView {
            MarkdownTableRow(
                rowIndex: 0,
                cells: Array(head.cells).map { renderedTableCell($0) }
            )
        }
    }
    
    func visitTableBody(_ body: Markdown.Table.Body) -> MarkdownNodeView {
        MarkdownNodeView {
            MarkdownTableBody(rows: renderedTableRows(for: body))
        }
    }
    
    func visitTableRow(_ row: Markdown.Table.Row) -> MarkdownNodeView {
        MarkdownNodeView {
            MarkdownTableRow(
                rowIndex: row.indexInParent + 1 /* header */,
                cells: Array(row.cells).map { renderedTableCell($0) }
            )
        }
    }
    
    func visitTableCell(_ cell: Markdown.Table.Cell) -> MarkdownNodeView {
        var cellViews = [MarkdownNodeView]()
        for child in cell.children {
            var renderer = MarkdownViewRenderer(
                configuration: configuration,
                mathContext: mathContext,
                elementRenderers: elementRenderers
            )
            let cellView = renderer.visit(child)
            cellViews.append(cellView)
        }
        // The cell's column alignment is applied by `MarkdownTableRow`, in the direction the
        // table lays out in.
        return MarkdownNodeView(cellViews)
    }
    
    func visitParagraph(_ paragraph: Paragraph) -> MarkdownNodeView {
        defaultVisit(paragraph).withDirection(contentDirection(of: paragraph))
    }
    
    func visitHeading(_ heading: Heading) -> MarkdownNodeView {
        MarkdownNodeView {
            MarkdownHeading(heading: heading)
        }
        .withDirection(contentDirection(of: heading))
    }
    
    func visitEmphasis(_ emphasis: Markdown.Emphasis) -> MarkdownNodeView {
        applyInlineIntent(.emphasized, to: emphasis.children)
    }

    func visitStrong(_ strong: Strong) -> MarkdownNodeView {
        applyInlineIntent(.stronglyEmphasized, to: strong.children)
    }

    func visitStrikethrough(_ strikethrough: Strikethrough) -> MarkdownNodeView {
        applyInlineIntent(.strikethrough, to: strikethrough.children)
    }
    
    func visitLink(_ link: Markdown.Link) -> MarkdownNodeView {
        guard let destination = link.destination,
              let url = configuration.resolvedMarkdownURL(for: destination)
        else { return descendInto(link) }
        
        let tintColor = configuration.tintColors[.link, default: .accentColor]
        let underlineLinks = configuration.underlineLinks
        
        let nodeView = descendInto(link)
        let availableRenderers = elementRenderers.compactMap(\.link)
        if availableRenderers.isEmpty == false,
           let urlScheme = url.scheme,
           let linkRenderer = availableRenderers.first(where: { $0.scheme == urlScheme })?.renderer {
            let labelContent: AnyView = nodeView
                .tint(tintColor)
                .underline(underlineLinks)
                .erasedToAnyView()
            let linkConfiguration = MarkdownLinkRendererConfiguration(
                url: url,
                label: labelContent
            )
            return MarkdownNodeView {
                linkRenderer
                    .makeBody(configuration: linkConfiguration)
                    .erasedToAnyView()
            }
        }

        return if let attributedString = nodeView.asAttributedString {
            MarkdownNodeView(
                attributedString.mergingAttributes({
                    var attributes = AttributeContainer()
                        .link(url)
                        .foregroundColor(tintColor)
                    if underlineLinks {
                        attributes.underlineStyle = .single
                    }
                    // numen fork (gemma4-qat#1765): an autolink (a URL or an email address as its
                    // own label) reads left to right inside right-to-left prose.
                    if MarkdownContentDirection.isAutolink(link) {
                        attributes[AttributeScopes.MarkdownViewAttributeScope.IsolatesLeftToRightAttribute.self] = true
                    }
                    return attributes
                }())
            )
        } else {
             MarkdownNodeView {
                Link(destination: url) {
                    nodeView
                }
                .foregroundStyle(tintColor)
                .underline(underlineLinks)
            }
        }
    }
    
    private func applyInlineIntent(
        _ newIntent: InlinePresentationIntent,
        to children: MarkupChildren
    ) -> MarkdownNodeView {
        var nodes = [MarkdownNodeView]()
        for child in children {
            var renderer = self
            renderer.activeInlineIntent.formUnion(newIntent)
            let node = renderer.visit(child)
            if let text = node.asAttributedString {
                let intent = text.inlinePresentationIntent ?? []
                let attributedNode = MarkdownNodeView(
                    text.mergingAttributes(
                        AttributeContainer().inlinePresentationIntent(intent.union(newIntent))
                    )
                )
                nodes.append(attributedNode)
            } else {
                nodes.append(node)
            }
        }
        return MarkdownNodeView(nodes)
    }
}

extension MarkdownViewRenderer {
    func renderedTable(for table: Markdown.Table) -> MarkdownTableStyleConfiguration.Table {
        MarkdownTableStyleConfiguration.Table(
            headerCells: Array(table.head.cells).map { renderedTableCell($0) },
            bodyRows: renderedTableRows(for: table.body)
        )
    }

    fileprivate func renderedTableRows(for tableBody: Markdown.Table.Body) -> [MarkdownTableStyleConfiguration.Table.Row] {
        tableBody.rows.map { row in
            MarkdownTableStyleConfiguration.Table.Row(
                rowIndex: row.indexInParent + 1 /* header */,
                cells: Array(row.cells).map { renderedTableCell($0) }
            )
        }
    }

    fileprivate func renderedTableCell(_ cell: Markdown.Table.Cell) -> MarkdownTableStyleConfiguration.Table.Cell {
        var renderer = MarkdownViewRenderer(
            configuration: configuration,
            mathContext: mathContext,
            elementRenderers: elementRenderers
        )
        let content = renderer.makeBody(for: cell)
        
        // numen fork (gemma4-qat#1765): explicit left/right columns stay physical in an RTL table.
        // Both alignments go to the row, which picks by the direction the table lays out in: its
        // own, or inherited when it has no strong letter (a numeric table in an Arabic quote).
        return MarkdownTableStyleConfiguration.Table.Cell(
            horizontalAlignment: cell.horizontalAlignment(tableDirection: .leftToRight),
            textAlignment: cell.textAlignment(tableDirection: .leftToRight),
            rightToLeftHorizontalAlignment: cell.horizontalAlignment(tableDirection: .rightToLeft),
            rightToLeftTextAlignment: cell.textAlignment(tableDirection: .rightToLeft),
            colspan: Int(cell.colspan),
            content: content
        )
    }
}
