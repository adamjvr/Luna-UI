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
    public static let hudID: LunaNodeID = "demo.hud"
    public static let statusID: LunaNodeID = "demo.status"

    public var viewport: LunaViewport
    public var frames: LunaLayoutResult

    public init(viewport: LunaViewport, frames: LunaLayoutResult) {
        self.viewport = viewport
        self.frames = frames
    }

    public var semanticWidgetBounds: LunaRectI {
        frames.frame(for: Self.semanticWidgetID) ?? LunaRectI(x: 0, y: 0, w: 0, h: 0)
    }

    public var hudBounds: LunaRectI {
        frames.frame(for: Self.hudID) ?? LunaRectI(x: 0, y: 0, w: viewport.size.width, h: 36)
    }

    public var statusBounds: LunaRectI {
        frames.frame(for: Self.statusID) ?? LunaRectI(x: 18, y: max(120, viewport.size.height - 34), w: max(1, viewport.size.width - 36), h: 28)
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
    /// same customization path Moth Text will use instead of hardcoding Luna's
    /// appearance.
    public var theme: LunaTheme

    /// Monotonic frame counter (increments each render).
    public private(set) var frameIndex: UInt64 = 0

    /// Number of successful semantic widget activations received through the
    /// platform-neutral Luna pointer routing path.
    public private(set) var semanticActivationCount: Int = 0

    /// Last interaction string displayed in the demo status area.
    private var lastInteractionStatus: String = "Click Phase 1B panel to open overlay; press 1/2/3 to switch themes"

    /// Phase 2 modal manager.  The demo owns a manager so we can prove a host
    /// click routes through: modal first, semantic widget second.
    private var modalManager = LunaModalOverlayManager()

    /// Create a new demo scene.
    public init(
        theme: LunaTheme = .mothDefaultDark,
        startTimeNanoseconds: UInt64 = LunaCPUDemoScene.nowMonotonicNanoseconds()
    ) {
        self.startTime = startTimeNanoseconds
        self.theme = theme
        self.modalManager = LunaModalOverlayManager(style: LunaMothDefaultDarkControlStyle(theme: theme))
    }



    /// Reflow scene-owned overlays after the host window/framebuffer resizes.
    ///
    /// Background widgets are recomputed from `layout(for:)` during render and
    /// hit testing. Active modals are stateful, so the manager explicitly
    /// recalculates their panel/choice/accessibility bounds here.
    public mutating func handleWindowResize(_ size: LunaSizeI) {
        modalManager.reflow(viewportSize: size)
        lastInteractionStatus = "Resized/reflowed Luna layout to \(size.width)x\(size.height)"
    }

    /// Switch the active theme and refresh all stateful visual styles.
    ///
    /// Phase 2E uses this in the demo so theme replacement is not theoretical:
    /// the same widget/modal code can be rendered with Luna demo blue, Moth
    /// default dark, or a high-contrast proof palette.
    public mutating func setTheme(_ newTheme: LunaTheme, framebufferSize: LunaSizeI) {
        theme = newTheme
        modalManager.style = LunaMothDefaultDarkControlStyle(theme: newTheme)
        modalManager.reflow(viewportSize: framebufferSize)
        lastInteractionStatus = "Theme: \(newTheme.name). Press 1=Luna demo, 2=Moth dark, 3=high contrast."
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

        // Draw.
        drawBackgroundChecker(into: &fb, theme: theme)
        drawMovingBlock(into: &fb, timeSeconds: t, theme: theme)
        drawSemanticWidgetProof(
            into: &fb,
            activationCount: semanticActivationCount,
            status: lastInteractionStatus,
            theme: theme
        )
        drawHUD(into: &fb, timeSeconds: t, frameIndex: frameIndex, theme: theme)
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

        switch event.key {
        case .number(1):
            setTheme(.lunaDemoBlue, framebufferSize: framebufferSize)
            return true
        case .number(2):
            setTheme(.mothDefaultDark, framebufferSize: framebufferSize)
            return true
        case .number(3):
            setTheme(.highContrastProof, framebufferSize: framebufferSize)
            return true
        default:
            return false
        }
    }



    /// Compute the current demo layout for a framebuffer size.
    ///
    /// This is intentionally public/testable so resize/reflow correctness can be
    /// validated without relying on screenshots.
    public static func layout(for framebufferSize: LunaSizeI) -> LunaCPUDemoSceneLayout {
        let viewport = LunaViewport(size: framebufferSize)
        let context = LunaLayoutContext(viewport: viewport)
        var result = LunaLayoutResult()

        let hudHeight = max(28, min(44, viewport.size.height / 12))
        result.set(id: LunaCPUDemoSceneLayout.hudID, bounds: LunaRectI(x: 0, y: 0, w: viewport.size.width, h: hudHeight))

        let panelW = min(300, max(180, viewport.size.width / 3))
        let semanticFrame = LunaAnchoredLayoutSpec(
            id: LunaCPUDemoSceneLayout.semanticWidgetID,
            anchor: .topRight,
            sizeRule: LunaLayoutSizeRule(
                preferred: LunaSizeI(width: panelW, height: 56),
                minimum: LunaSizeI(width: 180, height: 56),
                maximum: LunaSizeI(width: 300, height: 56)
            ),
            margin: LunaInsetsI(top: 54, right: 18, bottom: 18, left: 18)
        ).frame(in: context)
        result.set(semanticFrame)

        let statusY = min(max(semanticFrame.bounds.y + semanticFrame.bounds.h + 12, 120), max(120, viewport.size.height - 28))
        result.set(
            id: LunaCPUDemoSceneLayout.statusID,
            bounds: LunaRectI(x: 18, y: statusY, w: max(1, viewport.size.width - 36), h: 28)
        )

        return LunaCPUDemoSceneLayout(viewport: viewport, frames: result)
    }

    /// Build the Phase 1 semantic widget for a framebuffer size. The demo render
    /// path and input path both call this helper, which keeps draw bounds and
    /// hit-test bounds identical.
    public static func semanticWidget(
        for framebufferSize: LunaSizeI,
        isFocused: Bool,
        theme: LunaTheme = .mothDefaultDark
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

/// Fill the entire framebuffer with a subtle checker so “black window” bugs
/// are immediately obvious.
private func drawBackgroundChecker(into fb: inout LunaFramebuffer, theme: LunaTheme) {
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

        // We will write row-by-row.
        for y in 0..<h {
            let row = base.advanced(by: y * bpr)
            for x in 0..<w {
                // 16px checker pattern.
                let cx = (x >> 4) & 1
                let cy = (y >> 4) & 1
                let on = (cx ^ cy) != 0

                let color = on ? theme.ui.editor.background : theme.ui.windowBackground

                let p = row.advanced(by: x * 4)
                p[0] = color.b         // B
                p[1] = color.g         // G
                p[2] = color.r         // R
                p[3] = color.a         // A
            }
        }
    }
}

/// Draw a moving rectangle whose motion is driven by time.
private func drawMovingBlock(into fb: inout LunaFramebuffer, timeSeconds t: Double, theme: LunaTheme) {
    let w = fb.width
    let h = fb.height
    if w <= 0 || h <= 0 { return }

    // Block size scales a bit with window size.
    let blockW = max(32, w / 6)
    let blockH = max(32, h / 6)

    // Simple Lissajous-ish motion.
    let ampX = Double(max(1, w - blockW))
    let ampY = Double(max(1, h - blockH))
    let px = (sin(t * 1.2) * 0.5 + 0.5) * ampX
    let py = (cos(t * 0.9) * 0.5 + 0.5) * ampY
    let x0 = Int(px.rounded(.toNearestOrAwayFromZero))
    let y0 = Int(py.rounded(.toNearestOrAwayFromZero))

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
    status: String,
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
    drawText5x7BGRA(
        into: &fb,
        x: widgetText.title.bounds.x,
        y: widgetText.title.bounds.y,
        text: widgetText.title.text,
        scale: 2,
        b: 255,
        g: 255,
        r: 255,
        a: 255
    )
    if let subtitle = widgetText.subtitle {
        drawText5x7BGRA(
            into: &fb,
            x: subtitle.bounds.x,
            y: subtitle.bounds.y,
            text: subtitle.text,
            scale: 1,
            b: 230,
            g: 230,
            r: 230,
            a: 255
        )
    }

    let layout = LunaCPUDemoScene.layout(for: LunaSizeI(width: fb.width, height: fb.height))
    let statusBounds = layout.statusBounds
    let statusLayout = LunaBoundedTextLayout.layout(
        status,
        in: statusBounds,
        metrics: LunaDebugTextMetrics(scale: 2),
        overflow: .ellipsizeTail
    )
    if let statusLine = statusLayout.firstLine {
        drawText5x7Color(
            into: &fb,
            x: statusLine.bounds.x,
            y: statusLine.bounds.y,
            text: statusLine.text,
            scale: 2,
            color: theme.ui.statusText
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

/// Heads-up display: title + time + frame.
private func drawHUD(into fb: inout LunaFramebuffer, timeSeconds t: Double, frameIndex: UInt64, theme: LunaTheme) {
    // Draw a translucent-ish bar (we still write opaque alpha; translucency is
    // achieved by using a dark color over the checker).
    let barH = max(28, min(44, fb.height / 12))

    // LunaFramebuffer is row-major and presented by SDL/CoreGraphics with the
    // conventional framebuffer coordinate system: (0, 0) is the TOP-left pixel
    // and y increases downward.
    //
    // Older versions of this demo accidentally treated the framebuffer as
    // bottom-left-origin, which pushed the HUD to the bottom of the window and
    // flipped the 5x7 text vertically. Keep the demo aligned with the actual
    // byte layout so renderer bugs are visible instead of masked by coordinate
    // conversion hacks.
    let barY = 0
    fillRectColor(into: &fb, x: 0, y: barY, w: fb.width, h: barH, color: theme.ui.hudBackground)

    // Text (5x7 font, scaled).
    let title = "Luna-UI CPU Demo"
    let info = String(format: "t=%.2fs  frame=%llu", t, frameIndex)

    // Keep text inside the HUD bar.
    let textX = 10
    let titleY = barY + 8
    let infoY  = barY + 8 + 2 * (7 * 2 + 4)

    drawText5x7Color(into: &fb, x: textX, y: titleY, text: title, scale: 2, color: theme.ui.chrome.titleBarForeground)
    drawText5x7Color(into: &fb, x: textX, y: infoY,  text: info,  scale: 2, color: theme.ui.statusBar.foreground)
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
