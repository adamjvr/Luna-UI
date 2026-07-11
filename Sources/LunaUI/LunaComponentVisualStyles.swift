// SPDX-License-Identifier: MPL-2.0
// LunaComponentVisualStyles.swift
//
// Phase 2E: render-ready style snapshots for Luna's themeable UI
// surfaces. These do not implement menus/tabs/sidebars yet; they lock the
// token boundary so future widgets consume theme variables instead of inventing
// hardcoded colors one component at a time.

import Foundation
import LunaRender
import LunaTheme

public struct LunaChromeVisualStyle: Hashable, Sendable {
    public var titleBarBackground: LunaRender.LunaRGBA8
    public var titleBarForeground: LunaRender.LunaRGBA8
    public var menuBarBackground: LunaRender.LunaRGBA8
    public var menuBarForeground: LunaRender.LunaRGBA8
    public var menuBarHoveredBackground: LunaRender.LunaRGBA8
    public var menuBarActiveForeground: LunaRender.LunaRGBA8
    public var menuBarActiveUnderline: LunaRender.LunaRGBA8
    public var tabStripBackground: LunaRender.LunaRGBA8
    public var separator: LunaRender.LunaRGBA8
    public var windowBorder: LunaRender.LunaRGBA8

    public init(theme: LunaTheme) {
        let c = theme.ui.chrome
        self.titleBarBackground = c.titleBarBackground.asRenderColor
        self.titleBarForeground = c.titleBarForeground.asRenderColor
        self.menuBarBackground = c.menuBarBackground.asRenderColor
        self.menuBarForeground = c.menuBarForeground.asRenderColor
        self.menuBarHoveredBackground = c.menuBarHoveredBackground.asRenderColor
        self.menuBarActiveForeground = c.menuBarActiveForeground.asRenderColor
        self.menuBarActiveUnderline = c.menuBarActiveUnderline.asRenderColor
        self.tabStripBackground = c.tabStripBackground.asRenderColor
        self.separator = c.separator.asRenderColor
        self.windowBorder = c.windowBorder.asRenderColor
    }
}

public struct LunaEditorVisualStyle: Hashable, Sendable {
    public var background: LunaRender.LunaRGBA8
    public var foreground: LunaRender.LunaRGBA8
    public var gutterBackground: LunaRender.LunaRGBA8
    public var gutterForeground: LunaRender.LunaRGBA8
    public var currentLineBackground: LunaRender.LunaRGBA8
    public var selectionBackground: LunaRender.LunaRGBA8
    public var caret: LunaRender.LunaRGBA8
    public var invisibles: LunaRender.LunaRGBA8
    public var minimapBackground: LunaRender.LunaRGBA8
    public var minimapViewport: LunaRender.LunaRGBA8
    public var scrollbarTrack: LunaRender.LunaRGBA8
    public var scrollbarThumb: LunaRender.LunaRGBA8

    public init(theme: LunaTheme) {
        let e = theme.ui.editor
        self.background = e.background.asRenderColor
        self.foreground = e.foreground.asRenderColor
        self.gutterBackground = e.gutterBackground.asRenderColor
        self.gutterForeground = e.gutterForeground.asRenderColor
        self.currentLineBackground = e.currentLineBackground.asRenderColor
        self.selectionBackground = e.selectionBackground.asRenderColor
        self.caret = e.caret.asRenderColor
        self.invisibles = e.invisibles.asRenderColor
        self.minimapBackground = e.minimapBackground.asRenderColor
        self.minimapViewport = e.minimapViewport.asRenderColor
        self.scrollbarTrack = e.scrollbarTrack.asRenderColor
        self.scrollbarThumb = e.scrollbarThumb.asRenderColor
    }
}

public struct LunaMenuVisualStyle: Hashable, Sendable {
    public var background: LunaRender.LunaRGBA8
    public var border: LunaRender.LunaRGBA8
    public var rowForeground: LunaRender.LunaRGBA8
    public var rowMutedForeground: LunaRender.LunaRGBA8
    public var rowDisabledForeground: LunaRender.LunaRGBA8
    public var rowHoveredBackground: LunaRender.LunaRGBA8
    public var rowHoveredForeground: LunaRender.LunaRGBA8
    public var rowPressedBackground: LunaRender.LunaRGBA8
    public var shortcutForeground: LunaRender.LunaRGBA8
    public var separator: LunaRender.LunaRGBA8
    public var checkedMark: LunaRender.LunaRGBA8
    public var submenuArrow: LunaRender.LunaRGBA8

    public init(theme: LunaTheme) {
        let m = theme.ui.menu
        self.background = m.background.asRenderColor
        self.border = m.border.asRenderColor
        self.rowForeground = m.rowForeground.asRenderColor
        self.rowMutedForeground = m.rowMutedForeground.asRenderColor
        self.rowDisabledForeground = m.rowDisabledForeground.asRenderColor
        self.rowHoveredBackground = m.rowHoveredBackground.asRenderColor
        self.rowHoveredForeground = m.rowHoveredForeground.asRenderColor
        self.rowPressedBackground = m.rowPressedBackground.asRenderColor
        self.shortcutForeground = m.shortcutForeground.asRenderColor
        self.separator = m.separator.asRenderColor
        self.checkedMark = m.checkedMark.asRenderColor
        self.submenuArrow = m.submenuArrow.asRenderColor
    }
}

public struct LunaPanelVisualStyle: Hashable, Sendable {
    public var background: LunaRender.LunaRGBA8
    public var border: LunaRender.LunaRGBA8
    public var titleBackground: LunaRender.LunaRGBA8
    public var titleForeground: LunaRender.LunaRGBA8
    public var bodyForeground: LunaRender.LunaRGBA8
    public var mutedForeground: LunaRender.LunaRGBA8
    public var overlayBackdrop: LunaRender.LunaRGBA8
    public var selectedRowBackground: LunaRender.LunaRGBA8
    public var selectedRowForeground: LunaRender.LunaRGBA8
    public var shadow: LunaRender.LunaRGBA8

    public init(theme: LunaTheme) {
        let p = theme.ui.panel
        self.background = p.background.asRenderColor
        self.border = p.border.asRenderColor
        self.titleBackground = p.titleBackground.asRenderColor
        self.titleForeground = p.titleForeground.asRenderColor
        self.bodyForeground = p.bodyForeground.asRenderColor
        self.mutedForeground = p.mutedForeground.asRenderColor
        self.overlayBackdrop = p.overlayBackdrop.asRenderColor
        self.selectedRowBackground = p.selectedRowBackground.asRenderColor
        self.selectedRowForeground = p.selectedRowForeground.asRenderColor
        self.shadow = p.shadow.asRenderColor
    }
}

public struct LunaTextFieldVisualStyle: Hashable, Sendable {
    public var background: LunaRender.LunaRGBA8
    public var border: LunaRender.LunaRGBA8
    public var focusedBorder: LunaRender.LunaRGBA8
    public var foreground: LunaRender.LunaRGBA8
    public var placeholderForeground: LunaRender.LunaRGBA8
    public var selectionBackground: LunaRender.LunaRGBA8

    public init(theme: LunaTheme) {
        let f = theme.ui.textField
        self.background = f.background.asRenderColor
        self.border = f.border.asRenderColor
        self.focusedBorder = f.focusedBorder.asRenderColor
        self.foreground = f.foreground.asRenderColor
        self.placeholderForeground = f.placeholderForeground.asRenderColor
        self.selectionBackground = f.selectionBackground.asRenderColor
    }
}

public struct LunaTabVisualStyle: Hashable, Sendable {
    public var stripBackground: LunaRender.LunaRGBA8
    public var activeBackground: LunaRender.LunaRGBA8
    public var inactiveBackground: LunaRender.LunaRGBA8
    public var hoveredBackground: LunaRender.LunaRGBA8
    public var activeForeground: LunaRender.LunaRGBA8
    public var inactiveForeground: LunaRender.LunaRGBA8
    public var dirtyIndicator: LunaRender.LunaRGBA8
    public var closeButton: LunaRender.LunaRGBA8
    public var divider: LunaRender.LunaRGBA8

    public init(theme: LunaTheme) {
        let t = theme.ui.tabs
        self.stripBackground = t.stripBackground.asRenderColor
        self.activeBackground = t.activeBackground.asRenderColor
        self.inactiveBackground = t.inactiveBackground.asRenderColor
        self.hoveredBackground = t.hoveredBackground.asRenderColor
        self.activeForeground = t.activeForeground.asRenderColor
        self.inactiveForeground = t.inactiveForeground.asRenderColor
        self.dirtyIndicator = t.dirtyIndicator.asRenderColor
        self.closeButton = t.closeButton.asRenderColor
        self.divider = t.divider.asRenderColor
    }
}

public struct LunaSidebarVisualStyle: Hashable, Sendable {
    public var background: LunaRender.LunaRGBA8
    public var sectionForeground: LunaRender.LunaRGBA8
    public var rowForeground: LunaRender.LunaRGBA8
    public var rowMutedForeground: LunaRender.LunaRGBA8
    public var rowHoveredBackground: LunaRender.LunaRGBA8
    public var rowSelectedBackground: LunaRender.LunaRGBA8
    public var rowSelectedForeground: LunaRender.LunaRGBA8
    public var disclosureForeground: LunaRender.LunaRGBA8
    public var border: LunaRender.LunaRGBA8

    public init(theme: LunaTheme) {
        let s = theme.ui.sidebar
        self.background = s.background.asRenderColor
        self.sectionForeground = s.sectionForeground.asRenderColor
        self.rowForeground = s.rowForeground.asRenderColor
        self.rowMutedForeground = s.rowMutedForeground.asRenderColor
        self.rowHoveredBackground = s.rowHoveredBackground.asRenderColor
        self.rowSelectedBackground = s.rowSelectedBackground.asRenderColor
        self.rowSelectedForeground = s.rowSelectedForeground.asRenderColor
        self.disclosureForeground = s.disclosureForeground.asRenderColor
        self.border = s.border.asRenderColor
    }
}

public struct LunaStatusBarVisualStyle: Hashable, Sendable {
    public var background: LunaRender.LunaRGBA8
    public var foreground: LunaRender.LunaRGBA8
    public var mutedForeground: LunaRender.LunaRGBA8
    public var accent: LunaRender.LunaRGBA8
    public var border: LunaRender.LunaRGBA8

    public init(theme: LunaTheme) {
        let s = theme.ui.statusBar
        self.background = s.background.asRenderColor
        self.foreground = s.foreground.asRenderColor
        self.mutedForeground = s.mutedForeground.asRenderColor
        self.accent = s.accent.asRenderColor
        self.border = s.border.asRenderColor
    }
}

public struct LunaThemeVisualStyles: Hashable, Sendable {
    public var chrome: LunaChromeVisualStyle
    public var editor: LunaEditorVisualStyle
    public var menu: LunaMenuVisualStyle
    public var panel: LunaPanelVisualStyle
    public var textField: LunaTextFieldVisualStyle
    public var tabs: LunaTabVisualStyle
    public var sidebar: LunaSidebarVisualStyle
    public var statusBar: LunaStatusBarVisualStyle
    public var controls: LunaControlVisualStyle

    public init(theme: LunaTheme) {
        self.chrome = LunaChromeVisualStyle(theme: theme)
        self.editor = LunaEditorVisualStyle(theme: theme)
        self.menu = LunaMenuVisualStyle(theme: theme)
        self.panel = LunaPanelVisualStyle(theme: theme)
        self.textField = LunaTextFieldVisualStyle(theme: theme)
        self.tabs = LunaTabVisualStyle(theme: theme)
        self.sidebar = LunaSidebarVisualStyle(theme: theme)
        self.statusBar = LunaStatusBarVisualStyle(theme: theme)
        self.controls = LunaControlVisualStyle(theme: theme)
    }
}
