// LunaControlVisualStyle.swift
//
// Phase 2B/2C: shared interaction-state and default control palette.
//
// Phase 2B proved hover/press/focus states. Phase 2C moves the palette onto
// LunaTheme color tokens so Moth Text can supply exact hex-driven colors
// without inheriting demo colors.

import Foundation
import LunaRender
import LunaTheme

/// Platform-neutral interaction state for controls, menu rows, modal choices,
/// quick-panel rows, and future editor chrome widgets.
public enum LunaControlInteractionState: String, Hashable, Sendable {
    case normal
    case hovered
    case pressed
    case focused
    case selected
    case disabled
}

/// Sublime/Moth-shaped control colors for Luna widgets and overlays.
///
/// This struct stores render-ready colors because it is consumed directly by
/// display-list builders. It can be created from `LunaControlColorSet`, whose
/// values are app/theme supplied and can be defined with hex strings.
public struct LunaMothDefaultDarkControlStyle: Hashable, Sendable {
    public var overlayBackdrop: LunaRender.LunaRGBA8
    public var panelBackground: LunaRender.LunaRGBA8
    public var panelBorder: LunaRender.LunaRGBA8
    public var titleBackground: LunaRender.LunaRGBA8
    public var fieldBackground: LunaRender.LunaRGBA8
    public var fieldBorder: LunaRender.LunaRGBA8

    public var controlNormal: LunaRender.LunaRGBA8
    public var controlHovered: LunaRender.LunaRGBA8
    public var controlPressed: LunaRender.LunaRGBA8
    public var controlFocused: LunaRender.LunaRGBA8
    public var controlSelected: LunaRender.LunaRGBA8
    public var controlDisabled: LunaRender.LunaRGBA8

    public var text: LunaRender.LunaRGBA8
    public var mutedText: LunaRender.LunaRGBA8
    public var disabledText: LunaRender.LunaRGBA8
    public var selectedText: LunaRender.LunaRGBA8
    public var accent: LunaRender.LunaRGBA8
    public var accentStrong: LunaRender.LunaRGBA8

    public init(
        overlayBackdrop: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 22, g: 26, b: 31, a: 235),
        panelBackground: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 38, g: 42, b: 48, a: 255),
        panelBorder: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 20, g: 22, b: 26, a: 255),
        titleBackground: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 47, g: 52, b: 59, a: 255),
        fieldBackground: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 45, g: 50, b: 58, a: 255),
        fieldBorder: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 24, g: 26, b: 30, a: 255),
        controlNormal: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 48, g: 53, b: 61, a: 255),
        controlHovered: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 78, g: 87, b: 99, a: 255),
        controlPressed: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 33, g: 37, b: 43, a: 255),
        controlFocused: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 63, g: 72, b: 83, a: 255),
        controlSelected: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 134, g: 232, b: 229, a: 255),
        controlDisabled: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 38, g: 41, b: 46, a: 255),
        text: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 232, g: 236, b: 240, a: 255),
        mutedText: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 184, g: 191, b: 198, a: 255),
        disabledText: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 122, g: 128, b: 136, a: 255),
        selectedText: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 22, g: 30, b: 34, a: 255),
        accent: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 118, g: 206, b: 203, a: 255),
        accentStrong: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 148, g: 240, b: 237, a: 255)
    ) {
        self.overlayBackdrop = overlayBackdrop
        self.panelBackground = panelBackground
        self.panelBorder = panelBorder
        self.titleBackground = titleBackground
        self.fieldBackground = fieldBackground
        self.fieldBorder = fieldBorder
        self.controlNormal = controlNormal
        self.controlHovered = controlHovered
        self.controlPressed = controlPressed
        self.controlFocused = controlFocused
        self.controlSelected = controlSelected
        self.controlDisabled = controlDisabled
        self.text = text
        self.mutedText = mutedText
        self.disabledText = disabledText
        self.selectedText = selectedText
        self.accent = accent
        self.accentStrong = accentStrong
    }

    public init(uiColors: LunaUIThemeColors) {
        let controls = uiColors.controlColors
        self.init(
            overlayBackdrop: uiColors.panel.overlayBackdrop.asRenderColor,
            panelBackground: uiColors.panel.background.asRenderColor,
            panelBorder: uiColors.panel.border.asRenderColor,
            titleBackground: uiColors.panel.titleBackground.asRenderColor,
            fieldBackground: uiColors.textField.background.asRenderColor,
            fieldBorder: uiColors.textField.border.asRenderColor,
            controlNormal: controls.normalBackground.asRenderColor,
            controlHovered: controls.hoveredBackground.asRenderColor,
            controlPressed: controls.pressedBackground.asRenderColor,
            controlFocused: controls.focusedBackground.asRenderColor,
            controlSelected: controls.selectedBackground.asRenderColor,
            controlDisabled: controls.disabledBackground.asRenderColor,
            text: controls.foreground.asRenderColor,
            mutedText: controls.mutedForeground.asRenderColor,
            disabledText: controls.disabledForeground.asRenderColor,
            selectedText: controls.selectedForeground.asRenderColor,
            accent: controls.accent.asRenderColor,
            accentStrong: controls.accentStrong.asRenderColor
        )
    }

    public init(theme: LunaTheme) {
        self.init(uiColors: theme.ui)
    }

    public static let `default` = LunaMothDefaultDarkControlStyle(theme: .mothDefaultDark)

    public func background(for state: LunaControlInteractionState) -> LunaRender.LunaRGBA8 {
        switch state {
        case .normal:
            return controlNormal
        case .hovered:
            return controlHovered
        case .pressed:
            return controlPressed
        case .focused:
            return controlFocused
        case .selected:
            return controlSelected
        case .disabled:
            return controlDisabled
        }
    }

    public func foreground(for state: LunaControlInteractionState) -> LunaRender.LunaRGBA8 {
        switch state {
        case .disabled:
            return disabledText
        case .selected:
            return selectedText
        default:
            return text
        }
    }
}

public extension LunaColor {
    /// Convert theme color data into the renderer's current display-list color.
    /// The conversion lives in LunaUI so LunaTheme stays renderer-independent.
    var asRenderColor: LunaRender.LunaRGBA8 {
        LunaRender.LunaRGBA8(r: r, g: g, b: b, a: a)
    }
}
