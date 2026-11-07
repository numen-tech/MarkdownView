//
//  CodeHighlighter.swift
//  MarkdownView
//

#if canImport(Highlightr)
import Foundation
@preconcurrency import Highlightr

/// Syntax highlighting for the default code block style.
///
/// Every highlight builds its own JavaScript context (`Highlightr()` evaluates the 1 MB
/// `highlight.min.js` into a new `JSContext`), runs once and drops it, inside an `autoreleasepool`
/// so the temporaries JavaScriptCore and the HTML walk bridge are freed when the run ends rather
/// than when some outer pool drains. Nothing stays resident between blocks. A finished result is
/// kept in a small cache, so a block that comes back (scrolled into a lazy stack again, or the same
/// code drawn by the committed bubble that replaces a streaming one) is not highlighted twice.
enum CodeHighlighter {
    /// The highlighted code, or `nil` when the highlighter could not be built or gave up.
    static func attributedString(
        for code: String,
        language: String?,
        theme: String,
        renderer: (String, String?, String) -> AttributedString? = CodeHighlighter.render
    ) -> AttributedString? {
        // A block that has only just opened (its fence is still arriving) has nothing to colour.
        guard !code.isEmpty else { return nil }
        let key = Key(code: code, language: language, theme: theme)
        if let hit = cache.object(forKey: key) { return hit.value }
        guard let value = autoreleasepool(invoking: { renderer(code, language, theme) }) else {
            return nil
        }
        cache.setObject(Entry(value), forKey: key, cost: code.utf8.count)
        return value
    }

    private static func render(_ code: String, _ language: String?, _ theme: String) -> AttributedString? {
        guard let highlightr = Highlightr(), highlightr.setTheme(to: theme) else { return nil }
        // Streamed code is often cut mid-token. At the default (`false`) highlight.js returns the
        // whole block uncoloured for one illegal token, such as an unterminated Python string.
        highlightr.ignoreIllegals = true
        // highlight.js resolves a language name or alias itself (`js`, `py`, `sh`), and a name it
        // does not know falls back to auto-detection inside Highlightr.
        guard let highlighted = highlightr.highlight(code, as: language) else { return nil }
        let attributed = NSMutableAttributedString(attributedString: highlighted)
        attributed.removeAttribute(.font, range: NSRange(location: 0, length: attributed.length))
        return AttributedString(attributed)
    }

    // MARK: Cache

    private final class Key: NSObject {
        let code: String
        let language: String?
        let theme: String

        init(code: String, language: String?, theme: String) {
            self.code = code
            self.language = language
            self.theme = theme
        }

        // `String` equality is canonical equivalence (`é` equals `e` + U+0301), but the two are
        // different source text, so the code is compared and hashed by its UTF-8 bytes.
        override var hash: Int {
            var hasher = Hasher()
            for byte in code.utf8 { hasher.combine(byte) }
            hasher.combine(language)
            hasher.combine(theme)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return code.utf8.elementsEqual(other.code.utf8) && language == other.language && theme == other.theme
        }
    }

    private final class Entry {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    /// A few screens of blocks; `NSCache` also empties itself under memory pressure.
    private nonisolated(unsafe) static let cache: NSCache<Key, Entry> = {
        let cache = NSCache<Key, Entry>()
        cache.countLimit = 32
        cache.totalCostLimit = 1 << 20
        return cache
    }()
}
#endif
