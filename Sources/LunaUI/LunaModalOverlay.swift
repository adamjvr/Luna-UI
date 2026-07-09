// LunaModalOverlay.swift
//
// Phase 2 / 2B: overlay/modal runtime primitives.
//
// Phase 2 created the modal runtime. Phase 2B adds the interaction-state model
// that the screenshots of Sublime Text made clear we need before Phase 3:
// hover, press, focus, default/cancel choices, keyboard activation, and compact
// Theme-driven control visuals.

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

    /// Theme-driven visual palette for modal controls.
    public var style: LunaControlVisualStyle

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
        let text = textLayout()

        // Accessibility exposes the full semantic title/message even when the
        // visual demo font has to ellipsize or clip the drawn text.
        nodes.append(
            LunaAccessibilityNode(
                id: id.child("title"),
                role: .textRun,
                label: title,
                bounds: text.title.bounds.asAccessibilityRect
            )
        )

        if let message {
            nodes.append(
                LunaAccessibilityNode(
                    id: id.child("message"),
                    role: .textRun,
                    label: message,
                    bounds: text.messageRegion.asAccessibilityRect
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


// MARK: - Layout / resize reflow

public extension LunaModalOverlay {
    /// Recompute overlay, panel, field, and choice bounds for a new viewport
    /// while preserving semantic IDs and interaction identity where possible.
    ///
    /// This is the Phase 2D resize law for modals: the same calculated bounds
    /// drive drawing, hit testing, and accessibility nodes after every reflow.
    mutating func reflow(to viewportSize: LunaSizeI) {
        let oldFocused = focusedChoiceID
        let oldHovered = hoveredChoiceID
        let oldPressed = pressedChoiceID

        let layout: (overlay: LunaRectI, panel: LunaRectI)
        switch kind {
        case .prompt:
            layout = Self.contentAwareModalLayout(viewportSize: viewportSize, preferredWidth: 520, baseHeight: 160, message: message)
            fieldBounds = Self.promptFieldBounds(in: layout.panel)
            choices = Self.reflowHorizontalChoices(choices, panel: layout.panel, preferredWidth: 88)

        case .list:
            let visibleCount = min(max(choices.count, 1), 10)
            layout = Self.modalLayout(viewportSize: viewportSize, preferredWidth: 520, preferredHeight: 42 + visibleCount * 24)
            fieldBounds = nil
            choices = Self.reflowVerticalChoices(choices, startY: layout.panel.y + 38, panel: layout.panel, rowHeight: 22)

        case .confirm:
            layout = Self.contentAwareModalLayout(viewportSize: viewportSize, preferredWidth: 480, baseHeight: 150, message: message)
            fieldBounds = nil
            choices = Self.reflowHorizontalChoices(choices, panel: layout.panel, preferredWidth: nil)

        case .notice:
            layout = Self.contentAwareModalLayout(viewportSize: viewportSize, preferredWidth: 460, baseHeight: 138, message: message)
            fieldBounds = nil
            choices = Self.reflowHorizontalChoices(choices, panel: layout.panel, preferredWidth: 88)

        case .completion:
            let visibleCount = min(max(choices.count, 1), 10)
            layout = Self.modalLayout(viewportSize: viewportSize, preferredWidth: 420, preferredHeight: 42 + visibleCount * 24)
            fieldBounds = nil
            choices = Self.reflowVerticalChoices(choices, startY: layout.panel.y + 38, panel: layout.panel, rowHeight: 22)
        }

        bounds = layout.overlay
        panelBounds = layout.panel

        let validChoiceIDs = Set(choices.map(\.id))
        focusedChoiceID = oldFocused.flatMap { validChoiceIDs.contains($0) ? $0 : nil }
            ?? choices.first(where: { $0.isDefault && $0.isEnabled })?.id
            ?? choices.first(where: \.isEnabled)?.id
        hoveredChoiceID = oldHovered.flatMap { validChoiceIDs.contains($0) ? $0 : nil }
        pressedChoiceID = oldPressed.flatMap { validChoiceIDs.contains($0) ? $0 : nil }
    }
}

/// Owns the currently active modal overlay and converts queued LunaUIContext
/// modal requests into concrete overlay state.
public struct LunaModalOverlayManager: Sendable {
    public private(set) var active: LunaModalOverlay?
    public var style: LunaControlVisualStyle

    public init(
        active: LunaModalOverlay? = nil,
        style: LunaControlVisualStyle = .default
    ) {
        self.active = active
        self.style = style
    }

    public var hasActiveModal: Bool { active != nil }

    public mutating func dismissActive() {
        active = nil
    }

    /// Reflow the active overlay when the host viewport changes size.
    ///
    /// The active modal keeps its semantic IDs and interaction identity, but all
    /// draw/hit-test/accessibility bounds are recalculated from the new viewport.
    public mutating func reflow(viewportSize: LunaSizeI) {
        guard var overlay = active else { return }
        overlay.style = style
        overlay.reflow(to: viewportSize)
        active = overlay
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

        case .number:
            return LunaModalKeyboardInteractionResult(
                event: event,
                activeModalID: overlay.id,
                didConsumeEvent: false
            )

        case .arrowUp, .arrowDown, .pageUp, .pageDown, .home, .end, .other:
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
        let layout = contentAwareModalLayout(viewportSize: viewportSize, preferredWidth: 520, baseHeight: 160, message: request.placeholder)
        let field = promptFieldBounds(in: layout.panel)
        let choices = makeHorizontalChoices(
            id: request.id,
            labels: ["Submit"],
            command: request.commandOnSubmit,
            panel: layout.panel,
            preferredWidth: 88,
            defaultIndex: 0
        )

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
            choices: choices,
            fieldBounds: field,
            focusedChoiceID: choices.first(where: { $0.isDefault })?.id ?? choices.first?.id
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
        let layout = contentAwareModalLayout(viewportSize: viewportSize, preferredWidth: 480, baseHeight: 150, message: request.message)
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
        let layout = contentAwareModalLayout(viewportSize: viewportSize, preferredWidth: 460, baseHeight: 138, message: request.message)
        let choices = makeHorizontalChoices(
            id: request.id,
            labels: ["OK"],
            command: nil,
            panel: layout.panel,
            preferredWidth: 88,
            defaultIndex: 0
        )

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
            choices: choices,
            fieldBounds: nil,
            focusedChoiceID: choices.first(where: { $0.isDefault })?.id ?? choices.first?.id
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
        style: LunaControlVisualStyle = .default
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

    /// Build a modal panel whose height can grow when its message wraps at a
    /// narrow viewport. This keeps title/body/button regions from overlapping
    /// before the real text engine and scrolling panels exist.
    static func contentAwareModalLayout(
        viewportSize: LunaSizeI,
        preferredWidth: Int,
        baseHeight: Int,
        message: String?
    ) -> (overlay: LunaRectI, panel: LunaRectI) {
        let preliminary = modalLayout(viewportSize: viewportSize, preferredWidth: preferredWidth, preferredHeight: baseHeight)
        let contentWidth = modalContentBounds(in: preliminary.panel).w
        let wrappedLines = estimatedWrappedLineCount(for: message, width: contentWidth)

        // Base heights were authored around one body line. Add vertical room for
        // additional wrapped lines while still clamping to the viewport.
        let extraLines = max(0, wrappedLines - 1)
        let preferredHeight = baseHeight + extraLines * debugFontLineHeight(scale: bodyScale)
        return modalLayout(viewportSize: viewportSize, preferredWidth: preferredWidth, preferredHeight: preferredHeight)
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
        let content = modalContentBounds(in: panel)
        let x = content.x
        let w = max(1, content.w)
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
        panel: LunaRectI,
        preferredWidth: Int? = nil,
        defaultIndex explicitDefaultIndex: Int? = nil
    ) -> [LunaModalChoice] {
        let clampedLabels = Array(labels.prefix(max(1, min(labels.count, 4))))
        let frames = horizontalChoiceFrames(count: clampedLabels.count, panel: panel, preferredWidth: preferredWidth)

        return clampedLabels.enumerated().map { index, label in
            let lower = label.lowercased()
            let isCancel = lower.contains("cancel") || lower.contains("no") || lower.contains("don't")
            let isDefault: Bool
            if let explicitDefaultIndex {
                isDefault = index == explicitDefaultIndex
            } else {
                isDefault = !isCancel && index == clampedLabels.indices.last
            }

            return LunaModalChoice(
                id: clampedLabels.count == 1 ? id.child(label.lowercased().replacingOccurrences(of: " ", with: "-")) : id.child("choice").child(index),
                label: label,
                command: command,
                dismissesModal: true,
                bounds: frames[index],
                index: index,
                isEnabled: true,
                isDefault: isDefault,
                isCancel: isCancel
            )
        }
    }

    static func reflowVerticalChoices(
        _ choices: [LunaModalChoice],
        startY: Int,
        panel: LunaRectI,
        rowHeight: Int
    ) -> [LunaModalChoice] {
        let maxVisible = min(choices.count, 10)
        let visibleChoices = Array(choices.prefix(maxVisible))
        let content = modalContentBounds(in: panel)
        let x = content.x
        let w = max(1, content.w)
        let gap = 2

        return visibleChoices.enumerated().map { index, old in
            LunaModalChoice(
                id: old.id,
                label: old.label,
                command: old.command,
                dismissesModal: old.dismissesModal,
                bounds: LunaRectI(x: x, y: startY + index * (rowHeight + gap), w: w, h: rowHeight),
                index: index,
                isEnabled: old.isEnabled,
                isDefault: old.isDefault,
                isCancel: old.isCancel
            )
        }
    }

    static func reflowHorizontalChoices(
        _ choices: [LunaModalChoice],
        panel: LunaRectI,
        preferredWidth: Int?
    ) -> [LunaModalChoice] {
        let clampedChoices = Array(choices.prefix(max(1, min(choices.count, 4))))
        guard !clampedChoices.isEmpty else { return [] }

        let frames = horizontalChoiceFrames(count: clampedChoices.count, panel: panel, preferredWidth: preferredWidth)

        return clampedChoices.enumerated().map { index, old in
            LunaModalChoice(
                id: old.id,
                label: old.label,
                command: old.command,
                dismissesModal: old.dismissesModal,
                bounds: frames[index],
                index: index,
                isEnabled: old.isEnabled,
                isDefault: old.isDefault,
                isCancel: old.isCancel
            )
        }
    }

    /// Responsive row/stack layout for modal controls.
    ///
    /// Phase 2D.2 made text stay inside assigned bounds. Phase 2D.3 fixes the
    /// next layer down: controls must choose sane bounds before text is laid out.
    /// Single-button rows become full-width in emergency-narrow panels. Multiple
    /// buttons shrink to a usable minimum, then stack vertically when they no
    /// longer fit horizontally.
    static func horizontalChoiceFrames(count requestedCount: Int, panel: LunaRectI, preferredWidth: Int?) -> [LunaRectI] {
        let count = max(0, min(requestedCount, 4))
        guard count > 0 else { return [] }

        let content = modalContentBounds(in: panel)
        let availableW = max(1, content.w)
        let gap = availableW >= 120 ? 8 : 4
        let buttonH = 24
        let bottomInset = modalContentInset(forPanelWidth: panel.w)
        let baselineY = max(panel.y + 1, panel.y + panel.h - bottomInset - buttonH)
        let preferred = max(44, preferredWidth ?? 88)
        let minimum = min(44, availableW)

        if count == 1 {
            let useFullWidth = availableW < preferred + 16
            let width = max(1, min(availableW, useFullWidth ? availableW : preferred))
            let x = useFullWidth ? content.x : content.x + max(0, availableW - width)
            return [LunaRectI(x: x, y: baselineY, w: width, h: buttonH)]
        }

        let preferredTotal = preferred * count + gap * (count - 1)
        if preferredTotal <= availableW {
            let startX = content.x + availableW - preferredTotal
            return (0..<count).map { index in
                LunaRectI(x: startX + index * (preferred + gap), y: baselineY, w: preferred, h: buttonH)
            }
        }

        let minimumTotal = minimum * count + gap * (count - 1)
        if minimumTotal <= availableW {
            let width = max(1, (availableW - gap * (count - 1)) / count)
            let total = width * count + gap * (count - 1)
            let startX = content.x + max(0, availableW - total)
            return (0..<count).map { index in
                LunaRectI(x: startX + index * (width + gap), y: baselineY, w: width, h: buttonH)
            }
        }

        // Emergency-narrow multi-button mode: stack buttons vertically inside the
        // same content column rather than letting them spill outside the panel.
        let verticalGap = 4
        let totalH = buttonH * count + verticalGap * (count - 1)
        let startY = max(panel.y + 40, panel.y + panel.h - bottomInset - totalH)
        return (0..<count).map { index in
            LunaRectI(x: content.x, y: startY + index * (buttonH + verticalGap), w: availableW, h: buttonH)
        }
    }

    static func promptFieldBounds(in panel: LunaRectI) -> LunaRectI {
        let content = modalContentBounds(in: panel)
        return LunaRectI(x: content.x, y: panel.y + 58, w: max(1, content.w), h: 28)
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
