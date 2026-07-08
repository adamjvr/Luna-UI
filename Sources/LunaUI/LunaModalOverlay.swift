// LunaModalOverlay.swift
//
// Phase 2 / 2B: overlay/modal runtime primitives.
//
// Phase 2 created the modal runtime. Phase 2B adds the interaction-state model
// that the screenshots of Sublime Text made clear we need before Phase 3:
// hover, press, focus, default/cancel choices, keyboard activation, and compact
// Moth/Sublime-shaped control visuals.

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
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
    public var isEnabled: Bool
    public var isDefault: Bool
    public var isCancel: Bool

    public init(
        id: LunaNodeID,
        label: String,
        command: LunaCommandID? = nil,
        dismissesModal: Bool = true,
        bounds: LunaRectI,
        index: Int,
        isEnabled: Bool = true,
        isDefault: Bool = false,
        isCancel: Bool = false
    ) {
        self.id = id
        self.label = label
        self.command = command
        self.dismissesModal = dismissesModal
        self.bounds = bounds
        self.index = index
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.isCancel = isCancel
    }
}

/// A concrete active overlay created from a typed modal request.
///
/// The overlay is a LunaWidget, so it can draw, hit-test, and expose an
/// accessibility subtree. Text is currently represented semantically and drawn
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

    /// Phase 2B interaction state.
    public var hoveredChoiceID: LunaNodeID?
    public var pressedChoiceID: LunaNodeID?
    public var focusedChoiceID: LunaNodeID?

    /// Default Sublime/Moth-shaped visual palette for modal controls.
    public var style: LunaMothDefaultDarkControlStyle

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
        // backdrop rather than true alpha compositing. Keeping alpha in the
        // color still preserves intent for future renderers.
        displayList.append(.rect(bounds, style.overlayBackdrop))
        displayList.append(.rect(panelBounds, style.panelBorder))
        displayList.append(.rect(panelBounds.inset(by: 1), style.panelBackground))

        let titleBar = LunaRectI(
            x: panelBounds.x + 1,
            y: panelBounds.y + 1,
            w: max(0, panelBounds.w - 2),
            h: min(36, max(0, panelBounds.h - 2))
        )
        displayList.append(.rect(titleBar, style.titleBackground))

        // Sublime's active menu/overlay states lean cyan/teal, but subtly.
        displayList.append(.rect(LunaRectI(x: panelBounds.x, y: panelBounds.y, w: panelBounds.w, h: 1), style.accent))

        if let fieldBounds {
            displayList.append(.rect(fieldBounds, style.fieldBorder))
            displayList.append(.rect(fieldBounds.inset(by: 1), style.fieldBackground))
        }

        for choice in choices {
            let state = visualState(for: choice)
            displayList.append(.rect(choice.bounds, style.background(for: state)))

            // Focus/default affordance: thin, rectangular, no bubbly button look.
            if choice.isDefault || choice.id == focusedChoiceID {
                displayList.appendStroke(choice.bounds, color: style.accent, thickness: 1)
            }

            if state == .pressed {
                displayList.append(.rect(LunaRectI(x: choice.bounds.x, y: choice.bounds.y, w: choice.bounds.w, h: 1), style.panelBorder))
            }
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
                    isEnabled: choice.isEnabled,
                    isFocused: choice.id == focusedChoiceID,
                    actions: choice.isEnabled ? [.press, .focus] : []
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

    public func visualState(for choice: LunaModalChoice) -> LunaControlInteractionState {
        guard choice.isEnabled else { return .disabled }
        if pressedChoiceID == choice.id { return .pressed }
        if hoveredChoiceID == choice.id { return .hovered }
        if choice.id == focusedChoiceID {
            switch kind {
            case .list, .completion:
                return .selected
            case .prompt, .confirm, .notice:
                return .focused
            }
        }
        return .normal
    }

    public func foregroundColor(for choice: LunaModalChoice) -> LunaRender.LunaRGBA8 {
        style.foreground(for: visualState(for: choice))
    }

    public func isChoiceNode(_ nodeID: LunaNodeID?) -> Bool {
        guard let nodeID else { return false }
        return choice(for: nodeID) != nil
    }

    public func focusedChoice() -> LunaModalChoice? {
        if let focusedChoiceID, let choice = choice(for: focusedChoiceID), choice.isEnabled {
            return choice
        }
        if let defaultChoice = choices.first(where: { $0.isDefault && $0.isEnabled }) {
            return defaultChoice
        }
        return choices.first(where: \ .isEnabled)
    }

    public mutating func updateHover(at point: LunaPointI) -> LunaNodeID? {
        let hit = hitTest(point)
        if let hit, let choice = choice(for: hit), choice.isEnabled {
            hoveredChoiceID = choice.id
            return choice.id
        }
        hoveredChoiceID = nil
        return nil
    }

    public mutating func beginPress(at point: LunaPointI) -> LunaNodeID? {
        let hit = updateHover(at: point)
        guard let hit, let choice = choice(for: hit), choice.isEnabled else {
            pressedChoiceID = nil
            return nil
        }
        pressedChoiceID = choice.id
        focusedChoiceID = choice.id
        return choice.id
    }

    public mutating func cancelPress() {
        pressedChoiceID = nil
    }

    public mutating func moveFocus(forward: Bool) -> LunaModalChoice? {
        let enabledChoices = choices.filter(\.isEnabled)
        guard !enabledChoices.isEmpty else {
            focusedChoiceID = nil
            return nil
        }

        guard let focusedChoiceID,
              let currentIndex = enabledChoices.firstIndex(where: { $0.id == focusedChoiceID }) else {
            let next = forward ? enabledChoices[0] : enabledChoices[enabledChoices.count - 1]
            self.focusedChoiceID = next.id
            return next
        }

        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % enabledChoices.count
        } else {
            nextIndex = (currentIndex - 1 + enabledChoices.count) % enabledChoices.count
        }

        let next = enabledChoices[nextIndex]
        self.focusedChoiceID = next.id
        return next
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
    public var didChangeVisualState: Bool

    public init(
        event: LunaPointerEvent,
        activeModalID: LunaNodeID?,
        hitNodeID: LunaNodeID?,
        choiceIndex: Int? = nil,
        choiceLabel: String? = nil,
        requestedCommand: LunaCommandID? = nil,
        didDismiss: Bool = false,
        didConsumeEvent: Bool = false,
        didChangeVisualState: Bool = false
    ) {
        self.event = event
        self.activeModalID = activeModalID
        self.hitNodeID = hitNodeID
        self.choiceIndex = choiceIndex
        self.choiceLabel = choiceLabel
        self.requestedCommand = requestedCommand
        self.didDismiss = didDismiss
        self.didConsumeEvent = didConsumeEvent
        self.didChangeVisualState = didChangeVisualState
    }
}

/// Result of routing a keyboard event through the active modal overlay.
public struct LunaModalKeyboardInteractionResult: Hashable, Sendable {
    public var event: LunaKeyboardEvent
    public var activeModalID: LunaNodeID?
    public var choiceIndex: Int?
    public var choiceLabel: String?
    public var requestedCommand: LunaCommandID?
    public var didDismiss: Bool
    public var didConsumeEvent: Bool
    public var didChangeVisualState: Bool

    public init(
        event: LunaKeyboardEvent,
        activeModalID: LunaNodeID?,
        choiceIndex: Int? = nil,
        choiceLabel: String? = nil,
        requestedCommand: LunaCommandID? = nil,
        didDismiss: Bool = false,
        didConsumeEvent: Bool = false,
        didChangeVisualState: Bool = false
    ) {
        self.event = event
        self.activeModalID = activeModalID
        self.choiceIndex = choiceIndex
        self.choiceLabel = choiceLabel
        self.requestedCommand = requestedCommand
        self.didDismiss = didDismiss
        self.didConsumeEvent = didConsumeEvent
        self.didChangeVisualState = didChangeVisualState
    }
}

/// Owns the currently active modal overlay and converts queued LunaUIContext
/// modal requests into concrete overlay state.
public struct LunaModalOverlayManager: Sendable {
    public private(set) var active: LunaModalOverlay?
    public var style: LunaMothDefaultDarkControlStyle

    public init(
        active: LunaModalOverlay? = nil,
        style: LunaMothDefaultDarkControlStyle = .default
    ) {
        self.active = active
        self.style = style
    }

    public var hasActiveModal: Bool { active != nil }

    public mutating func dismissActive() {
        active = nil
    }

    @discardableResult
    public mutating func open(_ request: LunaModalRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        var overlay = LunaModalOverlay(request: request, viewportSize: viewportSize)
        overlay.style = style
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
    /// tree sees it. If a modal exists, it consumes pointer events even when the
    /// click misses the panel, preventing background activation.
    @discardableResult
    public mutating func handlePointerEvent(
        _ event: LunaPointerEvent,
        context: inout LunaUIContext
    ) -> LunaModalInteractionResult {
        guard var overlay = active else {
            return LunaModalInteractionResult(
                event: event,
                activeModalID: nil,
                hitNodeID: nil,
                didConsumeEvent: false
            )
        }

        guard event.button == .primary else {
            return LunaModalInteractionResult(
                event: event,
                activeModalID: overlay.id,
                hitNodeID: nil,
                didConsumeEvent: true
            )
        }

        switch event.phase {
        case .moved:
            let previousHover = overlay.hoveredChoiceID
            let hit = overlay.updateHover(at: event.location)
            active = overlay
            if previousHover != overlay.hoveredChoiceID {
                context.requestRefresh()
            }
            return LunaModalInteractionResult(
                event: event,
                activeModalID: overlay.id,
                hitNodeID: hit,
                didConsumeEvent: true,
                didChangeVisualState: previousHover != overlay.hoveredChoiceID
            )

        case .down:
            let previousFocus = overlay.focusedChoiceID
            let previousPressed = overlay.pressedChoiceID
            let hit = overlay.beginPress(at: event.location)
            active = overlay
            if previousFocus != overlay.focusedChoiceID || previousPressed != overlay.pressedChoiceID {
                context.requestRefresh()
            }
            return LunaModalInteractionResult(
                event: event,
                activeModalID: overlay.id,
                hitNodeID: hit ?? overlay.hitTest(event.location),
                didConsumeEvent: true,
                didChangeVisualState: previousFocus != overlay.focusedChoiceID || previousPressed != overlay.pressedChoiceID
            )

        case .up:
            let hit = overlay.updateHover(at: event.location)
            defer {
                if active?.id == overlay.id {
                    active = overlay
                }
            }

            guard let pressedChoiceID = overlay.pressedChoiceID else {
                overlay.cancelPress()
                return LunaModalInteractionResult(
                    event: event,
                    activeModalID: overlay.id,
                    hitNodeID: hit,
                    didConsumeEvent: true,
                    didChangeVisualState: false
                )
            }

            overlay.cancelPress()
            guard hit == pressedChoiceID,
                  let choice = overlay.choice(for: pressedChoiceID),
                  choice.isEnabled else {
                context.requestRefresh()
                return LunaModalInteractionResult(
                    event: event,
                    activeModalID: overlay.id,
                    hitNodeID: hit,
                    didConsumeEvent: true,
                    didChangeVisualState: true
                )
            }

            return activate(choice, from: overlay, event: event, context: &context)
        }
    }

    @discardableResult
    public mutating func handleKeyboardEvent(
        _ event: LunaKeyboardEvent,
        context: inout LunaUIContext
    ) -> LunaModalKeyboardInteractionResult {
        guard var overlay = active else {
            return LunaModalKeyboardInteractionResult(
                event: event,
                activeModalID: nil,
                didConsumeEvent: false
            )
        }

        switch event.key {
        case .escape:
            let cancel = overlay.choices.first(where: { $0.isCancel && $0.isEnabled })
            if let cancel {
                return activate(cancel, from: overlay, event: event, context: &context)
            }
            context.announce("Dismissed \(overlay.title)")
            active = nil
            context.requestRefresh()
            return LunaModalKeyboardInteractionResult(
                event: event,
                activeModalID: overlay.id,
                didDismiss: true,
                didConsumeEvent: true,
                didChangeVisualState: true
            )

        case .enter, .space:
            guard let choice = overlay.focusedChoice() else {
                return LunaModalKeyboardInteractionResult(
                    event: event,
                    activeModalID: overlay.id,
                    didConsumeEvent: true
                )
            }
            return activate(choice, from: overlay, event: event, context: &context)

        case .tab:
            let previousFocus = overlay.focusedChoiceID
            let choice = overlay.moveFocus(forward: !event.modifiers.shift)
            active = overlay
            if previousFocus != overlay.focusedChoiceID {
                context.requestRefresh()
            }
            return LunaModalKeyboardInteractionResult(
                event: event,
                activeModalID: overlay.id,
                choiceIndex: choice?.index,
                choiceLabel: choice?.label,
                didConsumeEvent: true,
                didChangeVisualState: previousFocus != overlay.focusedChoiceID
            )

        case .other:
            return LunaModalKeyboardInteractionResult(
                event: event,
                activeModalID: overlay.id,
                didConsumeEvent: true
            )
        }
    }

    private mutating func activate(
        _ choice: LunaModalChoice,
        from overlay: LunaModalOverlay,
        event: LunaPointerEvent,
        context: inout LunaUIContext
    ) -> LunaModalInteractionResult {
        if let command = choice.command {
            context.requestCommand(command)
        }
        context.announce("\(choice.label) selected")
        context.requestRefresh()

        if choice.dismissesModal {
            active = nil
        } else {
            var updated = overlay
            updated.focusedChoiceID = choice.id
            updated.pressedChoiceID = nil
            active = updated
        }

        return LunaModalInteractionResult(
            event: event,
            activeModalID: overlay.id,
            hitNodeID: choice.id,
            choiceIndex: choice.index,
            choiceLabel: choice.label,
            requestedCommand: choice.command,
            didDismiss: choice.dismissesModal,
            didConsumeEvent: true,
            didChangeVisualState: true
        )
    }

    private mutating func activate(
        _ choice: LunaModalChoice,
        from overlay: LunaModalOverlay,
        event: LunaKeyboardEvent,
        context: inout LunaUIContext
    ) -> LunaModalKeyboardInteractionResult {
        if let command = choice.command {
            context.requestCommand(command)
        }
        context.announce("\(choice.label) selected")
        context.requestRefresh()

        if choice.dismissesModal {
            active = nil
        } else {
            var updated = overlay
            updated.focusedChoiceID = choice.id
            active = updated
        }

        return LunaModalKeyboardInteractionResult(
            event: event,
            activeModalID: overlay.id,
            choiceIndex: choice.index,
            choiceLabel: choice.label,
            requestedCommand: choice.command,
            didDismiss: choice.dismissesModal,
            didConsumeEvent: true,
            didChangeVisualState: true
        )
    }
}

// MARK: - Construction helpers

private extension LunaModalOverlay {
    static func makePrompt(_ request: LunaPromptRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let layout = modalLayout(viewportSize: viewportSize, preferredWidth: 520, preferredHeight: 160)
        let field = LunaRectI(x: layout.panel.x + 18, y: layout.panel.y + 58, w: layout.panel.w - 36, h: 28)
        let button = LunaRectI(x: layout.panel.x + layout.panel.w - 112, y: layout.panel.y + layout.panel.h - 38, w: 88, h: 24)

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
                    index: 0,
                    isDefault: true
                )
            ],
            fieldBounds: field,
            focusedChoiceID: request.id.child("submit")
        )
    }

    static func makeList(_ request: LunaListRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let visibleCount = min(max(request.items.count, 1), 10)
        let layout = modalLayout(viewportSize: viewportSize, preferredWidth: 520, preferredHeight: 42 + visibleCount * 24)
        let choices = makeVerticalChoices(
            id: request.id,
            labels: request.items.isEmpty ? ["No items"] : request.items,
            command: request.items.isEmpty ? nil : request.commandOnPick,
            startY: layout.panel.y + 38,
            panel: layout.panel,
            rowHeight: 22
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
            fieldBounds: nil,
            focusedChoiceID: choices.first(where: \.isEnabled)?.id
        )
    }

    static func makeConfirm(_ request: LunaConfirmRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let labels = request.buttons.isEmpty ? ["OK", "Cancel"] : request.buttons
        let layout = modalLayout(viewportSize: viewportSize, preferredWidth: 480, preferredHeight: 150)
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
            fieldBounds: nil,
            focusedChoiceID: choices.first(where: { $0.isDefault })?.id ?? choices.last?.id
        )
    }

    static func makeNotice(_ request: LunaNoticeRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let layout = modalLayout(viewportSize: viewportSize, preferredWidth: 460, preferredHeight: 138)
        let ok = LunaRectI(x: layout.panel.x + layout.panel.w - 112, y: layout.panel.y + layout.panel.h - 38, w: 88, h: 24)
        let okID = request.id.child("ok")

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
                    id: okID,
                    label: "OK",
                    command: nil,
                    dismissesModal: true,
                    bounds: ok,
                    index: 0,
                    isDefault: true
                )
            ],
            fieldBounds: nil,
            focusedChoiceID: okID
        )
    }

    static func makeCompletion(_ request: LunaCompletionRequest, viewportSize: LunaSizeI) -> LunaModalOverlay {
        let visibleCount = min(max(request.items.count, 1), 10)
        let layout = modalLayout(viewportSize: viewportSize, preferredWidth: 420, preferredHeight: 42 + visibleCount * 24)
        let choices = makeVerticalChoices(
            id: request.id,
            labels: request.items.isEmpty ? ["No completions"] : request.items,
            command: request.items.isEmpty ? nil : request.commandOnPick,
            startY: layout.panel.y + 38,
            panel: layout.panel,
            rowHeight: 22
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
            fieldBounds: nil,
            focusedChoiceID: choices.first(where: \.isEnabled)?.id
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
        fieldBounds: LunaRectI?,
        hoveredChoiceID: LunaNodeID? = nil,
        pressedChoiceID: LunaNodeID? = nil,
        focusedChoiceID: LunaNodeID? = nil,
        style: LunaMothDefaultDarkControlStyle = .default
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
        self.hoveredChoiceID = hoveredChoiceID
        self.pressedChoiceID = pressedChoiceID
        self.focusedChoiceID = focusedChoiceID ?? choices.first(where: { $0.isDefault && $0.isEnabled })?.id ?? choices.first(where: \.isEnabled)?.id
        self.style = style
    }

    static func modalLayout(viewportSize: LunaSizeI, preferredWidth: Int, preferredHeight: Int) -> (overlay: LunaRectI, panel: LunaRectI) {
        let viewportW = max(1, viewportSize.width)
        let viewportH = max(1, viewportSize.height)
        let margin = 24
        let panelW = min(max(280, preferredWidth), max(1, viewportW - margin * 2))
        let panelH = min(max(96, preferredHeight), max(1, viewportH - margin * 2))
        let panelX = max(0, (viewportW - panelW) / 2)
        let panelY = max(0, (viewportH - panelH) / 3)

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
        let maxVisible = min(labels.count, 10)
        let clampedLabels = Array(labels.prefix(maxVisible))
        let x = panel.x + 6
        let w = max(1, panel.w - 12)
        let gap = 2

        return clampedLabels.enumerated().map { index, label in
            let enabled = command != nil
            return LunaModalChoice(
                id: id.child("choice").child(index),
                label: label,
                command: command,
                dismissesModal: command != nil,
                bounds: LunaRectI(x: x, y: startY + index * (rowHeight + gap), w: w, h: rowHeight),
                index: index,
                isEnabled: enabled,
                isDefault: index == 0 && enabled
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
        let buttonW = max(72, min(104, (panel.w - 36 - gap * max(0, clampedLabels.count - 1)) / max(1, clampedLabels.count)))
        let totalW = buttonW * clampedLabels.count + gap * max(0, clampedLabels.count - 1)
        let startX = panel.x + panel.w - 18 - totalW
        let y = panel.y + panel.h - 38

        return clampedLabels.enumerated().map { index, label in
            let lower = label.lowercased()
            let isCancel = lower.contains("cancel") || lower.contains("no") || lower.contains("don't")
            let isDefault = !isCancel && index == clampedLabels.indices.last
            return LunaModalChoice(
                id: id.child("choice").child(index),
                label: label,
                command: command,
                dismissesModal: true,
                bounds: LunaRectI(x: startX + index * (buttonW + gap), y: y, w: buttonW, h: 24),
                index: index,
                isEnabled: true,
                isDefault: isDefault,
                isCancel: isCancel
            )
        }
    }
}

// MARK: - Draw helpers

private extension LunaRectI {
    func inset(by amount: Int) -> LunaRectI {
        let a = max(0, amount)
        return LunaRectI(x: x + a, y: y + a, w: max(0, w - a * 2), h: max(0, h - a * 2))
    }
}

private extension LunaDisplayList {
    mutating func appendStroke(_ rect: LunaRectI, color: LunaRender.LunaRGBA8, thickness: Int) {
        guard !rect.isEmpty else { return }
        let t = max(1, thickness)
        append(.rect(LunaRectI(x: rect.x, y: rect.y, w: rect.w, h: t), color))
        append(.rect(LunaRectI(x: rect.x, y: rect.y + rect.h - t, w: rect.w, h: t), color))
        append(.rect(LunaRectI(x: rect.x, y: rect.y, w: t, h: rect.h), color))
        append(.rect(LunaRectI(x: rect.x + rect.w - t, y: rect.y, w: t, h: rect.h), color))
    }
}
