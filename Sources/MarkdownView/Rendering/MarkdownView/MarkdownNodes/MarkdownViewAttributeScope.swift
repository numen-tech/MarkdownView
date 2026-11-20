//
//  MarkdownViewAttributeScope.swift
//  MarkdownView
//
//  Created by Yanan Li on 2025/10/20.
//

import Foundation

extension AttributeScopes {
    struct MarkdownViewAttributeScope: AttributeScope {
        let isHTML: IsHTMLAttribute
        let isolatesLeftToRight: IsolatesLeftToRightAttribute
    }
}

extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.MarkdownViewAttributeScope, T>) -> T {
        return self[T.self]
    }
}

extension AttributeScopes.MarkdownViewAttributeScope {
    enum IsHTMLAttribute: AttributedStringKey {
        static let name: String = "isHTML"
        
        typealias Value = Bool
    }

    /// numen fork (gemma4-qat#1765): a run that reads left to right as one unit (inline code, a
    /// bare link), isolated at display time (`MarkdownBidiIsolation`).
    enum IsolatesLeftToRightAttribute: AttributedStringKey {
        static let name: String = "numenIsolatesLeftToRight"

        typealias Value = Bool
    }
}
