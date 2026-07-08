import XCTest
import LunaCore
import LunaRender
import LunaTheme
import LunaUI

final class LunaUIPhase2ETests: XCTestCase {
    func testDefaultDarkThemeExposesComponentTokenGroups() {
        let theme = LunaTheme.lunaDefaultDark

        XCTAssertEqual(theme.ui.editor.background.hexRGBA, "#2B333BFF")
        XCTAssertEqual(theme.ui.chrome.menuBarActiveUnderline.hexRGBA, "#76CECBFF")
        XCTAssertEqual(theme.ui.menu.rowHoveredBackground.hexRGBA, "#86E8E5FF")
        XCTAssertEqual(theme.ui.tabs.dirtyIndicator.hexRGBA, "#9ECF8BFF")
        XCTAssertEqual(theme.ui.sidebar.background.hexRGBA, "#1D242BFF")
        XCTAssertEqual(theme.ui.statusBar.background.hexRGBA, "#20262DFF")
    }

    func testComponentVisualStylesUseThemeTokens() {
        let theme = LunaTheme.lunaDefaultDark
        let styles = LunaThemeVisualStyles(theme: theme)

        XCTAssertEqual(styles.editor.background, theme.ui.editor.background.asRenderColor)
        XCTAssertEqual(styles.chrome.menuBarActiveUnderline, theme.ui.chrome.menuBarActiveUnderline.asRenderColor)
        XCTAssertEqual(styles.menu.rowHoveredBackground, theme.ui.menu.rowHoveredBackground.asRenderColor)
        XCTAssertEqual(styles.panel.background, theme.ui.panel.background.asRenderColor)
        XCTAssertEqual(styles.textField.focusedBorder, theme.ui.textField.focusedBorder.asRenderColor)
        XCTAssertEqual(styles.tabs.dirtyIndicator, theme.ui.tabs.dirtyIndicator.asRenderColor)
        XCTAssertEqual(styles.sidebar.rowSelectedBackground, theme.ui.sidebar.rowSelectedBackground.asRenderColor)
        XCTAssertEqual(styles.statusBar.accent, theme.ui.statusBar.accent.asRenderColor)
    }

    func testCustomThemeOverridesMenuAndEditorTokens() {
        var colors = LunaUIThemeColors.lunaDefaultDark
        colors.editor.background = .hex("#010203")
        colors.menu.rowHoveredBackground = .hex("#AA5500")
        colors.textField.focusedBorder = .hex("#123456")
        colors.statusBar.accent = .hex("#FEDCBA")

        let custom = LunaTheme(
            name: "Custom Theme Proof",
            background: colors.editor.background,
            foreground: colors.editor.foreground,
            caret: colors.editor.caret,
            selection: colors.editor.selectionBackground,
            ui: colors
        )

        let styles = LunaThemeVisualStyles(theme: custom)
        XCTAssertEqual(styles.editor.background, LunaRender.LunaRGBA8(r: 1, g: 2, b: 3, a: 255))
        XCTAssertEqual(styles.menu.rowHoveredBackground, LunaRender.LunaRGBA8(r: 170, g: 85, b: 0, a: 255))
        XCTAssertEqual(styles.textField.focusedBorder, LunaRender.LunaRGBA8(r: 18, g: 52, b: 86, a: 255))
        XCTAssertEqual(styles.statusBar.accent, LunaRender.LunaRGBA8(r: 254, g: 220, b: 186, a: 255))
    }

    func testSemanticWidgetUsesCustomControlThemeColors() {
        var colors = LunaUIThemeColors.lunaDefaultDark
        colors.controlColors.normalBackground = .hex("#112233")
        colors.controlColors.accent = .hex("#445566")
        colors.controlColors.focusedBorder = .hex("#778899")
        colors.controlColors.disabledBackground = .hex("#AABBCC")

        let custom = LunaTheme(
            name: "Widget Token Proof",
            background: colors.editor.background,
            foreground: colors.editor.foreground,
            caret: colors.editor.caret,
            selection: colors.editor.selectionBackground,
            ui: colors
        )

        let widget = LunaSemanticActionWidget(
            id: "phase2e.widget",
            bounds: LunaRectI(x: 0, y: 0, w: 120, h: 44),
            title: "Theme",
            primaryCommand: "luna.theme.proof",
            theme: custom
        )

        XCTAssertEqual(widget.backgroundColor, LunaRender.LunaRGBA8(r: 17, g: 34, b: 51, a: 255))
        XCTAssertEqual(widget.accentColor, LunaRender.LunaRGBA8(r: 68, g: 85, b: 102, a: 255))
        XCTAssertEqual(widget.focusColor, LunaRender.LunaRGBA8(r: 119, g: 136, b: 153, a: 255))
        XCTAssertEqual(widget.disabledOverlayColor, LunaRender.LunaRGBA8(r: 170, g: 187, b: 204, a: 255))
    }

    func testModalControlStyleUsesPanelAndTextFieldTokens() {
        var colors = LunaUIThemeColors.lunaDefaultDark
        colors.panel.background = .hex("#101112")
        colors.panel.border = .hex("#202122")
        colors.panel.titleBackground = .hex("#303132")
        colors.panel.overlayBackdrop = .hex("#40414280")
        colors.textField.background = .hex("#505152")
        colors.textField.border = .hex("#606162")

        let custom = LunaTheme(
            name: "Modal Token Proof",
            background: colors.editor.background,
            foreground: colors.editor.foreground,
            caret: colors.editor.caret,
            selection: colors.editor.selectionBackground,
            ui: colors
        )

        let style = LunaControlVisualStyle(theme: custom)
        XCTAssertEqual(style.panelBackground, LunaRender.LunaRGBA8(r: 16, g: 17, b: 18, a: 255))
        XCTAssertEqual(style.panelBorder, LunaRender.LunaRGBA8(r: 32, g: 33, b: 34, a: 255))
        XCTAssertEqual(style.titleBackground, LunaRender.LunaRGBA8(r: 48, g: 49, b: 50, a: 255))
        XCTAssertEqual(style.overlayBackdrop, LunaRender.LunaRGBA8(r: 64, g: 65, b: 66, a: 128))
        XCTAssertEqual(style.fieldBackground, LunaRender.LunaRGBA8(r: 80, g: 81, b: 82, a: 255))
        XCTAssertEqual(style.fieldBorder, LunaRender.LunaRGBA8(r: 96, g: 97, b: 98, a: 255))
    }

}
