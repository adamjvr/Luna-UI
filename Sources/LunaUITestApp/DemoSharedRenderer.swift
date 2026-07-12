// SPDX-License-Identifier: MPL-2.0
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
import LunaHostCore
import LunaRender
import LunaTheme
import LunaUI

// MARK: - Public demo API


/// Layout snapshot for the CPU demo scene.
///
/// Phase 2D uses this as the integration proof that drawing, hit testing, and
/// future accessibility bounds are derived from the same reflowed geometry.
public enum LunaDemoMode: String, Hashable, Sendable, CaseIterable, CustomStringConvertible {
    case editor
    case proofGallery

    public var description: String { rawValue }

    public var usesProofGallerySurfaces: Bool { self == .proofGallery }

    public static func parse(arguments: [String], environment: [String: String]) -> LunaDemoMode {
        let normalizedArguments = Set(arguments.map { $0.lowercased() })
        if normalizedArguments.contains("--proof-gallery") || normalizedArguments.contains("--proof") {
            return .proofGallery
        }
        if normalizedArguments.contains("--editor") {
            return .editor
        }

        if let value = environment["LUNA_DEMO_MODE"]?.lowercased() {
            switch value {
            case "proof", "proof-gallery", "proofgallery", "gallery":
                return .proofGallery
            case "editor", "moth", "default":
                return .editor
            default:
                break
            }
        }
        return .editor
    }
}

public struct LunaCPUDemoSceneLayout: Sendable {
    public static let semanticWidgetID: LunaNodeID = "demo.phase1.semantic-widget"
    public static let textViewID: LunaNodeID = "demo.phase3a.static-text-view"
    public static let hudID: LunaNodeID = "demo.hud"
    public static let statusID: LunaNodeID = "demo.phase4d.status-bar"
    public static let menuBarID: LunaNodeID = "demo.phase4c.menu-bar"
    public static let editorShellID: LunaNodeID = "demo.phase4d.editor-shell"
    public static let tabStripID: LunaNodeID = "demo.phase4d.tab-strip"
    public static let sidebarID: LunaNodeID = "demo.phase4d.sidebar"
    public static let proofPanelID: LunaNodeID = "demo.proof-panel"
    public static let quickPanelID: LunaNodeID = "demo.phase4a.quick-panel"
    public static let findPanelID: LunaNodeID = "demo.phase4b.find-panel"
    public static let contextMenuID: LunaNodeID = "demo.phase4e.context-menu"
    public static let completionPopupID: LunaNodeID = "demo.phase4f.completion-popup"

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

    public var menuBarBounds: LunaRectI {
        frames.frame(for: Self.menuBarID) ?? LunaRectI(x: 0, y: 0, w: viewport.size.width, h: 24)
    }

    public var editorShellBounds: LunaRectI {
        frames.frame(for: Self.editorShellID) ?? LunaRectI(x: 0, y: 24, w: viewport.size.width, h: max(1, viewport.size.height - 24))
    }

    public var tabStripBounds: LunaRectI {
        frames.frame(for: Self.tabStripID) ?? LunaRectI(x: editorShellBounds.x, y: editorShellBounds.y, w: editorShellBounds.w, h: 30)
    }

    public var sidebarBounds: LunaRectI {
        frames.frame(for: Self.sidebarID) ?? LunaRectI(x: editorShellBounds.x, y: editorShellBounds.y + tabStripBounds.h, w: 0, h: max(1, editorShellBounds.h - tabStripBounds.h))
    }
}


/// Cached static proof-gallery frame used for animation-only frames.
///
/// The proof gallery is intentionally a stress harness, but the bouncing-square
/// proof should not force the expensive editor/sidebar/text surfaces to be
/// rebuilt every vsync when nothing except the square's position changes. The
/// cache stores a fully rendered static frame with the dynamic animation/HUD and
/// transient overlays omitted; animation-only frames restore it and redraw just
/// the moving proof surface.
private struct LunaProofGalleryStaticFrameCache {
    public var framebuffer: LunaFramebuffer

    public init(width: Int, height: Int) {
        self.framebuffer = LunaFramebuffer(width: width, height: height)
    }

    public func matches(width: Int, height: Int) -> Bool {
        framebuffer.width == width && framebuffer.height == height
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
    /// Active theme. Demo colors are theme-provided so the demo exercises the
    /// same customization path applications use instead of hardcoding Luna's
    /// appearance.
    public var theme: LunaTheme

    /// Monotonic frame counter (increments each render).
    public private(set) var frameIndex: UInt64 = 0

    /// Proof-gallery-only animation phase. This is intentionally logical time,
    /// not raw process uptime, so the moving proof square does not jump after
    /// modal dialogs, debugger pauses, or host scheduling stalls.
    private var proofGalleryAnimationClock = LunaAnimationClock()

    /// Static proof-gallery frame used for animation-only frames.
    ///
    /// This cache is intentionally demo-owned: it keeps proof-gallery animation
    /// smooth without turning LunaUI widgets into retained/async objects. Any
    /// non-animation invalidation refreshes the cache through the normal render
    /// path before dynamic proof surfaces are drawn.
    private var proofGalleryStaticFrameCache: LunaProofGalleryStaticFrameCache? = nil

    /// Demo harness mode. The default editor mode is the Moth-like performance
    /// baseline; proofGallery keeps old phase/stress surfaces available without
    /// putting them on the hot path for ordinary editor testing.
    public var demoMode: LunaDemoMode

    /// Number of successful semantic widget activations received through the
    /// platform-neutral Luna pointer routing path.
    public private(set) var semanticActivationCount: Int = 0

    /// Last interaction string displayed in the demo status area.
    private var lastInteractionStatus: String = "Ready. Phase 5C.1 frame pacing active; UI state remains single-lane and deterministic."

    /// Phase 2 modal manager.  The demo owns a manager so we can prove a host
    /// click routes through: modal first, semantic widget second.
    private var modalManager = LunaModalOverlayManager()

    /// Phase 5A open document/buffer proof. LunaUI supplies product-neutral
    /// document descriptors, editable buffer state, dirty tracking, and shell-tab
    /// projection; the demo supplies fake documents instead of real file I/O.
    private var documentStore = LunaCPUDemoScene.demoDocumentStore

    /// Phase 5D/5D.2 file/project adapter boundary proof. The adapter lives in
    /// the demo app target and can serve in-memory fixtures, real UTF-8 local
    /// files, created empty files, and Save As targets. LunaUI still owns only
    /// product-neutral workspace/open/save contracts; filesystem access and path
    /// policy stay outside Luna.
    private var workspaceState = LunaCPUDemoScene.demoWorkspaceState
    private var workspaceAdapter = LunaCPUDemoWorkspaceAdapter.demo

    /// Phase 5D.2 untitled-document naming stays demo/app policy. LunaUI only
    /// needs stable document descriptors and save requests.
    private var nextUntitledDocumentIndex: Int = 1
    private var dialogService: any LunaDialogService
    private var overwritesDemoSaveAsTarget: Bool = false

    /// Phase 5C.1 runtime/frame diagnostics supplied by the host loop. Widgets
    /// stay synchronous; the host records timing and invalidation reasons.
    private var frameTimingStats = LunaFrameTimingStats()
    private var latestFrameInvalidations = LunaFrameInvalidationSet(.initial)
    private var latestInputCoalescingStats = LunaInputCoalescingStats()


    /// Phase 4A command palette / quick-panel state. This is app/demo-owned: LunaUI
    /// supplies the generic widget/model, while the demo supplies its commands.
    private var quickPanelState: LunaQuickPanelState? = nil

    /// Phase 4C product-neutral menu bar/dropdown state. The reusable LunaUI
    /// menu primitives own layout/input/accessibility; the demo owns which
    /// commands are present and how they are handled.
    private var menuBarState = LunaMenuBarState()

    /// Phase 4E product-neutral context menu state. The reusable LunaUI context
    /// menu owns floating-menu layout/input/accessibility; the demo chooses menu
    /// contents based on the clicked surface.
    private var contextMenuState = LunaContextMenuState()

    /// Phase 4F product-neutral completion-popup state. LunaUI owns anchored
    /// popup layout/input/accessibility; the demo supplies static completion
    /// candidates and applies the selected insertion text.
    private var completionPopupState = LunaCompletionPopupState()

    /// Phase 4D product-neutral editor shell state. Tabs/sidebar/status are
    /// LunaUI primitives; the demo supplies fake documents/project/status data.
    private var editorShellState = LunaCPUDemoScene.demoEditorShellState


    /// Phase 5F.1 product-neutral split/pane proof. The demo maps pane IDs to
    /// presentation regions only; document/view cloning remains application
    /// policy and is intentionally not encoded in LunaPaneContainer.
    private var paneWorkspaceState = LunaCPUDemoScene.demoPaneWorkspaceState
    private var paneInteractionState = LunaPaneContainerInteractionState()
    private var textSelectionInteractionState = LunaTextSelectionInteractionState()
    private var currentCursorIntent: LunaCursorIntent = .arrow

    /// Per-pane viewport state for the Phase 5F.2A integration proof. The primary
    /// pane continues to use the active document's existing scroll state; other
    /// panes retain independent logical top-line positions.
    private var paneScrollTopLineOverrides: [LunaPaneID: Int] = [
        "demo.editor.secondary": 2,
    ]

    /// Soft wrapping can create several visual rows inside one logical line.
    /// Keep that row offset per document and pane so a long wrapped line can be
    /// scrolled independently without changing the app-owned document model.
    private var paneScrollTopVisualRowOverrides: [String: Int] = [:]

    /// Phase 4B generic find/replace panel state. The state lives in the demo
    /// because the app owns when a find UI is open and which document it targets;
    /// LunaUI owns the reusable panel/search primitives.
    private var findPanelState: LunaFindPanelState? = nil

    /// Some SDL/input stacks may still emit a committed text event for a control
    /// shortcut key after Luna has already handled the shortcut as a command.
    ///
    /// Example: Ctrl+A should Select All, not replace the document with a stray
    /// committed "a" before the user's next real typed character. The suppression
    /// is one-shot and only consumes the exact shortcut character, so normal text
    /// typed after the command still reaches the editor.
    private var pendingShortcutTextInputSuppression: String? = nil

    private var editableTextState: LunaEditableTextState {
        get { documentStore.activeTextState ?? LunaEditableTextState(text: "") }
        set { documentStore.replaceActiveTextState(newValue) }
    }

    private var staticTextScroll: LunaStaticTextScrollState {
        get { documentStore.activeScrollState ?? LunaStaticTextScrollState() }
        set { documentStore.replaceActiveScrollState(newValue) }
    }

    private func scrollTopLine(for paneID: LunaPaneID) -> Int {
        if paneID == "demo.editor.primary" {
            return staticTextScroll.scrollTopLine
        }
        return max(0, paneScrollTopLineOverrides[paneID] ?? 0)
    }

    private mutating func setScrollTopLine(_ line: Int, for paneID: LunaPaneID) {
        if paneID == "demo.editor.primary" {
            staticTextScroll = LunaStaticTextScrollState(scrollTopLine: line)
        } else {
            paneScrollTopLineOverrides[paneID] = max(0, line)
        }
    }


    private func paneViewportKey(for paneID: LunaPaneID) -> String {
        let documentID = activeDocumentDescriptor?.id.rawValue ?? "no-document"
        return "\(documentID)::\(paneID.rawValue)"
    }

    private func scrollTopVisualRow(for paneID: LunaPaneID) -> Int? {
        paneScrollTopVisualRowOverrides[paneViewportKey(for: paneID)]
    }

    private mutating func setScrollTopVisualRow(_ row: Int?, for paneID: LunaPaneID) {
        let key = paneViewportKey(for: paneID)
        if let row {
            paneScrollTopVisualRowOverrides[key] = max(0, row)
        } else {
            paneScrollTopVisualRowOverrides.removeValue(forKey: key)
        }
    }

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

    private func paneContainer(
        for framebufferSize: LunaSizeI,
        theme: LunaTheme
    ) -> LunaPaneContainer {
        let paneBounds = Self.layout(for: framebufferSize, mode: demoMode).textViewBounds
        return LunaPaneContainer(
            id: "demo.phase5f2a.panes",
            bounds: paneBounds,
            state: paneWorkspaceState,
            interactionState: paneInteractionState,
            theme: theme,
            metrics: LunaPaneContainerMetrics(
                dividerThickness: 11,
                dividerRuleThickness: 1,
                minimumPaneExtent: 80,
                activePaneBorderThickness: 2
            )
        )
    }

    private func paneTextView(
        for paneID: LunaPaneID,
        framebufferSize: LunaSizeI,
        theme: LunaTheme
    ) -> LunaStaticTextView? {
        let container = paneContainer(for: framebufferSize, theme: theme)
        guard let frame = container.layout().contentFrame(
            for: paneID,
            metrics: LunaPaneContentMetrics(headerHeight: 22)
        ) else { return nil }
        let isActive = paneID == paneWorkspaceState.activePaneID
        return Self.staticTextView(
            id: frame.nodeID,
            bounds: frame.contentBounds,
            document: staticTextDocument,
            scrollTopLine: scrollTopLine(for: paneID),
            scrollTopVisualRow: scrollTopVisualRow(for: paneID),
            caret: isActive ? staticTextCaret : nil,
            selection: isActive ? staticTextSelection : nil,
            highlights: findHighlights(theme: theme),
            theme: theme,
            wrapMode: .soft
        )
    }

    private func paneTextView(
        at point: LunaPointI,
        framebufferSize: LunaSizeI,
        theme: LunaTheme
    ) -> (paneID: LunaPaneID, view: LunaStaticTextView)? {
        let container = paneContainer(for: framebufferSize, theme: theme)
        let contentFrames = container.layout().contentFrames(
            metrics: LunaPaneContentMetrics(headerHeight: 22)
        )
        guard let frame = contentFrames.first(where: { $0.contentBounds.contains(x: point.x, y: point.y) }),
              let view = paneTextView(for: frame.paneID, framebufferSize: framebufferSize, theme: theme)
        else { return nil }
        return (frame.paneID, view)
    }

    public var cursorIntent: LunaCursorIntent { currentCursorIntent }
    public var wantsPointerCapture: Bool {
        paneInteractionState.wantsPointerCapture || textSelectionInteractionState.wantsPointerCapture
    }

    public mutating func cancelPointerInteraction() {
        paneInteractionState.cancelDrag()
        paneInteractionState.hoveredSplitID = nil
        textSelectionInteractionState.cancel()
        currentCursorIntent = .arrow
        lastInteractionStatus = "C1B pointer interaction cancelled after native capture loss"
    }

    private func resolvedCursorIntent(
        at point: LunaPointI,
        framebufferSize: LunaSizeI
    ) -> LunaCursorIntent {
        if textSelectionInteractionState.isSelecting { return .text }
        if hasActiveTransientOverlay { return .arrow }
        let container = paneContainer(for: framebufferSize, theme: theme)
        if let dividerIntent = container.cursorIntent(at: point) {
            return dividerIntent
        }
        if paneTextView(at: point, framebufferSize: framebufferSize, theme: theme) != nil {
            return .text
        }
        return .arrow
    }

    private var activeDocumentDescriptor: LunaDocumentDescriptor? {
        documentStore.activeDescriptor
    }

    /// Create a new demo scene.
    ///
    /// `startTimeNanoseconds` seeds the proof-gallery animation clock so tests
    /// and scripted demo launches can use deterministic timing without exposing
    /// wall-clock policy to LunaUI.
    public init(
        theme: LunaTheme = MothDemoTheme.theme,
        mode: LunaDemoMode = .editor,
        openLocalFilePaths: [String] = [],
        createLocalFilePaths: [String] = [],
        newUntitledDocumentCount: Int = 0,
        dialogService: any LunaDialogService = LunaNoOpDialogService(),
        overwritesDemoSaveAsTarget: Bool = false,
        overwritesCreatedLocalFiles: Bool = false,
        startTimeNanoseconds: UInt64 = LunaCPUDemoScene.nowMonotonicNanoseconds()
    ) {
        let resolvedTheme = MothDemoTheme.canonicalTheme(for: theme)
        self.proofGalleryAnimationClock = LunaAnimationClock(
            defaultDeltaSeconds: 1.0 / 60.0,
            maximumDeltaSeconds: 1.0 / 30.0,
            startTimeNanoseconds: startTimeNanoseconds
        )
        self.theme = resolvedTheme
        self.demoMode = mode
        self.dialogService = dialogService
        self.overwritesDemoSaveAsTarget = overwritesDemoSaveAsTarget
        self.lastInteractionStatus = "Ready. Mode=\(mode.rawValue). Luna UI state remains single-lane and deterministic."
        self.modalManager = LunaModalOverlayManager(style: LunaControlVisualStyle(theme: resolvedTheme))
        createLocalFilesAtLaunch(createLocalFilePaths, overwrite: overwritesCreatedLocalFiles)
        openLocalFilesAtLaunch(openLocalFilePaths)
        openUntitledDocumentsAtLaunch(count: newUntitledDocumentCount)
    }



    /// Reflow scene-owned overlays after the host window/framebuffer resizes.
    ///
    /// Background widgets are recomputed from `layout(for:)` during render and
    /// hit testing. Active modals are stateful, so the manager explicitly
    /// recalculates their panel/choice/accessibility bounds here.
    public mutating func handleWindowResize(_ size: LunaSizeI) {
        let activePaneID = paneWorkspaceState.activePaneID
        if let view = paneTextView(for: activePaneID, framebufferSize: size, theme: theme) {
            let layout = view.layout()
            setScrollTopLine(min(scrollTopLine(for: activePaneID), layout.maxScrollTopLine), for: activePaneID)
            if let visualRow = scrollTopVisualRow(for: activePaneID) {
                setScrollTopVisualRow(min(visualRow, layout.maxScrollTopVisualRow), for: activePaneID)
            }
        }
        proofGalleryStaticFrameCache = nil
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
        proofGalleryStaticFrameCache = nil
        modalManager.style = LunaControlVisualStyle(theme: resolvedTheme)
        menuBarState.close()
        contextMenuState.close()
        completionPopupState.close()
        modalManager.reflow(viewportSize: framebufferSize)
        lastInteractionStatus = "Theme: \(resolvedTheme.name) bg=\(resolvedTheme.ui.windowBackground.hexRGBA). Use Ctrl+P and run a Theme command to switch themes."
    }

    public mutating func updateFrameRuntimeDiagnostics(
        timingStats: LunaFrameTimingStats,
        invalidations: LunaFrameInvalidationSet,
        inputCoalescingStats: LunaInputCoalescingStats = LunaInputCoalescingStats()
    ) {
        frameTimingStats = timingStats
        latestFrameInvalidations = invalidations
        latestInputCoalescingStats = inputCoalescingStats
    }

    public var wantsContinuousRendering: Bool {
        demoMode.usesProofGallerySurfaces || textSelectionInteractionState.wantsContinuousUpdates
    }

    /// Render one frame into the provided framebuffer.
    ///
    /// - Important: The default editor mode remains event/invalidation driven.
    ///   Proof-gallery mode may request continuous frames for the moving-square
    ///   proof, but animation-only frames reuse a static framebuffer cache so the
    ///   editor shell, sidebar, status rows, and text viewport are not rebuilt
    ///   every vsync when no UI state changed.
    public mutating func render(into fb: inout LunaFramebuffer) {
        advanceTextSelectionAutoscroll(
            framebufferSize: LunaSizeI(width: fb.width, height: fb.height)
        )
        frameIndex &+= 1

        let now = Self.nowMonotonicNanoseconds()
        let proofAnimationFrame = demoMode.usesProofGallerySurfaces
            ? proofGalleryAnimationClock.advance(toNanoseconds: now)
            : nil
        let proofAnimationSeconds = proofAnimationFrame?.elapsedSeconds ?? 0.0

        // Draw from a canonicalized copy of the active theme. This makes key 2
        // impossible to confuse with the Luna demo-blue palette: if the theme is
        // named as the Moth demo, all visible pixels resolve through the demo-only
        // Moth palette before any drawing happens.
        let renderTheme = MothDemoTheme.canonicalTheme(for: theme)
        let frameSize = LunaSizeI(width: fb.width, height: fb.height)
        let renderLayout = Self.layout(for: frameSize, mode: demoMode)
        let activeMenuBar = demoMenuBar(for: frameSize, state: menuBarState, theme: renderTheme)

        if canUseProofGalleryStaticFrameCache(framebufferSize: frameSize),
           restoreProofGalleryStaticFrame(into: &fb, framebufferSize: frameSize) {
            drawProofGalleryDynamicSurfaces(
                into: &fb,
                layout: renderLayout,
                timeSeconds: proofAnimationSeconds,
                animationFrame: proofAnimationFrame,
                theme: renderTheme
            )
            return
        }

        drawStaticDemoFrame(
            into: &fb,
            frameSize: frameSize,
            layout: renderLayout,
            menuBar: activeMenuBar,
            theme: renderTheme
        )

        if demoMode.usesProofGallerySurfaces {
            storeProofGalleryStaticFrame(from: fb)
            drawProofGalleryDynamicSurfaces(
                into: &fb,
                layout: renderLayout,
                timeSeconds: proofAnimationSeconds,
                animationFrame: proofAnimationFrame,
                theme: renderTheme
            )
        }

        drawTransientOverlays(
            into: &fb,
            frameSize: frameSize,
            menuBar: activeMenuBar,
            theme: renderTheme
        )
    }

    /// Draw the full static scene. Dynamic proof-gallery animation/HUD surfaces
    /// and transient overlays are intentionally drawn by separate helpers so
    /// animation-only frames can restore this static frame from cache.
    private mutating func drawStaticDemoFrame(
        into fb: inout LunaFramebuffer,
        frameSize: LunaSizeI,
        layout renderLayout: LunaCPUDemoSceneLayout,
        menuBar activeMenuBar: LunaMenuBar,
        theme renderTheme: LunaTheme
    ) {
        drawBackground(into: &fb, theme: renderTheme)
        drawDemoChrome(into: &fb, layout: renderLayout, theme: renderTheme)
        drawMenuBarOverlay(
            into: &fb,
            menuBar: activeMenuBar,
            theme: renderTheme
        )
        drawEditorShellOverlay(
            into: &fb,
            shell: Self.editorShell(
                for: frameSize,
                state: editorShellState,
                theme: renderTheme,
                tabs: demoShellTabs(),
                statusSegments: demoStatusSegments(),
                mode: demoMode
            ),
            theme: renderTheme
        )
        if demoMode.usesProofGallerySurfaces {
            drawProofPanelChrome(into: &fb, layout: renderLayout, theme: renderTheme)
        }
        let paneScrollPositions = Dictionary(
            uniqueKeysWithValues: paneWorkspaceState.paneIDs.map { paneID in
                (paneID, (line: scrollTopLine(for: paneID), visualRow: scrollTopVisualRow(for: paneID)))
            }
        )
        drawPaneBoundTextViews(
            into: &fb,
            state: paneWorkspaceState,
            bounds: renderLayout.textViewBounds,
            document: staticTextDocument,
            scrollPositions: paneScrollPositions,
            caret: staticTextCaret,
            selection: staticTextSelection,
            highlights: findHighlights(theme: renderTheme),
            theme: renderTheme
        )
        if demoMode.usesProofGallerySurfaces {
            drawSemanticWidgetProof(
                into: &fb,
                activationCount: semanticActivationCount,
                theme: renderTheme
            )
        }
    }

    /// Draw only the proof-gallery surfaces that are supposed to change on every
    /// animation frame. Keeping this small makes the old proof demo smooth while
    /// preserving the default editor harness as the real app-performance baseline.
    private func drawProofGalleryDynamicSurfaces(
        into fb: inout LunaFramebuffer,
        layout renderLayout: LunaCPUDemoSceneLayout,
        timeSeconds proofAnimationSeconds: Double,
        animationFrame proofAnimationFrame: LunaAnimationFrame?,
        theme renderTheme: LunaTheme
    ) {
        guard demoMode.usesProofGallerySurfaces else { return }
        drawMovingBlock(
            into: &fb,
            timeSeconds: proofAnimationSeconds,
            bounds: renderLayout.proofPanelBounds,
            theme: renderTheme
        )
        drawHUD(
            into: &fb,
            layout: renderLayout,
            timeSeconds: proofAnimationSeconds,
            animationFrame: proofAnimationFrame,
            frameIndex: frameIndex,
            theme: renderTheme
        )
    }

    private func drawTransientOverlays(
        into fb: inout LunaFramebuffer,
        frameSize: LunaSizeI,
        menuBar activeMenuBar: LunaMenuBar,
        theme renderTheme: LunaTheme
    ) {
        if activeMenuBar.state.isOpen {
            drawMenuDropdownOverlay(
                into: &fb,
                menuBar: activeMenuBar,
                theme: renderTheme
            )
        }
        drawContextMenuOverlay(
            into: &fb,
            contextMenu: Self.contextMenu(for: frameSize, state: contextMenuState, theme: renderTheme),
            theme: renderTheme
        )
        drawCompletionPopupOverlay(
            into: &fb,
            completionPopup: Self.completionPopup(for: frameSize, state: completionPopupState, theme: renderTheme),
            theme: renderTheme
        )
        drawActiveFindPanelOverlay(
            into: &fb,
            findPanel: activeFindPanel(framebufferSize: frameSize, theme: renderTheme),
            theme: renderTheme
        )
        drawActiveQuickPanelOverlay(
            into: &fb,
            quickPanel: activeQuickPanel(framebufferSize: frameSize, theme: renderTheme),
            theme: renderTheme
        )
        drawActiveModalOverlay(into: &fb, manager: modalManager)
    }

    private var hasActiveTransientOverlay: Bool {
        menuBarState.isOpen ||
        contextMenuState.isOpen ||
        completionPopupState.isOpen ||
        findPanelState != nil ||
        quickPanelState != nil ||
        modalManager.hasActiveModal
    }

    private func canUseProofGalleryStaticFrameCache(framebufferSize: LunaSizeI) -> Bool {
        guard demoMode.usesProofGallerySurfaces else { return false }
        guard !hasActiveTransientOverlay else { return false }
        guard latestFrameInvalidations.reasons == Set([LunaInvalidationReason.animation]) else { return false }
        guard let cache = proofGalleryStaticFrameCache else { return false }
        return cache.matches(width: framebufferSize.width, height: framebufferSize.height)
    }

    private func restoreProofGalleryStaticFrame(into fb: inout LunaFramebuffer, framebufferSize: LunaSizeI) -> Bool {
        guard let cache = proofGalleryStaticFrameCache,
              cache.matches(width: framebufferSize.width, height: framebufferSize.height) else {
            return false
        }
        fb.copyPixels(from: cache.framebuffer)
        return true
    }

    private mutating func storeProofGalleryStaticFrame(from framebuffer: LunaFramebuffer) {
        if proofGalleryStaticFrameCache?.matches(width: framebuffer.width, height: framebuffer.height) != true {
            proofGalleryStaticFrameCache = LunaProofGalleryStaticFrameCache(width: framebuffer.width, height: framebuffer.height)
        }
        proofGalleryStaticFrameCache?.framebuffer.copyPixels(from: framebuffer)
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
        currentCursorIntent = resolvedCursorIntent(
            at: event.location,
            framebufferSize: framebufferSize
        )

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
                    announcementTexts: context.announcements.map(\.text),
                    didChangeVisualState: modalResult.didChangeVisualState || modalResult.didDismiss || modalResult.requestedCommand != nil
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
                        performDemoCommand(command, framebufferSize: framebufferSize)
                    } else if let item = result.selectedItem {
                        lastInteractionStatus = "Phase 4A selected quick panel item: \(item.title)"
                    }
                    return LunaPointerActivationResult(
                        event: event,
                        hitNodeID: hit,
                        requestedCommand: result.requestedCommand,
                        announcementTexts: ["Command palette selected"],
                        didChangeVisualState: true
                    )
                }

                // The quick panel consumes backdrop/panel clicks while active.
                quickPanelState = hit == panel.id ? nil : state
                lastInteractionStatus = hit == panel.id ? "Phase 4A command palette dismissed" : "Phase 4A command palette pointer hit: \(hit.rawValue)"
                return LunaPointerActivationResult(event: event, hitNodeID: hit, requestedCommand: nil, didChangeVisualState: true)
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
                return LunaPointerActivationResult(event: event, hitNodeID: hit, requestedCommand: nil, didChangeVisualState: true)
            }
        }

        // Phase 4E context menu routing. A floating context menu owns pointer
        // input until activation or dismissal, so clicks do not leak into tabs,
        // sidebar rows, status segments, or the editor underneath.
        if contextMenuState.isOpen {
            let commandContextAttributes = contextMenuState.definition?.commandContextAttributes ?? [:]
            var state = contextMenuState
            let contextMenu = Self.contextMenu(for: framebufferSize, state: state, theme: theme)
            let result = contextMenu.handlePointerEvent(event, state: &state)
            contextMenuState = state
            if let command = result.requestedCommand {
                performDemoCommand(command, framebufferSize: framebufferSize, source: "context-menu", attributes: commandContextAttributes)
                lastInteractionStatus = "Phase 4E context menu ran command: \(result.activatedTitle ?? command.rawValue)"
            } else if result.didDismiss {
                lastInteractionStatus = "Phase 4E context menu dismissed"
            } else if result.didChangeState, let hit = result.hitNodeID {
                lastInteractionStatus = "Phase 4E context menu hit: \(hit.rawValue)"
            }
            if result.didConsumeEvent {
                return LunaPointerActivationResult(
                    event: event,
                    hitNodeID: result.hitNodeID,
                    requestedCommand: result.requestedCommand,
                    announcementTexts: result.requestedCommand == nil ? [] : ["Context menu command activated"],
                    didChangeVisualState: result.didChangeState || result.didDismiss || result.requestedCommand != nil
                )
            }
        }

        // Phase 4F completion popup routing. The anchored popup owns pointer
        // events until activation/dismissal so row clicks do not also move the
        // editor caret underneath. Secondary/context clicks are consumed while
        // open; the user can right-click again after the popup closes.
        if completionPopupState.isOpen {
            var state = completionPopupState
            let completionPopup = Self.completionPopup(for: framebufferSize, state: state, theme: theme)
            let result = completionPopup.handlePointerEvent(event, state: &state)
            completionPopupState = state
            if let item = result.selectedItem {
                applyCompletionSelection(item, insertionText: result.insertionText, framebufferSize: framebufferSize)
            } else if result.didDismiss {
                lastInteractionStatus = "Phase 4F completion popup dismissed"
            } else if result.didChangeState, let hit = result.hitNodeID {
                lastInteractionStatus = "Phase 4F completion popup hit: \(hit.rawValue)"
            }
            if result.didConsumeEvent {
                return LunaPointerActivationResult(
                    event: event,
                    hitNodeID: result.hitNodeID,
                    requestedCommand: result.requestedCommand,
                    announcementTexts: result.selectedItem == nil ? [] : ["Completion accepted"],
                    didChangeVisualState: result.didChangeState || result.didDismiss || result.selectedItem != nil
                )
            }
        }

        // Phase 4C menu routing. Menus sit below modal/palette/find overlays but
        // above the editor surface. When a menu is open, outside clicks close it
        // and are consumed so they do not accidentally edit text underneath.
        do {
            var state = menuBarState
            let menu = demoMenuBar(for: framebufferSize, state: state, theme: theme)
            let result = menu.handlePointerEvent(event, state: &state)
            menuBarState = state
            if let command = result.requestedCommand {
                performDemoCommand(command, framebufferSize: framebufferSize)
                lastInteractionStatus = "Phase 4C menu ran command: \(result.activatedTitle ?? command.rawValue)"
            } else if result.didDismiss {
                lastInteractionStatus = "Phase 4C menu dismissed"
            } else if result.didChangeState, let hit = result.hitNodeID {
                lastInteractionStatus = "Phase 4C menu hit: \(hit.rawValue)"
            }
            if result.didConsumeEvent {
                return LunaPointerActivationResult(
                    event: event,
                    hitNodeID: result.hitNodeID,
                    requestedCommand: result.requestedCommand,
                    announcementTexts: result.requestedCommand == nil ? [] : ["Menu command activated"],
                    didChangeVisualState: result.didChangeState || result.didDismiss || result.requestedCommand != nil
                )
            }
        }

        if event.phase == .down, event.button == .secondary,
           let definition = demoContextMenuDefinition(at: event.location, framebufferSize: framebufferSize) {
            contextMenuState.open(definition, at: event.location)
            menuBarState.close()
            completionPopupState.close()
            textSelectionInteractionState.cancel()
            lastInteractionStatus = "Phase 4E context menu opened: \(definition.title)"
            return LunaPointerActivationResult(
                event: event,
                hitNodeID: definition.sourceNodeID,
                requestedCommand: nil,
                announcementTexts: ["Context menu opened"],
                didChangeVisualState: true
            )
        }

        // Phase 4D shell routing. The shell owns its chrome regions (tabs,
        // project/sidebar rows, status segments) but deliberately does not
        // consume editor-content hits, so the text surface can still receive
        // caret/selection events inside the editor frame.
        do {
            var state = editorShellState
            let shell = Self.editorShell(
                for: framebufferSize,
                state: state,
                theme: theme,
                tabs: demoShellTabs(),
                statusSegments: demoStatusSegments(),
                mode: demoMode
            )
            let result = shell.handlePointerEvent(event, state: &state)
            editorShellState = state
            if let command = result.requestedCommand {
                let attributes = result.closedTabID.map { shellTabID in
                    [
                        LunaCommandContextAttributeKey.targetDocumentID: shellTabID.rawValue,
                        LunaCommandContextAttributeKey.targetShellTabID: shellTabID.rawValue,
                    ]
                } ?? [:]
                performDemoCommand(command, framebufferSize: framebufferSize, source: "editor-shell", attributes: attributes)
            } else if let tab = result.selectedTabID {
                lastInteractionStatus = "Phase 4D selected tab: \(tab.rawValue)"
            } else if let tab = result.closedTabID {
                lastInteractionStatus = "Phase 4D close tab requested: \(tab.rawValue)"
            } else if let item = result.selectedSidebarItemID {
                lastInteractionStatus = "Phase 4D selected sidebar item: \(item.rawValue)"
            } else if let item = result.toggledSidebarItemID {
                lastInteractionStatus = "Phase 4D toggled sidebar item: \(item.rawValue)"
            } else if let segment = result.activatedStatusSegmentID {
                lastInteractionStatus = "Phase 4D status segment: \(segment.rawValue)"
            }
            if result.didConsumeEvent {
                return LunaPointerActivationResult(
                    event: event,
                    hitNodeID: result.hitNodeID,
                    requestedCommand: result.requestedCommand,
                    announcementTexts: result.requestedCommand == nil ? [] : ["Shell command activated"],
                    didChangeVisualState: result.didChangeState || result.requestedCommand != nil
                )
            }
        }

        // C1A pane routing. The reusable interaction state owns hover and drag
        // identity. A divider drag consumes pointer motion until mouse-up and
        // requests native capture through the SDL scene contract.
        do {
            let wasDragging = paneInteractionState.isDraggingDivider
            let container = paneContainer(for: framebufferSize, theme: theme)
            var workspace = paneWorkspaceState
            var interaction = paneInteractionState
            let result = container.handlePointerEvent(
                event,
                state: &workspace,
                interactionState: &interaction
            )
            paneWorkspaceState = workspace
            paneInteractionState = interaction
            currentCursorIntent = resolvedCursorIntent(
                at: event.location,
                framebufferSize: framebufferSize
            )

            if let split = result.resizedSplitID {
                lastInteractionStatus = interaction.isDraggingDivider
                    ? "C1A dragging split with pointer capture: \(split.rawValue)"
                    : "C1A split drag completed: \(split.rawValue)"
            } else if let pane = result.activatedPaneID {
                lastInteractionStatus = "C1A active pane: \(pane.rawValue)"
            }

            let ownsDividerGesture = wasDragging || interaction.isDraggingDivider || result.resizedSplitID != nil
            if ownsDividerGesture {
                textSelectionInteractionState.cancel()
                return LunaPointerActivationResult(
                    event: event,
                    hitNodeID: result.hitNodeID,
                    requestedCommand: nil,
                    announcementTexts: [interaction.isDraggingDivider ? "Split divider dragging" : "Split divider resized"],
                    didChangeVisualState: true
                )
            }
        }

        // C1B text selection routing. The reusable Luna gesture state owns
        // click count, drag capture, UTF-8-safe word/line ranges, and edge
        // autoscroll requests. The demo continues to own editable document state.
        if event.button == .primary {
            let target: (paneID: LunaPaneID, view: LunaStaticTextView)?
            if event.phase == .down {
                target = paneTextView(
                    at: event.location,
                    framebufferSize: framebufferSize,
                    theme: theme
                )
            } else {
                target = paneTextView(
                    forSurfaceID: textSelectionInteractionState.activeSurfaceID,
                    framebufferSize: framebufferSize,
                    theme: theme
                )
            }

            if let target {
                var interaction = textSelectionInteractionState
                let result = LunaTextSelectionInteraction.handlePointerEvent(
                    event,
                    in: target.view,
                    currentCaret: staticTextCaret.location,
                    currentSelection: staticTextSelection?.range,
                    state: &interaction
                )
                textSelectionInteractionState = interaction
                currentCursorIntent = resolvedCursorIntent(
                    at: event.location,
                    framebufferSize: framebufferSize
                )

                if result.didConsumeEvent {
                    applyTextSelectionResult(
                        result,
                        paneID: target.paneID,
                        framebufferSize: framebufferSize
                    )
                    let selectedBytes = staticTextSelection.map {
                        staticTextDocument.accessibilityRange(for: $0.range).utf8Length
                    } ?? 0
                    let gestureName: String
                    switch result.granularity ?? interaction.granularity {
                    case .character: gestureName = result.didEndGesture ? "selection complete" : "drag selection"
                    case .word: gestureName = "word selection"
                    case .line: gestureName = "line selection"
                    }
                    lastInteractionStatus = "C1B \(gestureName) in \(target.paneID.rawValue): bytes=\(selectedBytes)"
                    return LunaPointerActivationResult(
                        event: event,
                        hitNodeID: result.hitNodeID,
                        requestedCommand: nil,
                        announcementTexts: [selectedBytes > 0 ? "Text selected" : "Caret placed"],
                        didChangeVisualState: result.didChangeSelection || result.didBeginGesture || result.didEndGesture
                    )
                }
            } else if event.phase == .down {
                textSelectionInteractionState.cancel()
            }
        }

        if demoMode.usesProofGallerySurfaces {
            // The background semantic widget still uses the Phase 1B activation rule:
            // primary pointer-down activates. Hover support for ordinary widgets will
            // come after the modal/control-state model is proven.
            var widget = Self.semanticWidget(for: framebufferSize, isFocused: true, theme: theme, mode: demoMode)
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
                return LunaPointerActivationResult(
                    event: event,
                    hitNodeID: result.hitNodeID,
                    requestedCommand: result.requestedCommand,
                    announcementTexts: result.announcementTexts,
                    didChangeVisualState: true
                )
            } else if result.didHit {
                lastInteractionStatus = "Hit semantic widget, but no command was requested"
                return LunaPointerActivationResult(event: event, hitNodeID: result.hitNodeID, requestedCommand: nil, didChangeVisualState: true)
            } else if event.phase == .down {
                lastInteractionStatus = "Missed semantic widget at x=\(event.location.x), y=\(event.location.y)"
                return LunaPointerActivationResult(event: event, hitNodeID: nil, requestedCommand: nil, didChangeVisualState: true)
            }

            return result
        }

        return LunaPointerActivationResult(event: event, hitNodeID: nil, requestedCommand: nil)
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

        if let suppressed = pendingShortcutTextInputSuppression {
            pendingShortcutTextInputSuppression = nil
            if event.text.lowercased() == suppressed {
                lastInteractionStatus = "Shortcut text input suppressed: \(event.text.debugDescription)"
                return true
            }
        }

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

        if contextMenuState.isOpen {
            lastInteractionStatus = "Phase 4E context menu consumed text input"
            return true
        }

        if completionPopupState.isOpen {
            completionPopupState.close()
        }

        textSelectionInteractionState.cancel()
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
                    performDemoCommand(command, framebufferSize: framebufferSize)
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
            // While the command palette is open it owns keyboard input. This
            // prevents command/control chords and other unhandled key-downs from
            // leaking into the editor underneath the overlay.
            return true
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
            // While the find panel is open it owns keyboard input. The editor
            // underneath should not receive keys that the find UI chooses not to
            // handle yet.
            return true
        }

        if contextMenuState.isOpen {
            let commandContextAttributes = contextMenuState.definition?.commandContextAttributes ?? [:]
            var state = contextMenuState
            let contextMenu = Self.contextMenu(for: framebufferSize, state: state, theme: theme)
            let result = contextMenu.handleKeyboardEvent(event, state: &state)
            contextMenuState = state
            if let command = result.requestedCommand {
                performDemoCommand(command, framebufferSize: framebufferSize, source: "context-menu", attributes: commandContextAttributes)
                lastInteractionStatus = "Phase 4E context menu ran command: \(result.activatedTitle ?? command.rawValue)"
            } else if result.didDismiss {
                lastInteractionStatus = "Phase 4E context menu dismissed"
            } else if result.didChangeState {
                lastInteractionStatus = "Phase 4E context menu keyboard navigation"
            }
            return result.didConsumeEvent
        }

        if completionPopupState.isOpen {
            var state = completionPopupState
            let completionPopup = Self.completionPopup(for: framebufferSize, state: state, theme: theme)
            let result = completionPopup.handleKeyboardEvent(event, state: &state)
            completionPopupState = state
            if let item = result.selectedItem {
                applyCompletionSelection(item, insertionText: result.insertionText, framebufferSize: framebufferSize)
                lastInteractionStatus = "Phase 4F accepted completion: \(item.title)"
            } else if result.didDismiss {
                lastInteractionStatus = "Phase 4F completion popup dismissed"
            } else if result.didChangeState {
                lastInteractionStatus = "Phase 4F completion popup keyboard navigation"
            }
            if result.didConsumeEvent { return true }
        }

        if menuBarState.isOpen {
            var state = menuBarState
            let menu = demoMenuBar(for: framebufferSize, state: state, theme: theme)
            let result = menu.handleKeyboardEvent(event, state: &state)
            menuBarState = state
            if let command = result.requestedCommand {
                performDemoCommand(command, framebufferSize: framebufferSize)
                lastInteractionStatus = "Phase 4C menu ran command: \(result.activatedTitle ?? command.rawValue)"
            } else if result.didDismiss {
                lastInteractionStatus = "Phase 4C menu dismissed"
            } else if result.didChangeState {
                lastInteractionStatus = "Phase 4C menu keyboard navigation"
            }
            return result.didConsumeEvent
        }

        textSelectionInteractionState.cancel()

        if let command = Self.demoCommandRuntime.command(
            matching: event.lunaCommandKeyStroke,
            host: self,
            context: demoCommandContext(framebufferSize: framebufferSize, source: "keyboard")
        ) {
            if let suppressed = event.lunaShortcutTextInputSuppressionCandidate {
                suppressShortcutTextInput(suppressed)
            }
            performDemoCommand(command, framebufferSize: framebufferSize)
            return true
        }

        switch event.key {
        case .enter:
            let result = editableTextState.insertNewline()
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
            lastInteractionStatus = "Phase 3D newline: caret line \(result.newCaret.location.lineIndex + 1), col \(result.newCaret.location.utf8Column); rev=\(editableTextState.editRevision)"
            return true
        case .backspace:
            textSelectionInteractionState.cancel()
            let result = editableTextState.deleteBackward()
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
            lastInteractionStatus = result.didChange
                ? "Phase 3D backspace: caret line \(result.newCaret.location.lineIndex + 1), col \(result.newCaret.location.utf8Column); rev=\(editableTextState.editRevision)"
                : "Phase 3D backspace: start of document"
            return true
        case .delete:
            textSelectionInteractionState.cancel()
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

    private mutating func suppressShortcutTextInput(_ text: String) {
        pendingShortcutTextInputSuppression = text.lowercased()
    }

    private mutating func openQuickPanel() {
        menuBarState.close()
        contextMenuState.close()
        completionPopupState.close()
        findPanelState = nil
        let context = demoCommandContext(framebufferSize: LunaSizeI(width: 1024, height: 768), source: "palette")
        let descriptors = Self.demoCommandRuntime.paletteDescriptors(host: self, context: context)
        quickPanelState = LunaQuickPanelState(items: descriptors.map(LunaQuickPanelItem.init(command:)))
    }

    private func activeQuickPanel(framebufferSize: LunaSizeI, theme: LunaTheme) -> LunaQuickPanel? {
        guard let state = quickPanelState else { return nil }
        return Self.quickPanel(for: framebufferSize, state: state, theme: theme)
    }

    private mutating func openFindPanel(framebufferSize: LunaSizeI) {
        menuBarState.close()
        contextMenuState.close()
        completionPopupState.close()
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

    private func demoMenuBar(for framebufferSize: LunaSizeI, state: LunaMenuBarState, theme: LunaTheme) -> LunaMenuBar {
        Self.menuBar(
            for: framebufferSize,
            state: state,
            theme: theme,
            menus: resolvedDemoMenus(for: theme, framebufferSize: framebufferSize),
            mode: demoMode
        )
    }

    private func resolvedDemoMenus(for theme: LunaTheme, framebufferSize: LunaSizeI) -> [LunaMenuDefinition] {
        let context = demoCommandContext(framebufferSize: framebufferSize, source: "menu")
        return Self.demoMenus(for: theme).map { definition in
            LunaMenuDefinition(
                id: definition.id,
                title: definition.title,
                items: resolvedMenuItems(definition.items, context: context)
            )
        }
    }

    private func resolvedMenuItems(_ items: [LunaMenuItem], context: LunaCommandContext) -> [LunaMenuItem] {
        items.map { item in
            var resolved = item
            if !item.children.isEmpty {
                resolved.children = resolvedMenuItems(item.children, context: context)
            }
            guard let command = item.command,
                  let surface = Self.demoCommandRuntime.surfaceItem(for: command, host: self, context: context) else {
                return resolved
            }
            resolved.title = surface.title
            resolved.keyEquivalent = surface.keyEquivalent ?? item.keyEquivalent
            resolved.isEnabled = item.isEnabled && surface.isEnabled
            resolved.isChecked = item.isChecked || surface.isChecked
            resolved.accessibilityLabel = surface.accessibilityLabel
            return resolved
        }
    }


    private mutating func openCompletionPopup(framebufferSize: LunaSizeI) {
        menuBarState.close()
        contextMenuState.close()
        quickPanelState = nil
        findPanelState = nil
        textSelectionInteractionState.cancel()

        let anchor = completionAnchorRect(framebufferSize: framebufferSize)
        completionPopupState.open(items: Self.demoCompletionItems, anchorRect: anchor)
        lastInteractionStatus = "Phase 4F completion popup opened; arrows navigate, Enter/Tab accepts, Esc closes"
    }

    private func activeCompletionPopup(framebufferSize: LunaSizeI, theme: LunaTheme) -> LunaCompletionPopup? {
        guard completionPopupState.isOpen else { return nil }
        return Self.completionPopup(for: framebufferSize, state: completionPopupState, theme: theme)
    }

    private func completionAnchorRect(framebufferSize: LunaSizeI) -> LunaRectI {
        if let textView = paneTextView(
            for: paneWorkspaceState.activePaneID,
            framebufferSize: framebufferSize,
            theme: theme
        ), let caretRect = textView.layout().caretRect {
            return caretRect
        }
        let layout = Self.layout(for: framebufferSize, mode: demoMode)
        return LunaRectI(x: layout.textViewBounds.x + 72, y: layout.textViewBounds.y + 24, w: 2, h: 18)
    }

    private mutating func applyCompletionSelection(_ item: LunaCompletionItem, insertionText: String?, framebufferSize: LunaSizeI) {
        completionPopupState.close()
        if let command = item.command {
            performDemoCommand(command, framebufferSize: framebufferSize)
            return
        }
        let text = insertionText ?? item.insertText ?? item.title
        let result = editableTextState.insertText(text)
        ensureEditableCaretVisible(framebufferSize: framebufferSize)
        lastInteractionStatus = "Phase 4F inserted completion \(item.title.debugDescription); caret line \(result.newCaret.location.lineIndex + 1), col \(result.newCaret.location.utf8Column)"
    }


    private func demoContextMenuDefinition(at point: LunaPointI, framebufferSize: LunaSizeI) -> LunaContextMenuDefinition? {
        let renderTheme = MothDemoTheme.canonicalTheme(for: theme)
        let shell = Self.editorShell(
            for: framebufferSize,
            state: editorShellState,
            theme: renderTheme,
            tabs: demoShellTabs(),
            statusSegments: demoStatusSegments(),
            mode: demoMode
        )
        let shellLayout = shell.layout()
        let shellHit = shell.hitTest(point)
        let textHit = paneTextView(
            at: point,
            framebufferSize: framebufferSize,
            theme: renderTheme
        )?.view.textHitTest(point)

        let themeItems = demoThemeContextMenuItems(for: renderTheme)
        let commandContext = demoCommandContext(framebufferSize: framebufferSize, source: "context-menu")
        let hasSelection = editableTextState.selection != nil
        let editorItems: [LunaMenuItem] = [
            LunaMenuItem.command(id: "editor.copy", title: "Copy", command: "luna.demo.context.copy", keyEquivalent: LunaKeyEquivalent("C", modifiers: [.primary]), isEnabled: hasSelection),
            LunaMenuItem.command(id: "editor.cut", title: "Cut", command: "luna.demo.context.cut", keyEquivalent: LunaKeyEquivalent("X", modifiers: [.primary]), isEnabled: false),
            LunaMenuItem.command(id: "editor.paste", title: "Paste Sample Text", command: "luna.demo.context.paste", keyEquivalent: LunaKeyEquivalent("V", modifiers: [.primary])),
            LunaMenuItem.separator(id: "editor.sep.0"),
            LunaMenuItem.command(id: "editor.selectAll", title: "Select All", command: "luna.demo.edit.selectAll", keyEquivalent: LunaKeyEquivalent("A", modifiers: [.primary])),
            LunaMenuItem.command(id: "editor.clearSelection", title: "Clear Selection", command: "luna.demo.selection.clear", isEnabled: hasSelection),
            LunaMenuItem.separator(id: "editor.sep.1"),
            LunaMenuItem.command(id: "editor.find", title: "Find / Replace…", command: "luna.demo.find.open", keyEquivalent: LunaKeyEquivalent("F", modifiers: [.primary])),
            LunaMenuItem.command(id: "editor.completions", title: "Show Completions", command: "luna.demo.completion.open", keyEquivalent: LunaKeyEquivalent("Space", modifiers: [.primary])),
            LunaMenuItem.submenu(id: "editor.theme", title: "Theme", children: themeItems),
            LunaMenuItem.separator(id: "editor.sep.2"),
            LunaMenuItem.command(id: "editor.info", title: "Context Menu Info", command: "luna.demo.context.info"),
        ]

        if let textHit {
            return LunaContextMenuDefinition(
                id: "editor-text",
                title: "Editor Context",
                items: resolvedMenuItems(editorItems, context: commandContext),
                sourceNodeID: textHit.nodeID,
                accessibilityLabel: "Editor Context Menu"
            )
        }

        if let shellHit, let tab = shellLayout.tabFrame(for: shellHit) {
            let items: [LunaMenuItem] = [
                LunaMenuItem.command(id: "tab.activate", title: "Activate Tab", command: tab.tab.activateCommand ?? "luna.demo.context.info"),
                LunaMenuItem.command(id: "tab.close", title: "Close Tab", command: tab.tab.closeCommand ?? "luna.demo.tab.close", keyEquivalent: LunaKeyEquivalent("W", modifiers: [.primary]), isEnabled: tab.tab.isClosable),
                LunaMenuItem.command(id: "tab.closeOthers", title: "Close Other Tabs", command: "luna.demo.context.info", isEnabled: false),
                LunaMenuItem.separator(id: "tab.sep.0"),
                LunaMenuItem.command(id: "tab.pin", title: "Pinned", command: "luna.demo.context.info", isChecked: tab.tab.isPinned),
                LunaMenuItem.command(id: "tab.reveal", title: "Reveal in Sidebar", command: "luna.demo.context.reveal"),
                LunaMenuItem.submenu(id: "tab.theme", title: "Theme", children: themeItems),
                LunaMenuItem.separator(id: "tab.sep.1"),
                LunaMenuItem.command(id: "tab.info", title: "Context Menu Info", command: "luna.demo.context.info"),
            ]
            return LunaContextMenuDefinition(
                id: "tab-\(tab.tab.id.rawValue)",
                title: "Tab: \(tab.tab.title)",
                items: resolvedMenuItems(items, context: commandContext.withAttributes([
                    LunaCommandContextAttributeKey.targetDocumentID: tab.tab.id.rawValue,
                    LunaCommandContextAttributeKey.targetShellTabID: tab.tab.id.rawValue,
                ])),
                sourceNodeID: tab.nodeID,
                accessibilityLabel: "Tab Context Menu",
                commandContextAttributes: [
                    LunaCommandContextAttributeKey.targetDocumentID: tab.tab.id.rawValue,
                    LunaCommandContextAttributeKey.targetShellTabID: tab.tab.id.rawValue,
                ]
            )
        }

        if let shellHit, let row = shellLayout.rowFrame(for: shellHit) {
            let isFolder = row.item.hasChildren
            let items: [LunaMenuItem] = [
                LunaMenuItem.command(id: "sidebar.open", title: isFolder ? "Open Folder" : "Open", command: row.item.activateCommand ?? "luna.demo.context.info", isEnabled: row.item.isSelectable),
                LunaMenuItem.command(id: "sidebar.reveal", title: "Reveal", command: "luna.demo.context.reveal"),
                LunaMenuItem.command(id: "sidebar.rename", title: "Rename…", command: "luna.demo.context.rename"),
                LunaMenuItem.separator(id: "sidebar.sep.0"),
                LunaMenuItem.command(id: "sidebar.newFile", title: "New File", command: "luna.demo.file.new"),
                LunaMenuItem.command(id: "sidebar.toggle", title: "Toggle Sidebar", command: "luna.demo.sidebar.toggle"),
                LunaMenuItem.submenu(id: "sidebar.theme", title: "Theme", children: themeItems),
                LunaMenuItem.separator(id: "sidebar.sep.1"),
                LunaMenuItem.command(id: "sidebar.info", title: "Context Menu Info", command: "luna.demo.context.info"),
            ]
            return LunaContextMenuDefinition(
                id: "sidebar-\(row.item.id.rawValue)",
                title: "Sidebar: \(row.item.title)",
                items: resolvedMenuItems(items, context: commandContext),
                sourceNodeID: row.nodeID,
                accessibilityLabel: "Sidebar Context Menu"
            )
        }

        if let shellHit, let segment = shellLayout.statusFrame(for: shellHit) {
            let items: [LunaMenuItem] = [
                LunaMenuItem.command(id: "status.toggleSidebar", title: "Toggle Sidebar", command: "luna.demo.sidebar.toggle"),
                LunaMenuItem.command(id: "status.scrollTop", title: "Scroll Editor to Top", command: "luna.demo.scroll.top"),
                LunaMenuItem.command(id: "status.scrollEnd", title: "Scroll Editor to End", command: "luna.demo.scroll.end"),
                LunaMenuItem.submenu(id: "status.theme", title: "Theme", children: themeItems),
                LunaMenuItem.separator(id: "status.sep.0"),
                LunaMenuItem.command(id: "status.info", title: "Context Menu Info", command: "luna.demo.context.info"),
            ]
            return LunaContextMenuDefinition(
                id: "status-\(segment.segment.id.rawValue)",
                title: "Status: \(segment.segment.visibleText)",
                items: resolvedMenuItems(items, context: commandContext),
                sourceNodeID: segment.nodeID,
                accessibilityLabel: "Status Bar Context Menu"
            )
        }

        if shellHit == shell.editorContentNodeID || shellLayout.editorContentBounds.contains(x: point.x, y: point.y) {
            return LunaContextMenuDefinition(
                id: "editor-content",
                title: "Editor Context",
                items: resolvedMenuItems(editorItems, context: commandContext),
                sourceNodeID: shell.editorContentNodeID,
                accessibilityLabel: "Editor Context Menu"
            )
        }

        return nil
    }

    private func demoThemeContextMenuItems(for theme: LunaTheme) -> [LunaMenuItem] {
        let current = MothDemoTheme.canonicalTheme(for: theme).name
        return [
            LunaMenuItem.command(id: "context.theme.blue", title: "Luna Demo Blue", command: "luna.demo.theme.blue", isChecked: current == LunaTheme.lunaDemoBlue.name),
            LunaMenuItem.command(id: "context.theme.moth", title: "Moth Obsidian Demo", command: "luna.demo.theme.moth", isChecked: current == MothDemoTheme.theme.name),
            LunaMenuItem.command(id: "context.theme.highContrast", title: "High Contrast Proof", command: "luna.demo.theme.highContrast", isChecked: current == LunaTheme.highContrastProof.name),
        ]
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

    private mutating func selectAllEditableText(framebufferSize: LunaSizeI) {
        editableTextState.selectAll()
        ensureEditableCaretVisible(framebufferSize: framebufferSize)
        let selectedBytes = editableTextState.selection.map { staticTextDocument.accessibilityRange(for: $0.range).utf8Length } ?? 0
        lastInteractionStatus = "Edit: Select All selected \(selectedBytes) UTF-8 bytes"
    }


    private mutating func activateDocument(_ id: LunaDocumentID, framebufferSize: LunaSizeI, reason: String) {
        guard documentStore.activate(id) else {
            lastInteractionStatus = "Phase 5A document missing: \(id.rawValue)"
            return
        }
        syncWorkspaceAndShellStateToActiveDocument()
        completionPopupState.close()
        textSelectionInteractionState.cancel()
        if var find = findPanelState {
            find.refreshResults(in: staticTextDocument, preservingSelectionNear: staticTextCaret.location)
            findPanelState = find
            syncSelectionToFindMatch(framebufferSize: framebufferSize)
        }
        ensureEditableCaretVisible(framebufferSize: framebufferSize)
        let title = activeDocumentDescriptor?.title ?? id.rawValue
        lastInteractionStatus = "Phase 5A active document: \(title) (\(reason))"
    }

    private mutating func syncWorkspaceAndShellStateToActiveDocument() {
        workspaceState.syncFromActiveDocument(documentStore)
        documentStore.syncShellState(&editorShellState, sidebarItemForDocument: { documentID in
            workspaceState.snapshot.node(for: LunaFileID(rawValue: documentID.rawValue)).map { LunaSidebarItemID(rawValue: $0.id.rawValue) }
        })
    }

    private mutating func openWorkspaceFile(_ fileID: LunaFileID, framebufferSize: LunaSizeI, source: String) {
        if documentStore.document(with: LunaDocumentID(rawValue: fileID.rawValue)) != nil {
            activateDocument(LunaDocumentID(rawValue: fileID.rawValue), framebufferSize: framebufferSize, reason: source)
            return
        }

        let result = workspaceAdapter.openFile(LunaWorkspaceOpenRequest(fileID: fileID, source: source))
        guard let file = result.file, let text = result.text else {
            lastInteractionStatus = result.statusMessage ?? "Phase 5D could not open file: \(fileID.rawValue)"
            return
        }

        workspaceState.snapshot = workspaceAdapter.projectTreeSnapshot()
        workspaceState.registerFile(file)
        _ = workspaceState.open(fileID: file.id)
        let documentID = documentStore.openOrActivate(file: file, text: text)
        syncWorkspaceAndShellStateToActiveDocument()
        completionPopupState.close()
        textSelectionInteractionState.cancel()
        ensureEditableCaretVisible(framebufferSize: framebufferSize)
        lastInteractionStatus = result.statusMessage ?? "Phase 5D opened \(file.title) through workspace adapter"
        if documentID != documentStore.activeDocumentID {
            lastInteractionStatus = "Phase 5D opened \(file.title)"
        }
    }

    private mutating func openLocalFilesAtLaunch(_ paths: [String]) {
        openLocalFiles(paths, source: "launch --open", statusPrefix: "Phase 5D opened local file(s)")
    }

    private mutating func openFileUsingDialog(framebufferSize: LunaSizeI) {
        var request = LunaFileDialogRequest(
            purpose: .open,
            title: "Open File…",
            message: "Choose a UTF-8 text file to open in the Luna editor harness.",
            defaultDirectory: FileManager.default.currentDirectoryPath,
            allowedExtensions: [],
            allowsMultipleSelection: false,
            source: "File > Open…"
        )
        request.allowsMultipleSelection = false
        let result = dialogService.chooseFileToOpen(request)
        switch result.outcome {
        case .selected:
            openLocalFiles(result.selectedPaths, source: "File > Open…", statusPrefix: "Phase 5D.3 Open… selected")
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
        case .cancelled:
            lastInteractionStatus = result.statusMessage ?? "Open… cancelled"
        case .unavailable:
            lastInteractionStatus = result.statusMessage ?? "Open… unavailable; use --open or LUNA_DEMO_DIALOG_OPEN_PATH for scripted testing"
        case .failed:
            lastInteractionStatus = result.statusMessage ?? "Open… failed"
        }
    }

    private mutating func openLocalFiles(_ paths: [String], source: String, statusPrefix: String) {
        guard !paths.isEmpty else {
            lastInteractionStatus = "\(statusPrefix): no paths selected"
            return
        }
        let registrations = workspaceAdapter.registerLocalFiles(paths)
        workspaceState.snapshot = workspaceAdapter.projectTreeSnapshot()
        var openedTitles: [String] = []
        var failures: [String] = []

        for registration in registrations {
            guard let descriptor = registration.descriptor else {
                failures.append(registration.statusMessage)
                continue
            }
            workspaceState.registerFile(descriptor)
            _ = workspaceState.open(fileID: descriptor.id)
            let result = workspaceAdapter.openFile(LunaWorkspaceOpenRequest(fileID: descriptor.id, source: source))
            guard let file = result.file, let text = result.text else {
                failures.append(result.statusMessage ?? registration.statusMessage)
                continue
            }
            _ = documentStore.openOrActivate(file: file, text: text)
            openedTitles.append(file.displayPath)
        }

        syncWorkspaceAndShellStateToActiveDocument()
        textSelectionInteractionState.cancel()
        completionPopupState.close()

        if !openedTitles.isEmpty {
            let suffix = failures.isEmpty ? "" : "; \(failures.count) file(s) failed"
            lastInteractionStatus = "\(statusPrefix): \(openedTitles.joined(separator: ", "))\(suffix)"
        } else if let firstFailure = failures.first {
            lastInteractionStatus = firstFailure
        } else {
            lastInteractionStatus = "\(statusPrefix): no local files opened"
        }
    }

    private mutating func createLocalFilesAtLaunch(_ paths: [String], overwrite: Bool) {
        guard !paths.isEmpty else { return }
        let registrations = workspaceAdapter.createEmptyLocalFiles(paths, overwrite: overwrite)
        workspaceState.snapshot = workspaceAdapter.projectTreeSnapshot()
        var openedTitles: [String] = []
        var failures: [String] = []

        for registration in registrations {
            guard let descriptor = registration.descriptor else {
                failures.append(registration.statusMessage)
                continue
            }
            workspaceState.registerFile(descriptor)
            _ = workspaceState.open(fileID: descriptor.id)
            let result = workspaceAdapter.openFile(LunaWorkspaceOpenRequest(fileID: descriptor.id, source: "launch --create"))
            guard let file = result.file, let text = result.text else {
                failures.append(result.statusMessage ?? registration.statusMessage)
                continue
            }
            _ = documentStore.openOrActivate(file: file, text: text)
            openedTitles.append(file.displayPath)
        }

        syncWorkspaceAndShellStateToActiveDocument()
        textSelectionInteractionState.cancel()
        completionPopupState.close()

        if !openedTitles.isEmpty {
            let suffix = failures.isEmpty ? "" : "; \(failures.count) create request(s) failed"
            lastInteractionStatus = "Phase 5D.2 created and opened local file(s): \(openedTitles.joined(separator: ", "))\(suffix)"
        } else if let firstFailure = failures.first {
            lastInteractionStatus = firstFailure
        }
    }

    private mutating func openUntitledDocumentsAtLaunch(count: Int) {
        guard count > 0 else { return }
        var titles: [String] = []
        for _ in 0..<count {
            titles.append(createUntitledDocument(activationReason: "launch --new-untitled"))
        }
        lastInteractionStatus = "Phase 5D.2 opened untitled document(s): \(titles.joined(separator: ", "))"
    }

    @discardableResult
    private mutating func createUntitledDocument(activationReason: String = "File > New File") -> String {
        let index = nextAvailableUntitledDocumentIndex()
        nextUntitledDocumentIndex = index + 1
        let title = "Untitled-\(index).txt"
        let id = LunaDocumentID(rawValue: "untitled.\(index)")
        _ = documentStore.openUntitledDocument(id: id, title: title, text: "", syntaxName: "Plain Text")
        syncWorkspaceAndShellStateToActiveDocument()
        completionPopupState.close()
        findPanelState = nil
        textSelectionInteractionState.cancel()
        lastInteractionStatus = "Phase 5D.2 new untitled document: \(title) (\(activationReason))"
        return title
    }

    private mutating func nextAvailableUntitledDocumentIndex() -> Int {
        var index = max(1, nextUntitledDocumentIndex)
        while documentStore.document(with: LunaDocumentID(rawValue: "untitled.\(index)")) != nil {
            index += 1
        }
        return index
    }

    private mutating func saveActiveDocumentUsingSaveDialog() {
        guard let request = documentStore.saveRequestForActiveDocument(kind: .saveAs) else {
            lastInteractionStatus = "Save As… skipped: no active document"
            return
        }
        _ = saveDocumentAsUsingDialog(request, source: "File > Save As…")
    }

    @discardableResult
    private mutating func saveDocumentAsUsingDialog(_ request: LunaDocumentSaveRequest, source: String) -> LunaDocumentSaveResult {
        let dialogResult = dialogService.chooseFileToSave(
            LunaFileDialogRequest(
                purpose: .save,
                title: "Save As…",
                message: "Choose where to save \(request.title).",
                defaultDirectory: defaultSaveDirectory(for: request),
                defaultFileName: request.title,
                allowedExtensions: [],
                allowsMultipleSelection: false,
                source: source
            )
        )
        guard let targetPath = dialogResult.firstSelectedPath else {
            let status = dialogResult.statusMessage ?? "Save As… cancelled for \(request.title)"
            lastInteractionStatus = status
            return LunaDocumentSaveResult(outcome: dialogResult.outcome == .cancelled ? .cancelled : .failed, documentID: request.documentID, statusMessage: status)
        }

        let oldDocumentID = request.documentID
        let result = workspaceAdapter.saveDocumentAsLocalFile(
            request,
            targetPath: targetPath,
            overwrite: dialogResult.allowsOverwrite || overwritesDemoSaveAsTarget
        )
        applySaveResultAndSyncWorkspace(result, replacingDocumentID: oldDocumentID)
        lastInteractionStatus = result.statusMessage ?? (result.didSave ? "Saved As \(request.title)" : "Save As failed for \(request.title)")
        return result
    }

    private func defaultSaveDirectory(for request: LunaDocumentSaveRequest) -> String? {
        if let displayPath = request.displayPath, displayPath.hasPrefix("/") {
            return URL(fileURLWithPath: displayPath).deletingLastPathComponent().path
        }
        return FileManager.default.currentDirectoryPath
    }

    private mutating func applySaveResultAndSyncWorkspace(_ result: LunaDocumentSaveResult, replacingDocumentID oldDocumentID: LunaDocumentID? = nil) {
        documentStore.applySaveResult(result)
        if let file = result.file {
            workspaceState.registerFile(file)
            if let oldDocumentID, LunaFileID(rawValue: oldDocumentID.rawValue) != file.id {
                _ = workspaceState.close(fileID: LunaFileID(rawValue: oldDocumentID.rawValue))
            }
            _ = workspaceState.open(fileID: file.id)
            workspaceState.snapshot = workspaceAdapter.projectTreeSnapshot()
        }
        syncWorkspaceAndShellStateToActiveDocument()
    }

    private mutating func saveActiveDocumentThroughWorkspaceAdapter() {
        guard let request = documentStore.saveRequestForActiveDocument() else {
            lastInteractionStatus = "Phase 5D save skipped: no active document"
            return
        }
        if request.fileID == nil {
            _ = saveDocumentAsUsingDialog(request, source: "File > Save on untitled document")
            return
        }
        let result = workspaceAdapter.saveDocument(request)
        applySaveResultAndSyncWorkspace(result)
        lastInteractionStatus = result.statusMessage ?? (result.didSave ? "Saved \(request.title)" : "Could not save \(request.title)")
    }

    private mutating func saveAllDirtyDocumentsThroughWorkspaceAdapter() {
        let dirtyIDs = documentStore.dirtyDocumentIDs()
        guard !dirtyIDs.isEmpty else {
            lastInteractionStatus = "Phase 5D save all: no dirty documents"
            return
        }
        var savedCount = 0
        var failedMessages: [String] = []
        for id in dirtyIDs {
            guard let request = documentStore.saveRequest(for: id, kind: .saveAll) else { continue }
            let result: LunaDocumentSaveResult
            if request.fileID == nil {
                result = saveDocumentAsUsingDialog(request, source: "File > Save All on untitled document")
            } else {
                result = workspaceAdapter.saveDocument(request)
                applySaveResultAndSyncWorkspace(result)
            }
            if result.didSave {
                savedCount += 1
            } else if result.outcome != .cancelled {
                failedMessages.append(result.statusMessage ?? "Could not save \(request.title)")
            }
        }
        if failedMessages.isEmpty {
            lastInteractionStatus = "Phase 5D save all: saved \(savedCount) document(s) through workspace adapter"
        } else {
            lastInteractionStatus = "Phase 5D save all: saved \(savedCount), failed \(failedMessages.count) — \(failedMessages[0])"
        }
    }

    private mutating func closeDocumentUsingWorkspacePolicy(_ documentID: LunaDocumentID) {
        guard let request = documentStore.closeRequest(for: documentID) else {
            lastInteractionStatus = "Phase 5C.2.1 close skipped: document not open (\(documentID.rawValue))"
            return
        }
        let resolution = LunaDirtyDocumentClosePolicy(promptsForDirtyDocuments: true).resolve(request)
        switch resolution.decision {
        case .closeNow:
            closeDocumentNow(documentID, statusMessage: resolution.statusMessage ?? "Closed \(request.title)")

        case .requestSave:
            confirmDirtyCloseAndApply(request)

        case .cancel:
            lastInteractionStatus = resolution.statusMessage ?? "Close cancelled"
        }
    }

    private mutating func closeDocumentNow(_ documentID: LunaDocumentID, statusMessage: String) {
        _ = documentStore.close(documentID)
        _ = workspaceState.close(fileID: LunaFileID(rawValue: documentID.rawValue))
        syncWorkspaceAndShellStateToActiveDocument()
        lastInteractionStatus = statusMessage
    }

    private mutating func confirmDirtyCloseAndApply(_ closeRequest: LunaDocumentCloseRequest) {
        let descriptor = documentStore.document(with: closeRequest.documentID)?.descriptor
        let dialogResult = dialogService.confirmUnsavedChanges(
            LunaUnsavedChangesDialogRequest(
                documentID: closeRequest.documentID.rawValue,
                title: closeRequest.title,
                displayPath: descriptor?.displayPath,
                isUntitled: descriptor?.isUntitled ?? false,
                source: "document close"
            )
        )
        switch dialogResult.decision {
        case .save:
            guard let saveRequest = documentStore.saveRequest(for: closeRequest.documentID, kind: .save) else {
                lastInteractionStatus = "Close cancelled: no save request available for \(closeRequest.title)"
                return
            }
            let saveResult: LunaDocumentSaveResult
            if saveRequest.fileID == nil {
                saveResult = saveDocumentAsUsingDialog(saveRequest, source: "dirty close Save")
            } else {
                saveResult = workspaceAdapter.saveDocument(saveRequest)
                applySaveResultAndSyncWorkspace(saveResult)
            }
            guard saveResult.didSave else {
                lastInteractionStatus = saveResult.statusMessage ?? "Close cancelled because \(closeRequest.title) was not saved"
                return
            }
            let savedDocumentID = saveResult.file.map { LunaDocumentID(rawValue: $0.id.rawValue) } ?? closeRequest.documentID
            closeDocumentNow(savedDocumentID, statusMessage: "Saved and closed \(closeRequest.title)")

        case .discard:
            closeDocumentNow(closeRequest.documentID, statusMessage: dialogResult.statusMessage ?? "Closed \(closeRequest.title) without saving")

        case .cancel:
            lastInteractionStatus = dialogResult.statusMessage ?? "Close cancelled for \(closeRequest.title)"
        }
    }

    private mutating func closeActiveDocumentUsingWorkspacePolicy() {
        guard let activeID = documentStore.activeDocumentID else {
            lastInteractionStatus = "Phase 5C.2.1 close skipped: no active document"
            return
        }
        closeDocumentUsingWorkspacePolicy(activeID)
    }

    private mutating func closeDocumentUsingCommandContext(_ context: LunaCommandContext) {
        guard let rawID = context.targetOrActiveDocumentID else {
            lastInteractionStatus = "Phase 5C.2.1 close skipped: no target document"
            return
        }
        closeDocumentUsingWorkspacePolicy(LunaDocumentID(rawValue: rawID))
    }

    private func demoCommandAvailability(for command: LunaCommandID, context: LunaCommandContext) -> LunaCommandAvailability {
        let currentTheme = MothDemoTheme.canonicalTheme(for: theme).name
        let hasSelection = editableTextState.selection != nil

        if let fileID = command.rawValue.lunaDemoOpenFileID {
            let canOpen = workspaceState.descriptor(for: fileID) != nil
            return LunaCommandAvailability(isEnabled: canOpen, disabledReason: canOpen ? nil : "Workspace file is unavailable")
        }

        switch command.rawValue {
        case "luna.demo.theme.blue":
            return LunaCommandAvailability(isChecked: currentTheme == LunaTheme.lunaDemoBlue.name)
        case "luna.demo.theme.moth":
            return LunaCommandAvailability(isChecked: currentTheme == MothDemoTheme.theme.name)
        case "luna.demo.theme.highContrast":
            return LunaCommandAvailability(isChecked: currentTheme == LunaTheme.highContrastProof.name)
        case "luna.demo.sidebar.toggle":
            return LunaCommandAvailability(isChecked: editorShellState.isSidebarVisible)
        case "luna.demo.file.new", "luna.demo.file.open":
            return .enabled
        case "luna.demo.file.save":
            let isDirty = documentStore.activeDocument?.isDirty ?? false
            return LunaCommandAvailability(isEnabled: isDirty, disabledReason: isDirty ? nil : "Active document is already saved")
        case "luna.demo.file.saveAs":
            let hasDocument = documentStore.activeDocument != nil
            return LunaCommandAvailability(isEnabled: hasDocument, disabledReason: hasDocument ? nil : "No active document")
        case "luna.demo.file.saveAll":
            let hasDirty = !documentStore.dirtyDocumentIDs().isEmpty
            return LunaCommandAvailability(isEnabled: hasDirty, disabledReason: hasDirty ? nil : "No dirty documents")
        case "luna.demo.file.close":
            let documentID = context.targetOrActiveDocumentID.map(LunaDocumentID.init(rawValue:))
            let canClose = documentID.flatMap { documentStore.document(with: $0)?.descriptor.isClosable } ?? false
            return LunaCommandAvailability(isEnabled: canClose, disabledReason: canClose ? nil : "Target document is not closable")
        case "luna.demo.edit.selectAll":
            return LunaCommandAvailability(isEnabled: !staticTextDocument.lines.isEmpty)
        case "luna.demo.selection.clear":
            return LunaCommandAvailability(isEnabled: hasSelection, disabledReason: hasSelection ? nil : "No active selection")
        case "luna.demo.context.copy":
            return LunaCommandAvailability(isEnabled: hasSelection, disabledReason: hasSelection ? nil : "No active selection")
        case "luna.demo.context.cut":
            return .disabled("Cut is not implemented in the demo yet")
        case "luna.demo.tab.overview":
            return LunaCommandAvailability(isChecked: documentStore.activeDocumentID == "overview")
        case "luna.demo.tab.editor":
            return LunaCommandAvailability(isChecked: documentStore.activeDocumentID == "editor")
        case "luna.demo.tab.theme":
            return LunaCommandAvailability(isChecked: documentStore.activeDocumentID == "theme")
        case "luna.demo.tab.close":
            let documentID = context.targetOrActiveDocumentID.map(LunaDocumentID.init(rawValue:))
            let canClose = documentID.flatMap { documentStore.document(with: $0)?.descriptor.isClosable } ?? false
            return LunaCommandAvailability(isEnabled: canClose, disabledReason: canClose ? nil : "Target tab is not closable in this demo")
        case "luna.demo.scroll.top":
            let paneID = paneWorkspaceState.activePaneID
            let isAwayFromTop = (scrollTopVisualRow(for: paneID) ?? 0) > 0 || scrollTopLine(for: paneID) > 0
            return LunaCommandAvailability(isEnabled: isAwayFromTop, disabledReason: isAwayFromTop ? nil : "Already at top")
        case "luna.demo.scroll.end":
            return .enabled
        default:
            return .enabled
        }
    }

    private mutating func performDemoCommand(
        _ command: LunaCommandID,
        framebufferSize: LunaSizeI,
        source: String = "demo",
        attributes additionalAttributes: [String: String] = [:]
    ) {
        contextMenuState.close()
        completionPopupState.close()

        // File-open commands can be generated dynamically from app-owned
        // workspace/sidebar state, especially for Phase 5D local files whose
        // IDs depend on absolute paths. Keep that dynamic policy in the demo
        // host instead of forcing LunaCommandRegistry to own every file path.
        if let fileID = command.rawValue.lunaDemoOpenFileID {
            openWorkspaceFile(fileID, framebufferSize: framebufferSize, source: source)
            return
        }

        let context = demoCommandContext(
            framebufferSize: framebufferSize,
            source: source,
            attributes: additionalAttributes
        )
        let result = Self.demoCommandRuntime.execute(command, host: &self, context: context)
        if !result.didHandle, let status = result.statusMessage {
            lastInteractionStatus = status
        }
    }

    private func demoCommandContext(
        framebufferSize: LunaSizeI,
        source: String? = nil,
        attributes additionalAttributes: [String: String] = [:]
    ) -> LunaCommandContext {
        var attributes = [
            "framebuffer.width": String(framebufferSize.width),
            "framebuffer.height": String(framebufferSize.height),
        ]
        for (key, value) in additionalAttributes {
            attributes[key] = value
        }
        return LunaCommandContext(
            focusedSurface: "editor",
            activeDocumentID: activeDocumentDescriptor?.id.rawValue,
            source: source,
            attributes: attributes
        )
    }

    private mutating func performDemoCommandBody(_ command: LunaCommandID, framebufferSize: LunaSizeI, context: LunaCommandContext) -> LunaCommandExecutionResult {
        if let fileID = command.rawValue.lunaDemoOpenFileID {
            openWorkspaceFile(fileID, framebufferSize: framebufferSize, source: "command runtime")
            return .handled(lastInteractionStatus)
        }

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
                    id: "demo.phase4c.notice",
                    title: "Luna Menu / Command Demo",
                    message: "Menus, the command palette, and keyboard shortcuts all route through product-neutral Luna command IDs. The demo supplies the command handlers."
                )
            )
            modalManager.openQueuedModals(from: &context, viewportSize: framebufferSize)
            lastInteractionStatus = "Demo command: Show Notice"
        case "luna.demo.palette.open":
            openQuickPanel()
            lastInteractionStatus = "Command palette opened from menu command"
        case "luna.demo.file.new":
            _ = createUntitledDocument()
        case "luna.demo.file.open":
            openFileUsingDialog(framebufferSize: framebufferSize)
        case "luna.demo.file.save":
            saveActiveDocumentThroughWorkspaceAdapter()
        case "luna.demo.file.saveAs":
            saveActiveDocumentUsingSaveDialog()
        case "luna.demo.file.saveAll":
            saveAllDirtyDocumentsThroughWorkspaceAdapter()
        case "luna.demo.file.close":
            closeDocumentUsingCommandContext(context)
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
        case "luna.demo.completion.open":
            openCompletionPopup(framebufferSize: framebufferSize)
        case "luna.demo.completion.info":
            var context = LunaUIContext()
            context.openNotice(
                LunaNoticeRequest(
                    id: "demo.phase4f.completion-info",
                    title: "Phase 4F Completion Popup",
                    message: "The anchored completion popup is a product-neutral Luna primitive. The demo supplies static suggestions and applies insertion text; real completion sources come later."
                )
            )
            modalManager.openQueuedModals(from: &context, viewportSize: framebufferSize)
            lastInteractionStatus = "Phase 4F completion info opened"
        case "luna.demo.edit.selectAll":
            selectAllEditableText(framebufferSize: framebufferSize)
        case "luna.demo.selection.clear":
            editableTextState.selection = nil
            lastInteractionStatus = "Selection cleared"
        case "luna.demo.sidebar.toggle":
            editorShellState.isSidebarVisible.toggle()
            lastInteractionStatus = editorShellState.isSidebarVisible ? "Phase 4D sidebar shown" : "Phase 4D sidebar hidden"
        case "luna.demo.tab.overview":
            activateDocument("overview", framebufferSize: framebufferSize, reason: "tab/sidebar command")
        case "luna.demo.tab.editor":
            activateDocument("editor", framebufferSize: framebufferSize, reason: "tab/sidebar command")
        case "luna.demo.tab.theme":
            activateDocument("theme", framebufferSize: framebufferSize, reason: "tab/sidebar command")
        case "luna.demo.tab.close":
            closeDocumentUsingCommandContext(context)
        case "luna.demo.context.copy":
            lastInteractionStatus = "Phase 4E context command: Copy requested from demo fixture"
        case "luna.demo.context.cut":
            lastInteractionStatus = "Phase 4E context command: Cut is disabled in the demo fixture"
        case "luna.demo.context.paste":
            let result = editableTextState.insertText("context-menu")
            ensureEditableCaretVisible(framebufferSize: framebufferSize)
            lastInteractionStatus = "Phase 4E context paste inserted sample text; caret line \(result.newCaret.location.lineIndex + 1), col \(result.newCaret.location.utf8Column)"
        case "luna.demo.context.reveal":
            lastInteractionStatus = "Phase 4E context command: Reveal in sidebar requested"
        case "luna.demo.context.rename":
            lastInteractionStatus = "Phase 4E context command: Rename requested from demo fixture"
        case "luna.demo.context.info":
            var context = LunaUIContext()
            context.openNotice(
                LunaNoticeRequest(
                    id: "demo.phase4e.context-info",
                    title: "Phase 4E Context Menu",
                    message: "The floating context menu is a product-neutral Luna primitive. The demo supplies the items for editor, tab, sidebar, and status contexts."
                )
            )
            modalManager.openQueuedModals(from: &context, viewportSize: framebufferSize)
            lastInteractionStatus = "Phase 4E context info opened"
        case "luna.demo.sidebar.documentBuffer":
            openWorkspaceFile("document-buffer", framebufferSize: framebufferSize, source: "legacy sidebar command")
        case "luna.demo.sidebar.editorShell":
            openWorkspaceFile("editor-shell", framebufferSize: framebufferSize, source: "legacy sidebar command")
        case "luna.demo.sidebar.completionPopup":
            openWorkspaceFile("completion-popup", framebufferSize: framebufferSize, source: "legacy sidebar command")
        case "luna.demo.sidebar.phase5aTests":
            openWorkspaceFile("phase5a-tests", framebufferSize: framebufferSize, source: "legacy sidebar command")
        case "luna.demo.sidebar.roadmap":
            openWorkspaceFile("roadmap", framebufferSize: framebufferSize, source: "legacy sidebar command")
        default:
            lastInteractionStatus = "Demo command: \(command.rawValue)"
        }
        return .handled(lastInteractionStatus)
    }

    private func paneTextView(
        forSurfaceID surfaceID: LunaNodeID?,
        framebufferSize: LunaSizeI,
        theme: LunaTheme
    ) -> (paneID: LunaPaneID, view: LunaStaticTextView)? {
        guard let surfaceID else { return nil }
        for paneID in paneWorkspaceState.paneIDs {
            guard let view = paneTextView(for: paneID, framebufferSize: framebufferSize, theme: theme) else { continue }
            if view.id == surfaceID { return (paneID, view) }
        }
        return nil
    }

    private mutating func applyTextSelectionResult(
        _ result: LunaTextSelectionInteractionResult,
        paneID: LunaPaneID,
        framebufferSize: LunaSizeI
    ) {
        if result.requestedVisualRowDelta != 0,
           let view = paneTextView(for: paneID, framebufferSize: framebufferSize, theme: theme) {
            let scrolled = view.scrolled(byLineDelta: result.requestedVisualRowDelta)
            setScrollTopLine(scrolled.scrollTopLine, for: paneID)
            setScrollTopVisualRow(scrolled.scrollTopVisualRow, for: paneID)
        }
        if result.didChangeSelection, let selection = result.selection {
            editableTextState.setSelection(selection)
        }
    }

    private mutating func advanceTextSelectionAutoscroll(framebufferSize: LunaSizeI) {
        guard textSelectionInteractionState.wantsContinuousUpdates,
              let target = paneTextView(
                forSurfaceID: textSelectionInteractionState.activeSurfaceID,
                framebufferSize: framebufferSize,
                theme: theme
              )
        else { return }

        var interaction = textSelectionInteractionState
        let result = LunaTextSelectionInteraction.advanceAutoscroll(
            in: target.view,
            state: &interaction
        )
        textSelectionInteractionState = interaction
        guard result.requestedVisualRowDelta != 0 || result.didChangeSelection else { return }
        applyTextSelectionResult(result, paneID: target.paneID, framebufferSize: framebufferSize)
        lastInteractionStatus = "C1B edge autoscroll in \(target.paneID.rawValue)"
    }

    private mutating func staticTextPageDelta(framebufferSize: LunaSizeI) -> Int {
        guard let view = paneTextView(
            for: paneWorkspaceState.activePaneID,
            framebufferSize: framebufferSize,
            theme: theme
        ) else { return 1 }
        return max(1, view.layout().maxVisibleLineCount - 1)
    }

    private mutating func scrollStaticTextView(byLineDelta delta: Int, framebufferSize: LunaSizeI) {
        let paneID = paneWorkspaceState.activePaneID
        guard let view = paneTextView(for: paneID, framebufferSize: framebufferSize, theme: theme) else { return }
        let scrolled = view.scrolled(byLineDelta: delta)
        setScrollTopLine(scrolled.scrollTopLine, for: paneID)
        setScrollTopVisualRow(scrolled.scrollTopVisualRow, for: paneID)
        let layout = scrolled.layout()
        lastInteractionStatus = "Phase 5F.2A pane scroll: \(paneID.rawValue), visual row \(layout.firstVisibleVisualRowIndex + 1) / \(max(1, layout.totalVisualRowCount))"
    }

    private mutating func setStaticTextScrollTopLine(_ line: Int, framebufferSize: LunaSizeI, reason: String) {
        let paneID = paneWorkspaceState.activePaneID
        guard let view = paneTextView(for: paneID, framebufferSize: framebufferSize, theme: theme) else { return }
        let layout = view.layout()
        if line == Int.max {
            setScrollTopLine(layout.maxScrollTopLine, for: paneID)
            setScrollTopVisualRow(layout.maxScrollTopVisualRow, for: paneID)
        } else {
            let nextLine = min(max(0, line), layout.maxScrollTopLine)
            setScrollTopLine(nextLine, for: paneID)
            setScrollTopVisualRow(line == 0 ? 0 : nil, for: paneID)
        }
        let updated = paneTextView(for: paneID, framebufferSize: framebufferSize, theme: theme)?.layout()
        lastInteractionStatus = "Phase 5F.2A pane scroll \(reason): \(paneID.rawValue), visual row \((updated?.firstVisibleVisualRowIndex ?? 0) + 1) / \(max(1, updated?.totalVisualRowCount ?? 1))"
    }

    private mutating func ensureEditableCaretVisible(framebufferSize: LunaSizeI) {
        let paneID = paneWorkspaceState.activePaneID
        guard let view = paneTextView(for: paneID, framebufferSize: framebufferSize, theme: theme) else { return }
        let adjusted = view.ensuringVisible(staticTextCaret.location)
        setScrollTopLine(adjusted.scrollTopLine, for: paneID)
        setScrollTopVisualRow(adjusted.scrollTopVisualRow, for: paneID)
    }



    /// Compute the current demo layout for a framebuffer size.
    ///
    /// This is intentionally public/testable so resize/reflow correctness can be
    /// validated without relying on screenshots. Phase 4D routes the editor area
    /// through the product-neutral LunaEditorShell layout before assigning the
    /// demo text/proof panels inside the shell content frame.
    public static func layout(for framebufferSize: LunaSizeI, mode: LunaDemoMode = .editor) -> LunaCPUDemoSceneLayout {
        let viewport = LunaViewport(size: framebufferSize)
        var result = LunaLayoutResult()

        let menuHeight = 24
        let margin = viewport.size.width >= 700 ? 18 : 10
        let gap = 12
        let hudHeight = mode.usesProofGallerySurfaces ? max(58, min(72, viewport.size.height / 8)) : 0
        let shellTop = menuHeight + (hudHeight > 0 ? hudHeight + gap : 0)
        let shellBottom = max(shellTop + 1, viewport.size.height - margin)
        let shellBounds = LunaRectI(
            x: margin,
            y: shellTop,
            w: max(1, viewport.size.width - margin * 2),
            h: max(1, shellBottom - shellTop)
        )

        result.set(
            id: LunaCPUDemoSceneLayout.menuBarID,
            bounds: LunaRectI(x: 0, y: 0, w: viewport.size.width, h: menuHeight)
        )

        result.set(
            id: LunaCPUDemoSceneLayout.hudID,
            bounds: LunaRectI(x: 0, y: menuHeight, w: viewport.size.width, h: hudHeight)
        )

        let shell = LunaEditorShell(
            id: LunaCPUDemoSceneLayout.editorShellID,
            bounds: shellBounds,
            tabs: demoShellTabs,
            sidebarTitle: "Project",
            sidebarItems: demoSidebarItems,
            statusSegments: demoStatusSegmentsSnapshot(),
            state: demoEditorShellState,
            theme: MothDemoTheme.theme,
            metrics: .demo
        )
        let shellLayout = shell.layout()
        result.set(id: LunaCPUDemoSceneLayout.editorShellID, bounds: shellBounds)
        result.set(id: LunaCPUDemoSceneLayout.tabStripID, bounds: shellLayout.tabStripBounds)
        result.set(id: LunaCPUDemoSceneLayout.sidebarID, bounds: shellLayout.sidebarBounds)
        result.set(id: LunaCPUDemoSceneLayout.statusID, bounds: shellLayout.statusBarBounds)

        let content = shellLayout.editorContentBounds
        let usesProofPanel = mode.usesProofGallerySurfaces && content.w >= 700 && content.h >= 180
        if usesProofPanel {
            let panelW = min(300, max(236, content.w / 3))
            let panelX = max(content.x, content.x + content.w - panelW)
            let panel = LunaRectI(x: panelX, y: content.y, w: max(1, content.x + content.w - panelX), h: content.h)
            result.set(id: LunaCPUDemoSceneLayout.proofPanelID, bounds: panel)

            result.set(
                id: LunaCPUDemoSceneLayout.semanticWidgetID,
                bounds: LunaRectI(
                    x: panel.x + 12,
                    y: panel.y + 38,
                    w: max(1, panel.w - 24),
                    h: 72
                )
            )

            let textRight = max(content.x + 1, panel.x - gap)
            result.set(
                id: LunaCPUDemoSceneLayout.textViewID,
                bounds: LunaRectI(
                    x: content.x,
                    y: content.y,
                    w: max(1, textRight - content.x),
                    h: content.h
                )
            )
        } else {
            result.set(id: LunaCPUDemoSceneLayout.semanticWidgetID, bounds: LunaRectI(x: 0, y: 0, w: 0, h: 0))
            result.set(id: LunaCPUDemoSceneLayout.proofPanelID, bounds: LunaRectI(x: 0, y: 0, w: 0, h: 0))
            result.set(
                id: LunaCPUDemoSceneLayout.textViewID,
                bounds: LunaRectI(
                    x: content.x,
                    y: content.y,
                    w: max(1, content.w),
                    h: max(1, content.h)
                )
            )
        }

        return LunaCPUDemoSceneLayout(viewport: viewport, frames: result)
    }

    private func demoStatusSegments() -> [LunaStatusSegment] {
        var segments = Self.workspaceStatusSegments(
            status: lastInteractionStatus,
            store: documentStore,
            projectTitle: workspaceState.snapshot.projects.first?.title ?? "Workspace"
        )
        segments.append(
            LunaStatusSegment(
                id: "demoMode",
                title: "Mode",
                value: demoMode.rawValue,
                placement: .trailing,
                emphasis: demoMode == .editor ? .muted : .accent
            )
        )
        segments.append(
            LunaStatusSegment(
                id: "dialogs",
                title: "Dialogs",
                value: dialogService.providerDescription,
                placement: .trailing,
                emphasis: .muted
            )
        )
        segments.append(
            LunaStatusSegment(
                id: "inputStats",
                title: "Input",
                value: latestInputCoalescingStats.statusText,
                placement: .trailing,
                emphasis: latestInputCoalescingStats.coalescedPointerMotionCount > 0 ? .accent : .muted
            )
        )
        if demoMode.usesProofGallerySurfaces {
            segments.append(
                LunaStatusSegment(
                    id: "animationStats",
                    title: "Anim",
                    value: proofGalleryAnimationClock.statusText,
                    placement: .trailing,
                    emphasis: proofGalleryAnimationClock.latestFrame?.wasDeltaClamped == true ? .accent : .muted
                )
            )
        }
        segments.append(
            LunaStatusSegment(
                id: "frameTiming",
                title: "Frame",
                value: frameTimingStats.statusText,
                placement: .trailing,
                emphasis: .muted
            )
        )
        segments.append(
            LunaStatusSegment(
                id: "invalidations",
                title: "Invalid",
                value: latestFrameInvalidations.description,
                placement: .trailing,
                emphasis: latestFrameInvalidations.isEmpty ? .muted : .accent
            )
        )
        return segments
    }

    public static func demoStatusSegmentsSnapshot(
        status: String = "Ready",
        store: LunaDocumentStore = LunaCPUDemoScene.demoDocumentStore
    ) -> [LunaStatusSegment] {
        workspaceStatusSegments(status: status, store: store, projectTitle: demoProjectDescriptor.title)
    }

    private static func workspaceStatusSegments(status: String, store: LunaDocumentStore, projectTitle: String) -> [LunaStatusSegment] {
        var segments = store.statusSegments(status: status, syntaxFallback: "Swift")
        segments.insert(
            LunaStatusSegment(id: "workspace", title: "Project", value: projectTitle, placement: .leading, emphasis: .muted),
            at: min(1, segments.count)
        )
        return segments
    }

    /// Build the Phase 4D product-neutral editor shell proof. The shell contents
    /// are demo-owned, while LunaUI owns the layout/hit-test/accessibility model
    /// for tabs, sidebar rows, editor content frame, and status segments.
    public static func editorShell(
        for framebufferSize: LunaSizeI,
        state: LunaEditorShellState,
        theme: LunaTheme = MothDemoTheme.theme,
        tabs: [LunaShellTab] = LunaCPUDemoScene.demoShellTabs,
        sidebarItems: [LunaSidebarItem] = LunaCPUDemoScene.demoSidebarItems,
        statusSegments: [LunaStatusSegment] = LunaCPUDemoScene.demoStatusSegmentsSnapshot(),
        mode: LunaDemoMode = .editor
    ) -> LunaEditorShell {
        let layout = Self.layout(for: framebufferSize, mode: mode)
        return LunaEditorShell(
            id: LunaCPUDemoSceneLayout.editorShellID,
            bounds: layout.editorShellBounds,
            tabs: tabs,
            sidebarTitle: "Project",
            sidebarItems: sidebarItems,
            statusSegments: statusSegments,
            state: state,
            theme: theme,
            metrics: .demo
        )
    }

    /// Build a static text-view proof in explicit product-neutral bounds.
    public static func staticTextView(
        id: LunaNodeID,
        bounds: LunaRectI,
        document: LunaStaticTextDocument,
        scrollTopLine: Int = 0,
        scrollTopVisualRow: Int? = nil,
        caret: LunaStaticTextCaret? = nil,
        selection: LunaStaticTextSelection? = nil,
        highlights: [LunaStaticTextHighlight] = [],
        theme: LunaTheme = MothDemoTheme.theme,
        wrapMode: LunaStaticTextWrapMode = .none
    ) -> LunaStaticTextView {
        LunaStaticTextView(
            id: id,
            bounds: bounds,
            document: document,
            scrollTopLine: scrollTopLine,
            scrollTopVisualRow: scrollTopVisualRow,
            currentLineIndex: caret?.location.lineIndex ?? 3,
            theme: theme,
            metrics: .demo,
            wrapMode: wrapMode,
            isFocused: caret != nil,
            isEditable: true,
            caret: caret,
            selection: selection,
            highlights: highlights
        )
    }

    /// Build the Phase 3A/3B static text-view proof for a framebuffer size.
    public static func staticTextView(
        for framebufferSize: LunaSizeI,
        document: LunaStaticTextDocument,
        scrollTopLine: Int = 0,
        caret: LunaStaticTextCaret? = nil,
        selection: LunaStaticTextSelection? = nil,
        highlights: [LunaStaticTextHighlight] = [],
        theme: LunaTheme = MothDemoTheme.theme,
        mode: LunaDemoMode = .editor
    ) -> LunaStaticTextView {
        let layout = Self.layout(for: framebufferSize, mode: mode)
        return staticTextView(
            id: LunaCPUDemoSceneLayout.textViewID,
            bounds: layout.textViewBounds,
            document: document,
            scrollTopLine: scrollTopLine,
            caret: caret,
            selection: selection,
            highlights: highlights,
            theme: theme,
            wrapMode: .none
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

    /// Build the Phase 4C product-neutral menu bar proof. The menu contents are
    /// demo-owned, but layout/hit testing/accessibility/keyboard behavior live in
    /// LunaUI's reusable `LunaMenuBar`.
    public static func menuBar(
        for framebufferSize: LunaSizeI,
        state: LunaMenuBarState,
        theme: LunaTheme = MothDemoTheme.theme,
        menus: [LunaMenuDefinition]? = nil,
        mode: LunaDemoMode = .editor
    ) -> LunaMenuBar {
        let layout = Self.layout(for: framebufferSize, mode: mode)
        return LunaMenuBar(
            id: LunaCPUDemoSceneLayout.menuBarID,
            bounds: layout.menuBarBounds,
            menus: menus ?? demoMenus(for: theme),
            state: state,
            theme: theme,
            metrics: .demo
        )
    }

    /// Build the Phase 4E product-neutral context menu proof. The menu contents
    /// live in `contextMenuState.definition`, while LunaUI owns layout, hit
    /// testing, keyboard/pointer routing, and accessibility semantics.
    public static func contextMenu(
        for framebufferSize: LunaSizeI,
        state: LunaContextMenuState,
        theme: LunaTheme = MothDemoTheme.theme
    ) -> LunaContextMenu {
        LunaContextMenu(
            id: LunaCPUDemoSceneLayout.contextMenuID,
            bounds: LunaRectI(x: 0, y: 0, w: framebufferSize.width, h: framebufferSize.height),
            state: state,
            theme: theme,
            metrics: .demo
        )
    }

    /// Build the Phase 4F product-neutral anchored completion-popup proof.
    public static func completionPopup(
        for framebufferSize: LunaSizeI,
        state: LunaCompletionPopupState,
        theme: LunaTheme = MothDemoTheme.theme
    ) -> LunaCompletionPopup {
        LunaCompletionPopup(
            id: LunaCPUDemoSceneLayout.completionPopupID,
            bounds: LunaRectI(x: 0, y: 0, w: framebufferSize.width, h: framebufferSize.height),
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


    private func demoShellTabs() -> [LunaShellTab] {
        documentStore.shellTabs(
            activateCommand: { id in LunaCommandID(rawValue: "luna.demo.file.open.\(id.rawValue)") },
            closeCommand: { id in
                documentStore.document(with: id)?.descriptor.isClosable == true
                    ? LunaCommandID(rawValue: "luna.demo.tab.close")
                    : nil
            }
        )
    }

    public static var demoShellTabs: [LunaShellTab] {
        demoDocumentStore.shellTabs(
            activateCommand: { id in LunaCommandID(rawValue: "luna.demo.file.open.\(id.rawValue)") },
            closeCommand: { id in
                demoDocumentStore.document(with: id)?.descriptor.isClosable == true
                    ? LunaCommandID(rawValue: "luna.demo.tab.close")
                    : nil
            }
        )
    }

    public static let demoProjectDescriptor = LunaProjectDescriptor(
        id: "luna-ui",
        title: "Luna-UI",
        rootPath: "/demo/Luna-UI",
        displayPath: "Luna-UI"
    )

    public static let demoWorkspaceFiles: [LunaFileDescriptor] = [
        LunaFileDescriptor(id: "overview", path: "/demo/Luna-UI/Demo/Overview.swift", displayPath: "Demo/Overview.swift", projectID: "luna-ui", syntaxName: "Swift"),
        LunaFileDescriptor(id: "editor", path: "/demo/Luna-UI/Sources/LunaUI/LunaStaticTextView.swift", displayPath: "Sources/LunaUI/LunaStaticTextView.swift", projectID: "luna-ui", syntaxName: "Swift"),
        LunaFileDescriptor(id: "theme", path: "/demo/Luna-UI/Demo/Theme.json", displayPath: "Demo/Theme.json", projectID: "luna-ui", syntaxName: "JSON"),
        LunaFileDescriptor(id: "document-buffer", path: "/demo/Luna-UI/Sources/LunaUI/LunaDocumentBuffer.swift", displayPath: "Sources/LunaUI/LunaDocumentBuffer.swift", projectID: "luna-ui", syntaxName: "Swift"),
        LunaFileDescriptor(id: "editor-shell", path: "/demo/Luna-UI/Sources/LunaUI/LunaEditorShell.swift", displayPath: "Sources/LunaUI/LunaEditorShell.swift", projectID: "luna-ui", syntaxName: "Swift"),
        LunaFileDescriptor(id: "completion-popup", path: "/demo/Luna-UI/Sources/LunaUI/LunaCompletionPopup.swift", displayPath: "Sources/LunaUI/LunaCompletionPopup.swift", projectID: "luna-ui", syntaxName: "Swift"),
        LunaFileDescriptor(id: "phase5a-tests", path: "/demo/Luna-UI/Tests/LunaUIPhase5ATests/LunaUIPhase5ATests.swift", displayPath: "Tests/LunaUIPhase5ATests/LunaUIPhase5ATests.swift", projectID: "luna-ui", syntaxName: "Swift"),
        LunaFileDescriptor(id: "roadmap", path: "/demo/Luna-UI/docs/LUNA_UI_ROADMAP.md", displayPath: "docs/LUNA_UI_ROADMAP.md", projectID: "luna-ui", syntaxName: "Markdown"),
    ]

    public static let demoWorkspaceSnapshot = LunaProjectTreeSnapshot(
        projects: [demoProjectDescriptor],
        roots: [
            .project(
                id: "workspace",
                title: "Luna-UI",
                projectID: "luna-ui",
                children: [
                    .folder(id: "open-documents", title: "Open Documents", projectID: "luna-ui", children: [
                        .file(id: "file.overview", title: "Overview.swift", fileID: "overview", projectID: "luna-ui"),
                        .file(id: "file.editor", title: "EditorSurface.swift", fileID: "editor", projectID: "luna-ui"),
                        .file(id: "file.theme", title: "Theme.json", fileID: "theme", projectID: "luna-ui"),
                    ]),
                    .folder(id: "sources", title: "Sources", projectID: "luna-ui", children: [
                        .folder(id: "luna-ui-module", title: "LunaUI", projectID: "luna-ui", children: [
                            .file(id: "file.document-buffer", title: "LunaDocumentBuffer.swift", fileID: "document-buffer", projectID: "luna-ui"),
                            .file(id: "file.editor-shell", title: "LunaEditorShell.swift", fileID: "editor-shell", projectID: "luna-ui"),
                            .file(id: "file.completion-popup", title: "LunaCompletionPopup.swift", fileID: "completion-popup", projectID: "luna-ui"),
                        ]),
                        .folder(id: "test-app", title: "LunaUITestApp", projectID: "luna-ui", children: []),
                    ]),
                    .folder(id: "tests", title: "Tests", projectID: "luna-ui", children: [
                        .file(id: "file.phase5a-tests", title: "LunaUIPhase5ATests.swift", fileID: "phase5a-tests", projectID: "luna-ui"),
                    ]),
                    .file(id: "file.roadmap", title: "LUNA_UI_ROADMAP.md", fileID: "roadmap", projectID: "luna-ui"),
                ]
            )
        ],
        version: 5
    )

    public static let demoWorkspaceState = LunaWorkspaceState(
        snapshot: demoWorkspaceSnapshot,
        fileDescriptors: demoWorkspaceFiles,
        openFileIDs: ["overview", "editor", "theme"],
        activeFileID: "editor",
        selectedNodeID: "file.editor",
        expandedNodeIDs: ["workspace", "open-documents", "sources", "luna-ui-module", "tests"]
    )

    public static var demoSidebarItems: [LunaSidebarItem] {
        demoWorkspaceState.sidebarItems { node in
            node.fileID.map { LunaCommandID(rawValue: "luna.demo.file.open.\($0.rawValue)") }
        }
    }

    public static let demoEditorShellState = LunaEditorShellState(
        tabStrip: LunaTabStripState(activeTabID: "editor"),
        sidebar: LunaSidebarState(
            selectedItemID: "file.editor",
            expandedItemIDs: ["workspace", "open-documents", "sources", "luna-ui-module", "tests"]
        ),
        isSidebarVisible: true,
        sidebarWidth: 236
    )


    public static let demoPaneWorkspaceState = LunaPaneWorkspaceState(
        root: .split(
            id: "demo.primary-split",
            axis: .horizontal,
            fraction: 0.68,
            first: .pane("demo.editor.primary"),
            second: .pane("demo.editor.secondary")
        ),
        activePaneID: "demo.editor.primary"
    )

    public static let demoDocumentStore = LunaDocumentStore(
        openDocuments: [
            LunaDocumentBuffer(
                descriptor: LunaDocumentDescriptor(
                    id: "overview",
                    title: "Overview.swift",
                    displayPath: "Demo/Overview.swift",
                    syntaxName: "Swift",
                    isClosable: false
                ),
                text: demoOverviewText,
                caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 1, utf8Column: 0))
            ),
            LunaDocumentBuffer(
                descriptor: LunaDocumentDescriptor(
                    id: "editor",
                    title: "EditorSurface.swift",
                    displayPath: "Sources/LunaUI/LunaStaticTextView.swift",
                    syntaxName: "Swift"
                ),
                text: demoText,
                caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 1, utf8Column: 0))
            ),
            LunaDocumentBuffer(
                descriptor: LunaDocumentDescriptor(
                    id: "theme",
                    title: "Theme.json",
                    displayPath: "Demo/Theme.json",
                    syntaxName: "JSON",
                    isPinned: true
                ),
                text: demoThemeDocumentText,
                caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 0))
            ),
        ],
        activeDocumentID: "editor"
    )

    public static let demoCompletionItems: [LunaCompletionItem] = [
        LunaCompletionItem(id: "let", title: "let", annotation: "keyword", detail: "Create an immutable binding.", insertText: "let "),
        LunaCompletionItem(id: "var", title: "var", annotation: "keyword", detail: "Create a mutable binding.", insertText: "var "),
        LunaCompletionItem(id: "struct", title: "struct", annotation: "keyword", detail: "Declare a new Swift type.", insertText: "struct "),
        LunaCompletionItem(id: "luna-theme", title: "LunaTheme", annotation: "type", detail: "Theme object carrying editor and UI token sets.", insertText: "LunaTheme"),
        LunaCompletionItem(id: "luna-menu", title: "LunaMenuItem", annotation: "type", detail: "Product-neutral menu item shared by menu bars and context menus.", insertText: "LunaMenuItem"),
        LunaCompletionItem(id: "completion-popup", title: "LunaCompletionPopup", annotation: "type", detail: "Anchored completion surface introduced in Phase 4F.", insertText: "LunaCompletionPopup"),
        LunaCompletionItem(id: "notice", title: "Show Completion Info", annotation: "command", detail: "Routes through LunaCommandID instead of inserting text.", command: "luna.demo.completion.info"),
    ]

    public static let demoCommandDescriptors: [LunaCommandDescriptor] = [
        LunaCommandDescriptor(id: "luna.demo.palette.open", title: "Open Command Palette", defaultKey: LunaKeyEquivalent("P", modifiers: [.primary]), menuPath: ["View"]),
        LunaCommandDescriptor(id: "luna.demo.notice", title: "Show Demo Notice", defaultKey: nil, menuPath: ["Help"]),
        LunaCommandDescriptor(id: "luna.demo.file.new", title: "New Untitled File", defaultKey: LunaKeyEquivalent("N", modifiers: [.primary]), menuPath: ["File"]),
        LunaCommandDescriptor(id: "luna.demo.file.open", title: "Open File…", defaultKey: LunaKeyEquivalent("O", modifiers: [.primary]), menuPath: ["File"]),
        LunaCommandDescriptor(id: "luna.demo.file.save", title: "Save Active Document", defaultKey: LunaKeyEquivalent("S", modifiers: [.primary]), menuPath: ["File"]),
        LunaCommandDescriptor(id: "luna.demo.file.saveAs", title: "Save Active Document As…", defaultKey: LunaKeyEquivalent("S", modifiers: [.primary, .shift, .option]), menuPath: ["File"]),
        LunaCommandDescriptor(id: "luna.demo.file.saveAll", title: "Save All Dirty Documents", defaultKey: LunaKeyEquivalent("S", modifiers: [.primary, .shift]), menuPath: ["File"]),
        LunaCommandDescriptor(id: "luna.demo.file.close", title: "Close Active Document", defaultKey: LunaKeyEquivalent("W", modifiers: [.primary]), menuPath: ["File"]),
        LunaCommandDescriptor(id: "luna.demo.file.open.overview", title: "Open Overview.swift", menuPath: ["Workspace"]),
        LunaCommandDescriptor(id: "luna.demo.file.open.editor", title: "Open EditorSurface.swift", menuPath: ["Workspace"]),
        LunaCommandDescriptor(id: "luna.demo.file.open.theme", title: "Open Theme.json", menuPath: ["Workspace"]),
        LunaCommandDescriptor(id: "luna.demo.file.open.document-buffer", title: "Open LunaDocumentBuffer.swift", menuPath: ["Workspace"]),
        LunaCommandDescriptor(id: "luna.demo.file.open.editor-shell", title: "Open LunaEditorShell.swift", menuPath: ["Workspace"]),
        LunaCommandDescriptor(id: "luna.demo.file.open.completion-popup", title: "Open LunaCompletionPopup.swift", menuPath: ["Workspace"]),
        LunaCommandDescriptor(id: "luna.demo.file.open.phase5a-tests", title: "Open LunaUIPhase5ATests.swift", menuPath: ["Workspace"]),
        LunaCommandDescriptor(id: "luna.demo.file.open.roadmap", title: "Open LUNA_UI_ROADMAP.md", menuPath: ["Workspace"]),
        LunaCommandDescriptor(id: "luna.demo.theme.blue", title: "Theme: Luna Demo Blue", defaultKey: nil, menuPath: ["Theme"]),
        LunaCommandDescriptor(id: "luna.demo.theme.moth", title: "Theme: Moth Obsidian Demo", defaultKey: nil, menuPath: ["Theme"]),
        LunaCommandDescriptor(id: "luna.demo.theme.highContrast", title: "Theme: High Contrast Proof", defaultKey: nil, menuPath: ["Theme"]),
        LunaCommandDescriptor(id: "luna.demo.scroll.top", title: "Scroll Text View to Top", menuPath: ["View"]),
        LunaCommandDescriptor(id: "luna.demo.scroll.end", title: "Scroll Text View to End", menuPath: ["View"]),
        LunaCommandDescriptor(id: "luna.demo.sidebar.toggle", title: "Toggle Sidebar", menuPath: ["View"]),
        LunaCommandDescriptor(id: "luna.demo.insert.sample", title: "Insert Sample Text", menuPath: ["Edit", "Demo"]),
        LunaCommandDescriptor(id: "luna.demo.edit.selectAll", title: "Select All", defaultKey: LunaKeyEquivalent("A", modifiers: [.primary]), menuPath: ["Edit"]),
        LunaCommandDescriptor(id: "luna.demo.selection.clear", title: "Clear Selection", menuPath: ["Selection"]),
        LunaCommandDescriptor(id: "luna.demo.find.open", title: "Open Find / Replace Panel", defaultKey: LunaKeyEquivalent("F", modifiers: [.primary]), menuPath: ["Find"]),
        LunaCommandDescriptor(id: "luna.demo.completion.open", title: "Open Completion Popup", defaultKey: LunaKeyEquivalent("Space", modifiers: [.primary]), menuPath: ["Edit", "Completion"]),
        LunaCommandDescriptor(id: "luna.demo.completion.info", title: "Completion: Show Info", menuPath: ["Completion"]),
        LunaCommandDescriptor(id: "luna.demo.sidebar.documentBuffer", title: "Sidebar: LunaDocumentBuffer.swift", menuPath: ["Sidebar"]),
        LunaCommandDescriptor(id: "luna.demo.sidebar.editorShell", title: "Sidebar: LunaEditorShell.swift", menuPath: ["Sidebar"]),
        LunaCommandDescriptor(id: "luna.demo.sidebar.completionPopup", title: "Sidebar: LunaCompletionPopup.swift", menuPath: ["Sidebar"]),
        LunaCommandDescriptor(id: "luna.demo.sidebar.phase5aTests", title: "Sidebar: LunaUIPhase5ATests.swift", menuPath: ["Sidebar"]),
        LunaCommandDescriptor(id: "luna.demo.sidebar.roadmap", title: "Sidebar: LUNA_UI_ROADMAP.md", menuPath: ["Sidebar"]),
        LunaCommandDescriptor(id: "luna.demo.context.copy", title: "Context: Copy", menuPath: ["Context"]),
        LunaCommandDescriptor(id: "luna.demo.context.paste", title: "Context: Paste Sample", menuPath: ["Context"]),
        LunaCommandDescriptor(id: "luna.demo.context.reveal", title: "Context: Reveal", menuPath: ["Context"]),
        LunaCommandDescriptor(id: "luna.demo.context.rename", title: "Context: Rename", menuPath: ["Context"]),
        LunaCommandDescriptor(id: "luna.demo.context.info", title: "Context: Show Info", menuPath: ["Context"]),
        LunaCommandDescriptor(id: "luna.demo.tab.overview", title: "Activate Overview Tab", menuPath: ["Tabs"]),
        LunaCommandDescriptor(id: "luna.demo.tab.editor", title: "Activate Editor Tab", menuPath: ["Tabs"]),
        LunaCommandDescriptor(id: "luna.demo.tab.theme", title: "Activate Theme Tab", menuPath: ["Tabs"]),
        LunaCommandDescriptor(id: "luna.demo.tab.close", title: "Close Tab", menuPath: ["Tabs"]),
    ]

    public static let demoQuickPanelItems: [LunaQuickPanelItem] = demoCommandDescriptors.map(LunaQuickPanelItem.init(command:))

    /// Product-neutral command runtime proof for Phase 5B. Luna supplies the
    /// registry, keymap, availability, and execution path; this demo scene
    /// supplies the handlers and dynamic policy. The property is computed so it
    /// remains a pure value builder instead of a shared mutable singleton.
    public static var demoCommandRuntime: LunaCommandRuntime<LunaCPUDemoScene> {
        var runtime = LunaCommandRuntime<LunaCPUDemoScene>()
        runtime.register(
            contentsOf: demoCommandDescriptors,
            handler: { command, scene, context in
                let size = LunaSizeI(
                    width: context.integerValue(for: "framebuffer.width") ?? 1024,
                    height: context.integerValue(for: "framebuffer.height") ?? 768
                )
                return scene.performDemoCommandBody(command, framebufferSize: size, context: context)
            },
            availability: { command, scene, context in
                scene.demoCommandAvailability(for: command, context: context)
            }
        )
        return runtime
    }

    /// Demo menu contents for Phase 4C. These are deliberately app-local. LunaUI
    /// owns `LunaMenuBar`; this test app owns the editor-ish menu structure.
    public static func demoMenus(for theme: LunaTheme) -> [LunaMenuDefinition] {
        let current = MothDemoTheme.canonicalTheme(for: theme).name
        let isBlue = current == LunaTheme.lunaDemoBlue.name
        let isMoth = current == MothDemoTheme.theme.name
        let isHighContrast = current == LunaTheme.highContrastProof.name

        return [
            LunaMenuDefinition(id: "file", title: "File", items: [
                LunaMenuItem.command(id: "file.new", title: "New File", command: "luna.demo.file.new", keyEquivalent: LunaKeyEquivalent("N", modifiers: [.primary])),
                LunaMenuItem.command(id: "file.open", title: "Open…", command: "luna.demo.file.open", keyEquivalent: LunaKeyEquivalent("O", modifiers: [.primary])),
                LunaMenuItem.separator(id: "file.sep.0"),
                LunaMenuItem.command(id: "file.save", title: "Save", command: "luna.demo.file.save", keyEquivalent: LunaKeyEquivalent("S", modifiers: [.primary])),
                LunaMenuItem.command(id: "file.saveAs", title: "Save As…", command: "luna.demo.file.saveAs", keyEquivalent: LunaKeyEquivalent("S", modifiers: [.primary, .shift, .option])),
                LunaMenuItem.command(id: "file.saveAll", title: "Save All", command: "luna.demo.file.saveAll", keyEquivalent: LunaKeyEquivalent("S", modifiers: [.primary, .shift])),
                LunaMenuItem.separator(id: "file.sep.1"),
                LunaMenuItem.command(id: "file.closeDocument", title: "Close Document", command: "luna.demo.file.close", keyEquivalent: LunaKeyEquivalent("W", modifiers: [.primary])),
                LunaMenuItem.command(id: "file.closeWindow", title: "Close Window", command: "luna.demo.notice", isEnabled: false),
            ]),
            LunaMenuDefinition(id: "edit", title: "Edit", items: [
                LunaMenuItem.command(id: "edit.undo", title: "Undo", command: "luna.demo.notice", keyEquivalent: LunaKeyEquivalent("Z", modifiers: [.primary]), isEnabled: false),
                LunaMenuItem.command(id: "edit.redo", title: "Redo", command: "luna.demo.notice", keyEquivalent: LunaKeyEquivalent("Z", modifiers: [.primary, .shift]), isEnabled: false),
                LunaMenuItem.separator(id: "edit.sep.0"),
                LunaMenuItem.command(id: "edit.selectAll", title: "Select All", command: "luna.demo.edit.selectAll", keyEquivalent: LunaKeyEquivalent("A", modifiers: [.primary])),
                LunaMenuItem.command(id: "edit.insertSample", title: "Insert Sample Text", command: "luna.demo.insert.sample"),
                LunaMenuItem.separator(id: "edit.sep.1"),
                LunaMenuItem.command(id: "edit.completions", title: "Show Completions", command: "luna.demo.completion.open", keyEquivalent: LunaKeyEquivalent("Space", modifiers: [.primary])),
            ]),
            LunaMenuDefinition(id: "selection", title: "Selection", items: [
                LunaMenuItem.command(id: "selection.selectAll", title: "Select All", command: "luna.demo.edit.selectAll", keyEquivalent: LunaKeyEquivalent("A", modifiers: [.primary])),
                LunaMenuItem.command(id: "selection.clear", title: "Clear Selection", command: "luna.demo.selection.clear"),
            ]),
            LunaMenuDefinition(id: "find", title: "Find", items: [
                LunaMenuItem.command(id: "find.open", title: "Find / Replace…", command: "luna.demo.find.open", keyEquivalent: LunaKeyEquivalent("F", modifiers: [.primary])),
            ]),
            LunaMenuDefinition(id: "view", title: "View", items: [
                LunaMenuItem.command(id: "view.palette", title: "Command Palette…", command: "luna.demo.palette.open", keyEquivalent: LunaKeyEquivalent("P", modifiers: [.primary])),
                LunaMenuItem.separator(id: "view.sep.0"),
                LunaMenuItem.command(id: "view.top", title: "Scroll Text View to Top", command: "luna.demo.scroll.top"),
                LunaMenuItem.command(id: "view.end", title: "Scroll Text View to End", command: "luna.demo.scroll.end"),
                LunaMenuItem.separator(id: "view.sep.1"),
                LunaMenuItem.command(id: "view.sidebar", title: "Toggle Sidebar", command: "luna.demo.sidebar.toggle"),
            ]),
            LunaMenuDefinition(id: "theme", title: "Theme", items: [
                LunaMenuItem.command(id: "theme.blue", title: "Luna Demo Blue", command: "luna.demo.theme.blue", isChecked: isBlue),
                LunaMenuItem.command(id: "theme.moth", title: "Moth Obsidian Demo", command: "luna.demo.theme.moth", isChecked: isMoth),
                LunaMenuItem.command(id: "theme.highContrast", title: "High Contrast Proof", command: "luna.demo.theme.highContrast", isChecked: isHighContrast),
            ]),
            LunaMenuDefinition(id: "help", title: "Help", items: [
                LunaMenuItem.command(id: "help.notice", title: "Show Demo Notice", command: "luna.demo.notice"),
            ]),
        ]
    }

    /// Sample documents for Phase 5A. They are still demo fixtures, but they now
    /// travel through `LunaDocumentStore` as app-supplied document descriptors and
    /// independent editable buffers instead of one global text fixture.
    public static let demoOverviewText = """
    // Phase 5A: Document / Buffer Integration
    // This is a separate Overview.swift buffer. Clicking tabs now switches the
    // actual editable text state instead of only changing shell chrome.

    struct DocumentOverview {
        let primitive = "LunaDocumentID"
        let descriptor = "LunaDocumentDescriptor"
        let store = "LunaDocumentStore"
    }

    // Try this:
    // 1. Type into this tab and watch its dirty marker appear.
    // 2. Switch to EditorSurface.swift and confirm this text is preserved.
    // 3. Switch back and confirm caret/selection state is still document-local.
    """

    public static let demoThemeDocumentText = """
    {
      "phase": "5A",
      "document": "Theme.json",
      "syntax": "JSON",
      "purpose": "prove tab switching changes the real active buffer",
      "tokens": {
        "editor.background": "theme.ui.editor.background",
        "menu.background": "theme.ui.menu.background",
        "status.foreground": "theme.ui.statusBar.foreground"
      }
    }
    """

    public static let demoText = """
    // Phase 5A: Real Document / Buffer Integration
    // Click in this editor surface and type. Enter, Backspace, Delete, Left,
    // and Right edit; Ctrl+A selects all; Ctrl+P opens commands; Ctrl+F opens find/replace; Ctrl+Space opens completions.
    struct LunaProof {
        let background = "theme.ui.editor.background"
        let gutter = "theme.ui.editor.gutterBackground"
        let text = "theme.ui.editor.foreground"
    }

    // Phase 3A added the static accessible text surface.
    // Phase 3B added caret geometry and static selection.
    // Phase 3C added logical-line scrolling and viewport metrics.
    // Phase 5A connects tabs to real active document buffers; Phase 4F anchors completions near the caret.

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

    public static func demoGeneratedWorkspaceText(title: String, phase: String, focus: String) -> String {
        """
        // \(title)
        //
        // This is an in-memory workspace-adapter fixture. Phase 5D keeps these
        // synthetic files for the default demo workspace while also allowing
        // real UTF-8 local files to be opened through the same adapter seam.

        let phase = "\(phase)"
        let focus = "\(focus)"

        // Moth can later replace this demo-owned adapter with its real project
        // adapter. Luna should keep owning only neutral descriptors, requests,
        // results, and projection helpers.
        """
    }

    /// Build the Phase 1 semantic widget for a framebuffer size. The demo render
    /// path and input path both call this helper, which keeps draw bounds and
    /// hit-test bounds identical.
    public static func semanticWidget(
        for framebufferSize: LunaSizeI,
        isFocused: Bool,
        theme: LunaTheme = MothDemoTheme.theme,
        mode: LunaDemoMode = .proofGallery
    ) -> LunaSemanticActionWidget {
        let layout = Self.layout(for: framebufferSize, mode: mode)

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

private extension String {
    var lunaDemoOpenFileID: LunaFileID? {
        let prefix = "luna.demo.file.open."
        guard hasPrefix(prefix) else { return nil }
        let id = String(dropFirst(prefix.count))
        return id.isEmpty ? nil : LunaFileID(rawValue: id)
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
    fb.clear(theme.ui.windowBackground.asRenderColor)
}

/// Draw the Phase 3A static text-view proof through Luna's text-view widget.
///
/// Rect/background/current-line geometry comes from `LunaStaticTextView`'s
/// display-list output. Glyphs still use the demo 5x7 font until LunaRender
/// grows backend-neutral text/glyph commands.
private func drawStaticTextView(
    into fb: inout LunaFramebuffer,
    view: LunaStaticTextView,
    theme: LunaTheme
) {
    guard !view.bounds.isEmpty else { return }

    var displayList = LunaDisplayList()
    view.buildDisplayList(into: &displayList)
    LunaCPURenderer().render(displayList: displayList, into: &fb)

    let layout = view.layout()
    for line in layout.visibleLines {
        if !line.lineNumberText.isEmpty && line.lineNumberBounds.w > 0 {
            drawText5x7Color(
                into: &fb,
                x: line.lineNumberBounds.x,
                y: line.lineNumberBounds.y,
                text: line.lineNumberText,
                scale: 1,
                color: theme.ui.editor.gutterForeground
            )
        }
        if line.visualText.bounds.w > 0 {
            drawText5x7Color(
                into: &fb,
                x: line.visualText.bounds.x,
                y: line.visualText.bounds.y,
                text: line.visualText.text,
                scale: 1,
                color: theme.ui.editor.foreground
            )
        }
    }

    // Draw the caret again over debug-font pixels. The widget display list also
    // contains the caret rect so pure Luna tests validate the same geometry.
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

/// Phase 5F.2A proof: each pane leaf owns a real bounded text-view instance.
///
/// Both views consume the same immutable document snapshot, but their viewport
/// bounds and scroll positions are independent. Soft-wrap breakpoints therefore
/// recompute from each pane's own content width whenever the divider moves.
private func drawPaneBoundTextViews(
    into fb: inout LunaFramebuffer,
    state: LunaPaneWorkspaceState,
    bounds: LunaRectI,
    document: LunaStaticTextDocument,
    scrollPositions: [LunaPaneID: (line: Int, visualRow: Int?)],
    caret: LunaStaticTextCaret?,
    selection: LunaStaticTextSelection?,
    highlights: [LunaStaticTextHighlight],
    theme: LunaTheme
) {
    guard !bounds.isEmpty else { return }

    let container = LunaPaneContainer(
        id: "demo.phase5f2a.panes",
        bounds: bounds,
        state: state,
        theme: theme,
        metrics: LunaPaneContainerMetrics(
            dividerThickness: 5,
            minimumPaneExtent: 80,
            activePaneBorderThickness: 2
        )
    )
    let contentMetrics = LunaPaneContentMetrics(
        headerHeight: 22,
        contentInsets: LunaInsetsI(top: 0, right: 0, bottom: 0, left: 0)
    )
    let paneLayout = container.layout()

    for frame in paneLayout.contentFrames(metrics: contentMetrics) {
        let isActive = frame.paneID == state.activePaneID
        let view = LunaCPUDemoScene.staticTextView(
            id: frame.nodeID,
            bounds: frame.contentBounds,
            document: document,
            scrollTopLine: scrollPositions[frame.paneID]?.line ?? 0,
            scrollTopVisualRow: scrollPositions[frame.paneID]?.visualRow,
            caret: isActive ? caret : nil,
            selection: isActive ? selection : nil,
            highlights: highlights,
            theme: theme,
            wrapMode: .soft
        )
        drawStaticTextView(into: &fb, view: view, theme: theme)

        fillRectColor(
            into: &fb,
            x: frame.headerBounds.x,
            y: frame.headerBounds.y,
            w: frame.headerBounds.w,
            h: frame.headerBounds.h,
            color: isActive ? theme.ui.panelTitleBackground : theme.ui.chrome.tabStripBackground
        )
        if frame.headerBounds.h > 0 {
            fillRectColor(
                into: &fb,
                x: frame.headerBounds.x,
                y: frame.headerBounds.y + frame.headerBounds.h - 1,
                w: frame.headerBounds.w,
                h: 1,
                color: theme.ui.chrome.separator
            )
        }

        let rawTitle = isActive ? "ACTIVE VIEW • SOFT WRAP" : "SECONDARY VIEW • SOFT WRAP"
        let titleCapacity = max(0, (frame.headerBounds.w - 16) / LunaDebugTextMetrics.body.advance)
        let title = LunaBoundedTextLayout.ellipsized(rawTitle, maxCharacters: titleCapacity)
        drawText5x7Color(
            into: &fb,
            x: frame.headerBounds.x + 8,
            y: frame.headerBounds.y + 5,
            text: title,
            scale: 1,
            color: isActive ? theme.ui.statusBar.accent : theme.ui.editor.gutterForeground
        )
    }

    var displayList = LunaDisplayList()
    container.buildDisplayList(into: &displayList)
    LunaCPURenderer().render(displayList: displayList, into: &fb)
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
}

private func drawProofPanelChrome(into fb: inout LunaFramebuffer, layout: LunaCPUDemoSceneLayout, theme: LunaTheme) {
    guard !layout.proofPanelBounds.isEmpty else { return }
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

/// Draw the Phase 4D editor shell chrome and visible labels. The reusable shell
/// widget owns geometry/display-list rectangles; this demo-owned CPU text path
/// draws debug-font titles until LunaDisplayList grows text-run commands.
private func drawEditorShellOverlay(into fb: inout LunaFramebuffer, shell: LunaEditorShell, theme: LunaTheme) {
    var displayList = LunaDisplayList()
    shell.buildDisplayList(into: &displayList, includesEditorContentBackground: false)
    LunaCPURenderer().render(displayList: displayList, into: &fb)

    let layout = shell.layout()
    let metrics = shell.metrics.glyphMetrics

    for tab in layout.tabFrames {
        let isActive = shell.state.tabStrip.activeTabID == tab.tab.id
        let color = isActive ? theme.ui.tabs.activeForeground : theme.ui.tabs.inactiveForeground
        if let line = LunaBoundedTextLayout.layout(tab.tab.title, in: tab.titleBounds, metrics: metrics, overflow: .ellipsizeTail).firstLine {
            drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: shell.metrics.textScale, color: color)
        }
        if let close = tab.closeButtonBounds {
            let textBounds = LunaRectI(x: close.x + 3, y: close.y + 2, w: max(1, close.w - 3), h: metrics.lineHeight)
            if let line = LunaBoundedTextLayout.layout("x", in: textBounds, metrics: metrics, overflow: .clip).firstLine {
                drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: shell.metrics.textScale, color: theme.ui.tabs.activeBackground)
            }
        }
    }

    if !layout.sidebarBounds.isEmpty {
        let headerBounds = LunaRectI(
            x: layout.sidebarHeaderBounds.x + 10,
            y: layout.sidebarHeaderBounds.y + max(0, (layout.sidebarHeaderBounds.h - metrics.glyphHeight) / 2),
            w: max(1, layout.sidebarHeaderBounds.w - 20),
            h: metrics.lineHeight
        )
        if let line = LunaBoundedTextLayout.layout(shell.sidebarTitle.uppercased(), in: headerBounds, metrics: metrics, overflow: .ellipsizeTail).firstLine {
            drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: shell.metrics.textScale, color: theme.ui.sidebar.sectionForeground)
        }

        for row in layout.sidebarRows {
            let isSelected = shell.state.sidebar.selectedItemID == row.item.id
            let fg: LunaColor
            if isSelected {
                fg = theme.ui.sidebar.rowSelectedForeground
            } else if row.item.kind == .section {
                fg = theme.ui.sidebar.sectionForeground
            } else if row.item.isEnabled {
                fg = theme.ui.sidebar.rowForeground
            } else {
                fg = theme.ui.sidebar.rowMutedForeground
            }

            if let disclosure = row.disclosureBounds {
                let marker = shell.state.sidebar.isExpanded(row.item.id) ? "v" : ">"
                let markerBounds = LunaRectI(x: disclosure.x + 1, y: row.titleBounds.y, w: disclosure.w, h: metrics.lineHeight)
                if let line = LunaBoundedTextLayout.layout(marker, in: markerBounds, metrics: metrics, overflow: .clip).firstLine {
                    drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: shell.metrics.textScale, color: theme.ui.sidebar.disclosureForeground)
                }
            }

            if let line = LunaBoundedTextLayout.layout(row.item.title, in: row.titleBounds, metrics: metrics, overflow: .ellipsizeTail).firstLine {
                drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: shell.metrics.textScale, color: fg)
            }
        }
    }

    for segment in layout.statusSegments {
        let color: LunaColor
        switch segment.segment.emphasis {
        case .normal: color = theme.ui.statusBar.foreground
        case .muted: color = theme.ui.statusBar.mutedForeground
        case .accent: color = theme.ui.statusBar.accent
        }
        if let line = LunaBoundedTextLayout.layout(segment.segment.visibleText, in: segment.textBounds, metrics: metrics, overflow: .ellipsizeTail).firstLine {
            drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: shell.metrics.textScale, color: color)
        }
    }
}

/// Draw the always-visible top menu bar. Dropdowns are drawn later as an overlay
/// so they sit above the editor/proof/status surfaces.
private func drawMenuBarOverlay(into fb: inout LunaFramebuffer, menuBar: LunaMenuBar, theme: LunaTheme) {
    let layout = menuBar.layout()
    fillRectColor(into: &fb, x: menuBar.bounds.x, y: menuBar.bounds.y, w: menuBar.bounds.w, h: menuBar.bounds.h, color: theme.ui.chrome.menuBarBackground)
    strokeRectColor(into: &fb, x: menuBar.bounds.x, y: menuBar.bounds.y + menuBar.bounds.h - 1, w: menuBar.bounds.w, h: 1, thickness: 1, color: theme.ui.chrome.separator)

    for top in layout.topLevelFrames {
        let isActive = menuBar.state.activeMenuIndex == top.index
        let isHovered = menuBar.state.hoveredMenuIndex == top.index
        if isActive || isHovered {
            fillRectColor(into: &fb, x: top.bounds.x, y: top.bounds.y, w: top.bounds.w, h: top.bounds.h, color: theme.ui.chrome.menuBarHoveredBackground)
        }
        if isActive {
            fillRectColor(into: &fb, x: top.bounds.x + 5, y: top.bounds.y + top.bounds.h - 2, w: max(1, top.bounds.w - 10), h: 2, color: theme.ui.chrome.menuBarActiveUnderline)
        }
        let color = isActive ? theme.ui.chrome.menuBarActiveForeground : theme.ui.chrome.menuBarForeground
        let textMetrics = menuBar.metrics.glyphMetrics
        let textBounds = LunaRectI(
            x: top.bounds.x + 8,
            y: top.bounds.y + max(0, (top.bounds.h - textMetrics.glyphHeight) / 2),
            w: max(1, top.bounds.w - 16),
            h: textMetrics.lineHeight
        )
        if let line = LunaBoundedTextLayout.layout(top.title, in: textBounds, metrics: textMetrics, overflow: .ellipsizeTail).firstLine {
            drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: menuBar.metrics.textScale, color: color)
        }
    }
}

/// Draw active dropdown menus plus row labels/shortcuts/check/submenu marks.
private func drawMenuDropdownOverlay(into fb: inout LunaFramebuffer, menuBar: LunaMenuBar, theme: LunaTheme) {
    guard menuBar.state.isOpen else { return }

    var displayList = LunaDisplayList()
    menuBar.buildDisplayList(into: &displayList)
    LunaCPURenderer().render(displayList: displayList, into: &fb)

    let layout = menuBar.layout()
    drawMenuBarOverlay(into: &fb, menuBar: menuBar, theme: theme)

    for dropdown in layout.dropdowns {
        for row in dropdown.rows {
            if row.item.isSeparator { continue }

            let isHighlighted = menuBar.state.highlightedPath == row.path
            let isEnabled = row.item.isEnabled
            let fg: LunaColor
            if !isEnabled {
                fg = theme.ui.menu.rowDisabledForeground
            } else if isHighlighted {
                fg = theme.ui.menu.rowHoveredForeground
            } else {
                fg = theme.ui.menu.rowForeground
            }
            let muted: LunaColor = isEnabled ? theme.ui.menu.shortcutForeground : theme.ui.menu.rowDisabledForeground

            if row.item.isChecked {
                drawText5x7Color(into: &fb, x: row.bounds.x + 8, y: row.titleBounds.y, text: "*", scale: menuBar.metrics.textScale, color: theme.ui.menu.checkedMark)
            }

            let textMetrics = menuBar.metrics.glyphMetrics
            if let titleLine = LunaBoundedTextLayout.layout(row.item.title, in: row.titleBounds, metrics: textMetrics, overflow: .ellipsizeTail).firstLine {
                drawText5x7Color(into: &fb, x: titleLine.bounds.x, y: titleLine.bounds.y, text: titleLine.text, scale: menuBar.metrics.textScale, color: fg)
            }

            if let shortcut = row.item.keyEquivalent?.lunaMenuDisplayString,
               let shortcutLine = LunaBoundedTextLayout.layout(shortcut, in: row.shortcutBounds, metrics: menuBar.metrics.glyphMetrics, overflow: .ellipsizeTail, alignment: .trailing).firstLine {
                drawText5x7Color(into: &fb, x: shortcutLine.bounds.x, y: shortcutLine.bounds.y, text: shortcutLine.text, scale: menuBar.metrics.textScale, color: muted)
            }

            if row.item.hasSubmenu {
                drawText5x7Color(into: &fb, x: row.bounds.x + row.bounds.w - 14, y: row.titleBounds.y, text: ">", scale: menuBar.metrics.textScale, color: theme.ui.menu.submenuArrow)
            }
        }
    }
}

/// Draw the active Phase 4E context menu plus row labels/shortcuts/check/submenu marks.
private func drawContextMenuOverlay(into fb: inout LunaFramebuffer, contextMenu: LunaContextMenu, theme: LunaTheme) {
    guard contextMenu.state.isOpen else { return }

    var displayList = LunaDisplayList()
    contextMenu.buildDisplayList(into: &displayList)
    LunaCPURenderer().render(displayList: displayList, into: &fb)

    let layout = contextMenu.layout()
    let textMetrics = contextMenu.metrics.glyphMetrics

    for dropdown in layout.dropdowns {
        for row in dropdown.rows {
            if row.item.isSeparator { continue }

            let isHighlighted = contextMenu.state.highlightedPath == row.path
            let isEnabled = row.item.isEnabled
            let fg: LunaColor
            if !isEnabled {
                fg = theme.ui.menu.rowDisabledForeground
            } else if isHighlighted {
                fg = theme.ui.menu.rowHoveredForeground
            } else {
                fg = theme.ui.menu.rowForeground
            }
            let muted: LunaColor = isEnabled ? theme.ui.menu.shortcutForeground : theme.ui.menu.rowDisabledForeground

            if row.item.isChecked {
                drawText5x7Color(into: &fb, x: row.bounds.x + 8, y: row.titleBounds.y, text: "*", scale: contextMenu.metrics.textScale, color: theme.ui.menu.checkedMark)
            }

            if let titleLine = LunaBoundedTextLayout.layout(row.item.title, in: row.titleBounds, metrics: textMetrics, overflow: .ellipsizeTail).firstLine {
                drawText5x7Color(into: &fb, x: titleLine.bounds.x, y: titleLine.bounds.y, text: titleLine.text, scale: contextMenu.metrics.textScale, color: fg)
            }

            if let shortcut = row.item.keyEquivalent?.lunaMenuDisplayString,
               let shortcutLine = LunaBoundedTextLayout.layout(shortcut, in: row.shortcutBounds, metrics: textMetrics, overflow: .ellipsizeTail, alignment: .trailing).firstLine {
                drawText5x7Color(into: &fb, x: shortcutLine.bounds.x, y: shortcutLine.bounds.y, text: shortcutLine.text, scale: contextMenu.metrics.textScale, color: muted)
            }

            if row.item.hasSubmenu {
                drawText5x7Color(into: &fb, x: row.bounds.x + row.bounds.w - 14, y: row.titleBounds.y, text: ">", scale: contextMenu.metrics.textScale, color: theme.ui.menu.submenuArrow)
            }
        }
    }
}

/// Draw the active Phase 4F completion popup plus row/detail text.
private func drawCompletionPopupOverlay(into fb: inout LunaFramebuffer, completionPopup: LunaCompletionPopup, theme: LunaTheme) {
    guard completionPopup.state.isOpen else { return }

    var displayList = LunaDisplayList()
    completionPopup.buildDisplayList(into: &displayList)
    LunaCPURenderer().render(displayList: displayList, into: &fb)

    let text = completionPopup.textLayout()
    for row in text.rows {
        let titleColor = row.isSelected ? theme.ui.menu.rowHoveredForeground : theme.ui.menu.rowForeground
        let annotationColor = row.isSelected ? theme.ui.menu.rowHoveredForeground : theme.ui.menu.rowMutedForeground
        drawText5x7Color(
            into: &fb,
            x: row.title.bounds.x,
            y: row.title.bounds.y,
            text: row.title.text,
            scale: completionPopup.metrics.textScale,
            color: titleColor
        )
        if let annotation = row.annotation {
            drawText5x7Color(
                into: &fb,
                x: annotation.bounds.x,
                y: annotation.bounds.y,
                text: annotation.text,
                scale: completionPopup.metrics.textScale,
                color: annotationColor
            )
        }
    }

    if let detail = text.detail {
        drawText5x7Color(
            into: &fb,
            x: detail.bounds.x,
            y: detail.bounds.y,
            text: detail.text,
            scale: completionPopup.metrics.textScale,
            color: theme.ui.panel.bodyForeground
        )
    }

    if let status = text.status {
        drawText5x7Color(
            into: &fb,
            x: status.bounds.x,
            y: status.bounds.y,
            text: status.text,
            scale: completionPopup.metrics.textScale,
            color: theme.ui.panel.mutedForeground
        )
    }
}

/// Heads-up display: title, current theme, and compact key help.
private func drawHUD(
    into fb: inout LunaFramebuffer,
    layout: LunaCPUDemoSceneLayout,
    timeSeconds t: Double,
    animationFrame: LunaAnimationFrame?,
    frameIndex: UInt64,
    theme: LunaTheme
) {
    let bounds = layout.hudBounds
    guard !bounds.isEmpty else { return }

    let title = "Luna-UI Test App"
    let animationInfo: String
    if let animationFrame {
        let clampMarker = animationFrame.wasDeltaClamped ? " clamped" : ""
        animationInfo = String(format: "phase=%.2fs dt=%.2fms%@", t, animationFrame.deltaMilliseconds, clampMarker)
    } else {
        animationInfo = String(format: "phase=%.2fs", t)
    }
    let info = String(format: "Theme: %@   %@   frame=%llu", theme.name, animationInfo, frameIndex)
    let keys = "Phase 4F: Ctrl+Space completions   right-click context menus   Menu bar   Ctrl+P palette/theme   Ctrl+F find"

    drawText5x7Color(into: &fb, x: bounds.x + 10, y: bounds.y + 8, text: title, scale: 2, color: theme.ui.chrome.titleBarForeground)

    let infoBounds = LunaRectI(x: bounds.x + 10, y: bounds.y + 31, w: max(1, bounds.w - 20), h: 9)
    if let line = LunaBoundedTextLayout.layout(info, in: infoBounds, metrics: LunaDebugTextMetrics(scale: 1), overflow: .ellipsizeTail).firstLine {
        drawText5x7Color(into: &fb, x: line.bounds.x, y: line.bounds.y, text: line.text, scale: 1, color: theme.ui.statusBar.foreground)
    }

    let keyBounds = LunaRectI(x: bounds.x + 10, y: bounds.y + 44, w: max(1, bounds.w - 20), h: 9)
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
    fb.withUnsafeMutablePixelBytes { base, strideBytes in
        // `withUnsafeMutablePixelBytes` passes row stride as the second argument.
        // Earlier hotfixes treated that as total byte count, clipping all writes
        // after the first scanline. Bounds and row math must use the stride.
        let n = strideBytes * fbH
        if n <= 0 { return }

        for yy in 0..<height {
            let row = base.advanced(by: (y0 + yy) * strideBytes)
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
    let fbW = fb.width
    let fbH = fb.height
    if fbW <= 0 || fbH <= 0 || text.isEmpty { return }

    fb.withUnsafeMutablePixelBytes { base, strideBytes in
        let safeByteCount = strideBytes * fbH
        guard safeByteCount > 0 else { return }

        @inline(__always)
        func writePixel(_ px: Int, _ py: Int) {
            if px < 0 || py < 0 || px >= fbW || py >= fbH { return }
            let offset = py * strideBytes + px * 4
            if offset < 0 || offset + 3 >= safeByteCount { return }
            let p = base.advanced(by: offset)
            p[0] = b
            p[1] = g
            p[2] = r
            p[3] = a
        }

        @inline(__always)
        func fillSpan(rowY: Int, x0: Int, x1: Int) {
            if rowY < 0 || rowY >= fbH { return }
            let clippedX0 = max(0, x0)
            let clippedX1 = min(fbW, x1)
            if clippedX1 <= clippedX0 { return }
            var p = base.advanced(by: rowY * strideBytes + clippedX0 * 4)
            for _ in clippedX0..<clippedX1 {
                p[0] = b
                p[1] = g
                p[2] = r
                p[3] = a
                p = p.advanced(by: 4)
            }
        }

        var penX = x
        for scalar in text.unicodeScalars {
            let code = Int(scalar.value)
            if code == 10 {
                penX = x
                continue
            }
            let advance = 6 * s
            defer { penX += advance }
            if code < 32 || code > 127 { continue }
            if penX >= fbW || penX + 5 * s <= 0 { continue }
            if y >= fbH || y + 7 * s <= 0 { continue }

            let glyphBase = (code - 32) * 5
            for col in 0..<5 {
                let columnBits = font5x7[glyphBase + col]
                if columnBits == 0 { continue }
                let px0 = penX + col * s
                if px0 >= fbW || px0 + s <= 0 { continue }
                for row in 0..<7 where ((columnBits >> row) & 1) != 0 {
                    let py0 = y + row * s
                    if s == 1 {
                        writePixel(px0, py0)
                    } else {
                        for yy in py0..<(py0 + s) {
                            fillSpan(rowY: yy, x0: px0, x1: px0 + s)
                        }
                    }
                }
            }
        }
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
