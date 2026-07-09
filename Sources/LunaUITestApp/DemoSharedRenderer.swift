//
//  DemoSharedRenderer.swift
//  Luna-UI
//
//  CPU-only demo renderer shared between macOS + Linux test apps.
//
//  IMPORTANT DESIGN GOALS (for this repo / your engine work):
//  - Absolutely NO GPU requirements for this demo.
//  - No platform UI dependencies in this file.
//  - The demo draws into `LunaFramebuffer` using only raw pixel writes.
//  - The presenter (AppKit/SDL) is responsible for displaying the pixels.
//
//  Pixel format expectations:
//  - `LunaFramebuffer` stores pixels as BGRA8 (premultiplied alpha is fine; we draw opaque).
//  - Byte layout per pixel: [B, G, R, A]
//
//  This file intentionally includes a tiny built-in 5x7 bitmap font so the
//  demo does not depend on any font stack while the engine is still in flux.
//

import Foundation
import LunaCommands
import LunaCore
import LunaLayout
import LunaRender
import LunaTheme
import LunaUI

// MARK: - Public demo API


/// Layout snapshot for the CPU demo scene.
///
/// Phase 2D uses this as the integration proof that drawing, hit testing, and
/// future accessibility bounds are derived from the same reflowed geometry.
public struct LunaCPUDemoSceneLayout: Sendable {
    public static let semanticWidgetID: LunaNodeID = "demo.phase1.semantic-widget"
    public static let textViewID: LunaNodeID = "demo.phase3a.static-text-view"
    public static let hudID: LunaNodeID = "demo.hud"
    public static let statusID: LunaNodeID = "demo.status"
    public static let proofPanelID: LunaNodeID = "demo.proof-panel"
    public static let quickPanelID: LunaNodeID = "demo.phase4a.quick-panel"
    public static let findPanelID: LunaNodeID = "demo.phase4b.find-panel"

    public var viewport: LunaViewport
    public var frames: LunaLayoutResult

    public init(viewport: LunaViewport, frames: LunaLayoutResult) {
        self.viewport = viewport
        self.frames = frames
    }

    public var semanticWidgetBounds: LunaRectI {
        frames.frame(for: Self.semanticWidgetID) ?? LunaRectI(x: 0, y: 0, w: 0, h: 0)
    }

    public var textViewBounds: LunaRectI {
        frames.frame(for: Self.textViewID) ?? LunaRectI(x: 0, y: 0, w: 0, h: 0)
    }

    public var hudBounds: LunaRectI {
        frames.frame(for: Self.hudID) ?? LunaRectI(x: 0, y: 0, w: viewport.size.width, h: 36)
    }

    public var statusBounds: LunaRectI {
        frames.frame(for: Self.statusID) ?? LunaRectI(x: 0, y: max(0, viewport.size.height - 34), w: viewport.size.width, h: 34)
    }

    public var proofPanelBounds: LunaRectI {
        frames.frame(for: Self.proofPanelID) ?? LunaRectI(x: 0, y: 0, w: 0, h: 0)
    }
}


/// A small, deterministic demo scene that can be rendered purely on CPU.
///
/// Feature set (matches your request):
/// - Moving block
/// - Text overlay
/// - Phase 1B semantic pointer activation demo
/// - Phase 2 modal/overlay runtime demo
public struct LunaCPUDemoScene {
    /// Scene start time reference.
    private let startTime: UInt64

    /// Active theme. Demo colors are theme-provided so the demo exercises the
    /// same customization path applications use instead of hardcoding Luna's
    /// appearance.
    public var theme: LunaTheme

    /// Monotonic frame counter (increments each render).
    public private(set) var frameIndex: UInt64 = 0

    /// Number of successful semantic widget activations received through the
    /// platform-neutral Luna pointer routing path.
    public private(set) var semanticActivationCount: Int = 0

    /// Last interaction string displayed in the demo status area.
    private var lastInteractionStatus: String = "Ready. Click/type editor, Ctrl+P opens palette, Ctrl+F opens find/replace."

    /// Phase 2 modal manager.  The demo owns a manager so we can prove a host
    /// click routes through: modal first, semantic widget second.
    private var modalManager = LunaModalOverlayManager()

    /// Phase 3D editable editor-surface proof. Rendering still goes through the
    /// LunaStaticTextView line snapshot, while mutation is owned by this small
    /// editable document/state wrapper.
    private var editableTextState = LunaEditableTextState(
        text: LunaCPUDemoScene.demoText,
        caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 1, utf8Column: 0))
    )

    /// Phase 3C scroll state. This remains a logical line viewport offset;
    /// pixel-fractional scrolling comes later.
    private var staticTextScroll = LunaStaticTextScrollState(scrollTopLine: 0)

    /// Phase 4A command palette / quick-panel state. This is app/demo-owned: LunaUI
    /// supplies the generic widget/model, while the demo supplies its commands.
    private var quickPanelState: LunaQuickPanelState? = nil

    /// Phase 4B generic find/replace panel state. The state lives in the demo
    /// because the app owns when a find UI is open and which document it targets;
    /// LunaUI owns the reusable panel/search primitives.
    private var findPanelState: LunaFindPanelState? = nil

    /// Phase 4B.1 user-selection drag anchor. This lives in the demo app because
    /// it is transient interaction state, not document content. The reusable
    /// Luna text model owns the final caret/selection range.
    private var activeTextSelectionAnchor: LunaTextLocation? = nil

    private var staticTextDocument: LunaStaticTextDocument {
        editableTextState.document.staticDocument
    }

    private var staticTextCaret: LunaStaticTextCaret {
        get { editableTextState.caret }
        set { editableTextState.caret = newValue }
    }

    private var staticTextSelection: LunaStaticTextSelection? {
        get { editableTextState.selection }
        set { editableTextState.selection = newValue }
    }

    /// Create a new demo scene.
    public init(
        theme: LunaTheme = MothDemoTheme.theme,
        startTimeNanoseconds: UInt64 = LunaCPUDemoScene.nowMonotonicNanoseconds()
    ) {
        let resolvedTheme = MothDemoTheme.canonicalTheme(for: theme)
        self.startTime = startTimeNanoseconds
        self.theme = resolvedTheme
        self.modalManager = LunaModalOverlayManager(style: LunaControlVisualStyle(theme: resolvedTheme))
    }



    /// Reflow scene-owned overlays after the host window/framebuffer resizes.
    ///
    /// Background widgets are recomputed from `layout(for:)` during render and
    /// hit testing. Active modals are stateful, so the manager explicitly
    /// recalculates their panel/choice/accessibility bounds here.
    public mutating func handleWindowResize(_ size: LunaSizeI) {
        let view = Self.staticTextView(
            for: size,
            document: staticTextDocument,
            scrollTopLine: staticTextScroll.scrollTopLine,
            caret: staticTextCaret,
            selection: staticTextSelection,
            theme: theme
        )
        staticTextScroll = LunaStaticTextScrollState(scrollTopLine: staticTextScroll.scrollTopLine)
            .clamped(document: staticTextDocument, maxVisibleLineCount: view.layout().maxVisibleLineCount)
        modalManager.reflow(viewportSize: size)
        lastInteractionStatus = "Resized/reflowed Luna layout to \(size.width)x\(size.height)"
    }

    /// Switch the active theme and refresh all stateful visual styles.
    ///
    /// Phase 2E uses this in the demo so theme replacement is not theoretical:
    /// the same widget/modal code can be rendered with Luna demo blue,
    /// default dark, or a high-contrast proof palette.
    public mutating func setTheme(_ newTheme: LunaTheme, framebufferSize: LunaSizeI) {
        let resolvedTheme = MothDemoTheme.canonicalTheme(for: newTheme)
        theme = resolvedTheme
        modalManager.style = LunaControlVisualStyle(theme: resolvedTheme)
        modalManager.reflow(viewportSize: framebufferSize)
        lastInteractionStatus = "Theme: \(resolvedTheme.name) bg=\(resolvedTheme.ui.windowBackground.hexRGBA). Press 1=Luna demo, 2=Moth demo, 3=high contrast."
    }

    /// Render one frame into the provided framebuffer.
    ///
    /// - Important: This function does *not* allocate on the hot path other than
    ///   small, short-lived strings for the HUD/status text.
    public mutating func render(into fb: inout LunaFramebuffer) {
        frameIndex &+= 1

        // Compute time (seconds) since scene start.
        let now = Self.nowMonotonicNanoseconds()
        let dtNs = now &- startTime
        let t = Double(dtNs) / 1_000_000_000.0

        // Draw from a canonicalized copy of the active theme. This makes key 2
        // impossible to confuse with the Luna demo-blue palette: if the theme is
        // named as the Moth demo, all visible pixels resolve through the demo-only
        // Moth palette before any drawing happens.
        let renderTheme = MothDemoTheme.canonicalTheme(for: theme)
        let renderLayout = Self.layout(for: LunaSizeI(width: fb.width, height: fb.height))
        drawBackground(into: &fb, theme: renderTheme)
        drawDemoChrome(into: &fb, layout: renderLayout, theme: renderTheme)
        drawStaticTextViewProof(
            into: &fb,
            document: staticTextDocument,
            scrollTopLine: staticTextScroll.scrollTopLine,
            caret: staticTextCaret,
            selection: staticTextSelection,
            highlights: findHighlights(theme: renderTheme),
            theme: renderTheme
        )
        drawMovingBlock(
            into: &fb,
            timeSeconds: t,
            bounds: renderLayout.proofPanelBounds,
            theme: renderTheme
        )
        drawSemanticWidgetProof(
            into: &fb,
            activationCount: semanticActivationCount,
            theme: renderTheme
        )
        drawHUD(
            into: &fb,
            layout: renderLayout,
            timeSeconds: t,
            frameIndex: frameIndex,
            theme: renderTheme
        )
        drawStatusBar(
            into: &fb,
            layout: renderLayout,
            status: lastInteractionStatus,
            caret: staticTextCaret,
            scrollTopLine: staticTextScroll.scrollTopLine,
            lineCount: staticTextDocument.lineCount,
            editRevision: editableTextState.editRevision,
            theme: renderTheme
        )
        drawActiveFindPanelOverlay(
            into: &fb,
            findPanel: activeFindPanel(framebufferSize: LunaSizeI(width: fb.width, height: fb.height), theme: renderTheme),
            theme: renderTheme
        )
        drawActiveQuickPanelOverlay(
            into: &fb,
            quickPanel: activeQuickPanel(framebufferSize: LunaSizeI(width: fb.width, height: fb.height), theme: renderTheme),
            theme: renderTheme
        )
        drawActiveModalOverlay(into: &fb, manager: modalManager)
    }

    /// Route a host pointer event into Luna's modal-first pointer path.
    ///
    /// Phase 2B extends Phase 1B so the demo can prove hover/press/focus states
    /// on modal choices before background widgets ever see the event.
    @discardableResult
    public mutating func handlePointerEvent(
        _ event: LunaPointerEvent,
        framebufferSize: LunaSizeI
    ) -> LunaPointerActivationResult {
        // Phase 2/2B routing rule: active modal overlays see pointer events
        // before background widgets. Even a miss is consumed while a modal is
        // open, preventing accidental background activation.
        if modalManager.hasActiveModal {
            var context = LunaUIContext()
            let modalResult = modalManager.handlePointerEvent(event, context: &context)
            if modalResult.didConsumeEvent {
                if let label = modalResult.choiceLabel {
                    lastInteractionStatus = modalResult.didDismiss
                        ? "Phase 2B modal choice: \(label) dismissed overlay"
                        : "Phase 2B modal choice: \(label)"
                } else if let hit = modalResult.hitNodeID {
                    lastInteractionStatus = "Phase 2B modal hit: \(hit.rawValue)"
                } else if modalResult.didChangeVisualState {
                    lastInteractionStatus = "Phase 2B modal hover/press state changed"
                } else {
                    lastInteractionStatus = "Phase 2B modal consumed background pointer"
                }

                return LunaPointerActivationResult(
                    event: event,
                    hitNodeID: modalResult.hitNodeID,
                    requestedCommand: modalResult.requestedCommand,
                    announcementTexts: context.announcements.map(\.text)
                )
            }
        }

        if var state = quickPanelState {
            let panel = Self.quickPanel(
                for: framebufferSize,
                state: state,
                theme: theme
            )
            if event.phase == .down, event.button == .primary, let hit = panel.hitTest(event.location) {
                if let rowIndex = panel.rowIndex(for: hit), let row = panel.layout().rows.first(where: { $0.index == rowIndex }) {
                    let result = state.selectOriginalIndex(row.match.originalIndex)
                    quickPanelState = nil
                    if let command = result.requestedCommand {
                        performQuickPanelCommand(command, framebufferSize: framebufferSize)
                    } else if let item = result.selectedItem {
                        lastInteractionStatus = "Phase 4A selected quick panel item: \(item.title)"
                    }
                    return LunaPointerActivationResult(
                        event: event,
                        hitNodeID: hit,
                        requestedCommand: result.requestedCommand,
                        announcementTexts: ["Command palette selected"]
                    )
                }

                // The quick panel consumes backdrop/panel clicks while active.
                quickPanelState = hit == panel.id ? nil : state
                lastInteractionStatus = hit == panel.id ? "Phase 4A command palette dismissed" : "Phase 4A command palette pointer hit: \(hit.rawValue)"
                return LunaPointerActivationResult(event: event, hitNodeID: hit, requestedCommand: nil)
            }
        }

        if var state = findPanelState {
            let panel = Self.findPanel(for: framebufferSize, state: state, theme: theme)
            if event.phase == .down, event.button == .primary, let hit = panel.hitTest(event.location) {
                switch hit {
                case panel.queryFieldNodeID:
                    state.focusedField = .query
                    findPanelState = state
                    lastInteractionStatus = "Phase 4B find field focused"
                case panel.replaceFieldNodeID:
                    state.focusedField = .replace
                    findPanelState = state
                    lastInteractionStatus = "Phase 4B replace field focused"
                case panel.caseToggleNodeID:
                    state.toggleCaseSensitive()
                    state.refreshResults(in: staticTextDocument)
                    findPanelState = state
                    syncSelectionToFindMatch(framebufferSize: framebufferSize)
                    lastInteractionStatus = "Phase 4B case-sensitive \(state.options.isCaseSensitive ? "on" : "off"); \(state.results.statusText)"
                case panel.wholeWordToggleNodeID:
                    state.toggleWholeWord()
                    state.refreshResults(in: staticTextDocument)
                    findPanelState = state
                    syncSelectionToFindMatch(framebufferSize: framebufferSize)
                    lastInteractionStatus = "Phase 4B whole-word \(state.options.matchesWholeWord ? "on" : "off"); \(state.results.statusText)"
                case panel.regexToggleNodeID:
                    state.toggleRegex()
                    state.refreshResults(in: staticTextDocument)
                    findPanelState = state
                    syncSelectionToFindMatch(framebufferSize: framebufferSize)
                    lastInteractionStatus = "Phase 4B regex \(state.options.usesRegularExpression ? "on" : "off"); \(state.results.statusText)"
                case panel.previousButtonNodeID:
                    findPanelState = state
                    performFindPanelAction(.findPrevious, framebufferSize: framebufferSize)
                case panel.nextButtonNodeID:
                    findPanelState = state
                    performFindPanelAction(.findNext, framebufferSize: framebufferSize)
                case panel.replaceButtonNodeID:
                    findPanelState = state
                    performFindPanelAction(.replaceCurrent, framebufferSize: framebufferSize)
                case panel.replaceAllButtonNodeID:
                    findPanelState = state
                    performFindPanelAction(.replaceAll, framebufferSize: framebufferSize)
                default:
                    findPanelState = state
                    lastInteractionStatus = "Phase 4B find panel pointer hit: \(hit.rawValue)"
                }
                return LunaPointerActivationResult(event: event, hitNodeID: hit, requestedCommand: nil)
            }
        }

        // Phase 4B.1 text surface routing: ordinary clicks move the caret,
        // Shift-click extends the current selection, and click-drag creates a
        // real editor-style user selection range. Text mutation still happens
        // only from committed text/key events.
        if event.button == .primary {
            let textView = Self.staticTextView(
                for: framebufferSize,
                document: staticTextDocument,
                scrollTopLine: staticTextScroll.scrollTopLine,
                caret: staticTextCaret,
                selection: staticTextSelection,
                theme: theme
            )

            switch event.phase {
            case .down:
                if let hit = textView.textHitTest(event.location) {
                    if event.modifiers.shift {
                        editableTextState.extendSelection(to: hit.location)
                        activeTextSelectionAnchor = editableTextState.selection?.range.anchor ?? staticTextCaret.location
                        lastInteractionStatus = "Phase 4B.1 Shift-click selection: line \(hit.location.lineIndex + 1), col \(hit.location.utf8Column)"
                    } else {
                        editableTextState.beginSelection(at: hit.location)
                        activeTextSelectionAnchor = hit.location
                        lastInteractionStatus = "Phase 4B.1 caret: line \(hit.location.lineIndex + 1), col \(hit.location.utf8Column); drag to select text"
                    }
                    ensureEditableCaretVisible(framebufferSize: framebufferSize)
                    return LunaPointerActivationResult(
                        event: event,
                        hitNodeID: hit.nodeID,
                        requestedCommand: nil,
                        announcementTexts: ["Text caret/selection updated at line \(hit.location.lineIndex + 1), column \(hit.location.utf8Column)"]
                    )
                }
                activeTextSelectionAnchor = nil

            case .moved:
                if let anchor = activeTextSelectionAnchor, let hit = textView.textHitTest(event.location) {
                    editableTextState.setSelection(LunaTextRange(anchor: anchor, focus: hit.location))
                    ensureEditableCaretVisible(framebufferSize: framebufferSize)
                    let selected = staticTextSelection.map { staticTextDocument.accessibilityRange(for: $0.range).utf8Length } ?? 0
                    lastInteractionStatus = "Phase 4B.1 dragging selection: line \(hit.location.lineIndex + 1), col \(hit.location.utf8Column), bytes=\(selected)"
                    return LunaPointerActivationResult(
                        event: event,
                        hitNodeID: hit.nodeID,
                        requestedCommand: nil,
                        announcementTexts: ["Text selection extended"]
                    )
                }

            case .up:
                if let anchor = activeTextSelectionAnchor {
                    activeTextSelectionAnchor = nil
                    if let hit = textView.textHitTest(event.location) {
                        editableTextState.setSelection(LunaTextRange(anchor: anchor, focus: hit.location))
                        ensureEditableCaretVisible(framebufferSize: framebufferSize)
                        let selected = staticTextSelection.map { staticTextDocument.accessibilityRange(for: $0.range).utf8Length } ?? 0
                        lastInteractionStatus = selected > 0
                            ? "Phase 4B.1 selection complete: bytes=\(selected), caret line \(staticTextCaret.location.lineIndex + 1), col \(staticTextCaret.location.utf8Column)"
                            : "Phase 4B.1 caret placed: line \(staticTextCaret.location.lineIndex + 1), col \(staticTextCaret.location.utf8Column)"
                        return LunaPointerActivationResult(
                            event: event,
                            hitNodeID: hit.nodeID,
                            requestedCommand: nil,
                            announcementTexts: [selected > 0 ? "Text selected" : "Caret placed"]
                        )
                    }
                }
            }
        }

        // The background semantic widget still uses the Phase 1B activation rule:
        // primary pointer-down activates. Hover support for ordinary widgets will
        // come after the modal/control-state model is proven.
        var widget = Self.semanticWidget(for: framebufferSize, isFocused: true, theme: theme)
        var context = LunaUIContext()
        let result = widget.handlePointerEvent(event, context: &context)

        if let command = result.requestedCommand {
            semanticActivationCount += 1
            lastInteractionStatus = "Clicked: \(command.rawValue)  count=\(semanticActivationCount); opened Phase 2B notice"
            context.openNotice(
                LunaNoticeRequest(
                    id: "demo.phase2.notice",
                    title: "Phase 2B Overlay",
                    message: "Hover OK, hold mouse down to see pressed state, release to dismiss. Enter activates OK; Escape dismisses."
                )
            )
            modalManager.openQueuedModals(from: &context, viewportSize: framebufferSize)
        } else if result.didHit {
            lastInteractionStatus = "Hit semantic widget, but no command was requested"
        } else if event.phase == .down {
            lastInteractionStatus = "Missed semantic widget at x=\(event.location.x), y=\(event.location.y)"
        }

        return result
    }

    /// Backward-compatible helper kept for the Linux/macOS demo hosts while the
    /// host event loop migrates from pointer-down only to full pointer routing.
    @discardableResult
    public mutating func handlePointerDown(
        at point: LunaPointI,
        framebufferSize: LunaSizeI
    ) -> LunaPointerActivationResult {
        handlePointerEvent(
            LunaPointerEvent(phase: .down, location: point, button: .primary),
            framebufferSize: framebufferSize
        )
    }

    @discardableResult
    public mutating func handleTextInput(_ event: LunaTextInputEvent, framebufferSize: LunaSizeI) -> Bool {
        guard !event.text.isEmpty else { return false }
        if var state = quickPanelState {
            let result = state.handleTextInput(event)
            quickPanelState = state
            lastInteractionStatus = "Phase 4A palette query: \(state.query.debugDescription) (\(state.matches.count) matches)"
            return result.didConsumeEvent
        }

        if var state = findPanelState {
            let result = state.handleTextInput(event, document: staticTextDocument)
            findPanelState = state
            syncSelectionToFindMatch(framebufferSize: framebufferSize)
            lastInteractionStatus = "Phase 4B find: \(state.queryText.debugDescription), \(state.results.statusText)"
            return result.didConsumeEvent
        }

        activeTextSelectionAnchor = nil
        let result = editableTextState.insertText(event.text)
        ensureEditableCaretVisible(framebufferSize: framebufferSize)
        lastInteractionStatus = "Phase 3D inserted \(event.text.debugDescription); caret line \(result.newCaret.location.lineIndex + 1), col \(result.newCaret.location.utf8Column); rev=\(editableTextState.editRevision)"
        return true
    }

    @discardableResult
    public mutating func handleKeyboardEvent(_ event: LunaKeyboardEvent, framebufferSize: LunaSizeI) -> Bool {
        if modalManager.hasActiveModal {
            var context = LunaUIContext()
            let result = modalManager.handleKeyboardEvent(event, context: &context)

            if let label = result.choiceLabel {
                lastInteractionStatus = result.didDismiss
                    ? "Phase 2B keyboard choice: \(label) dismissed overlay"
                    : "Phase 2B keyboard choice: \(label)"
            } else if result.didDismiss {
                lastInteractionStatus = "Phase 2B keyboard dismissed modal"
            } else if result.didChangeVisualState {
                lastInteractionStatus = "Phase 2B keyboard focus moved"
            }

            if result.didConsumeEvent { return true }
        }

        if var state = quickPanelState {
            let result = state.handleKeyboardEvent(event)
            if result.didDismiss {
                quickPanelState = nil
                if let command = result.requestedCommand {
                    performQuickPanelCommand(command, framebufferSize: framebufferSize)
                } else if let item = result.selectedItem {
                    lastInteractionStatus = "Phase 4A selected quick panel item: \(item.title)"
                } else {
                    lastInteractionStatus = "Phase 4A command palette dismissed"
                }
            } else {
                quickPanelState = state
                if result.didChangeState {
                    let selectedTitle = state.selectedMatch?.item.title ?? "none"
                    lastInteractionStatus = "Phase 4A palette query: \(state.query.debugDescription), selected: \(selectedTitle)"
                }
            }
            if result.didConsumeEvent { return true }
        }

        if var state = findPanelState {
            let result = state.handleKeyboardEvent(event, document: staticTextDocument)
            findPanelState = state
            if let action = result.requestedAction {
                performFindPanelAction(action, framebufferSize: framebufferSize)
            } else if result.didDismiss {
                findPanelState = nil
                editableTextState.selection = nil
                lastInteractionStatus = "Phase 4B find panel dismissed"
            } else if result.didChangeState {
                syncSelectionToFindMatch(framebufferSize: framebufferSize)
                let focused = state.focusedField == .query ? "find" : "replace"
                lastInteractionStatus = "Phase 4B \(focused): \(state.queryText.debugDescription), \(state.results.statusText)"
            }
            if result.didConsumeEvent { return true }
        }

        activeTextSelectionAnchor = nil

        if isCommandPaletteShortcut(event) {
            openQuickPanel()
            lastInteractionStatus = "Phase 4A command palette opened; type to filter, Enter runs, Esc closes"
            return true
        }

        if isFindPanelShortcut(event) {
            openFindPanel(framebufferSize: framebufferSize)
            return true
        }

        switch event.key {
        case .number(1):
            setTheme(.lunaDemoBlue, framebufferSize: framebufferSize)
            return true
        case .number(2):
            setTheme(MothDemoTheme.theme, framebufferSize: framebufferSize)
            return true
        case .number(3):
            setTheme(.highContrastProof, framebufferSize: framebufferSize)
            return true
        case .enter:
            let result = editableTextState.insertNewline()
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
            lastInteractionStatus = "Phase 3D newline: caret line \(result.newCaret.location.lineIndex + 1), col \(result.newCaret.location.utf8Column); rev=\(editableTextState.editRevision)"
            return true
        case .backspace:
            activeTextSelectionAnchor = nil
            let result = editableTextState.deleteBackward()
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
            lastInteractionStatus = result.didChange
                ? "Phase 3D backspace: caret line \(result.newCaret.location.lineIndex + 1), col \(result.newCaret.location.utf8Column); rev=\(editableTextState.editRevision)"
                : "Phase 3D backspace: start of document"
            return true
        case .delete:
            activeTextSelectionAnchor = nil
            let result = editableTextState.deleteForward()
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
            lastInteractionStatus = result.didChange
                ? "Phase 3D delete: caret line \(result.newCaret.location.lineIndex + 1), col \(result.newCaret.location.utf8Column); rev=\(editableTextState.editRevision)"
                : "Phase 3D delete: end of document"
            return true
        case .arrowLeft:
            editableTextState.moveCaretBackward(extendingSelection: event.modifiers.shift)
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
            lastInteractionStatus = event.modifiers.shift
                ? "Phase 4B.1 Shift+Left selection: caret line \(editableTextState.caret.location.lineIndex + 1), col \(editableTextState.caret.location.utf8Column)"
                : "Phase 4B.1 caret left: line \(editableTextState.caret.location.lineIndex + 1), col \(editableTextState.caret.location.utf8Column)"
            return true
        case .arrowRight:
            editableTextState.moveCaretForward(extendingSelection: event.modifiers.shift)
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
            lastInteractionStatus = event.modifiers.shift
                ? "Phase 4B.1 Shift+Right selection: caret line \(editableTextState.caret.location.lineIndex + 1), col \(editableTextState.caret.location.utf8Column)"
                : "Phase 4B.1 caret right: line \(editableTextState.caret.location.lineIndex + 1), col \(editableTextState.caret.location.utf8Column)"
            return true
        case .arrowUp:
            scrollStaticTextView(byLineDelta: -1, framebufferSize: framebufferSize)
            return true
        case .arrowDown:
            scrollStaticTextView(byLineDelta: 1, framebufferSize: framebufferSize)
            return true
        case .pageUp:
            scrollStaticTextView(byLineDelta: -staticTextPageDelta(framebufferSize: framebufferSize), framebufferSize: framebufferSize)
            return true
        case .pageDown:
            scrollStaticTextView(byLineDelta: staticTextPageDelta(framebufferSize: framebufferSize), framebufferSize: framebufferSize)
            return true
        case .home:
            setStaticTextScrollTopLine(0, framebufferSize: framebufferSize, reason: "home")
            return true
        case .end:
            setStaticTextScrollTopLine(Int.max, framebufferSize: framebufferSize, reason: "end")
            return true
        default:
            return false
        }
    }

    private func isCommandPaletteShortcut(_ event: LunaKeyboardEvent) -> Bool {
        switch event.key {
        case .other(let key):
            return key.lowercased() == "p" && (event.modifiers.control || event.modifiers.command)
        default:
            return false
        }
    }

    private func isFindPanelShortcut(_ event: LunaKeyboardEvent) -> Bool {
        switch event.key {
        case .other(let key):
            return key.lowercased() == "f" && (event.modifiers.control || event.modifiers.command)
        default:
            return false
        }
    }

    private mutating func openQuickPanel() {
        quickPanelState = LunaQuickPanelState(items: Self.demoQuickPanelItems)
    }

    private func activeQuickPanel(framebufferSize: LunaSizeI, theme: LunaTheme) -> LunaQuickPanel? {
        guard let state = quickPanelState else { return nil }
        return Self.quickPanel(for: framebufferSize, state: state, theme: theme)
    }

    private mutating func openFindPanel(framebufferSize: LunaSizeI) {
        quickPanelState = nil
        var state = findPanelState ?? LunaFindPanelState()
        state.refreshResults(in: staticTextDocument, preservingSelectionNear: staticTextCaret.location)
        findPanelState = state
        syncSelectionToFindMatch(framebufferSize: framebufferSize)
        lastInteractionStatus = "Phase 4B find panel opened; type query, Enter next, Shift+Enter previous, Tab replace, Esc closes"
    }

    private func activeFindPanel(framebufferSize: LunaSizeI, theme: LunaTheme) -> LunaFindPanel? {
        guard let state = findPanelState else { return nil }
        return Self.findPanel(for: framebufferSize, state: state, theme: theme)
    }

    private mutating func syncSelectionToFindMatch(framebufferSize: LunaSizeI) {
        guard let match = findPanelState?.results.selectedMatch else { return }
        editableTextState.selection = LunaStaticTextSelection(range: match.range)
        editableTextState.caret = LunaStaticTextCaret(location: match.range.normalized.focus)
        ensureEditableCaretVisible(framebufferSize: framebufferSize)
    }

    private func findHighlights(theme: LunaTheme) -> [LunaStaticTextHighlight] {
        guard let state = findPanelState else { return [] }
        let base = theme.ui.textField.selectionBackground
        let soft = LunaColor(r: base.r, g: base.g, b: base.b, a: min(base.a, 96))
        let strong = theme.selection
        return state.results.matches.map { match in
            let isCurrent = state.results.selectedMatchIndex == match.index
            return LunaStaticTextHighlight(range: match.range, color: isCurrent ? strong : soft)
        }
    }

    private mutating func performFindPanelAction(_ action: LunaFindPanelAction, framebufferSize: LunaSizeI) {
        guard var state = findPanelState else { return }
        switch action {
        case .findNext:
            state.selectNext()
            findPanelState = state
            syncSelectionToFindMatch(framebufferSize: framebufferSize)
            lastInteractionStatus = "Phase 4B find next: \(state.results.statusText)"
        case .findPrevious:
            state.selectPrevious()
            findPanelState = state
            syncSelectionToFindMatch(framebufferSize: framebufferSize)
            lastInteractionStatus = "Phase 4B find previous: \(state.results.statusText)"
        case .replaceCurrent:
            if let result = LunaFindReplaceController.replaceCurrent(state: &state, text: &editableTextState) {
                findPanelState = state
                syncSelectionToFindMatch(framebufferSize: framebufferSize)
                lastInteractionStatus = "Phase 4B replaced match; caret line \(result.newCaret.location.lineIndex + 1), col \(result.newCaret.location.utf8Column); \(state.results.statusText)"
            } else {
                findPanelState = state
                lastInteractionStatus = "Phase 4B replace: no current match"
            }
        case .replaceAll:
            let count = LunaFindReplaceController.replaceAll(state: &state, text: &editableTextState)
            findPanelState = state
            editableTextState.selection = nil
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
            lastInteractionStatus = "Phase 4B replace all: \(count) replacement(s)"
        }
    }

    private mutating func performQuickPanelCommand(_ command: LunaCommandID, framebufferSize: LunaSizeI) {
        switch command.rawValue {
        case "luna.demo.theme.blue":
            setTheme(.lunaDemoBlue, framebufferSize: framebufferSize)
        case "luna.demo.theme.moth":
            setTheme(MothDemoTheme.theme, framebufferSize: framebufferSize)
        case "luna.demo.theme.highContrast":
            setTheme(.highContrastProof, framebufferSize: framebufferSize)
        case "luna.demo.notice":
            var context = LunaUIContext()
            context.openNotice(
                LunaNoticeRequest(
                    id: "demo.phase4a.notice",
                    title: "Phase 4A Command Palette",
                    message: "The command palette is a generic Luna quick panel. The demo supplies these commands; LunaUI owns filtering, layout, theming, input, and accessibility."
                )
            )
            modalManager.openQueuedModals(from: &context, viewportSize: framebufferSize)
            lastInteractionStatus = "Phase 4A ran command: Show Demo Notice"
        case "luna.demo.scroll.top":
            setStaticTextScrollTopLine(0, framebufferSize: framebufferSize, reason: "quick panel top")
        case "luna.demo.scroll.end":
            setStaticTextScrollTopLine(Int.max, framebufferSize: framebufferSize, reason: "quick panel end")
        case "luna.demo.insert.sample":
            let result = editableTextState.insertText("quick-panel")
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
            lastInteractionStatus = "Phase 4A inserted sample text; caret line \(result.newCaret.location.lineIndex + 1), col \(result.newCaret.location.utf8Column)"
        case "luna.demo.find.open":
            openFindPanel(framebufferSize: framebufferSize)
        default:
            lastInteractionStatus = "Phase 4A ran command: \(command.rawValue)"
        }
    }

    private mutating func staticTextPageDelta(framebufferSize: LunaSizeI) -> Int {
        let view = Self.staticTextView(
            for: framebufferSize,
            document: staticTextDocument,
            scrollTopLine: staticTextScroll.scrollTopLine,
            caret: staticTextCaret,
            selection: staticTextSelection,
            theme: theme
        )
        return max(1, view.layout().maxVisibleLineCount - 1)
    }

    private mutating func scrollStaticTextView(byLineDelta delta: Int, framebufferSize: LunaSizeI) {
        let view = Self.staticTextView(
            for: framebufferSize,
            document: staticTextDocument,
            scrollTopLine: staticTextScroll.scrollTopLine,
            caret: staticTextCaret,
            selection: staticTextSelection,
            theme: theme
        )
        let layout = view.layout()
        staticTextScroll = staticTextScroll.scrolled(
            byLineDelta: delta,
            document: staticTextDocument,
            maxVisibleLineCount: layout.maxVisibleLineCount
        )
        lastInteractionStatus = "Phase 3C scroll: top line \(staticTextScroll.scrollTopLine + 1) / \(staticTextDocument.lineCount)"
    }

    private mutating func setStaticTextScrollTopLine(_ line: Int, framebufferSize: LunaSizeI, reason: String) {
        let view = Self.staticTextView(
            for: framebufferSize,
            document: staticTextDocument,
            scrollTopLine: staticTextScroll.scrollTopLine,
            caret: staticTextCaret,
            selection: staticTextSelection,
            theme: theme
        )
        staticTextScroll = LunaStaticTextScrollState(scrollTopLine: line)
            .clamped(document: staticTextDocument, maxVisibleLineCount: view.layout().maxVisibleLineCount)
        lastInteractionStatus = "Phase 3C scroll \(reason): top line \(staticTextScroll.scrollTopLine + 1) / \(staticTextDocument.lineCount)"
    }

    private mutating func ensureEditableCaretVisible(framebufferSize: LunaSizeI) {
        let view = Self.staticTextView(
            for: framebufferSize,
            document: staticTextDocument,
            scrollTopLine: staticTextScroll.scrollTopLine,
            caret: staticTextCaret,
            selection: staticTextSelection,
            theme: theme
        )
        staticTextScroll = LunaStaticTextScrollState(scrollTopLine: staticTextScroll.scrollTopLine)
            .ensuringVisible(
                staticTextCaret.location,
                document: staticTextDocument,
                maxVisibleLineCount: view.layout().maxVisibleLineCount
            )
    }



    /// Compute the current demo layout for a framebuffer size.
    ///
    /// This is intentionally public/testable so resize/reflow correctness can be
    /// validated without relying on screenshots.
    public static func layout(for framebufferSize: LunaSizeI) -> LunaCPUDemoSceneLayout {
        let viewport = LunaViewport(size: framebufferSize)
        var result = LunaLayoutResult()

        let margin = 18
        let gap = 14
        let headerHeight = max(54, min(68, viewport.size.height / 8))
        let statusHeight = max(30, min(38, viewport.size.height / 14))
        let contentTop = headerHeight + gap
        let contentBottom = max(contentTop + 1, viewport.size.height - statusHeight - gap)
        let contentHeight = max(1, contentBottom - contentTop)

        result.set(
            id: LunaCPUDemoSceneLayout.hudID,
            bounds: LunaRectI(x: 0, y: 0, w: viewport.size.width, h: headerHeight)
        )

        result.set(
            id: LunaCPUDemoSceneLayout.statusID,
            bounds: LunaRectI(x: 0, y: max(0, viewport.size.height - statusHeight), w: viewport.size.width, h: statusHeight)
        )

        let usesSidePanel = viewport.size.width >= 760 && contentHeight >= 180
        if usesSidePanel {
            let panelW = min(320, max(260, viewport.size.width / 3))
            let panelX = max(margin, viewport.size.width - margin - panelW)
            let panel = LunaRectI(x: panelX, y: contentTop, w: panelW, h: contentHeight)
            result.set(id: LunaCPUDemoSceneLayout.proofPanelID, bounds: panel)

            result.set(
                id: LunaCPUDemoSceneLayout.semanticWidgetID,
                bounds: LunaRectI(
                    x: panel.x + 12,
                    y: panel.y + 34,
                    w: max(1, panel.w - 24),
                    h: 72
                )
            )

            let textRight = max(margin + 1, panel.x - gap)
            result.set(
                id: LunaCPUDemoSceneLayout.textViewID,
                bounds: LunaRectI(
                    x: margin,
                    y: contentTop,
                    w: max(1, textRight - margin),
                    h: contentHeight
                )
            )
        } else {
            let semanticHeight = viewport.size.height >= 360 ? 64 : 52
            let semantic = LunaRectI(
                x: margin,
                y: contentTop,
                w: max(1, viewport.size.width - margin * 2),
                h: semanticHeight
            )
            result.set(id: LunaCPUDemoSceneLayout.semanticWidgetID, bounds: semantic)
            result.set(id: LunaCPUDemoSceneLayout.proofPanelID, bounds: LunaRectI(x: 0, y: 0, w: 0, h: 0))

            let textY = semantic.y + semantic.h + gap
            result.set(
                id: LunaCPUDemoSceneLayout.textViewID,
                bounds: LunaRectI(
                    x: margin,
                    y: textY,
                    w: max(1, viewport.size.width - margin * 2),
                    h: max(1, contentBottom - textY)
                )
            )
        }

        return LunaCPUDemoSceneLayout(viewport: viewport, frames: result)
    }

    /// Build the Phase 3A/3B static text-view proof for a framebuffer size.
    public static func staticTextView(
        for framebufferSize: LunaSizeI,
        document: LunaStaticTextDocument,
        scrollTopLine: Int = 0,
        caret: LunaStaticTextCaret? = nil,
        selection: LunaStaticTextSelection? = nil,
        highlights: [LunaStaticTextHighlight] = [],
        theme: LunaTheme = MothDemoTheme.theme
    ) -> LunaStaticTextView {
        let layout = Self.layout(for: framebufferSize)
        return LunaStaticTextView(
            id: LunaCPUDemoSceneLayout.textViewID,
            bounds: layout.textViewBounds,
            document: document,
            scrollTopLine: scrollTopLine,
            currentLineIndex: 3,
            theme: theme,
            metrics: .demo,
            isFocused: caret != nil,
            isEditable: true,
            caret: caret,
            selection: selection,
            highlights: highlights
        )
    }

    /// Build the Phase 4B generic find/replace panel proof.
    public static func findPanel(
        for framebufferSize: LunaSizeI,
        state: LunaFindPanelState,
        theme: LunaTheme = MothDemoTheme.theme
    ) -> LunaFindPanel {
        LunaFindPanel(
            id: LunaCPUDemoSceneLayout.findPanelID,
            bounds: LunaRectI(x: 0, y: 0, w: framebufferSize.width, h: framebufferSize.height),
            title: "Find / Replace",
            queryPlaceholder: "Find in editor…",
            replacePlaceholder: "Replace with…",
            state: state,
            theme: theme,
            metrics: .demo
        )
    }

    /// Build the Phase 4A command-palette / quick-panel proof.
    public static func quickPanel(
        for framebufferSize: LunaSizeI,
        state: LunaQuickPanelState,
        theme: LunaTheme = MothDemoTheme.theme
    ) -> LunaQuickPanel {
        LunaQuickPanel(
            id: LunaCPUDemoSceneLayout.quickPanelID,
            bounds: LunaRectI(x: 0, y: 0, w: framebufferSize.width, h: framebufferSize.height),
            title: "Command Palette",
            placeholder: "Type a command…",
            state: state,
            theme: theme,
            metrics: .demo
        )
    }

    public static let demoCommandDescriptors: [LunaCommandDescriptor] = [
        LunaCommandDescriptor(id: "luna.demo.notice", title: "Show Demo Notice", defaultKey: nil, menuPath: ["Tools", "Demo"]),
        LunaCommandDescriptor(id: "luna.demo.theme.blue", title: "Theme: Luna Demo Blue", defaultKey: LunaKeyEquivalent("1"), menuPath: ["View", "Theme"]),
        LunaCommandDescriptor(id: "luna.demo.theme.moth", title: "Theme: Moth Obsidian Demo", defaultKey: LunaKeyEquivalent("2"), menuPath: ["View", "Theme"]),
        LunaCommandDescriptor(id: "luna.demo.theme.highContrast", title: "Theme: High Contrast Proof", defaultKey: LunaKeyEquivalent("3"), menuPath: ["View", "Theme"]),
        LunaCommandDescriptor(id: "luna.demo.scroll.top", title: "Scroll Text View to Top", menuPath: ["Goto"]),
        LunaCommandDescriptor(id: "luna.demo.scroll.end", title: "Scroll Text View to End", menuPath: ["Goto"]),
        LunaCommandDescriptor(id: "luna.demo.insert.sample", title: "Insert Sample Text", menuPath: ["Edit", "Demo"]),
        LunaCommandDescriptor(id: "luna.demo.find.open", title: "Open Find / Replace Panel", defaultKey: LunaKeyEquivalent("Ctrl+F"), menuPath: ["Find"]),
    ]

    public static let demoQuickPanelItems: [LunaQuickPanelItem] = demoCommandDescriptors.map(LunaQuickPanelItem.init(command:))

    /// Sample static document for Phase 3A. This is demo data, not editor
    /// policy; the LunaStaticTextView itself accepts any app-supplied text.
    public static let demoText = """
    // Phase 4B: Generic Find / Replace Panel Foundation
    // Click in this editor surface and type. Enter, Backspace, Delete, Left,
    // and Right edit; Ctrl+P opens the quick panel; Ctrl+F opens find/replace.
    struct LunaProof {
        let background = "theme.ui.editor.background"
        let gutter = "theme.ui.editor.gutterBackground"
        let text = "theme.ui.editor.foreground"
    }

    // Phase 3A added the static accessible text surface.
    // Phase 3B added caret geometry and static selection.
    // Phase 3C added logical-line scrolling and viewport metrics.
    // Phase 3D adds a tiny editable model before ropes, undo, IME, or clipboard.

    let phase3d_editing = "insert text, newline, backspace, delete"
    let phase3d_input = "host text-input events, not guessed printable keycodes"
    let phase3d_storage = "temporary String-backed model; rope/piece-table later"
    let phase3d_accessibility = "text area reports editable=true"

    // More lines so the viewport actually overflows in normal windows.
    line_01: Luna text viewport proof
    line_02: black/graphite Moth demo still comes from app-supplied theme
    line_03: caret stays document-coordinate stable while viewport moves
    line_04: hit testing maps screen points into scrolled text coordinates
    line_05: selection replacement collapses to the inserted caret
    line_06: accessibility reports visible ranges in UTF-8 byte offsets
    line_07: scroll thumb position is derived from line offset
    line_08: scroll lane uses editor scrollbar theme tokens
    line_09: editable mutation is intentionally minimal right now
    line_10: no undo stack yet
    line_11: no clipboard yet
    line_12: no IME composition yet
    line_13: no soft wrap yet
    line_14: no minimap rendering yet
    line_15: all of that comes later on top of this foundation
    """

    /// Build the Phase 1 semantic widget for a framebuffer size. The demo render
    /// path and input path both call this helper, which keeps draw bounds and
    /// hit-test bounds identical.
    public static func semanticWidget(
        for framebufferSize: LunaSizeI,
        isFocused: Bool,
        theme: LunaTheme = MothDemoTheme.theme
    ) -> LunaSemanticActionWidget {
        let layout = Self.layout(for: framebufferSize)

        return LunaSemanticActionWidget(
            id: LunaCPUDemoSceneLayout.semanticWidgetID,
            bounds: layout.semanticWidgetBounds,
            title: "Phase 1",
            subtitle: "Semantic widget proof",
            primaryCommand: "luna.demo.phase1",
            theme: theme,
            isFocused: isFocused
        )
    }

    // MARK: - Time helper

    /// A monotonic clock suitable for animation timing.
    ///
    /// - Note: `DispatchTime.now()` is monotonic on Apple + Linux.
    public static func nowMonotonicNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

// MARK: - Demo drawing primitives (BGRA8)

/// Fill the entire framebuffer from the active theme's root background token.
///
/// Earlier demo revisions used a checker pattern here. That made the theme demo
/// less truthful because the root canvas was not a direct view of
/// `theme.ui.windowBackground`. Key 1 should be blue because its root token is
/// blue; key 2 should be black because the Moth demo root token is #070709.
private func drawBackground(into fb: inout LunaFramebuffer, theme: LunaTheme) {
    // Capture these *outside* the pixel closure to avoid overlapping-access traps.
    let w = fb.width
    let h = fb.height

    // Capture outside the pixel closure to avoid Swift's inout exclusivity
    // complaints (reading `fb` inside the closure can overlap the `inout`).
    let bpr = fb.bytesPerRow

    fb.withUnsafeMutablePixelBytes { base, byteCount in
        // Defensive: expected size = bytesPerRow * height.
        // If this ever differs, avoid writing out of bounds.
        let expected = bpr * h
        let n = min(byteCount, expected)
        if n <= 0 { return }

        let color = theme.ui.windowBackground

        // We will write row-by-row.
        for y in 0..<h {
            let row = base.advanced(by: y * bpr)
            for x in 0..<w {
                let p = row.advanced(by: x * 4)
                p[0] = color.b         // B
                p[1] = color.g         // G
                p[2] = color.r         // R
                p[3] = color.a         // A
            }
        }
    }
}

/// Draw the Phase 3A static text-view proof through Luna's text-view widget.
///
/// Rect/background/current-line geometry comes from `LunaStaticTextView`'s
/// display-list output. Glyphs still use the demo 5x7 font until LunaRender
/// grows backend-neutral text/glyph commands.
private func drawStaticTextViewProof(
    into fb: inout LunaFramebuffer,
    document: LunaStaticTextDocument,
    scrollTopLine: Int,
    caret: LunaStaticTextCaret?,
    selection: LunaStaticTextSelection?,
    highlights: [LunaStaticTextHighlight],
    theme: LunaTheme
) {
    let view = LunaCPUDemoScene.staticTextView(
        for: LunaSizeI(width: fb.width, height: fb.height),
        document: document,
        scrollTopLine: scrollTopLine,
        caret: caret,
        selection: selection,
        highlights: highlights,
        theme: theme
    )
    guard !view.bounds.isEmpty else { return }

    var displayList = LunaDisplayList()
    view.buildDisplayList(into: &displayList)
    LunaCPURenderer().render(displayList: displayList, into: &fb)

    let layout = view.layout()
    for line in layout.visibleLines {
        drawText5x7Color(
            into: &fb,
            x: line.lineNumberBounds.x,
            y: line.lineNumberBounds.y,
            text: line.lineNumberText,
            scale: 1,
            color: theme.ui.editor.gutterForeground
        )
        drawText5x7Color(
            into: &fb,
            x: line.visualText.bounds.x,
            y: line.visualText.bounds.y,
            text: line.visualText.text,
            scale: 1,
            color: theme.ui.editor.foreground
        )
    }

    // Draw the caret again over debug-font pixels. The widget display list also
    // contains the caret rect so pure Luna tests can validate geometry without
    // touching this demo-only font path.
    if let caretRect = layout.caretRect {
        fillRectColor(
            into: &fb,
            x: caretRect.x,
            y: caretRect.y,
            w: caretRect.w,
            h: caretRect.h,
            color: theme.ui.editor.caret
        )
    }
}

/// Draw a moving rectangle whose motion is driven by time inside the demo proof panel.
///
/// Earlier demo revisions let this proof block roam across the whole framebuffer,
/// which made it cover the editor/status text. Keep the animation contained in
/// the side proof panel so the demo can keep proving animation without trashing
/// readability.
private func drawMovingBlock(
    into fb: inout LunaFramebuffer,
    timeSeconds t: Double,
    bounds: LunaRectI,
    theme: LunaTheme
) {
    guard !bounds.isEmpty else { return }

    let inner = LunaRectI(
        x: bounds.x + 18,
        y: bounds.y + 126,
        w: max(1, bounds.w - 36),
        h: max(1, bounds.h - 154)
    )
    guard inner.w > 12, inner.h > 12 else { return }

    let blockW = max(24, min(72, inner.w / 3))
    let blockH = max(24, min(72, inner.h / 3))
    let ampX = Double(max(1, inner.w - blockW))
    let ampY = Double(max(1, inner.h - blockH))
    let px = (sin(t * 1.2) * 0.5 + 0.5) * ampX
    let py = (cos(t * 0.9) * 0.5 + 0.5) * ampY
    let x0 = inner.x + Int(px.rounded(.toNearestOrAwayFromZero))
    let y0 = inner.y + Int(py.rounded(.toNearestOrAwayFromZero))

    strokeRectColor(into: &fb, x: inner.x, y: inner.y, w: inner.w, h: inner.h, thickness: 1, color: theme.ui.panelBorder)
    fillRectColor(into: &fb, x: x0, y: y0, w: blockW, h: blockH, color: theme.ui.movingBlock)
    strokeRectColor(into: &fb, x: x0, y: y0, w: blockW, h: blockH, thickness: 2, color: theme.ui.movingBlockBorder)
}


/// Draw the Phase 1 semantic widget proof through Luna's actual widget contract.
///
/// This deliberately uses `LunaSemanticActionWidget.buildDisplayList` instead of
/// hand-writing the panel rectangles in the demo. The same widget can also
/// hit-test, expose an accessibility node, and request a command through
/// `LunaUIContext`.
private func drawSemanticWidgetProof(
    into fb: inout LunaFramebuffer,
    activationCount: Int,
    theme: LunaTheme
) {
    let widget = LunaCPUDemoScene.semanticWidget(
        for: LunaSizeI(width: fb.width, height: fb.height),
        isFocused: true,
        theme: theme
    )

    var displayList = LunaDisplayList()
    widget.buildDisplayList(into: &displayList)
    LunaCPURenderer().render(displayList: displayList, into: &fb)

    // Text is still drawn by the demo's tiny debug font until LunaDisplayList
    // grows a real text/glyph-run command. Phase 2D.2 routes that text through
    // the same bounded-text primitive used by modal title/body/button labels so
    // demo widgets expose real Luna behavior instead of unbounded proof art.
    let title = activationCount > 0 ? "Phase 1B x\(activationCount)" : "Phase 1B"
    let widgetText = widget.textLayout(
        title: title,
        subtitle: "Click routing proof"
    )
    drawText5x7Color(
        into: &fb,
        x: widgetText.title.bounds.x,
        y: widgetText.title.bounds.y,
        text: widgetText.title.text,
        scale: 2,
        color: theme.ui.controlColors.foreground
    )
    if let subtitle = widgetText.subtitle {
        drawText5x7Color(
            into: &fb,
            x: subtitle.bounds.x,
            y: subtitle.bounds.y,
            text: subtitle.text,
            scale: 1,
            color: theme.ui.controlColors.mutedForeground
        )
    }

}


/// Draw the active Phase 4B find/replace panel through Luna's generic panel widget.
private func drawActiveFindPanelOverlay(
    into fb: inout LunaFramebuffer,
    findPanel: LunaFindPanel?,
    theme: LunaTheme
) {
    guard let findPanel else { return }

    var displayList = LunaDisplayList()
    findPanel.buildDisplayList(into: &displayList)
    LunaCPURenderer().render(displayList: displayList, into: &fb)

    let text = findPanel.textLayout()
    drawText5x7Color(
        into: &fb,
        x: text.title.bounds.x,
        y: text.title.bounds.y,
        text: text.title.text,
        scale: findPanel.metrics.titleScale,
        color: theme.ui.panel.titleForeground
    )

    let queryColor = findPanel.state.queryText.isEmpty
        ? theme.ui.textField.placeholderForeground
        : theme.ui.textField.foreground
    drawText5x7Color(
        into: &fb,
        x: text.query.bounds.x,
        y: text.query.bounds.y,
        text: text.query.text,
        scale: findPanel.metrics.textScale,
        color: queryColor
    )

    let replaceColor = findPanel.state.replaceText.isEmpty
        ? theme.ui.textField.placeholderForeground
        : theme.ui.textField.foreground
    drawText5x7Color(
        into: &fb,
        x: text.replace.bounds.x,
        y: text.replace.bounds.y,
        text: text.replace.text,
        scale: findPanel.metrics.textScale,
        color: replaceColor
    )

    drawText5x7Color(
        into: &fb,
        x: text.status.bounds.x,
        y: text.status.bounds.y,
        text: text.status.text,
        scale: findPanel.metrics.textScale,
        color: theme.ui.panel.mutedForeground
    )

    for button in text.buttons {
        let color = button.isSelected ? theme.ui.controlColors.selectedForeground : theme.ui.controlColors.foreground
        drawText5x7Color(
            into: &fb,
            x: button.bounds.x + 7,
            y: button.bounds.y + 7,
            text: button.label,
            scale: findPanel.metrics.textScale,
            color: color
        )
    }
}

/// Draw the active Phase 4A quick-panel overlay through Luna's generic quick-panel widget.
private func drawActiveQuickPanelOverlay(
    into fb: inout LunaFramebuffer,
    quickPanel: LunaQuickPanel?,
    theme: LunaTheme
) {
    guard let quickPanel else { return }

    var displayList = LunaDisplayList()
    quickPanel.buildDisplayList(into: &displayList)
    LunaCPURenderer().render(displayList: displayList, into: &fb)

    let text = quickPanel.textLayout()
    drawText5x7Color(
        into: &fb,
        x: text.title.bounds.x,
        y: text.title.bounds.y,
        text: text.title.text,
        scale: quickPanel.metrics.titleScale,
        color: theme.ui.panel.titleForeground
    )

    let queryColor = quickPanel.state.query.isEmpty
        ? theme.ui.textField.placeholderForeground
        : theme.ui.textField.foreground
    drawText5x7Color(
        into: &fb,
        x: text.query.bounds.x,
        y: text.query.bounds.y,
        text: text.query.text,
        scale: quickPanel.metrics.textScale,
        color: queryColor
    )

    for row in text.rows {
        let titleColor = row.isSelected ? theme.ui.menu.rowHoveredForeground : theme.ui.menu.rowForeground
        let subtitleColor = row.isSelected ? theme.ui.menu.rowHoveredForeground : theme.ui.menu.rowMutedForeground
        drawText5x7Color(
            into: &fb,
            x: row.title.bounds.x,
            y: row.title.bounds.y,
            text: row.title.text,
            scale: quickPanel.metrics.textScale,
            color: titleColor
        )
        if let subtitle = row.subtitle {
            drawText5x7Color(
                into: &fb,
                x: subtitle.bounds.x,
                y: subtitle.bounds.y,
                text: subtitle.text,
                scale: quickPanel.metrics.textScale,
                color: subtitleColor
            )
        }
    }

    if let empty = text.emptyState {
        drawText5x7Color(
            into: &fb,
            x: empty.bounds.x,
            y: empty.bounds.y,
            text: empty.text,
            scale: quickPanel.metrics.textScale,
            color: theme.ui.panel.mutedForeground
        )
    }
}

/// Draw the active Phase 2 modal overlay through Luna's modal/display-list path.
private func drawActiveModalOverlay(
    into fb: inout LunaFramebuffer,
    manager: LunaModalOverlayManager
) {
    guard let overlay = manager.active else { return }

    var displayList = LunaDisplayList()
    overlay.buildDisplayList(into: &displayList)
    LunaCPURenderer().render(displayList: displayList, into: &fb)

    // Text is drawn using the demo debug font until display-list text lands.
    // Phase 2D.1: title/body/field/choice labels now come from the modal text
    // layout helper so they respect the reflowed panel bounds instead of
    // spilling outside the dialog when the window is resized small.
    let text = overlay.textLayout()
    drawText5x7BGRA(
        into: &fb,
        x: text.title.bounds.x,
        y: text.title.bounds.y,
        text: text.title.text,
        scale: LunaModalOverlay.titleScale,
        b: overlay.style.text.b,
        g: overlay.style.text.g,
        r: overlay.style.text.r,
        a: overlay.style.text.a
    )

    for line in text.messageLines {
        drawText5x7BGRA(
            into: &fb,
            x: line.bounds.x,
            y: line.bounds.y,
            text: line.text,
            scale: LunaModalOverlay.bodyScale,
            b: overlay.style.mutedText.b,
            g: overlay.style.mutedText.g,
            r: overlay.style.mutedText.r,
            a: overlay.style.mutedText.a
        )
    }

    if let fieldText = text.fieldText {
        drawText5x7BGRA(
            into: &fb,
            x: fieldText.bounds.x,
            y: fieldText.bounds.y,
            text: fieldText.text,
            scale: LunaModalOverlay.bodyScale,
            b: overlay.style.text.b,
            g: overlay.style.text.g,
            r: overlay.style.text.r,
            a: overlay.style.text.a
        )
    }

    for choice in overlay.choices {
        let label = overlay.visualLabel(for: choice)
        let fg = overlay.foregroundColor(for: choice)
        drawText5x7BGRA(
            into: &fb,
            x: label.bounds.x,
            y: label.bounds.y,
            text: label.text,
            scale: LunaModalOverlay.bodyScale,
            b: fg.b,
            g: fg.g,
            r: fg.r,
            a: fg.a
        )
    }
}

/// Draw non-content demo chrome: header, optional side proof panel, and status bar backgrounds.
private func drawDemoChrome(into fb: inout LunaFramebuffer, layout: LunaCPUDemoSceneLayout, theme: LunaTheme) {
    fillRectColor(into: &fb, x: layout.hudBounds.x, y: layout.hudBounds.y, w: layout.hudBounds.w, h: layout.hudBounds.h, color: theme.ui.hudBackground)
    strokeRectColor(into: &fb, x: 0, y: layout.hudBounds.y + layout.hudBounds.h - 1, w: fb.width, h: 1, thickness: 1, color: theme.ui.panelBorder)

    if !layout.proofPanelBounds.isEmpty {
        fillRectColor(
            into: &fb,
            x: layout.proofPanelBounds.x,
            y: layout.proofPanelBounds.y,
            w: layout.proofPanelBounds.w,
            h: layout.proofPanelBounds.h,
            color: theme.ui.panelBackground
        )
        strokeRectColor(
            into: &fb,
            x: layout.proofPanelBounds.x,
            y: layout.proofPanelBounds.y,
            w: layout.proofPanelBounds.w,
            h: layout.proofPanelBounds.h,
            thickness: 1,
            color: theme.ui.panelBorder
        )
        drawText5x7Color(
            into: &fb,
            x: layout.proofPanelBounds.x + 12,
            y: layout.proofPanelBounds.y + 12,
            text: "Proof Panel",
            scale: 1,
            color: theme.ui.panel.mutedForeground
        )
    }

    fillRectColor(into: &fb, x: layout.statusBounds.x, y: layout.statusBounds.y, w: layout.statusBounds.w, h: layout.statusBounds.h, color: theme.ui.statusBar.background)
    strokeRectColor(into: &fb, x: 0, y: layout.statusBounds.y, w: fb.width, h: 1, thickness: 1, color: theme.ui.statusBar.border)
}

/// Heads-up display: title, current theme, and compact key help.
private func drawHUD(
    into fb: inout LunaFramebuffer,
    layout: LunaCPUDemoSceneLayout,
    timeSeconds t: Double,
    frameIndex: UInt64,
    theme: LunaTheme
) {
    let bounds = layout.hudBounds
    guard !bounds.isEmpty else { return }

    let title = "Luna-UI Test App"
    let info = String(format: "Theme: %@   t=%.2fs   frame=%llu", theme.name, t, frameIndex)
    let keys = "Ctrl+P palette   Ctrl+F find   1/2/3 themes   click/type editor   Enter/Backspace/Delete   arrows/Page/Home/End scroll"

    drawText5x7Color(into: &fb, x: bounds.x + 10, y: bounds.y + 8, text: title, scale: 2, color: theme.ui.chrome.titleBarForeground)

    let infoBounds = LunaRectI(x: bounds.x + 10, y: bounds.y + 30, w: max(1, bounds.w - 20), h: 9)
    if let line = LunaBoundedTextLayout.layout(info, in: infoBounds, metrics: LunaDebugTextMetrics(scale: 1), overflow: .ellipsizeTail).firstLine {
        drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: 1, color: theme.ui.statusBar.foreground)
    }

    let keyBounds = LunaRectI(x: bounds.x + 10, y: bounds.y + 43, w: max(1, bounds.w - 20), h: 9)
    if let line = LunaBoundedTextLayout.layout(keys, in: keyBounds, metrics: LunaDebugTextMetrics(scale: 1), overflow: .ellipsizeTail).firstLine {
        drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: 1, color: theme.ui.panel.mutedForeground)
    }
}

/// Bottom status bar for interaction/debug text. Keeping this out of the editor
/// surface makes Phase 3/4 iteration info readable while the text view grows.
private func drawStatusBar(
    into fb: inout LunaFramebuffer,
    layout: LunaCPUDemoSceneLayout,
    status: String,
    caret: LunaStaticTextCaret,
    scrollTopLine: Int,
    lineCount: Int,
    editRevision: Int,
    theme: LunaTheme
) {
    let bounds = layout.statusBounds
    guard !bounds.isEmpty else { return }

    let editorInfo = "Ln \(caret.location.lineIndex + 1), Col \(caret.location.utf8Column)   Top \(scrollTopLine + 1)/\(lineCount)   Rev \(editRevision)"
    let statusText = "Status: \(status)"

    let leftWidth = max(1, min(bounds.w * 2 / 3, bounds.w - 220))
    let statusBounds = LunaRectI(x: bounds.x + 10, y: bounds.y + 8, w: max(1, leftWidth), h: max(1, bounds.h - 10))
    let infoBounds = LunaRectI(x: statusBounds.x + statusBounds.w + 12, y: bounds.y + 8, w: max(1, bounds.w - statusBounds.w - 32), h: max(1, bounds.h - 10))

    if let line = LunaBoundedTextLayout.layout(statusText, in: statusBounds, metrics: LunaDebugTextMetrics(scale: 1), overflow: .ellipsizeTail).firstLine {
        drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: 1, color: theme.ui.statusText)
    }
    if let line = LunaBoundedTextLayout.layout(editorInfo, in: infoBounds, metrics: LunaDebugTextMetrics(scale: 1), overflow: .ellipsizeTail).firstLine {
        drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: 1, color: theme.ui.statusBar.mutedForeground)
    }
}


/// Fill a rectangle from a theme color.
private func fillRectColor(
    into fb: inout LunaFramebuffer,
    x: Int,
    y: Int,
    w: Int,
    h: Int,
    color: LunaColor
) {
    fillRectBGRA(into: &fb, x: x, y: y, w: w, h: h, b: color.b, g: color.g, r: color.r, a: color.a)
}

/// Stroke a rectangle from a theme color.
private func strokeRectColor(
    into fb: inout LunaFramebuffer,
    x: Int,
    y: Int,
    w: Int,
    h: Int,
    thickness: Int,
    color: LunaColor
) {
    strokeRectBGRA(into: &fb, x: x, y: y, w: w, h: h, thickness: thickness, b: color.b, g: color.g, r: color.r, a: color.a)
}

/// Draw text from a theme color.
private func drawText5x7Color(
    into fb: inout LunaFramebuffer,
    x: Int,
    y: Int,
    text: String,
    scale: Int,
    color: LunaColor
) {
    drawText5x7BGRA(into: &fb, x: x, y: y, text: text, scale: scale, b: color.b, g: color.g, r: color.r, a: color.a)
}

/// Fill a rectangle (clipped) with a solid BGRA color.
private func fillRectBGRA(
    into fb: inout LunaFramebuffer,
    x: Int,
    y: Int,
    w: Int,
    h: Int,
    b: UInt8,
    g: UInt8,
    r: UInt8,
    a: UInt8
) {
    let fbW = fb.width
    let fbH = fb.height
    if fbW <= 0 || fbH <= 0 { return }
    if w <= 0 || h <= 0 { return }

    // Clip.
    let x0 = max(0, min(fbW, x))
    let y0 = max(0, min(fbH, y))
    let x1 = max(0, min(fbW, x + w))
    let y1 = max(0, min(fbH, y + h))
    if x1 <= x0 || y1 <= y0 { return }

    let width = x1 - x0
    let height = y1 - y0
    let bpr = fb.bytesPerRow

    fb.withUnsafeMutablePixelBytes { base, byteCount in
        let expected = bpr * fbH
        let n = min(byteCount, expected)
        if n <= 0 { return }

        for yy in 0..<height {
            let row = base.advanced(by: (y0 + yy) * bpr)
            var p = row.advanced(by: x0 * 4)
            for _ in 0..<width {
                p[0] = b
                p[1] = g
                p[2] = r
                p[3] = a
                p = p.advanced(by: 4)
            }
        }
    }
}

/// Stroke the rectangle perimeter (clipped) with a solid BGRA color.
private func strokeRectBGRA(
    into fb: inout LunaFramebuffer,
    x: Int,
    y: Int,
    w: Int,
    h: Int,
    thickness: Int,
    b: UInt8,
    g: UInt8,
    r: UInt8,
    a: UInt8
) {
    let t = max(1, thickness)

    // Top
    fillRectBGRA(into: &fb, x: x, y: y, w: w, h: t, b: b, g: g, r: r, a: a)
    // Bottom
    fillRectBGRA(into: &fb, x: x, y: y + h - t, w: w, h: t, b: b, g: g, r: r, a: a)
    // Left
    fillRectBGRA(into: &fb, x: x, y: y, w: t, h: h, b: b, g: g, r: r, a: a)
    // Right
    fillRectBGRA(into: &fb, x: x + w - t, y: y, w: t, h: h, b: b, g: g, r: r, a: a)
}

// MARK: - Tiny built-in 5x7 bitmap font (ASCII 32..127)

/// Draw ASCII text using a compact 5x7 bitmap font.
///
/// The font table is a classic 5x7 set in a packed format:
/// - 96 glyphs (ASCII 32..127)
/// - Each glyph is 5 columns wide
/// - Each column is 7 bits high (LSB at top)
private func drawText5x7BGRA(
    into fb: inout LunaFramebuffer,
    x: Int,
    y: Int,
    text: String,
    scale: Int,
    b: UInt8,
    g: UInt8,
    r: UInt8,
    a: UInt8
) {
    let s = max(1, scale)
    var penX = x

    for scalar in text.unicodeScalars {
        let code = Int(scalar.value)

        // Newline support (simple).
        if code == 10 { // '\n'
            penX = x
            continue
        }

        if code < 32 || code > 127 {
            penX += (6 * s)
            continue
        }

        let glyphIndex = code - 32
        let glyphBase = glyphIndex * 5

        // Each glyph is 5 columns.
        for col in 0..<5 {
            let columnBits = font5x7[glyphBase + col]
            for row in 0..<7 {
                let bit = (columnBits >> row) & 1
                if bit == 0 { continue }

                // Draw a scaled pixel as a filled rect.
                let px = penX + col * s
                // Framebuffer coordinates are top-left origin, and the 5x7
                // font data is authored with row 0 at the top of the glyph.
                // Do not flip here; doing so mirrors text vertically.
                let py = y + row * s
                fillRectBGRA(into: &fb, x: px, y: py, w: s, h: s, b: b, g: g, r: r, a: a)
            }
        }

        // 1 column spacing.
        penX += (6 * s)
    }
}

/// 5x7 font table: ASCII 32..127.
///
/// Source: Common public-domain 5x7 font used widely in embedded demos.
/// Representation: 5 bytes per glyph, each byte is a column, LSB at top.
private let font5x7: [UInt8] = [
    // ASCII 32 ' '
    0x00,0x00,0x00,0x00,0x00,
    // '!'
    0x00,0x00,0x5F,0x00,0x00,
    // '"'
    0x00,0x07,0x00,0x07,0x00,
    // '#'
    0x14,0x7F,0x14,0x7F,0x14,
    // '$'
    0x24,0x2A,0x7F,0x2A,0x12,
    // '%'
    0x23,0x13,0x08,0x64,0x62,
    // '&'
    0x36,0x49,0x55,0x22,0x50,
    // '\''
    0x00,0x05,0x03,0x00,0x00,
    // '('
    0x00,0x1C,0x22,0x41,0x00,
    // ')'
    0x00,0x41,0x22,0x1C,0x00,
    // '*'
    0x14,0x08,0x3E,0x08,0x14,
    // '+'
    0x08,0x08,0x3E,0x08,0x08,
    // ','
    0x00,0x50,0x30,0x00,0x00,
    // '-'
    0x08,0x08,0x08,0x08,0x08,
    // '.'
    0x00,0x60,0x60,0x00,0x00,
    // '/'
    0x20,0x10,0x08,0x04,0x02,
    // '0'
    0x3E,0x51,0x49,0x45,0x3E,
    // '1'
    0x00,0x42,0x7F,0x40,0x00,
    // '2'
    0x42,0x61,0x51,0x49,0x46,
    // '3'
    0x21,0x41,0x45,0x4B,0x31,
    // '4'
    0x18,0x14,0x12,0x7F,0x10,
    // '5'
    0x27,0x45,0x45,0x45,0x39,
    // '6'
    0x3C,0x4A,0x49,0x49,0x30,
    // '7'
    0x01,0x71,0x09,0x05,0x03,
    // '8'
    0x36,0x49,0x49,0x49,0x36,
    // '9'
    0x06,0x49,0x49,0x29,0x1E,
    // ':'
    0x00,0x36,0x36,0x00,0x00,
    // ';'
    0x00,0x56,0x36,0x00,0x00,
    // '<'
    0x08,0x14,0x22,0x41,0x00,
    // '='
    0x14,0x14,0x14,0x14,0x14,
    // '>'
    0x00,0x41,0x22,0x14,0x08,
    // '?'
    0x02,0x01,0x51,0x09,0x06,
    // '@'
    0x32,0x49,0x79,0x41,0x3E,
    // 'A'
    0x7E,0x11,0x11,0x11,0x7E,
    // 'B'
    0x7F,0x49,0x49,0x49,0x36,
    // 'C'
    0x3E,0x41,0x41,0x41,0x22,
    // 'D'
    0x7F,0x41,0x41,0x22,0x1C,
    // 'E'
    0x7F,0x49,0x49,0x49,0x41,
    // 'F'
    0x7F,0x09,0x09,0x09,0x01,
    // 'G'
    0x3E,0x41,0x49,0x49,0x7A,
    // 'H'
    0x7F,0x08,0x08,0x08,0x7F,
    // 'I'
    0x00,0x41,0x7F,0x41,0x00,
    // 'J'
    0x20,0x40,0x41,0x3F,0x01,
    // 'K'
    0x7F,0x08,0x14,0x22,0x41,
    // 'L'
    0x7F,0x40,0x40,0x40,0x40,
    // 'M'
    0x7F,0x02,0x04,0x02,0x7F,
    // 'N'
    0x7F,0x04,0x08,0x10,0x7F,
    // 'O'
    0x3E,0x41,0x41,0x41,0x3E,
    // 'P'
    0x7F,0x09,0x09,0x09,0x06,
    // 'Q'
    0x3E,0x41,0x51,0x21,0x5E,
    // 'R'
    0x7F,0x09,0x19,0x29,0x46,
    // 'S'
    0x46,0x49,0x49,0x49,0x31,
    // 'T'
    0x01,0x01,0x7F,0x01,0x01,
    // 'U'
    0x3F,0x40,0x40,0x40,0x3F,
    // 'V'
    0x1F,0x20,0x40,0x20,0x1F,
    // 'W'
    0x7F,0x20,0x18,0x20,0x7F,
    // 'X'
    0x63,0x14,0x08,0x14,0x63,
    // 'Y'
    0x03,0x04,0x78,0x04,0x03,
    // 'Z'
    0x61,0x51,0x49,0x45,0x43,
    // '['
    0x00,0x7F,0x41,0x41,0x00,
    // '\\'
    0x02,0x04,0x08,0x10,0x20,
    // ']'
    0x00,0x41,0x41,0x7F,0x00,
    // '^'
    0x04,0x02,0x01,0x02,0x04,
    // '_'
    0x40,0x40,0x40,0x40,0x40,
    // '`'
    0x00,0x01,0x02,0x04,0x00,
    // 'a'
    0x20,0x54,0x54,0x54,0x78,
    // 'b'
    0x7F,0x48,0x44,0x44,0x38,
    // 'c'
    0x38,0x44,0x44,0x44,0x20,
    // 'd'
    0x38,0x44,0x44,0x48,0x7F,
    // 'e'
    0x38,0x54,0x54,0x54,0x18,
    // 'f'
    0x08,0x7E,0x09,0x01,0x02,
    // 'g'
    0x0C,0x52,0x52,0x52,0x3E,
    // 'h'
    0x7F,0x08,0x04,0x04,0x78,
    // 'i'
    0x00,0x44,0x7D,0x40,0x00,
    // 'j'
    0x20,0x40,0x44,0x3D,0x00,
    // 'k'
    0x7F,0x10,0x28,0x44,0x00,
    // 'l'
    0x00,0x41,0x7F,0x40,0x00,
    // 'm'
    0x7C,0x04,0x18,0x04,0x78,
    // 'n'
    0x7C,0x08,0x04,0x04,0x78,
    // 'o'
    0x38,0x44,0x44,0x44,0x38,
    // 'p'
    0x7C,0x14,0x14,0x14,0x08,
    // 'q'
    0x08,0x14,0x14,0x18,0x7C,
    // 'r'
    0x7C,0x08,0x04,0x04,0x08,
    // 's'
    0x48,0x54,0x54,0x54,0x20,
    // 't'
    0x04,0x3F,0x44,0x40,0x20,
    // 'u'
    0x3C,0x40,0x40,0x20,0x7C,
    // 'v'
    0x1C,0x20,0x40,0x20,0x1C,
    // 'w'
    0x3C,0x40,0x30,0x40,0x3C,
    // 'x'
    0x44,0x28,0x10,0x28,0x44,
    // 'y'
    0x0C,0x50,0x50,0x50,0x3C,
    // 'z'
    0x44,0x64,0x54,0x4C,0x44,
    // '{'
    0x00,0x08,0x36,0x41,0x00,
    // '|'
    0x00,0x00,0x7F,0x00,0x00,
    // '}'
    0x00,0x41,0x36,0x08,0x00,
    // '~'
    0x08,0x04,0x08,0x10,0x08,
    // ASCII 127 (DEL) – render as blank
    0x00,0x00,0x00,0x00,0x00,
]
