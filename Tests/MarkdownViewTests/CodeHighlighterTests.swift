//
//  CodeHighlighterTests.swift
//  MarkdownView
//

import CoreGraphics
import Foundation
import Testing

@testable import MarkdownView

#if os(macOS)
import AppKit
import SwiftUI
#endif

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
        func render(_ code: String, _: String?, _ theme: String, _: [CodeHighlighterColorOverride]) -> AttributedString? {
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
        // So are other colour overrides.
        let override = [CodeHighlighterColorOverride(0x6C7986, to: 0x8C98A5)]
        _ = CodeHighlighter.attributedString(
            for: code, language: "swift", theme: "xcode", colorOverrides: override, renderer: counter.render)
        _ = CodeHighlighter.attributedString(
            for: code, language: "swift", theme: "xcode", colorOverrides: override, renderer: counter.render)
        #expect(counter.count == 4)
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

    // MARK: Colour overrides

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func color(_ rgb: UInt32, alpha: CGFloat = 1, in space: CGColorSpace = sRGB) -> CGColor {
        let channel = { (shift: UInt32) in CGFloat((rgb >> shift) & 0xFF) / 255 }
        return CGColor(colorSpace: space, components: [channel(16), channel(8), channel(0), alpha])!
    }

    private static func rgb(_ color: CGColor) -> UInt32? {
        guard let c = color.components, c.count == 4 else { return nil }
        let byte = { (v: CGFloat) in UInt32((v * 255).rounded()) }
        return byte(c[0]) << 16 | byte(c[1]) << 8 | byte(c[2])
    }

    @Test("An override redraws its colour in the same colour space and alpha, and leaves others alone")
    func overrideReplacesOnlyItsColour() throws {
        let overrides = [
            CodeHighlighterColorOverride(0x6C7986, to: 0x8C98A5),
            CodeHighlighterColorOverride(0x41A1C0, to: 0x4EB0CF),
        ]
        let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let comment = try #require(
            CodeHighlighterColorOverride.replacement(for: Self.color(0x6C7986, alpha: 0.5, in: displayP3), in: overrides))
        #expect(Self.rgb(comment) == 0x8C98A5)
        #expect(comment.alpha == 0.5)
        #expect(comment.colorSpace?.name == displayP3.name)
        let number = try #require(CodeHighlighterColorOverride.replacement(for: Self.color(0x41A1C0), in: overrides))
        #expect(Self.rgb(number) == 0x4EB0CF)
        #expect(CodeHighlighterColorOverride.replacement(for: Self.color(0xFC5FA3), in: overrides) == nil)
        #expect(CodeHighlighterColorOverride.replacement(for: Self.color(0x6C7986), in: []) == nil)
        let gray = CGColor(gray: 0.5, alpha: 1)
        #expect(CodeHighlighterColorOverride.replacement(for: gray, in: overrides) == nil)
    }

    #if os(macOS)
    private struct CodeBlockStyleProbe: View {
        @Environment(\.codeBlockStyle) private var style
        let sink: (any MarkdownCodeBlockStyle) -> Void

        var body: some View {
            sink(style)
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    @available(*, deprecated, message: "Exercises the deprecated `.codeHighlighterTheme(_:)` modifier.")
    @MainActor
    private static func styleThroughDeprecatedThemeModifier(_ theme: CodeHighlighterTheme) -> (any MarkdownCodeBlockStyle)? {
        var seen: (any MarkdownCodeBlockStyle)?
        let renderer = ImageRenderer(content: CodeBlockStyleProbe { seen = $0 }.codeHighlighterTheme(theme))
        _ = renderer.nsImage
        return seen
    }

    @available(*, deprecated, message: "Exercises the deprecated `.codeHighlighterTheme(_:)` modifier.")
    @Test("The deprecated theme modifier keeps a theme's colour overrides")
    @MainActor
    func themeModifierKeepsOverrides() throws {
        let theme = CodeHighlighterTheme(
            lightModeThemeName: "xcode",
            darkModeThemeName: "xcode-dark",
            lightModeColorOverrides: [CodeHighlighterColorOverride(0x000000, to: 0x111111)],
            darkModeColorOverrides: [CodeHighlighterColorOverride(0x6C7986, to: 0x8C98A5)]
        )
        let style = try #require(Self.styleThroughDeprecatedThemeModifier(theme) as? DefaultCodeBlockStyle)
        #expect(style.highlighterTheme == theme)
        #expect(style.highlighterTheme.colorOverrides(for: .dark) == theme.darkModeColorOverrides)
        #expect(style.highlighterTheme.colorOverrides(for: .light) == theme.lightModeColorOverrides)
    }

    private static func foregroundColors(_ string: AttributedString) -> [String: UInt32] {
        var colors: [String: UInt32] = [:]
        for run in string.runs {
            guard let color = run.appKit.foregroundColor, let rgb = rgb(color.cgColor) else { continue }
            colors[String(string[run.range].characters), default: rgb] = rgb
        }
        return colors
    }

    @Test("A highlighted block draws the overridden theme colours, and only those")
    func highlightedBlockUsesOverrides() throws {
        let code = "// note \(UUID())\nlet n = 41\n"
        let overrides = [
            CodeHighlighterColorOverride(0x6C7986, to: 0x8C98A5),
            CodeHighlighterColorOverride(0x41A1C0, to: 0x4EB0CF),
        ]
        let plain = Self.foregroundColors(
            try #require(CodeHighlighter.attributedString(for: code, language: "swift", theme: "xcode-dark")))
        let recolored = Self.foregroundColors(
            try #require(
                CodeHighlighter.attributedString(
                    for: code, language: "swift", theme: "xcode-dark", colorOverrides: overrides)))
        let comment = try #require(plain.keys.first { $0.hasPrefix("// note") })
        #expect(plain[comment] == 0x6C7986)
        #expect(recolored[comment] == 0x8C98A5)
        #expect(plain["41"] == 0x41A1C0)
        #expect(recolored["41"] == 0x4EB0CF)
        #expect(plain["let"] != nil)
        #expect(recolored["let"] == plain["let"])
    }
    #endif
}
#endif
