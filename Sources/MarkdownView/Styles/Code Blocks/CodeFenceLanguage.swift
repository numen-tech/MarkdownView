//
//  CodeFenceLanguage.swift
//  MarkdownView
//

import Foundation

/// The language name a code fence asks for.
///
/// swift-markdown hands over the fence's whole info string, and models put more than a bare name in
/// it: `js`, `Python`, `python title="a.py"`. highlight.js resolves a name or an alias on its own
/// (`js` and `jsx` are `javascript`, `py` is `python`, `sh` is `bash`), so what is needed here is
/// the name itself, the first word of the info string lowercased, plus the few names models write
/// that highlight.js has no alias for.
enum CodeFenceLanguage {
    /// The name to hand to highlight.js, or `nil` when the fence names no language, so the
    /// highlighter detects one.
    static func name(fromInfo info: String?) -> String? {
        guard let word = info?.split(whereSeparator: \.isWhitespace).first?.lowercased() else {
            return nil
        }
        return extraAliases[word] ?? word
    }

    /// Names highlight.js 11 does not know (checked against `hljs.getLanguage`), and what they
    /// mean. Output and log fences are not code, so they are shown plain, not guessed at.
    private static let extraAliases: [String: String] = [
        "python3": "python",
        "py3": "python",
        "node": "javascript",
        "nodejs": "javascript",
        "objective-c": "objectivec",
        "jsonl": "json",
        "terminal": "plaintext",
        "output": "plaintext",
        "log": "plaintext",
    ]
}
