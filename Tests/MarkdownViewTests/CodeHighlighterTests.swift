//
//  CodeHighlighterTests.swift
//  MarkdownView
//

import Foundation
import Testing

@testable import MarkdownView

#if os(iOS) || os(macOS)
@Suite("Code Highlighter")
struct CodeHighlighterTests {
    // MARK: Fence language

    @Test(
        "Takes the first word of the fence info string, lowercased",
        arguments: [
            (Optional("js"), Optional("js")),
            ("Python", "python"),
            ("python title=\"a.py\"", "python"),
            ("  sh  ", "sh"),
            ("", nil),
            ("   ", nil),
            (nil, nil),
            ("python3", "python"),
            ("Node", "javascript"),
            ("objective-c", "objectivec"),
            ("output", "plaintext"),
        ]
    )
    func fenceLanguageName(info: String?, expected: String?) {
        #expect(CodeFenceLanguage.name(fromInfo: info) == expected)
    }

    @Test("A name highlight.js has no alias for is mapped before it is looked up")
    func extraAliasesResolve() throws {
        let code = "def total(items):\n    return sum(items)\n"
        let viaFence = try #require(
            CodeHighlighter.attributedString(
                for: code, language: CodeFenceLanguage.name(fromInfo: "python3"), theme: "xcode")
        )
        let viaName = try #require(CodeHighlighter.attributedString(for: code, language: "python", theme: "xcode"))
        #expect(viaFence.runs.count > 1)
        #expect(viaFence == viaName)
    }

    // MARK: Aliases

    private static let samples: [(alias: String, canonical: String, code: String)] = [
        ("js", "javascript", "const total = items.map((x) => x * 2);\nconsole.log(`sum: ${total}`);\n"),
        ("jsx", "javascript", "const el = <div className=\"a\">{count}</div>;\n"),
        ("py", "python", "def total(items):\n    \"\"\"Sum.\"\"\"\n    return sum(items)\n"),
        ("sh", "bash", "for f in *.txt; do\n  echo \"$f\"\ndone\n"),
        ("zsh", "bash", "if [ -f \"$HOME/.zshrc\" ]; then source \"$HOME/.zshrc\"; fi\n"),
        ("ts", "typescript", "interface Point { x: number; y: number }\nconst p: Point = { x: 1, y: 2 };\n"),
        ("yml", "yaml", "name: build\non: [push]\njobs:\n  test:\n    runs-on: ubuntu-latest\n"),
        ("rs", "rust", "fn main() {\n    let v: Vec<i32> = Vec::new();\n    println!(\"{:?}\", v);\n}\n"),
        ("c++", "cpp", "#include <vector>\nint main() { std::vector<int> v; return v.size(); }\n"),
        ("rb", "ruby", "def total(items)\n  items.sum\nend\n"),
        ("kt", "kotlin", "fun main() {\n    val xs = listOf(1, 2, 3)\n    println(xs.sum())\n}\n"),
    ]

    @Test("A short fence name highlights like the language it stands for")
    func aliasesHighlightLikeTheirLanguage() throws {
        for sample in Self.samples {
            let viaAlias = try #require(
                CodeHighlighter.attributedString(for: sample.code, language: sample.alias, theme: "xcode"),
                "\(sample.alias)"
            )
            let viaName = try #require(
                CodeHighlighter.attributedString(for: sample.code, language: sample.canonical, theme: "xcode"),
                "\(sample.canonical)"
            )
            #expect(String(viaAlias.characters) == sample.code, "\(sample.alias) keeps the text")
            #expect(viaAlias.runs.count > 1, "\(sample.alias) is coloured")
            #expect(viaAlias == viaName, "\(sample.alias) should colour like \(sample.canonical)")
        }
    }

    @Test("A short name is not sent to auto-detection, which reads this JavaScript as another grammar")
    func aliasIsNotAutoDetected() throws {
        let code = "const a = 1;\nconsole.log(a);\n"
        let viaAlias = try #require(CodeHighlighter.attributedString(for: code, language: "js", theme: "xcode"))
        let auto = try #require(CodeHighlighter.attributedString(for: code, language: nil, theme: "xcode"))
        #expect(viaAlias != auto)
    }

    @Test("A name highlight.js does not know falls back to auto-detection, and still colours")
    func unknownNameFallsBack() throws {
        let code = "def total(items):\n    return sum(items)\n"
        let highlighted = try #require(
            CodeHighlighter.attributedString(for: code, language: "not-a-language", theme: "xcode")
        )
        #expect(String(highlighted.characters) == code)
    }

    // MARK: Half-streamed code

    @Test("Code cut mid-token keeps its colour")
    func illegalTokenKeepsColour() throws {
        // An unterminated Python string is "illegal" to highlight.js, which at its strict setting
        // returns the whole block uncoloured (one run).
        let code = "def greet(name):\n    message = \"hello, \n    return"
        let highlighted = try #require(
            CodeHighlighter.attributedString(for: code, language: "python", theme: "xcode")
        )
        #expect(String(highlighted.characters) == code)
        #expect(highlighted.runs.count > 1)
    }

    // MARK: Cache

    private final class RenderCounter {
        var count = 0
        func render(_ code: String, _: String?, _ theme: String) -> AttributedString? {
            count += 1
            return AttributedString("\(theme):\(code)")
        }
    }

    @Test("The same block is rendered once and served from the cache after")
    func sameBlockRendersOnce() throws {
        let code = "let cached = \(UUID())\n"
        let counter = RenderCounter()
        let first = try #require(
            CodeHighlighter.attributedString(for: code, language: "swift", theme: "xcode", renderer: counter.render))
        let second = try #require(
            CodeHighlighter.attributedString(for: code, language: "swift", theme: "xcode", renderer: counter.render))
        #expect(first == second)
        #expect(counter.count == 1)
        // Another theme or language is another entry.
        _ = CodeHighlighter.attributedString(for: code, language: "swift", theme: "dark", renderer: counter.render)
        _ = CodeHighlighter.attributedString(for: code, language: nil, theme: "xcode", renderer: counter.render)
        #expect(counter.count == 3)
    }

    @Test("Text that differs only in Unicode normalization is not served from the other's entry")
    func canonicallyEquivalentCodeIsNotConflated() throws {
        let tag = UUID().uuidString
        let composed = "\"caf\u{00E9}\" // \(tag)\n"
        let decomposed = "\"cafe\u{0301}\" // \(tag)\n"
        #expect(composed == decomposed)  // Swift treats these as equal strings
        #expect(!composed.utf8.elementsEqual(decomposed.utf8))
        let counter = RenderCounter()
        let a = try #require(
            CodeHighlighter.attributedString(for: composed, language: "swift", theme: "xcode", renderer: counter.render))
        let b = try #require(
            CodeHighlighter.attributedString(for: decomposed, language: "swift", theme: "xcode", renderer: counter.render))
        #expect(counter.count == 2)
        #expect(String(a.characters).utf8.elementsEqual("xcode:\(composed)".utf8))
        #expect(String(b.characters).utf8.elementsEqual("xcode:\(decomposed)".utf8))
    }
}
#endif
