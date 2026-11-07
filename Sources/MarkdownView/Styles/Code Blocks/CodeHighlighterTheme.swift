//
//  CodeHighlighterTheme.swift
//  MarkdownView
//
//  Created by LiYanan2004 on 2025/3/25.
//

import Foundation
import SwiftUI

/// Code highlighting themes configuration for both light and dark mode.
///
/// - note: For more information, Check out [raspu/Highlightr](https://github.com/raspu/Highlightr).
public struct CodeHighlighterTheme: Hashable, Sendable {
    var lightModeThemeName: String
    var darkModeThemeName: String
    var lightModeColorOverrides: [CodeHighlighterColorOverride] = []
    var darkModeColorOverrides: [CodeHighlighterColorOverride] = []
    
    /// Creates a single theme for both light and dark mode.
    ///
    /// - Parameter themeName: the name of the theme to use in both Light Mode and Dark Mode.
    ///
    /// - warning: You should test the visibility of the code in Light Mode and Dark Mode first.
    public init(themeName: String) {
        lightModeThemeName = themeName
        darkModeThemeName = themeName
    }
    
    /// Creates a combination of two themes that will perfectly adapt both Light Mode and Dark Mode.
    ///
    /// - Parameters:
    ///   - lightModeThemeName: the name of the theme to use in Light Mode.
    ///   - darkModeThemeName: the name of the theme to use in Dark Mode.
    ///
    ///  If you want to use the same theme on both Dark Mode and Light Mode,
    ///  you should use ``init(themeName:)``.
    public init(lightModeThemeName: String, darkModeThemeName: String) {
        self.lightModeThemeName = lightModeThemeName
        self.darkModeThemeName = darkModeThemeName
    }

    /// Creates a combination of two themes, each with colours drawn as others.
    ///
    /// - Parameters:
    ///   - lightModeThemeName: the name of the theme to use in Light Mode.
    ///   - darkModeThemeName: the name of the theme to use in Dark Mode.
    ///   - lightModeColorOverrides: colours of the Light Mode theme drawn as others.
    ///   - darkModeColorOverrides: colours of the Dark Mode theme drawn as others.
    public init(
        lightModeThemeName: String,
        darkModeThemeName: String,
        lightModeColorOverrides: [CodeHighlighterColorOverride],
        darkModeColorOverrides: [CodeHighlighterColorOverride]
    ) {
        self.lightModeThemeName = lightModeThemeName
        self.darkModeThemeName = darkModeThemeName
        self.lightModeColorOverrides = lightModeColorOverrides
        self.darkModeColorOverrides = darkModeColorOverrides
    }
    
    func themeName(for colorScheme: ColorScheme) -> String {
        switch colorScheme {
        case .light:
            lightModeThemeName
        case .dark:
            darkModeThemeName
        @unknown default:
            lightModeThemeName
        }
    }

    func colorOverrides(for colorScheme: ColorScheme) -> [CodeHighlighterColorOverride] {
        switch colorScheme {
        case .light:
            lightModeColorOverrides
        case .dark:
            darkModeColorOverrides
        @unknown default:
            lightModeColorOverrides
        }
    }
}

extension CodeHighlighterTheme {
    static let `default` = CodeHighlighterTheme(lightModeThemeName: "xcode", darkModeThemeName: "dark")
}
