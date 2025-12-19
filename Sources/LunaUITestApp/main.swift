//
//  Sources/LunaUITestApp/main.swift
//
//  Luna-UI Test Harness
//  --------------------
//  Purpose of this file (right now):
//    1) Prove the CPU framebuffer pipeline works end-to-end on Linux + macOS.
//    2) Prove HarfBuzz shaping works (ligatures, RTL, complex scripts).
//    3) Prove FreeType metrics are usable for placement.
//    4) Provide a visual on-screen debug: glyph bounding boxes + baseline.
//
//  IMPORTANT NOTE (why your text looked "blocky"):
//    - We are NOT rendering glyph bitmaps yet.
//    - We are drawing glyph *bounding boxes* as rectangles.
//    - Previously we drew FILLED rectangles, so it looked like chunky "text blocks".
//    - This patch switches to OUTLINED rectangles (wireframe boxes) + baseline lines.
//      This makes it obvious it's just debug geometry, not rasterized text.
//

import Foundation

import LunaUI
import LunaRender
import LunaHost
import LunaText

// ------------------------------------------------------------
// MARK: - Helpers
// ------------------------------------------------------------

/// Convert HarfBuzz 26.6 fixed-point values (scaled by 64) into integer pixels.
/// We also round to the nearest pixel for stability (especially for small offsets).
@inline(__always)
func hb26_6_to_px(_ v: Int32) -> Int {
    return Int((v + 32) / 64)
}

// ------------------------------------------------------------
// MARK: - LunaText smoke test (terminal-only, runs once)
// ------------------------------------------------------------

/// Runs a small “prove it works” terminal log for shaping.
/// This is intentionally noisy while we are wiring up HarfBuzz/FreeType.
/// Later we’ll downgrade this to a unit test or a debug flag.
func runLunaTextSmokeTest() {
    print("------------------------------------------------------------")
    print("[LunaText] Smoke test: shaping (ligatures + complex scripts)")
    print("------------------------------------------------------------")

    struct Case {
        let label: String
        let text: String
        let dir: LunaTextDirection
        let lang: String?
        let scriptTag: String?
        let scriptHint: LunaScriptHint
    }

    let cases: [Case] = [
        Case(label: "Ligatures (Latin)", text: "office -> fi fl ffi", dir: .ltr, lang: "en", scriptTag: "Latn", scriptHint: .latin),
        Case(label: "Arabic (RTL)", text: "مرحبا بالعالم", dir: .rtl, lang: "ar", scriptTag: "Arab", scriptHint: .arabic),
        Case(label: "Devanagari", text: "हिन्दी भाषा", dir: .ltr, lang: "hi", scriptTag: "Deva", scriptHint: .devanagari),
    ]

    for c in cases {
        let fontPath = LunaFontLocator.bestFontPath(for: c.scriptHint)

        if fontPath.isEmpty || !FileManager.default.fileExists(atPath: fontPath) {
            print("")
            print("[LunaText] \(c.label) — SKIPPED (no font found)")
            continue
        }

        do {
            let shaper = try LunaTextShaper(font: LunaFontDescriptor(filePath: fontPath, pointSize: 16))
            let run = shaper.shape(c.text, direction: c.dir, language: c.lang, script: c.scriptTag)

            print("")
            print("[LunaText] \(c.label)")
            print("  font: \(fontPath)")
            print("  text: \(c.text)")
            print("  glyphCount: \(run.glyphs.count)")

            // Print a bunch of glyphs so we can verify clustering + advances.
            let N = min(14, run.glyphs.count)
            for i in 0..<N {
                let g = run.glyphs[i]
                // NOTE: LunaGlyphPosition stores HarfBuzz-style names here (xAdvance/xOffset).
                //       These are 26.6 (scaled by 64) in the current API.
                print("   [\(i)] gid=\(g.glyphID) cluster=\(g.cluster) adv=(\(g.xAdvance),\(g.yAdvance)) off=(\(g.xOffset),\(g.yOffset))")
            }

            if run.glyphs.count > N {
                print("   ... (\(run.glyphs.count - N) more)")
            }
        } catch {
            print("")
            print("[LunaText] \(c.label) — FAILED: \(error)")
        }
    }

    print("")
    print("------------------------------------------------------------")
    print("[LunaText] Smoke test complete.")
    print("------------------------------------------------------------")
}

// Run smoke test once at startup.
runLunaTextSmokeTest()

// ------------------------------------------------------------
// MARK: - On-screen debug drawing: glyph boxes (OUTLINES, not filled)
// ------------------------------------------------------------

/// Draws glyph bounding boxes as thin OUTLINES instead of filled rectangles.
/// This makes it obvious we’re not rendering real glyph bitmaps yet.
///
/// Placement rules (baseline-based):
///   - (penX, baselineY) is the text baseline origin.
///   - HarfBuzz provides offsets/advances per glyph in 26.6.
///   - FreeType provides glyph metrics:
///       * bearingX = bitmap_left (px)
///       * bearingY = bitmap_top  (px above baseline)
///       * width/height = bitmap size (px)
///
/// So the glyph top-left pixel becomes:
///   gx = penX + xOff + bearingX
///   gy = baselineY + yOff - bearingY
func appendTextBoxes(
    commands: inout [LunaDrawCommand],
    shaper: LunaTextShaper,
    run: LunaShapedRun,
    originX: Int,
    baselineY: Int,
    color: LunaRGBA8
) {
    var penX = originX
    let penY = baselineY

    // Draw a baseline line (1px tall) for placement sanity checking.
    commands.append(.rect(LunaRectI(x: originX, y: baselineY, w: 800, h: 1), color))

    /// Draw a rectangle outline using four thin filled rects.
    /// This keeps the renderer primitive set minimal (only .rect).
    @inline(__always)
    func outlineRect(_ r: LunaRectI, _ c: LunaRGBA8, thickness: Int = 1) {
        guard r.w > 0, r.h > 0 else { return }

        let t = max(1, thickness)

        // Top edge
        commands.append(.rect(LunaRectI(x: r.x, y: r.y, w: r.w, h: t), c))
        // Bottom edge
        commands.append(.rect(LunaRectI(x: r.x, y: r.y + r.h - t, w: r.w, h: t), c))
        // Left edge
        commands.append(.rect(LunaRectI(x: r.x, y: r.y, w: t, h: r.h), c))
        // Right edge
        commands.append(.rect(LunaRectI(x: r.x + r.w - t, y: r.y, w: t, h: r.h), c))
    }

    for g in run.glyphs {

        // Convert HarfBuzz per-glyph offsets (26.6) → px.
        let xOff = hb26_6_to_px(g.xOffset)
        let yOff = hb26_6_to_px(g.yOffset)

        // Get FreeType raster metrics for this glyph.
        // (At this stage we only use metrics, not the actual bitmap).
        let info: LunaGlyphRasterInfo
        do {
            info = try shaper.rasterInfo(forGlyphID: g.glyphID)
        } catch {
            // If something fails, just advance using HarfBuzz advance and continue.
            penX += hb26_6_to_px(g.xAdvance)
            continue
        }

        // Glyph top-left in framebuffer coordinates.
        let gx = penX + xOff + info.bearingX
        let gy = penY + yOff - info.bearingY

        if info.width > 0 && info.height > 0 {
            outlineRect(LunaRectI(x: gx, y: gy, w: info.width, h: info.height), color, thickness: 1)
        }

        // Advance pen:
        // Prefer HarfBuzz’s advance (because it accounts for shaping / ligatures / RTL),
        // but if it is 0, fall back to FreeType’s advance.
        let hbAdvPx = hb26_6_to_px(g.xAdvance)
        penX += (hbAdvPx != 0 ? hbAdvPx : info.advanceX)
    }
}

// ------------------------------------------------------------
// MARK: - Shared demo display list
// ------------------------------------------------------------

/// Builds a display list for this frame.
/// Everything we draw must be expressed in pixel-space framebuffer coordinates.
func buildTestDisplayList(
    t: Double,
    widthPx: Int,
    heightPx: Int,
    pixelsPerPoint: Double,
    latinShaper: LunaTextShaper,
    arabicShaper: LunaTextShaper,
    devaShaper: LunaTextShaper
) -> LunaDisplayList {

    // Background: deep bluish gray.
    let bg     = LunaRGBA8(r: 18,  g: 18,  b: 22,  a: 255)

    // Moving block: bright accent.
    let accent = LunaRGBA8(r: 110, g: 200, b: 255, a: 255)

    // Text-outline colors (debug).
    let textA  = LunaRGBA8(r: 240, g: 240, b: 245, a: 255)
    let textB  = LunaRGBA8(r: 180, g: 255, b: 180, a: 255)
    let textC  = LunaRGBA8(r: 255, g: 210, b: 140, a: 255)

    var cmds: [LunaDrawCommand] = []
    cmds.reserveCapacity(4096)

    cmds.append(.clear(bg))

    // --------------------------------------------------------
    // Moving block (frame pacing / CPU renderer sanity)
    // --------------------------------------------------------

    let rectW = max(40, widthPx / 6)
    let rectH = max(40, heightPx / 6)

    // Keep animation speed stable across displays:
    // "points per second" * pixelsPerPoint => pixels per second.
    let speedPointsPerSec: Double = 360.0
    let speedPxPerSec: Double = speedPointsPerSec * pixelsPerPoint

    let travel = max(1, widthPx - rectW - 20)
    let raw = 10.0 + (t * speedPxPerSec)
    let x = 10 + Int(raw.truncatingRemainder(dividingBy: Double(travel)))
    let y = max(10, heightPx / 3)

    cmds.append(.rect(LunaRectI(x: x, y: y, w: rectW, h: rectH), accent))

    // --------------------------------------------------------
    // “Text” debug: outlined glyph boxes + baseline lines
    // --------------------------------------------------------

    let marginX = 24
    let baseY1  = 70
    let baseY2  = 110
    let baseY3  = 150

    let latin = latinShaper.shape("office -> fi fl ffi", direction: .ltr, language: "en", script: "Latn")
    let arab  = arabicShaper.shape("مرحبا بالعالم", direction: .rtl, language: "ar", script: "Arab")
    let deva  = devaShaper.shape("हिन्दी भाषा", direction: .ltr, language: "hi", script: "Deva")

    appendTextBoxes(commands: &cmds, shaper: latinShaper,  run: latin, originX: marginX, baselineY: baseY1, color: textA)
    appendTextBoxes(commands: &cmds, shaper: arabicShaper, run: arab,  originX: marginX, baselineY: baseY2, color: textB)
    appendTextBoxes(commands: &cmds, shaper: devaShaper,   run: deva,  originX: marginX, baselineY: baseY3, color: textC)

    return LunaDisplayList(commands: cmds)
}

// ------------------------------------------------------------
// MARK: - Create shapers ONCE (do not allocate per frame)
// ------------------------------------------------------------

let latinFont = LunaFontLocator.bestFontPath(for: .latin)
let arabFont  = LunaFontLocator.bestFontPath(for: .arabic)
let devaFont  = LunaFontLocator.bestFontPath(for: .devanagari)

// NOTE:
// We use point size ~18 so the bounding boxes are easier to see.
let latinShaper  = try! LunaTextShaper(font: LunaFontDescriptor(filePath: latinFont, pointSize: 18))
let arabicShaper = try! LunaTextShaper(font: LunaFontDescriptor(filePath: arabFont,  pointSize: 18))
let devaShaper   = try! LunaTextShaper(font: LunaFontDescriptor(filePath: devaFont,  pointSize: 18))

// ------------------------------------------------------------
// MARK: - Platform hosts
// ------------------------------------------------------------

#if os(macOS)

import AppKit
import QuartzCore

/// A simple NSView whose only purpose is to become first responder (keyboard focus).
@MainActor
final class KeyCatcherView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class TestApp: NSObject, NSApplicationDelegate, NSWindowDelegate {

    var window: NSWindow!
    var root: KeyCatcherView!

    var cpuView: LunaFramebufferView!
    let cpuRenderer = LunaCPURenderer()
    var cpuFramebuffer = LunaFramebuffer(width: 900, height: 600)

    private let displayLink = LunaDisplayLink()
    private let t0: Double = CACurrentMediaTime()

    func applicationDidFinishLaunching(_ notification: Notification) {

        NSApp.setActivationPolicy(.regular)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.delegate = self

        root = KeyCatcherView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        cpuView = LunaFramebufferView(frame: root.bounds)
        cpuView.autoresizingMask = [.width, .height]
        root.addSubview(cpuView)

        window.title = "Luna-UI Test Harness — CPUFramebuffer"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        displayLink.onFrame = { [weak self] in
            guard let self else { return }
            self.tick()
        }
        displayLink.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func windowWillClose(_ notification: Notification) {
        displayLink.stop()
        cpuView.framebuffer = nil
        NSApplication.shared.terminate(nil)
    }

    private func tick() {
        let t = CACurrentMediaTime() - t0

        // HiDPI correctness:
        // - root.bounds is in points
        // - backingScaleFactor converts points → pixels
        let backingScale = window.backingScaleFactor
        let bounds = root.bounds

        let pixelW = max(1, Int((bounds.width * backingScale).rounded()))
        let pixelH = max(1, Int((bounds.height * backingScale).rounded()))

        if pixelW != cpuFramebuffer.width || pixelH != cpuFramebuffer.height {
            cpuFramebuffer.resize(width: pixelW, height: pixelH)
        }

        let dl = buildTestDisplayList(
            t: t,
            widthPx: cpuFramebuffer.width,
            heightPx: cpuFramebuffer.height,
            pixelsPerPoint: Double(backingScale),
            latinShaper: latinShaper,
            arabicShaper: arabicShaper,
            devaShaper: devaShaper
        )

        cpuRenderer.render(displayList: dl, into: &cpuFramebuffer)
        cpuView.framebuffer = cpuFramebuffer
        cpuView.needsDisplay = true
    }
}

let app = NSApplication.shared
let delegate = TestApp()
app.delegate = delegate
app.run()

#endif

#if os(Linux)

import SDL2

/// High-resolution monotonic time in seconds using SDL’s performance counter.
@inline(__always)
func nowSeconds() -> Double {
    let freq = Double(SDL_GetPerformanceFrequency())
    let cnt  = Double(SDL_GetPerformanceCounter())
    return cnt / freq
}

if SDL_Init(SDL_INIT_VIDEO) != 0 {
    fatalError("SDL_Init failed: \(String(cString: SDL_GetError()))")
}

guard let window = SDL_CreateWindow(
    "Luna-UI Test Harness (CPUFramebuffer)",
    0, 0,
    900, 600,
    UInt32(SDL_WINDOW_SHOWN.rawValue | SDL_WINDOW_RESIZABLE.rawValue)
) else {
    fatalError("SDL_CreateWindow failed: \(String(cString: SDL_GetError()))")
}

let presenter = LunaSDLPresenter(window: window)
let renderer = LunaCPURenderer()
var framebuffer = LunaFramebuffer(width: 900, height: 600)

var event = SDL_Event()
var running = true

let t0 = nowSeconds()

while running {

    while SDL_PollEvent(&event) != 0 {
        if event.type == SDL_QUIT.rawValue {
            running = false
        }
    }

    let t = nowSeconds() - t0

    // SDL gives us output size in pixels. This is the authoritative pixel resolution.
    let (pixelW, pixelH) = presenter.getOutputPixelSize(
        fallbackWidth: framebuffer.width,
        fallbackHeight: framebuffer.height
    )

    if pixelW != framebuffer.width || pixelH != framebuffer.height {
        framebuffer.resize(width: pixelW, height: pixelH)
        presenter.ensureTexture(width: Int32(pixelW), height: Int32(pixelH))
    }

    // NOTE:
    // On Linux, pixelsPerPoint is not directly known from SDL without DPI queries.
    // For now we use 1.0 so the moving block speed remains stable in pixel space.
    let dl = buildTestDisplayList(
        t: t,
        widthPx: framebuffer.width,
        heightPx: framebuffer.height,
        pixelsPerPoint: 1.0,
        latinShaper: latinShaper,
        arabicShaper: arabicShaper,
        devaShaper: devaShaper
    )

    renderer.render(displayList: dl, into: &framebuffer)
    presenter.present(framebuffer: framebuffer)

    // Tiny delay to avoid pegging a core in this early prototype.
    SDL_Delay(1)
}

SDL_DestroyWindow(window)
SDL_Quit()

#endif
