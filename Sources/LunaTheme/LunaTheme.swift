// SPDX-License-Identifier: MPL-2.0
// LunaTheme.swift
//
// LunaTheme is a standalone module so Luna-UI can expose theming as a public API
// and remain compatible with Sublime-style color schemes / themes.
//
// Phase 2E locks the visual style token surface down before Phase 3 text-view
// work. Luna widgets should not own hardcoded colors; applications supply
// theme/color values, including exact hex-driven schemes.

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


// MARK: - Component-specific token groups

public struct LunaEditorColorSet: Hashable, Sendable {
    public var background: LunaColor
    public var foreground: LunaColor
    public var gutterBackground: LunaColor
    public var gutterForeground: LunaColor
    public var currentLineBackground: LunaColor
    public var selectionBackground: LunaColor
    public var caret: LunaColor
    public var invisibles: LunaColor
    public var minimapBackground: LunaColor
    public var minimapViewport: LunaColor
    public var scrollbarTrack: LunaColor
    public var scrollbarThumb: LunaColor

    public init(
        background: LunaColor,
        foreground: LunaColor,
        gutterBackground: LunaColor,
        gutterForeground: LunaColor,
        currentLineBackground: LunaColor,
        selectionBackground: LunaColor,
        caret: LunaColor,
        invisibles: LunaColor,
        minimapBackground: LunaColor,
        minimapViewport: LunaColor,
        scrollbarTrack: LunaColor,
        scrollbarThumb: LunaColor
    ) {
        self.background = background
        self.foreground = foreground
        self.gutterBackground = gutterBackground
        self.gutterForeground = gutterForeground
        self.currentLineBackground = currentLineBackground
        self.selectionBackground = selectionBackground
        self.caret = caret
        self.invisibles = invisibles
        self.minimapBackground = minimapBackground
        self.minimapViewport = minimapViewport
        self.scrollbarTrack = scrollbarTrack
        self.scrollbarThumb = scrollbarThumb
    }

    public static let lunaDefaultDark = LunaEditorColorSet(
        background: .hex("#2B333B"),
        foreground: .hex("#D8DEE9"),
        gutterBackground: .hex("#263039"),
        gutterForeground: .hex("#7F8B99"),
        currentLineBackground: .hex("#34414D"),
        selectionBackground: .hex("#43505C"),
        caret: .hex("#FFFFFF"),
        invisibles: .hex("#55616E"),
        minimapBackground: .hex("#263039"),
        minimapViewport: .hex("#566271A8"),
        scrollbarTrack: .hex("#20262D"),
        scrollbarThumb: .hex("#6B7684")
    )

    public static let highContrastProof = LunaEditorColorSet(
        background: .hex("#090909"),
        foreground: .hex("#F8F8F2"),
        gutterBackground: .hex("#050505"),
        gutterForeground: .hex("#D0D0D0"),
        currentLineBackground: .hex("#222200"),
        selectionBackground: .hex("#FFCC00"),
        caret: .hex("#FFCC00"),
        invisibles: .hex("#808080"),
        minimapBackground: .hex("#050505"),
        minimapViewport: .hex("#FFCC0066"),
        scrollbarTrack: .hex("#000000"),
        scrollbarThumb: .hex("#FFCC00")
    )
}

public struct LunaChromeColorSet: Hashable, Sendable {
    public var titleBarBackground: LunaColor
    public var titleBarForeground: LunaColor
    public var menuBarBackground: LunaColor
    public var menuBarForeground: LunaColor
    public var menuBarHoveredBackground: LunaColor
    public var menuBarActiveForeground: LunaColor
    public var menuBarActiveUnderline: LunaColor
    public var tabStripBackground: LunaColor
    public var separator: LunaColor
    public var windowBorder: LunaColor

    public init(
        titleBarBackground: LunaColor,
        titleBarForeground: LunaColor,
        menuBarBackground: LunaColor,
        menuBarForeground: LunaColor,
        menuBarHoveredBackground: LunaColor,
        menuBarActiveForeground: LunaColor,
        menuBarActiveUnderline: LunaColor,
        tabStripBackground: LunaColor,
        separator: LunaColor,
        windowBorder: LunaColor
    ) {
        self.titleBarBackground = titleBarBackground
        self.titleBarForeground = titleBarForeground
        self.menuBarBackground = menuBarBackground
        self.menuBarForeground = menuBarForeground
        self.menuBarHoveredBackground = menuBarHoveredBackground
        self.menuBarActiveForeground = menuBarActiveForeground
        self.menuBarActiveUnderline = menuBarActiveUnderline
        self.tabStripBackground = tabStripBackground
        self.separator = separator
        self.windowBorder = windowBorder
    }

    public static let lunaDefaultDark = LunaChromeColorSet(
        titleBarBackground: .hex("#2D2D2D"),
        titleBarForeground: .hex("#E6E6E6"),
        menuBarBackground: .hex("#292929"),
        menuBarForeground: .hex("#C8C8C8"),
        menuBarHoveredBackground: .hex("#383D42"),
        menuBarActiveForeground: .hex("#A7F4F1"),
        menuBarActiveUnderline: .hex("#76CECB"),
        tabStripBackground: .hex("#56616C"),
        separator: .hex("#1B1B1B"),
        windowBorder: .hex("#111111")
    )
}

public struct LunaMenuColorSet: Hashable, Sendable {
    public var background: LunaColor
    public var border: LunaColor
    public var rowForeground: LunaColor
    public var rowMutedForeground: LunaColor
    public var rowDisabledForeground: LunaColor
    public var rowHoveredBackground: LunaColor
    public var rowHoveredForeground: LunaColor
    public var rowPressedBackground: LunaColor
    public var shortcutForeground: LunaColor
    public var separator: LunaColor
    public var checkedMark: LunaColor
    public var submenuArrow: LunaColor

    public init(
        background: LunaColor,
        border: LunaColor,
        rowForeground: LunaColor,
        rowMutedForeground: LunaColor,
        rowDisabledForeground: LunaColor,
        rowHoveredBackground: LunaColor,
        rowHoveredForeground: LunaColor,
        rowPressedBackground: LunaColor,
        shortcutForeground: LunaColor,
        separator: LunaColor,
        checkedMark: LunaColor,
        submenuArrow: LunaColor
    ) {
        self.background = background
        self.border = border
        self.rowForeground = rowForeground
        self.rowMutedForeground = rowMutedForeground
        self.rowDisabledForeground = rowDisabledForeground
        self.rowHoveredBackground = rowHoveredBackground
        self.rowHoveredForeground = rowHoveredForeground
        self.rowPressedBackground = rowPressedBackground
        self.shortcutForeground = shortcutForeground
        self.separator = separator
        self.checkedMark = checkedMark
        self.submenuArrow = submenuArrow
    }

    public static let lunaDefaultDark = LunaMenuColorSet(
        background: .hex("#282828"),
        border: .hex("#1B1B1B"),
        rowForeground: .hex("#D4D4D4"),
        rowMutedForeground: .hex("#A8A8A8"),
        rowDisabledForeground: .hex("#6E6E6E"),
        rowHoveredBackground: .hex("#86E8E5"),
        rowHoveredForeground: .hex("#142025"),
        rowPressedBackground: .hex("#6CCAC7"),
        shortcutForeground: .hex("#B7B7B7"),
        separator: .hex("#202020"),
        checkedMark: .hex("#F6A94B"),
        submenuArrow: .hex("#C6C6C6")
    )
}

public struct LunaPanelColorSet: Hashable, Sendable {
    public var background: LunaColor
    public var border: LunaColor
    public var titleBackground: LunaColor
    public var titleForeground: LunaColor
    public var bodyForeground: LunaColor
    public var mutedForeground: LunaColor
    public var overlayBackdrop: LunaColor
    public var selectedRowBackground: LunaColor
    public var selectedRowForeground: LunaColor
    public var shadow: LunaColor

    public init(
        background: LunaColor,
        border: LunaColor,
        titleBackground: LunaColor,
        titleForeground: LunaColor,
        bodyForeground: LunaColor,
        mutedForeground: LunaColor,
        overlayBackdrop: LunaColor,
        selectedRowBackground: LunaColor,
        selectedRowForeground: LunaColor,
        shadow: LunaColor
    ) {
        self.background = background
        self.border = border
        self.titleBackground = titleBackground
        self.titleForeground = titleForeground
        self.bodyForeground = bodyForeground
        self.mutedForeground = mutedForeground
        self.overlayBackdrop = overlayBackdrop
        self.selectedRowBackground = selectedRowBackground
        self.selectedRowForeground = selectedRowForeground
        self.shadow = shadow
    }

    public static let lunaDefaultDark = LunaPanelColorSet(
        background: .hex("#262A30"),
        border: .hex("#14161A"),
        titleBackground: .hex("#2F343B"),
        titleForeground: .hex("#F0F3F6"),
        bodyForeground: .hex("#E2E6EA"),
        mutedForeground: .hex("#B8BFC6"),
        overlayBackdrop: .hex("#161A1FEB"),
        selectedRowBackground: .hex("#525B66"),
        selectedRowForeground: .hex("#FFFFFF"),
        shadow: .hex("#00000088")
    )
}

public struct LunaTextFieldColorSet: Hashable, Sendable {
    public var background: LunaColor
    public var border: LunaColor
    public var focusedBorder: LunaColor
    public var foreground: LunaColor
    public var placeholderForeground: LunaColor
    public var selectionBackground: LunaColor

    public init(
        background: LunaColor,
        border: LunaColor,
        focusedBorder: LunaColor,
        foreground: LunaColor,
        placeholderForeground: LunaColor,
        selectionBackground: LunaColor
    ) {
        self.background = background
        self.border = border
        self.focusedBorder = focusedBorder
        self.foreground = foreground
        self.placeholderForeground = placeholderForeground
        self.selectionBackground = selectionBackground
    }

    public static let lunaDefaultDark = LunaTextFieldColorSet(
        background: .hex("#2D323A"),
        border: .hex("#181A1E"),
        focusedBorder: .hex("#F39C25"),
        foreground: .hex("#E8ECF0"),
        placeholderForeground: .hex("#8B949E"),
        selectionBackground: .hex("#43505C")
    )

    public static let highContrastProof = LunaTextFieldColorSet(
        background: .hex("#000000"),
        border: .hex("#FFCC00"),
        focusedBorder: .hex("#FFCC00"),
        foreground: .hex("#FFFFFF"),
        placeholderForeground: .hex("#D0D0D0"),
        selectionBackground: .hex("#FFCC00")
    )
}

public struct LunaTabColorSet: Hashable, Sendable {
    public var stripBackground: LunaColor
    public var activeBackground: LunaColor
    public var inactiveBackground: LunaColor
    public var hoveredBackground: LunaColor
    public var activeForeground: LunaColor
    public var inactiveForeground: LunaColor
    public var dirtyIndicator: LunaColor
    public var closeButton: LunaColor
    public var divider: LunaColor

    public init(
        stripBackground: LunaColor,
        activeBackground: LunaColor,
        inactiveBackground: LunaColor,
        hoveredBackground: LunaColor,
        activeForeground: LunaColor,
        inactiveForeground: LunaColor,
        dirtyIndicator: LunaColor,
        closeButton: LunaColor,
        divider: LunaColor
    ) {
        self.stripBackground = stripBackground
        self.activeBackground = activeBackground
        self.inactiveBackground = inactiveBackground
        self.hoveredBackground = hoveredBackground
        self.activeForeground = activeForeground
        self.inactiveForeground = inactiveForeground
        self.dirtyIndicator = dirtyIndicator
        self.closeButton = closeButton
        self.divider = divider
    }

    public static let lunaDefaultDark = LunaTabColorSet(
        stripBackground: .hex("#56616C"),
        activeBackground: .hex("#2B333B"),
        inactiveBackground: .hex("#56616C"),
        hoveredBackground: .hex("#626E7A"),
        activeForeground: .hex("#FFFFFF"),
        inactiveForeground: .hex("#C3CBD3"),
        dirtyIndicator: .hex("#9ECF8B"),
        closeButton: .hex("#9DA6B0"),
        divider: .hex("#35404A")
    )
}

public struct LunaSidebarColorSet: Hashable, Sendable {
    public var background: LunaColor
    public var sectionForeground: LunaColor
    public var rowForeground: LunaColor
    public var rowMutedForeground: LunaColor
    public var rowHoveredBackground: LunaColor
    public var rowSelectedBackground: LunaColor
    public var rowSelectedForeground: LunaColor
    public var disclosureForeground: LunaColor
    public var border: LunaColor

    public init(
        background: LunaColor,
        sectionForeground: LunaColor,
        rowForeground: LunaColor,
        rowMutedForeground: LunaColor,
        rowHoveredBackground: LunaColor,
        rowSelectedBackground: LunaColor,
        rowSelectedForeground: LunaColor,
        disclosureForeground: LunaColor,
        border: LunaColor
    ) {
        self.background = background
        self.sectionForeground = sectionForeground
        self.rowForeground = rowForeground
        self.rowMutedForeground = rowMutedForeground
        self.rowHoveredBackground = rowHoveredBackground
        self.rowSelectedBackground = rowSelectedBackground
        self.rowSelectedForeground = rowSelectedForeground
        self.disclosureForeground = disclosureForeground
        self.border = border
    }

    public static let lunaDefaultDark = LunaSidebarColorSet(
        background: .hex("#1D242B"),
        sectionForeground: .hex("#F0F3F6"),
        rowForeground: .hex("#C7D0D9"),
        rowMutedForeground: .hex("#8B949E"),
        rowHoveredBackground: .hex("#303943"),
        rowSelectedBackground: .hex("#3E4955"),
        rowSelectedForeground: .hex("#FFFFFF"),
        disclosureForeground: .hex("#9AA4AE"),
        border: .hex("#14191E")
    )
}

public struct LunaStatusBarColorSet: Hashable, Sendable {
    public var background: LunaColor
    public var foreground: LunaColor
    public var mutedForeground: LunaColor
    public var accent: LunaColor
    public var border: LunaColor

    public init(
        background: LunaColor,
        foreground: LunaColor,
        mutedForeground: LunaColor,
        accent: LunaColor,
        border: LunaColor
    ) {
        self.background = background
        self.foreground = foreground
        self.mutedForeground = mutedForeground
        self.accent = accent
        self.border = border
    }

    public static let lunaDefaultDark = LunaStatusBarColorSet(
        background: .hex("#20262D"),
        foreground: .hex("#D2D8DE"),
        mutedForeground: .hex("#9AA4AE"),
        accent: .hex("#76CECB"),
        border: .hex("#15191E")
    )
}

public struct LunaDiagnosticColorSet: Hashable, Sendable {
    public var info: LunaColor
    public var warning: LunaColor
    public var error: LunaColor
    public var success: LunaColor
    public var missingTokenFallback: LunaColor

    public init(info: LunaColor, warning: LunaColor, error: LunaColor, success: LunaColor, missingTokenFallback: LunaColor) {
        self.info = info
        self.warning = warning
        self.error = error
        self.success = success
        self.missingTokenFallback = missingTokenFallback
    }

    public static let lunaDefaultDark = LunaDiagnosticColorSet(
        info: .hex("#76CECB"),
        warning: .hex("#F6A94B"),
        error: .hex("#FF5F5F"),
        success: .hex("#9ECF8B"),
        missingTokenFallback: .hex("#FF00FF")
    )
}

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

    /// Default compact dark control palette, shaped by compact dark editor chrome.
    /// It is only a default; applications can replace every token.
    public static let lunaDefaultDark = LunaControlColorSet(
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
/// project-specific appearance; applications supply their own values here.
public struct LunaUIThemeColors: Hashable, Sendable {
    // Legacy broad tokens kept for source compatibility with earlier phases.
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

    // Phase 2E component-specific application UI tokens.
    public var editor: LunaEditorColorSet
    public var chrome: LunaChromeColorSet
    public var menu: LunaMenuColorSet
    public var panel: LunaPanelColorSet
    public var textField: LunaTextFieldColorSet
    public var tabs: LunaTabColorSet
    public var sidebar: LunaSidebarColorSet
    public var statusBar: LunaStatusBarColorSet
    public var diagnostics: LunaDiagnosticColorSet

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
        controlColors: LunaControlColorSet,
        editor: LunaEditorColorSet = .lunaDefaultDark,
        chrome: LunaChromeColorSet = .lunaDefaultDark,
        menu: LunaMenuColorSet = .lunaDefaultDark,
        panel: LunaPanelColorSet = .lunaDefaultDark,
        textField: LunaTextFieldColorSet = .lunaDefaultDark,
        tabs: LunaTabColorSet = .lunaDefaultDark,
        sidebar: LunaSidebarColorSet = .lunaDefaultDark,
        statusBar: LunaStatusBarColorSet = .lunaDefaultDark,
        diagnostics: LunaDiagnosticColorSet = .lunaDefaultDark
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
        self.editor = editor
        self.chrome = chrome
        self.menu = menu
        self.panel = panel
        self.textField = textField
        self.tabs = tabs
        self.sidebar = sidebar
        self.statusBar = statusBar
        self.diagnostics = diagnostics
    }

    public static let lunaDefaultDark = LunaUIThemeColors(
        windowBackground: .hex("#161A1F"),
        editorBackground: LunaEditorColorSet.lunaDefaultDark.background,
        editorForeground: LunaEditorColorSet.lunaDefaultDark.foreground,
        chromeBackground: LunaChromeColorSet.lunaDefaultDark.titleBarBackground,
        panelBackground: LunaPanelColorSet.lunaDefaultDark.background,
        panelBorder: LunaPanelColorSet.lunaDefaultDark.border,
        panelTitleBackground: LunaPanelColorSet.lunaDefaultDark.titleBackground,
        fieldBackground: LunaTextFieldColorSet.lunaDefaultDark.background,
        fieldBorder: LunaTextFieldColorSet.lunaDefaultDark.border,
        overlayBackdrop: LunaPanelColorSet.lunaDefaultDark.overlayBackdrop,
        movingBlock: .hex("#B9F5F2"),
        movingBlockBorder: .hex("#0A0A0A"),
        hudBackground: LunaChromeColorSet.lunaDefaultDark.titleBarBackground,
        statusText: LunaStatusBarColorSet.lunaDefaultDark.foreground,
        controlColors: .lunaDefaultDark,
        editor: .lunaDefaultDark,
        chrome: .lunaDefaultDark,
        menu: .lunaDefaultDark,
        panel: .lunaDefaultDark,
        textField: .lunaDefaultDark,
        tabs: .lunaDefaultDark,
        sidebar: .lunaDefaultDark,
        statusBar: .lunaDefaultDark,
        diagnostics: .lunaDefaultDark
    )

    /// Loud demo palette used only to prove theme swapping. This is *not* Luna's
    /// identity and should not be inherited by applications.
    public static let lunaDemoBlue = LunaUIThemeColors(
        windowBackground: .hex("#1218F2"),
        editorBackground: .hex("#1B25FF"),
        editorForeground: .hex("#FFFFFF"),
        chromeBackground: .hex("#080808"),
        panelBackground: .hex("#2C2AFF"),
        panelBorder: .hex("#A99CFF"),
        panelTitleBackground: .hex("#3A36FF"),
        fieldBackground: .hex("#302DFF"),
        fieldBorder: .hex("#C7BFFF"),
        overlayBackdrop: .hex("#1010A8F0"),
        movingBlock: .hex("#B9F5F2"),
        movingBlockBorder: .hex("#0A0A0A"),
        hudBackground: .hex("#0000EE"),
        statusText: .hex("#FFFFFF"),
        controlColors: LunaControlColorSet(
            normalBackground: .hex("#443CFF"),
            hoveredBackground: .hex("#5B52FF"),
            pressedBackground: .hex("#221DCC"),
            focusedBackground: .hex("#4E47FF"),
            selectedBackground: .hex("#B9F5F2"),
            disabledBackground: .hex("#1C1A99"),
            foreground: .hex("#FFFFFF"),
            mutedForeground: .hex("#D8D8FF"),
            disabledForeground: .hex("#9191CC"),
            selectedForeground: .hex("#080808"),
            border: .hex("#C7BFFF"),
            focusedBorder: .hex("#B9F5F2"),
            accent: .hex("#B9F5F2"),
            accentStrong: .hex("#FFFFFF")
        )
    )

    /// High-contrast token set used to prove every visible control pulls from
    /// replaceable theme variables. Not intended as final application styling.
    public static let highContrastProof = LunaUIThemeColors(
        windowBackground: .hex("#050505"),
        editorBackground: .hex("#090909"),
        editorForeground: .hex("#F8F8F2"),
        chromeBackground: .hex("#000000"),
        panelBackground: .hex("#111111"),
        panelBorder: .hex("#FFFFFF"),
        panelTitleBackground: .hex("#222222"),
        fieldBackground: .hex("#000000"),
        fieldBorder: .hex("#FFCC00"),
        overlayBackdrop: .hex("#000000F0"),
        movingBlock: .hex("#FFCC00"),
        movingBlockBorder: .hex("#FFFFFF"),
        hudBackground: .hex("#000000"),
        statusText: .hex("#FFCC00"),
        controlColors: LunaControlColorSet(
            normalBackground: .hex("#000000"),
            hoveredBackground: .hex("#333300"),
            pressedBackground: .hex("#663300"),
            focusedBackground: .hex("#111111"),
            selectedBackground: .hex("#FFCC00"),
            disabledBackground: .hex("#1A1A1A"),
            foreground: .hex("#FFFFFF"),
            mutedForeground: .hex("#D0D0D0"),
            disabledForeground: .hex("#808080"),
            selectedForeground: .hex("#000000"),
            border: .hex("#FFFFFF"),
            focusedBorder: .hex("#FFCC00"),
            accent: .hex("#FFCC00"),
            accentStrong: .hex("#FFFFFF")
        ),
        editor: .highContrastProof,
        textField: .highContrastProof
    )
}

// MARK: - Theme object

/// Luna's theme object. It keeps the legacy editor colors while adding a
/// semantic UI token set for widgets, overlays, menus, and future application chrome.
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
        ui: LunaUIThemeColors = .lunaDefaultDark
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
        ui: .lunaDefaultDark
    )

    /// Default compact dark UI theme. This is a default, not a
    /// hardcoded engine identity; applications can replace every token.
    public static let lunaDefaultDark = LunaTheme(
        name: "Luna Default Dark",
        background: LunaEditorColorSet.lunaDefaultDark.background,
        foreground: LunaEditorColorSet.lunaDefaultDark.foreground,
        caret: LunaEditorColorSet.lunaDefaultDark.caret,
        selection: LunaEditorColorSet.lunaDefaultDark.selectionBackground,
        ui: .lunaDefaultDark
    )

    /// Loud CPU-demo blue theme. Kept as an explicit demo/test theme to prove
    /// that the engine is themeable, not because Luna should look this way.
    public static let lunaDemoBlue = LunaTheme(
        name: "Luna CPU Demo Blue",
        background: .hex("#1218F2"),
        foreground: .hex("#FFFFFF"),
        caret: .hex("#FFFFFF"),
        selection: .hex("#B9F5F2"),
        ui: .lunaDemoBlue
    )

    /// High-contrast proof theme for manual and automated theme override tests.
    public static let highContrastProof = LunaTheme(
        name: "High Contrast Proof",
        background: .hex("#090909"),
        foreground: .hex("#F8F8F2"),
        caret: .hex("#FFCC00"),
        selection: .hex("#FFCC00"),
        ui: .highContrastProof
    )
}
