// LunaTheme.swift
//
// LunaTheme is a standalone module so Luna-UI can expose theming as a public API
// and remain compatible with Sublime-style color schemes / themes.
//
// This is a *stub* scaffold:
// - Enough to compile on macOS + Linux today.
// - Designed to evolve into a real Sublime theme/color-scheme loader.
//
// Roadmap for this module:
// - Parse .sublime-color-scheme (JSON) and .tmTheme (plist/XML)
// - Resolve scopes -> token colors
// - Provide "UI theme" values (tabs, sidebar, panel colors, etc.)

import Foundation

// MARK: - Theme primitives

/// Simple sRGBA 8-bit color used for theming.
///
/// Note:
/// - Renderer backends can convert this to linear/sRGB as needed.
/// - Keeping this in LunaTheme avoids coupling theme data to renderer internals.
public struct LunaRGBA8: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

/// A minimal theme object.
/// Today it only carries a few global colors.
/// Later it will contain:
/// - UI colors (tabs/sidebar/panels)
/// - text styles by scope
/// - font preferences and ligature toggles (though ligatures are Day-1 regardless)
public struct LunaTheme: Hashable, Sendable {

    /// Human-readable name (e.g., "Mariana", "Monokai", etc.)
    public var name: String

    /// Editor background.
    public var background: LunaRGBA8

    /// Default foreground/text.
    public var foreground: LunaRGBA8

    /// Caret color.
    public var caret: LunaRGBA8

    /// Selection background.
    public var selection: LunaRGBA8

    public init(
        name: String,
        background: LunaRGBA8,
        foreground: LunaRGBA8,
        caret: LunaRGBA8,
        selection: LunaRGBA8
    ) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.caret = caret
        self.selection = selection
    }

    /// A sane default theme so the API can be used immediately.
    public static let `default` = LunaTheme(
        name: "Luna Default (Stub)",
        background: LunaRGBA8(r: 18, g: 18, b: 22, a: 255),
        foreground: LunaRGBA8(r: 230, g: 230, b: 235, a: 255),
        caret: LunaRGBA8(r: 255, g: 255, b: 255, a: 255),
        selection: LunaRGBA8(r: 80, g: 120, b: 160, a: 180)
    )
}
