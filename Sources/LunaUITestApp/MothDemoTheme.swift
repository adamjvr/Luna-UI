// MothDemoTheme.swift
//
// Demo-only product theme for LunaUITestApp.
//
// This file intentionally lives in the executable demo target, not in LunaTheme
// or LunaUI. Luna's library API stays product-neutral; this app merely proves
// that an application can supply its own exact color scheme through LunaTheme.

import LunaTheme

/// Demo-only Moth color scheme used by key 2 in LunaUITestApp.
///
/// This is not Luna public API. It is an application-supplied theme that proves
/// Luna can render Moth's obsidian/graphite direction without hardcoding that
/// product into the engine.
public enum MothDemoTheme {
    public static let themeName = "Moth Obsidian Demo"

    public enum Palette {
        /// Main/background black.
        public static let void = LunaColor.hex("#070709")

        /// First black layer above the void for panels/chrome/HUD.
        public static let base = LunaColor.hex("#131416")

        /// Raised graphite layer for controls, modal title strips, borders, and hover surfaces.
        public static let raised = LunaColor.hex("#242426")

        /// Slightly stronger neutral hover gray derived from the palette ramp.
        public static let hover = LunaColor.hex("#303034")

        /// Moth selection/focus/highlight blue. Keep this mostly out of sight until
        /// text selection, focused fields, and selected rows exist.
        public static let selectionBlue = LunaColor.hex("#003CFF")

        /// Muted light-gray text and UI marks.
        public static let text = LunaColor.hex("#888991")
    }

    /// Computed instead of cached so the demo always rebuilds from the palette
    /// constants when the executable target is recompiled. This keeps the Moth
    /// demo theme obviously separate from Luna's built-in demo-blue theme.
    public static var editor: LunaEditorColorSet {
        LunaEditorColorSet(
            background: Palette.void,
            foreground: Palette.text,
            gutterBackground: Palette.void,
            gutterForeground: LunaColor.hex("#888991CC"),
            currentLineBackground: Palette.base,
            selectionBackground: LunaColor.hex("#003CFFAA"),
            caret: Palette.text,
            invisibles: LunaColor.hex("#88899166"),
            minimapBackground: Palette.void,
            minimapViewport: LunaColor.hex("#88899166"),
            scrollbarTrack: Palette.void,
            scrollbarThumb: Palette.raised
        )
    }

    public static var chrome: LunaChromeColorSet {
        LunaChromeColorSet(
            titleBarBackground: Palette.base,
            titleBarForeground: Palette.text,
            menuBarBackground: Palette.base,
            menuBarForeground: Palette.text,
            menuBarHoveredBackground: Palette.raised,
            menuBarActiveForeground: Palette.text,
            menuBarActiveUnderline: Palette.selectionBlue,
            tabStripBackground: Palette.base,
            separator: Palette.raised,
            windowBorder: Palette.base
        )
    }

    public static var menu: LunaMenuColorSet {
        LunaMenuColorSet(
            background: Palette.base,
            border: Palette.raised,
            rowForeground: Palette.text,
            rowMutedForeground: LunaColor.hex("#888991CC"),
            rowDisabledForeground: LunaColor.hex("#88899177"),
            rowHoveredBackground: Palette.raised,
            rowHoveredForeground: Palette.text,
            rowPressedBackground: Palette.raised,
            shortcutForeground: LunaColor.hex("#888991CC"),
            separator: Palette.raised,
            checkedMark: Palette.text,
            submenuArrow: Palette.text
        )
    }

    public static var panel: LunaPanelColorSet {
        LunaPanelColorSet(
            background: Palette.base,
            border: Palette.raised,
            titleBackground: Palette.raised,
            titleForeground: Palette.text,
            bodyForeground: Palette.text,
            mutedForeground: LunaColor.hex("#888991CC"),
            overlayBackdrop: LunaColor.hex("#070709EE"),
            selectedRowBackground: Palette.raised,
            selectedRowForeground: Palette.text,
            shadow: LunaColor.hex("#07070988")
        )
    }

    public static var textField: LunaTextFieldColorSet {
        LunaTextFieldColorSet(
            background: Palette.void,
            border: Palette.raised,
            focusedBorder: Palette.selectionBlue,
            foreground: Palette.text,
            placeholderForeground: LunaColor.hex("#88899199"),
            selectionBackground: LunaColor.hex("#003CFFAA")
        )
    }

    public static var tabs: LunaTabColorSet {
        LunaTabColorSet(
            stripBackground: Palette.void,
            activeBackground: Palette.raised,
            inactiveBackground: Palette.base,
            hoveredBackground: Palette.raised,
            activeForeground: Palette.text,
            inactiveForeground: LunaColor.hex("#888991CC"),
            dirtyIndicator: Palette.text,
            closeButton: Palette.text,
            divider: Palette.void
        )
    }

    public static var sidebar: LunaSidebarColorSet {
        LunaSidebarColorSet(
            background: Palette.void,
            sectionForeground: Palette.text,
            rowForeground: Palette.text,
            rowMutedForeground: LunaColor.hex("#888991AA"),
            rowHoveredBackground: Palette.raised,
            rowSelectedBackground: Palette.raised,
            rowSelectedForeground: Palette.text,
            disclosureForeground: Palette.text,
            border: Palette.base
        )
    }

    public static var statusBar: LunaStatusBarColorSet {
        LunaStatusBarColorSet(
            background: Palette.void,
            foreground: Palette.text,
            mutedForeground: LunaColor.hex("#888991AA"),
            accent: Palette.selectionBlue,
            border: Palette.raised
        )
    }

    public static var diagnostics: LunaDiagnosticColorSet {
        LunaDiagnosticColorSet(
            info: Palette.selectionBlue,
            warning: Palette.text,
            error: Palette.text,
            success: Palette.selectionBlue,
            missingTokenFallback: LunaColor.hex("#FF00FF")
        )
    }

    public static var controls: LunaControlColorSet {
        LunaControlColorSet(
            normalBackground: Palette.base,
            hoveredBackground: Palette.raised,
            pressedBackground: Palette.void,
            focusedBackground: Palette.base,
            selectedBackground: Palette.selectionBlue,
            disabledBackground: Palette.void,
            foreground: Palette.text,
            mutedForeground: LunaColor.hex("#888991CC"),
            disabledForeground: LunaColor.hex("#88899177"),
            selectedForeground: Palette.text,
            border: Palette.raised,
            focusedBorder: Palette.selectionBlue,
            accent: Palette.selectionBlue,
            accentStrong: Palette.text
        )
    }

    public static var ui: LunaUIThemeColors {
        LunaUIThemeColors(
            windowBackground: Palette.void,
            editorBackground: editor.background,
            editorForeground: editor.foreground,
            chromeBackground: chrome.titleBarBackground,
            panelBackground: panel.background,
            panelBorder: panel.border,
            panelTitleBackground: panel.titleBackground,
            fieldBackground: textField.background,
            fieldBorder: textField.border,
            overlayBackdrop: panel.overlayBackdrop,
            movingBlock: Palette.base,
            movingBlockBorder: Palette.raised,
            hudBackground: Palette.base,
            statusText: Palette.text,
            controlColors: controls,
            editor: editor,
            chrome: chrome,
            menu: menu,
            panel: panel,
            textField: textField,
            tabs: tabs,
            sidebar: sidebar,
            statusBar: statusBar,
            diagnostics: diagnostics
        )
    }

    public static var theme: LunaTheme {
        LunaTheme(
            name: themeName,
            background: editor.background,
            foreground: editor.foreground,
            caret: editor.caret,
            selection: editor.selectionBackground,
            ui: ui
        )
    }

    public static func isMothDemoTheme(_ theme: LunaTheme) -> Bool {
        theme.name == themeName
    }

    /// Force the named demo theme back through the demo-local palette. If a host
    /// or a stale incremental build ever manages to hand us a theme named Moth
    /// with the wrong UI tokens, the visible demo still renders the palette that
    /// key 2 promises to show.
    public static func canonicalTheme(for theme: LunaTheme) -> LunaTheme {
        isMothDemoTheme(theme) ? Self.theme : theme
    }
}
