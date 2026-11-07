//
//  CodeHighlighterColorOverride.swift
//  MarkdownView
//

import CoreGraphics

/// One colour of a highlighting theme drawn as another.
///
/// The bundled themes are CSS files inside Highlightr, so an app cannot ship an edited copy. An
/// override swaps one of a theme's colours for another after highlighting, for example to raise a
/// comment colour's contrast against the app's own code block background.
public struct CodeHighlighterColorOverride: Hashable, Sendable {
    /// The theme's colour, as `0xRRGGBB`.
    public var original: UInt32
    /// The colour drawn instead, as `0xRRGGBB`.
    public var replacement: UInt32

    /// Creates an override that draws `original` (`0xRRGGBB`) as `replacement`.
    public init(_ original: UInt32, to replacement: UInt32) {
        self.original = original
        self.replacement = replacement
    }

    /// `color` redrawn by the first override whose original it is, or `nil` when none matches.
    ///
    /// A colour matches when its red, green and blue components, read in its own colour space and
    /// rounded to 8 bits, equal the override's original. The replacement is built in that same
    /// space with the same alpha, so the override changes the theme's value and nothing else.
    public static func replacement(
        for color: CGColor,
        in overrides: [CodeHighlighterColorOverride]
    ) -> CGColor? {
        guard !overrides.isEmpty,
              let space = color.colorSpace, space.model == .rgb,
              let components = color.components, components.count == 4
        else { return nil }
        let byte = { (value: CGFloat) in UInt32((min(max(value, 0), 1) * 255).rounded()) }
        let rgb = byte(components[0]) << 16 | byte(components[1]) << 8 | byte(components[2])
        guard let match = overrides.first(where: { $0.original == rgb }) else { return nil }
        let channel = { (shift: UInt32) in CGFloat((match.replacement >> shift) & 0xFF) / 255 }
        return CGColor(colorSpace: space, components: [channel(16), channel(8), channel(0), components[3]])
    }
}
