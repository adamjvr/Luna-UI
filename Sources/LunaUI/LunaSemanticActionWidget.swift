// LunaSemanticActionWidget.swift
//
// Phase 1 proof widget.
//
// This is intentionally small, but it walks through the complete HybX-inspired
// Luna contract: stable identity, bounds, display output, hit testing,
// accessibility node generation, command intent, and UIContext side effects.

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaRender
import LunaTheme

/// Optional protocol for widgets that can directly request an application
/// command when activated.
///
/// Luna widgets should not execute app/editor policy. They should request a
/// command and let the application command table decide what that means.
public protocol LunaActionableWidget: LunaWidget {
    var primaryCommand: LunaCommandID { get }

    /// Activate the widget and queue the command through `LunaUIContext`.
    /// Returns the requested command when activation was accepted.
    @discardableResult
    mutating func activate(context: inout LunaUIContext) -> LunaCommandID?
}

/// A concrete semantic panel/button used to prove the Phase 1 widget contract.
///
/// It draws a simple panel using LunaRender display-list rectangles, exposes a
/// button-like accessibility node, hit-tests against its bounds, and queues a
/// typed command through LunaUIContext when activated.
public struct LunaSemanticActionWidget: LunaActionableWidget, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI
    public var title: String
    public var subtitle: String?
    public var primaryCommand: LunaCommandID
    public var isEnabled: Bool
    public var isFocused: Bool

    public var backgroundColor: LunaRender.LunaRGBA8
    public var accentColor: LunaRender.LunaRGBA8
    public var focusColor: LunaRender.LunaRGBA8
    public var disabledOverlayColor: LunaRender.LunaRGBA8

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        title: String,
        subtitle: String? = nil,
        primaryCommand: LunaCommandID,
        isEnabled: Bool = true,
        isFocused: Bool = false,
        backgroundColor: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 32, g: 36, b: 44, a: 255),
        accentColor: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 120, g: 170, b: 255, a: 255),
        focusColor: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 255, g: 255, b: 255, a: 255),
        disabledOverlayColor: LunaRender.LunaRGBA8 = LunaRender.LunaRGBA8(r: 0, g: 0, b: 0, a: 120)
    ) {
        self.id = id
        self.bounds = bounds
        self.title = title
        self.subtitle = subtitle
        self.primaryCommand = primaryCommand
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.backgroundColor = backgroundColor
        self.accentColor = accentColor
        self.focusColor = focusColor
        self.disabledOverlayColor = disabledOverlayColor
    }

    /// Convenience initializer that pulls default colors from a Luna theme.
    /// This proves the widget is connected to LunaTheme without making themes
    /// responsible for widget behavior.
    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        title: String,
        subtitle: String? = nil,
        primaryCommand: LunaCommandID,
        theme: LunaTheme,
        isEnabled: Bool = true,
        isFocused: Bool = false
    ) {
        self.init(
            id: id,
            bounds: bounds,
            title: title,
            subtitle: subtitle,
            primaryCommand: primaryCommand,
            isEnabled: isEnabled,
            isFocused: isFocused,
            backgroundColor: theme.ui.controlColors.normalBackground.asRenderColor,
            accentColor: theme.ui.controlColors.accent.asRenderColor,
            focusColor: theme.ui.controlColors.focusedBorder.asRenderColor,
            disabledOverlayColor: theme.ui.controlColors.disabledBackground.asRenderColor
        )
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        guard !bounds.isEmpty else { return }

        displayList.append(.rect(bounds, backgroundColor))

        let stripeWidth = min(max(3, bounds.w / 18), max(3, bounds.w))
        displayList.append(
            .rect(
                LunaRectI(x: bounds.x, y: bounds.y, w: stripeWidth, h: bounds.h),
                accentColor
            )
        )

        if isFocused {
            let t = min(2, max(1, bounds.w), max(1, bounds.h))
            displayList.append(.rect(LunaRectI(x: bounds.x, y: bounds.y, w: bounds.w, h: t), focusColor))
            displayList.append(.rect(LunaRectI(x: bounds.x, y: bounds.y + bounds.h - t, w: bounds.w, h: t), focusColor))
            displayList.append(.rect(LunaRectI(x: bounds.x, y: bounds.y, w: t, h: bounds.h), focusColor))
            displayList.append(.rect(LunaRectI(x: bounds.x + bounds.w - t, y: bounds.y, w: t, h: bounds.h), focusColor))
        }

        if !isEnabled {
            displayList.append(.rect(bounds, disabledOverlayColor))
        }
    }

    public func buildAccessibilityNode() -> LunaAccessibilityNode {
        LunaAccessibilityNode(
            id: id,
            role: .button,
            label: title,
            value: subtitle,
            bounds: bounds.asAccessibilityRect,
            isEnabled: isEnabled,
            isFocused: isFocused,
            actions: [.press, .focus]
        )
    }

    public func hitTest(_ point: LunaPointI) -> LunaNodeID? {
        bounds.contains(x: point.x, y: point.y) ? id : nil
    }

    @discardableResult
    public mutating func activate(context: inout LunaUIContext) -> LunaCommandID? {
        guard isEnabled else {
            context.announce("\(title) is disabled")
            return nil
        }

        context.requestCommand(primaryCommand)
        context.announce("\(title) activated")
        return primaryCommand
    }

}
