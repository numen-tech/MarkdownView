import SwiftUI
import Markdown

struct MarkdownListItem: View {
    var listItem: ListItem
    @Environment(\.markdownRendererConfiguration) private var configuration
    @Environment(\.markdownMathContext) private var mathContext
    @Environment(\.markdownElementRenderers) private var elementRenderers
    
    var body: some View {
        // numen fork (gemma4-qat#1765): each child block in its own content direction.
        MarkdownViewRenderer(
            configuration: configuration,
            mathContext: mathContext,
            elementRenderers: elementRenderers
        )
        .makeBlockStack(forChildrenOf: listItem, spacing: configuration.componentSpacing)
    }
}
