// LunaTheme.swift
//
// LunaTheme is a standalone module so Luna-UI can expose theming as a public API
// and remain compatible with Sublime-style color schemes / themes.
//
// Phase 2C makes color customization explicit.  Luna widgets should not own
// hardcoded colors; applications such as Moth Text supply theme/color values.

import Foundation

// MARK: - Theme color primitive

/// Errors that can occur while parsing a hex color string.
public enum LunaColorHexError: Error, Equatable, Sendable {
    case empty
    case invalidLength(Int)
    case invalidCharacter(String)
}

/// Simple sRGBA 8-bit color used for theming.
///
/// Supported hex formats:
/// - `#RGB`
/// - `#RGBA`
/// - `#RRGGBB`
/// - `#RRGGBBAA`
///
/// The stored order is logical RGBA. Renderer backends can convert to their
/// native pixel layout as needed.
public struct LunaColor: Hashable, Sendable {
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

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.init(r: red, g: green, b: blue, a: alpha)
    }

    public init(hex rawValue: String) throws {
        var s = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s.removeFirst(2) }

        guard !s.isEmpty else { throw LunaColorHexError.empty }

        func nibble(_ scalar: UnicodeScalar) throws -> UInt8 {
            switch scalar.value {
            case 48...57:   return UInt8(scalar.value - 48)
            case 65...70:   return UInt8(scalar.value - 65 + 10)
            case 97...102:  return UInt8(scalar.value - 97 + 10)
            default:        throw LunaColorHexError.invalidCharacter(String(scalar))
            }
        }

        func byte(_ a: UnicodeScalar, _ b: UnicodeScalar) throws -> UInt8 {
            (try nibble(a) << 4) | (try nibble(b))
        }

        let scalars = Array(s.unicodeScalars)
        switch scalars.count {
        case 3:
            self.r = try nibble(scalars[0]) * 17
            self.g = try nibble(scalars[1]) * 17
            self.b = try nibble(scalars[2]) * 17
            self.a = 255
        case 4:
            self.r = try nibble(scalars[0]) * 17
            self.g = try nibble(scalars[1]) * 17
            self.b = try nibble(scalars[2]) * 17
            self.a = try nibble(scalars[3]) * 17
        case 6:
            self.r = try byte(scalars[0], scalars[1])
            self.g = try byte(scalars[2], scalars[3])
            self.b = try byte(scalars[4], scalars[5])
            self.a = 255
        case 8:
            self.r = try byte(scalars[0], scalars[1])
            self.g = try byte(scalars[2], scalars[3])
            self.b = try byte(scalars[4], scalars[5])
            self.a = try byte(scalars[6], scalars[7])
        default:
            throw LunaColorHexError.invalidLength(scalars.count)
        }
    }

    /// Non-throwing helper for constants and demos. Falls back instead of
    /// trapping because user-provided theme files should never crash the app.
    public static func hex(_ rawValue: String, fallback: LunaColor = LunaColor(r: 255, g: 0, b: 255, a: 255)) -> LunaColor {
        (try? LunaColor(hex: rawValue)) ?? fallback
    }

    public var hexRGBA: String {
        String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

/// Backward-compatible name used by earlier LunaTheme code.
public typealias LunaRGBA8 = LunaColor

// MARK: - UI color token sets

/// Generic control colors used by Luna widgets, modal choices, menu rows,
/// quick-panel rows, and future editor chrome controls.
public struct LunaControlColorSet: Hashable, Sendable {
    public var normalBackground: LunaColor
    public var hoveredBackground: LunaColor
    public var pressedBackground: LunaColor
    public var focusedBackground: LunaColor
    public var selectedBackground: LunaColor
    public var disabledBackground: LunaColor

    public var foreground: LunaColor
    public var mutedForeground: LunaColor
    public var disabledForeground: LunaColor
    public var selectedForeground: LunaColor

    public var border: LunaColor
    public var focusedBorder: LunaColor
    public var accent: LunaColor
    public var accentStrong: LunaColor

    public init(
        normalBackground: LunaColor,
        hoveredBackground: LunaColor,
        pressedBackground: LunaColor,
        focusedBackground: LunaColor,
        selectedBackground: LunaColor,
        disabledBackground: LunaColor,
        foreground: LunaColor,
        mutedForeground: LunaColor,
        disabledForeground: LunaColor,
        selectedForeground: LunaColor,
        border: LunaColor,
        focusedBorder: LunaColor,
        accent: LunaColor,
        accentStrong: LunaColor
    ) {
        self.normalBackground = normalBackground
        self.hoveredBackground = hoveredBackground
        self.pressedBackground = pressedBackground
        self.focusedBackground = focusedBackground
        self.selectedBackground = selectedBackground
        self.disabledBackground = disabledBackground
        self.foreground = foreground
        self.mutedForeground = mutedForeground
        self.disabledForeground = disabledForeground
        self.selectedForeground = selectedForeground
        self.border = border
        self.focusedBorder = focusedBorder
        self.accent = accent
        self.accentStrong = accentStrong
    }

    /// Default compact dark control palette, shaped by the Sublime screenshots
    /// supplied during the Luna/Moth design pass.
    public static let mothDefaultDark = LunaControlColorSet(
        normalBackground: .hex("#30353D"),
        hoveredBackground: .hex("#4E5763"),
        pressedBackground: .hex("#21252B"),
        focusedBackground: .hex("#3F4853"),
        selectedBackground: .hex("#86E8E5"),
        disabledBackground: .hex("#26292E"),
        foreground: .hex("#E8ECF0"),
        mutedForeground: .hex("#B8BFC6"),
        disabledForeground: .hex("#7A8088"),
        selectedForeground: .hex("#161E22"),
        border: .hex("#14161A"),
        focusedBorder: .hex("#76CECB"),
        accent: .hex("#76CECB"),
        accentStrong: .hex("#94F0ED")
    )
}

/// High-level UI tokens. Apps can replace this entire struct to give Luna a
/// project-specific appearance; Moth Text will supply its own values here.
public struct LunaUIThemeColors: Hashable, Sendable {
    public var windowBackground: LunaColor
    public var editorBackground: LunaColor
    public var editorForeground: LunaColor
    public var chromeBackground: LunaColor
    public var panelBackground: LunaColor
    public var panelBorder: LunaColor
    public var panelTitleBackground: LunaColor
    public var fieldBackground: LunaColor
    public var fieldBorder: LunaColor
    public var overlayBackdrop: LunaColor
    public var movingBlock: LunaColor
    public var movingBlockBorder: LunaColor
    public var hudBackground: LunaColor
    public var statusText: LunaColor
    public var controlColors: LunaControlColorSet

    public init(
        windowBackground: LunaColor,
        editorBackground: LunaColor,
        editorForeground: LunaColor,
        chromeBackground: LunaColor,
        panelBackground: LunaColor,
        panelBorder: LunaColor,
        panelTitleBackground: LunaColor,
        fieldBackground: LunaColor,
        fieldBorder: LunaColor,
        overlayBackdrop: LunaColor,
        movingBlock: LunaColor,
        movingBlockBorder: LunaColor,
        hudBackground: LunaColor,
        statusText: LunaColor,
        controlColors: LunaControlColorSet
    ) {
        self.windowBackground = windowBackground
        self.editorBackground = editorBackground
        self.editorForeground = editorForeground
        self.chromeBackground = chromeBackground
        self.panelBackground = panelBackground
        self.panelBorder = panelBorder
        self.panelTitleBackground = panelTitleBackground
        self.fieldBackground = fieldBackground
        self.fieldBorder = fieldBorder
        self.overlayBackdrop = overlayBackdrop
        self.movingBlock = movingBlock
        self.movingBlockBorder = movingBlockBorder
        self.hudBackground = hudBackground
        self.statusText = statusText
        self.controlColors = controlColors
    }

    public static let mothDefaultDark = LunaUIThemeColors(
        windowBackground: .hex("#161A1F"),
        editorBackground: .hex("#2B333B"),
        editorForeground: .hex("#D8DEE9"),
        chromeBackground: .hex("#2A2A2A"),
        panelBackground: .hex("#262A30"),
        panelBorder: .hex("#14161A"),
        panelTitleBackground: .hex("#2F343B"),
        fieldBackground: .hex("#2D323A"),
        fieldBorder: .hex("#181A1E"),
        overlayBackdrop: .hex("#161A1FEB"),
        movingBlock: .hex("#B9F5F2"),
        movingBlockBorder: .hex("#0A0A0A"),
        hudBackground: .hex("#080808"),
        statusText: .hex("#DCDCDC"),
        controlColors: .mothDefaultDark
    )
}

// MARK: - Theme object

/// Luna's theme object. It keeps the legacy editor colors while adding a
/// semantic UI token set for widgets, overlays, menus, and future Moth chrome.
public struct LunaTheme: Hashable, Sendable {

    /// Human-readable name (e.g., "Mariana", "Monokai", etc.)
    public var name: String

    /// Editor background.
    public var background: LunaColor

    /// Default foreground/text.
    public var foreground: LunaColor

    /// Caret color.
    public var caret: LunaColor

    /// Selection background.
    public var selection: LunaColor

    /// Semantic UI/control color tokens.
    public var ui: LunaUIThemeColors

    public init(
        name: String,
        background: LunaColor,
        foreground: LunaColor,
        caret: LunaColor,
        selection: LunaColor,
        ui: LunaUIThemeColors = .mothDefaultDark
    ) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.caret = caret
        self.selection = selection
        self.ui = ui
    }

    /// A sane default theme so the API can be used immediately.
    public static let `default` = LunaTheme(
        name: "Luna Default (Stub)",
        background: .hex("#121216"),
        foreground: .hex("#E6E6EB"),
        caret: .hex("#FFFFFF"),
        selection: .hex("#5078A0B4"),
        ui: .mothDefaultDark
    )

    /// Default Moth/Sublime-shaped dark UI theme. This is a default, not a
    /// hardcoded engine identity; Moth can replace every token.
    public static let mothDefaultDark = LunaTheme(
        name: "Moth Default Dark",
        background: .hex("#2B333B"),
        foreground: .hex("#D8DEE9"),
        caret: .hex("#FFFFFF"),
        selection: .hex("#43505C"),
        ui: .mothDefaultDark
    )
}
