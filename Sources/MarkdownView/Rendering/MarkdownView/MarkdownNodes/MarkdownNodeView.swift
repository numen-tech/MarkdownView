import SwiftUI

struct MarkdownNodeView: View {
    private var storage: Either<AttributedString, AnyView>
    /// numen fork (gemma4-qat#1765): the reading direction of a block's content
    /// (`MarkdownContentDirection`), nil for inline nodes and for blocks with no strong character,
    /// which take their container's. A block with one lays out in it.
    var direction: LayoutDirection?
    
    enum ContentType: String {
        case text, view
    }
    var contentType: ContentType {
        switch storage {
        case .left(_): .text
        case .right(_): .view
        }
    }
    
    init(_ text: AttributedString) {
        self.storage = .left(text)
    }
    
    init(_ text: AttributedSubstring) {
        self.storage = .left(AttributedString(text))
    }
    
    init(_ text: String) {
        self.storage = .left(AttributedString(text))
    }
    
    init<Content: View>(@ViewBuilder _ content: () -> Content) {
        let content = content()
        if let markdownNode = content as? MarkdownNodeView {
            storage = markdownNode.storage
            direction = markdownNode.direction
        } else {
            storage = .right(AnyView(content))
        }
    }
    
    var body: some View {
        Group {
            if case .left(let attributedString) = storage {
                _MarkdownText(attributedString)
            } else if case .right(let view) = storage {
                view
            }
        }
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        // Not `.environment` over an `@Environment` read: `body` is also called directly, outside
        // the view graph (`FlowLayout`'s children, a single composed node), where a read gives
        // the default direction.
        .transformEnvironment(\.layoutDirection) { layoutDirection in
            if let direction { layoutDirection = direction }
        }
    }

    /// This node with its content's reading direction (nil keeps the container's).
    func withDirection(_ direction: LayoutDirection?) -> MarkdownNodeView {
        var node = self
        node.direction = direction
        return node
    }
    
    var asAttributedString: AttributedString? {
        if case let .left(attributedString) = storage {
            return attributedString
        }
        return nil
    }
}

extension MarkdownNodeView {
    enum LayoutPolicy {
        case adaptive
        case linebreak
    }
    
    /// Combine adjacent views of the same type.
    /// - Parameter contents: A set of contents to combine together.
    /// - Parameter alignment: The alignment in relation to these contents.
    init(
        _ contents: [MarkdownNodeView],
        alignment: HorizontalAlignment = .leading,
        layoutPolicy: LayoutPolicy = .adaptive
    ) {
        var composedContents = [MarkdownNodeView]()
        var attributedString = AttributedString()
        // numen fork (gemma4-qat#1765): blocks merge into one text only while their directions
        // agree (a block with none joins its neighbour); inline nodes carry none.
        var textDirection: LayoutDirection?
        for content in contents {
            if case let .left(text) = content.storage {
                if layoutPolicy == .linebreak, !attributedString.characters.isEmpty,
                   let direction = content.direction, let current = textDirection, direction != current {
                    composedContents.append(MarkdownNodeView(attributedString).withDirection(textDirection))
                    attributedString = AttributedString()
                    textDirection = nil
                }
                if layoutPolicy == .linebreak && !attributedString.characters.isEmpty {
                    attributedString += "\n\n"
                }
                attributedString += text
                textDirection = textDirection ?? content.direction
            } else {
                if !attributedString.characters.isEmpty {
                    composedContents.append(MarkdownNodeView(attributedString).withDirection(textDirection))
                    attributedString = AttributedString()
                    textDirection = nil
                }
                composedContents.append(content)
            }
        }
        if !attributedString.characters.isEmpty {
            composedContents.append(MarkdownNodeView(attributedString).withDirection(textDirection))
        }
        
        if composedContents.count == 1 {
            if let attributedString = composedContents[0].asAttributedString {
                storage = .left(attributedString)
            } else {
                storage = .right(AnyView(composedContents[0].body))
            }
            direction = composedContents[0].direction
        } else {
            if layoutPolicy == .adaptive {
                let composedView = FlowLayout(verticleSpacing: 8) {
                    ForEach(composedContents.indices, id: \.self) {
                        composedContents[$0].body
                    }
                }
                storage = .right(AnyView(composedView))
            } else {
                // numen fork (gemma4-qat#1765): each block in its own direction.
                storage = .right(AnyView(MarkdownBlockStack(blocks: composedContents, spacing: 8)))
            }
        }
    }
}
