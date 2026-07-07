// LunaModalOverlay.swift
//
// Phase 2: overlay/modal runtime primitives.
//
// These types turn the typed LunaModalRequest values recorded in LunaUIContext
// into a concrete, semantic, drawable overlay.  They intentionally stay pure
// Swift and platform-neutral: SDL/AppKit/etc. only translate host events into
// LunaPointerEvent and then route them through this layer.

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaRender

// MARK: - Modal kind / choice models

/// The concrete presentation kind for an active Luna modal overlay.
public enum LunaModalKind: String, Hashable, Sendable {
    case prompt
    case list
    case confirm
    case notice
    case completion
}

/// One actionable row/button inside a modal overlay.
public struct LunaModalChoice: Hashable, Sendable {
    public var id: LunaNodeID
    public var label: String
    public var command: LunaCommandID?
    public var dismissesModal: Bool
    public var bounds: LunaRectI
    public var index: Int

    public init(
        id: LunaNodeID,
        label: String,
        command: LunaCommandID? = nil,
        dismissesModal: Bool = true,
        bounds: LunaRectI,
        index: Int
    ) {
        self.id = id
        self.label = label
        self.command = command
        self.dismissesModal = dismissesModal
        self.bounds = bounds
        self.index = index
    }
}

/// A concrete active overlay created from a typed modal request.
///
/// The overlay is a LunaWidget, so it can draw, hit-test, and expose an
/// accessibility subtree.  Text is currently represented semantically and drawn
/// in the demo by its tiny debug font until LunaDisplayList grows a real text
/// command.
public struct LunaModalOverlay: LunaWidget, Sendable {
    public var id: LunaNodeID
    public var kind: LunaModalKind
    public var title: String
    public var message: String?
    public var placeholder: String?
    public var initialText: String?
    public var anchor: LunaNodeID?

    /// Full overlay/backdrop bounds, usually the whole window.
    public var bounds: LunaRectI

    /// Center panel bounds.
    public var panelBounds: LunaRectI

    /// Actionable choices/buttons/list rows owned by the overlay.
    public var choices: [LunaModalChoice]

    /// Optional prompt field bounds.
    public var fieldBounds: LunaRectI?

    public var backdropColor: LunaRender.LunaRGBA8
    public var panelColor: LunaRender.LunaRGBA8
    public var titleColor: LunaRender.LunaRGBA8
    public var accentColor: LunaRender.LunaRGBA8
    public var choiceColor: LunaRender.LunaRGBA8
    public var fieldColor: LunaRender.LunaRGBA8

    public init(request: LunaModalRequest, viewportSize: LunaSizeI) {
        switch request {
        case .prompt(let request):
            self = Self.makePrompt(request, viewportSize: viewportSize)
        case .list(let request):
            self = Self.makeList(request, viewportSize: viewportSize)
        case .confirm(let request):
            self = Self.makeConfirm(request, viewportSize: viewportSize)
        case .notice(let request):
            self = Self.makeNotice(request, viewportSize: viewportSize)
        case .completion(let request):
            self = Self.makeCompletion(request, viewportSize: viewportSize)
        }
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        guard !bounds.isEmpty, !panelBounds.isEmpty else { return }

        // The CPU renderer is opaque for now, so this is a darkened solid
        // backdrop rather than true alpha compositing.  Keeping alpha in the
        // color still preserves intent for future renderers.
        displayList.append(.rect(bounds, backdropColor))
        displayList.append(.rect(panelBounds, panelColor))

        let titleBar = LunaRectI(x: panelBounds.x, y: panelBounds.y, w: panelBounds.w, h: min(38, panelBounds.h))
        displayList.append(.rect(titleBar, titleColor))

        let stripeW = min(6, max(3, panelBounds.w))
        displayList.append(.rect(LunaRectI(x: panelBounds.x, y: panelBounds.y, w: stripeW, h: panelBounds.h), accentColor))

        if let fieldBounds {
            displayList.append(.rect(fieldBounds, fieldColor))
        }

        for choice in choices {
            displayList.append(.rect(choice.bounds, choiceColor))
        }
    }

    public func buildAccessibilityNode() -> LunaAccessibilityNode {
        var children: [LunaNodeID] = []
        children.append(id.child("title"))

        if message != nil {
            children.append(id.child("message"))
        }

        if fieldBounds != nil {
            children.append(id.child("field"))
        }

        children.append(contentsOf: choices.map(\.id))

        return LunaAccessibilityNode(
            id: id,
            role: .dialog,
            label: title,
            value: message,
            bounds: panelBounds.asAccessibilityRect,
            isEnabled: true,
            isFocused: true,
            children: children,
            actions: [.focus]
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        var nodes: [LunaAccessibilityNode] = []

        nodes.append(
            LunaAccessibilityNode(
                id: id.child("title"),
                role: .textRun,
                label: title,
                bounds: LunaAccessibilityRect(
                    x: panelBounds.x + 16,
                    y: panelBounds.y + 8,
                    width: max(0, panelBounds.w - 32),
                    height: 24
                )
            )
        )

        if let message {
            nodes.append(
                LunaAccessibilityNode(
                    id: id.child("message"),
                    role: .textRun,
                    label: message,
                    bounds: LunaAccessibilityRect(
                        x: panelBounds.x + 18,
                        y: panelBounds.y + 48,
                        width: max(0, panelBounds.w - 36),
                        height: 32
                    )
                )
            )
        }

        if let fieldBounds {
            nodes.append(
                LunaAccessibilityNode(
                    id: id.child("field"),
                    role: .textArea,
                    label: placeholder,
                    value: initialText,
                    bounds: fieldBounds.asAccessibilityRect,
                    isEnabled: true,
                    isFocused: true,
                    actions: [.focus]
                )
            )
        }

        for choice in choices {
            let role: LunaAccessibilityRole
            switch kind {
            case .list, .completion:
                role = .listItem
            case .prompt, .confirm, .notice:
                role = .button
            }

            nodes.append(
                LunaAccessibilityNode(
                    id: choice.id,
                    role: role,
                    label: choice.label,
                    bounds: choice.bounds.asAccessibilityRect,
                    isEnabled: true,
                    actions: [.press, .focus]
                )
            )
        }

        return nodes
    }

    public func hitTest(_ point: LunaPointI) -> LunaNodeID? {
        for choice in choices where choice.bounds.contains(x: point.x, y: point.y) {
            return choice.id
        }

        if let fieldBounds, fieldBounds.contains(x: point.x, y: point.y) {
            return id.child("field")
        }

        if panelBounds.contains(x: point.x, y: point.y) {
            return id
        }

        // The manager still consumes background clicks while a modal is active,
        // but the overlay itself only reports semantic hits on the panel/owned
        // controls.
        return nil
    }

    public func choice(for nodeID: LunaNodeID) -> LunaModalChoice? {
        choices.first { $0.id == nodeID }
    }

    public func accessibilityTree() -> LunaAccessibilityTree {
        let root = buildAccessibilityNode()
        let children = buildAccessibilityChildren()
        var nodes: [LunaNodeID: LunaAccessibilityNode] = [root.id: root]
        for child in children {
            nodes[child.id] = child
        }
        return LunaAccessibilityTree(rootID: root.id, nodes: nodes)
    }
}

// MARK: - Overlay manager

/// Result of routing a pointer event through the active modal overlay.
public struct LunaModalInteractionResult: Hashable, Sendable {
    public var event: LunaPointerEvent
    public var activeModalID: LunaNodeID?
    public var hitNodeID: LunaNodeID?
    public var choiceIndex: Int?
    public var choiceLabel: String?
    public var requestedCommand: LunaCommandID?
    public var didDismiss: Bool
    public var didConsumeEvent: Bool

    public init(
        event: LunaPointerEvent,
        activeModalID: LunaNodeID?,
        hitNodeID: LunaNodeID?,
        choiceIndex: Int? = nil,
        choiceLabel: String? = nil,
        requestedCommand: LunaCommandID? = nil,
        didDismiss: Bool = false,
        didConsumeEvent: Bool = false
    ) {
        self.event = event
        self.activeModalID = activeModalID
        self.hitNodeID = hitNodeID
        self.choiceIndex = choiceIndex
        self.choiceLabel = choiceLabel
        self.requestedCommand = requestedCommand
        self.didDismiss = didDismiss
        self.didConsumeEvent = didConsumeEvent
    }
}

/// Owns the currently active modal overlay and converts queued LunaUIContext
/// modal requests into concrete overlay state.
public struct LunaModalOverlayManager: Sendable {
    public private(set) var active: LunaModalOverlay?

    public init(active: LunaModalOverlay? = nil) {
        self.active = active
    }

    public var hasActiveModal: Bool { active != nil }

    public mutating func dismissActive() {
        active = nil
    }

    @discardableResult
    public mutating func open(_ request: LunaModalRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let overlay = LunaModalOverlay(request: request, viewportSize: viewportSize)
        active = overlay
        return overlay
    }

    /// Drain queued requests from a UI context and open the newest one.
    ///
    /// Returning all opened overlays makes this testable and keeps the policy
    /// explicit: Luna currently supports one active modal at a time, so later
    /// requests replace earlier ones.
    @discardableResult
    public mutating func openQueuedModals(
        from context: inout LunaUIContext,
        viewportSize: LunaSizeI
    ) -> [LunaModalOverlay] {
        let requests = context.drainModalRequests()
        var opened: [LunaModalOverlay] = []
        for request in requests {
            opened.append(open(request, viewportSize: viewportSize))
        }
        return opened
    }

    /// Route a pointer event to the active overlay before the background/widget
    /// tree sees it.  If a modal exists, it consumes primary pointer-down events
    /// even when the click misses the panel, preventing background activation.
    @discardableResult
    public mutating func handlePointerEvent(
        _ event: LunaPointerEvent,
        context: inout LunaUIContext
    ) -> LunaModalInteractionResult {
        guard let overlay = active else {
            return LunaModalInteractionResult(
                event: event,
                activeModalID: nil,
                hitNodeID: nil,
                didConsumeEvent: false
            )
        }

        guard event.phase == .down, event.button == .primary else {
            return LunaModalInteractionResult(
                event: event,
                activeModalID: overlay.id,
                hitNodeID: nil,
                didConsumeEvent: true
            )
        }

        let hitNodeID = overlay.hitTest(event.location)
        guard let hitNodeID else {
            return LunaModalInteractionResult(
                event: event,
                activeModalID: overlay.id,
                hitNodeID: nil,
                didConsumeEvent: true
            )
        }

        guard let choice = overlay.choice(for: hitNodeID) else {
            return LunaModalInteractionResult(
                event: event,
                activeModalID: overlay.id,
                hitNodeID: hitNodeID,
                didConsumeEvent: true
            )
        }

        if let command = choice.command {
            context.requestCommand(command)
        }
        context.announce("\(choice.label) selected")

        if choice.dismissesModal {
            active = nil
        }

        return LunaModalInteractionResult(
            event: event,
            activeModalID: overlay.id,
            hitNodeID: hitNodeID,
            choiceIndex: choice.index,
            choiceLabel: choice.label,
            requestedCommand: choice.command,
            didDismiss: choice.dismissesModal,
            didConsumeEvent: true
        )
    }
}

// MARK: - Construction helpers

private extension LunaModalOverlay {
    static func makePrompt(_ request: LunaPromptRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let layout = modalLayout(viewportSize: viewportSize, preferredWidth: 460, preferredHeight: 176)
        let field = LunaRectI(x: layout.panel.x + 18, y: layout.panel.y + 78, w: layout.panel.w - 36, h: 32)
        let button = LunaRectI(x: layout.panel.x + layout.panel.w - 118, y: layout.panel.y + layout.panel.h - 46, w: 96, h: 28)

        return LunaModalOverlay(
            id: request.id,
            kind: .prompt,
            title: request.title,
            message: request.placeholder.isEmpty ? nil : request.placeholder,
            placeholder: request.placeholder,
            initialText: request.initialText,
            anchor: nil,
            bounds: layout.overlay,
            panelBounds: layout.panel,
            choices: [
                LunaModalChoice(
                    id: request.id.child("submit"),
                    label: "Submit",
                    command: request.commandOnSubmit,
                    dismissesModal: true,
                    bounds: button,
                    index: 0
                )
            ],
            fieldBounds: field
        )
    }

    static func makeList(_ request: LunaListRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let visibleCount = min(max(request.items.count, 1), 8)
        let layout = modalLayout(viewportSize: viewportSize, preferredWidth: 500, preferredHeight: 86 + visibleCount * 32)
        let choices = makeVerticalChoices(
            id: request.id,
            labels: request.items.isEmpty ? ["No items"] : request.items,
            command: request.items.isEmpty ? nil : request.commandOnPick,
            startY: layout.panel.y + 54,
            panel: layout.panel,
            rowHeight: 28
        )

        return LunaModalOverlay(
            id: request.id,
            kind: .list,
            title: request.title,
            message: nil,
            placeholder: nil,
            initialText: nil,
            anchor: nil,
            bounds: layout.overlay,
            panelBounds: layout.panel,
            choices: choices,
            fieldBounds: nil
        )
    }

    static func makeConfirm(_ request: LunaConfirmRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let labels = request.buttons.isEmpty ? ["OK", "Cancel"] : request.buttons
        let layout = modalLayout(viewportSize: viewportSize, preferredWidth: 480, preferredHeight: 166)
        let choices = makeHorizontalChoices(
            id: request.id,
            labels: labels,
            command: request.commandOnChoice,
            panel: layout.panel
        )

        return LunaModalOverlay(
            id: request.id,
            kind: .confirm,
            title: request.title,
            message: request.message,
            placeholder: nil,
            initialText: nil,
            anchor: nil,
            bounds: layout.overlay,
            panelBounds: layout.panel,
            choices: choices,
            fieldBounds: nil
        )
    }

    static func makeNotice(_ request: LunaNoticeRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let layout = modalLayout(viewportSize: viewportSize, preferredWidth: 460, preferredHeight: 156)
        let ok = LunaRectI(x: layout.panel.x + layout.panel.w - 118, y: layout.panel.y + layout.panel.h - 46, w: 96, h: 28)

        return LunaModalOverlay(
            id: request.id,
            kind: .notice,
            title: request.title,
            message: request.message,
            placeholder: nil,
            initialText: nil,
            anchor: nil,
            bounds: layout.overlay,
            panelBounds: layout.panel,
            choices: [
                LunaModalChoice(
                    id: request.id.child("ok"),
                    label: "OK",
                    command: nil,
                    dismissesModal: true,
                    bounds: ok,
                    index: 0
                )
            ],
            fieldBounds: nil
        )
    }

    static func makeCompletion(_ request: LunaCompletionRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let visibleCount = min(max(request.items.count, 1), 8)
        let layout = modalLayout(viewportSize: viewportSize, preferredWidth: 420, preferredHeight: 84 + visibleCount * 30)
        let choices = makeVerticalChoices(
            id: request.id,
            labels: request.items.isEmpty ? ["No completions"] : request.items,
            command: request.items.isEmpty ? nil : request.commandOnPick,
            startY: layout.panel.y + 54,
            panel: layout.panel,
            rowHeight: 26
        )

        return LunaModalOverlay(
            id: request.id,
            kind: .completion,
            title: "Completions",
            message: nil,
            placeholder: nil,
            initialText: nil,
            anchor: request.anchor,
            bounds: layout.overlay,
            panelBounds: layout.panel,
            choices: choices,
            fieldBounds: nil
        )
    }

    init(
        id: LunaNodeID,
        kind: LunaModalKind,
        title: String,
        message: String?,
        placeholder: String?,
        initialText: String?,
        anchor: LunaNodeID?,
        bounds: LunaRectI,
        panelBounds: LunaRectI,
        choices: [LunaModalChoice],
        fieldBounds: LunaRectI?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.placeholder = placeholder
        self.initialText = initialText
        self.anchor = anchor
        self.bounds = bounds
        self.panelBounds = panelBounds
        self.choices = choices
        self.fieldBounds = fieldBounds
        self.backdropColor = LunaRender.LunaRGBA8(r: 8, g: 10, b: 14, a: 220)
        self.panelColor = LunaRender.LunaRGBA8(r: 34, g: 38, b: 48, a: 255)
        self.titleColor = LunaRender.LunaRGBA8(r: 22, g: 26, b: 34, a: 255)
        self.accentColor = LunaRender.LunaRGBA8(r: 120, g: 170, b: 255, a: 255)
        self.choiceColor = LunaRender.LunaRGBA8(r: 58, g: 68, b: 84, a: 255)
        self.fieldColor = LunaRender.LunaRGBA8(r: 18, g: 21, b: 27, a: 255)
    }

    static func modalLayout(viewportSize: LunaSizeI, preferredWidth: Int, preferredHeight: Int) -> (overlay: LunaRectI, panel: LunaRectI) {
        let viewportW = max(1, viewportSize.width)
        let viewportH = max(1, viewportSize.height)
        let margin = 24
        let panelW = min(max(280, preferredWidth), max(1, viewportW - margin * 2))
        let panelH = min(max(120, preferredHeight), max(1, viewportH - margin * 2))
        let panelX = max(0, (viewportW - panelW) / 2)
        let panelY = max(0, (viewportH - panelH) / 2)

        return (
            LunaRectI(x: 0, y: 0, w: viewportW, h: viewportH),
            LunaRectI(x: panelX, y: panelY, w: panelW, h: panelH)
        )
    }

    static func makeVerticalChoices(
        id: LunaNodeID,
        labels: [String],
        command: LunaCommandID?,
        startY: Int,
        panel: LunaRectI,
        rowHeight: Int
    ) -> [LunaModalChoice] {
        let maxVisible = min(labels.count, 8)
        let clampedLabels = Array(labels.prefix(maxVisible))
        let x = panel.x + 18
        let w = max(1, panel.w - 36)
        let gap = 4

        return clampedLabels.enumerated().map { index, label in
            LunaModalChoice(
                id: id.child("choice").child(index),
                label: label,
                command: command,
                dismissesModal: command != nil,
                bounds: LunaRectI(x: x, y: startY + index * (rowHeight + gap), w: w, h: rowHeight),
                index: index
            )
        }
    }

    static func makeHorizontalChoices(
        id: LunaNodeID,
        labels: [String],
        command: LunaCommandID?,
        panel: LunaRectI
    ) -> [LunaModalChoice] {
        let clampedLabels = Array(labels.prefix(max(1, min(labels.count, 4))))
        let gap = 8
        let buttonW = max(72, min(110, (panel.w - 36 - gap * max(0, clampedLabels.count - 1)) / max(1, clampedLabels.count)))
        let totalW = buttonW * clampedLabels.count + gap * max(0, clampedLabels.count - 1)
        let startX = panel.x + panel.w - 18 - totalW
        let y = panel.y + panel.h - 46

        return clampedLabels.enumerated().map { index, label in
            LunaModalChoice(
                id: id.child("choice").child(index),
                label: label,
                command: command,
                dismissesModal: true,
                bounds: LunaRectI(x: startX + index * (buttonW + gap), y: y, w: buttonW, h: 28),
                index: index
            )
        }
    }
}
