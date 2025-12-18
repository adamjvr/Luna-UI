// main.swift
// Luna-UI Test Harness (CPU framebuffer)
//
// This harness now uses:
// - macOS: CVDisplayLink (vsync clock) -> schedules tick() on main thread
// - Linux: SDL loop (we will add vsync renderer flags next)
//
// It also keeps:
// - time-based animation
// - points/sec speed (perceived consistent across displays)
// - HiDPI correctness (framebuffer sized in device pixels, with optional CPU quality scaling)
// - safe shutdown on window close (no segfaults)

import LunaUI
import LunaRender
import LunaHost

// -----------------------------------------------------------------------------
// Shared test scene generator (TIME-BASED, POINTS-BASED SPEED)
// -----------------------------------------------------------------------------

/// Build a display list for a moving rectangle.
///
/// Parameters:
/// - t: elapsed seconds
/// - widthPx/heightPx: framebuffer dimensions in pixels
/// - pixelsPerPoint: effective scale used for rendering (backingScaleFactor * cpuHiDPIQuality)
///
/// Why points/sec:
/// - "Pixels/sec" looks different on HiDPI vs non-HiDPI screens.
/// - "Points/sec" looks consistent to humans across displays.
/// - We convert points/sec to pixels/sec using pixelsPerPoint.
func buildTestDisplayList(
    t: Double,
    widthPx: Int,
    heightPx: Int,
    pixelsPerPoint: Double
) -> LunaDisplayList {

    let bg = LunaRGBA8(r: 18, g: 18, b: 22, a: 255)
    let accent = LunaRGBA8(r: 110, g: 200, b: 255, a: 255)

    let rectW = max(40, widthPx / 6)
    let rectH = max(40, heightPx / 6)

    // Perceived speed in points/sec
    let speedPointsPerSec: Double = 360.0

    // Convert to pixels/sec
    let speedPxPerSec: Double = speedPointsPerSec * pixelsPerPoint

    let travel = max(1, widthPx - rectW - 20)

    let raw = 10.0 + (t * speedPxPerSec)
    let x = 10 + Int(raw.truncatingRemainder(dividingBy: Double(travel)))
    let y = max(10, heightPx / 3)

    return LunaDisplayList(commands: [
        .clear(bg),
        .rect(LunaRectI(x: x, y: y, w: rectW, h: rectH), accent),
    ])
}

// -----------------------------------------------------------------------------
// macOS host (CVDisplayLink-driven)
// -----------------------------------------------------------------------------
#if os(macOS)
import AppKit
import QuartzCore // CACurrentMediaTime()

@MainActor
final class TestApp: NSObject, NSApplicationDelegate, NSWindowDelegate {

    var window: NSWindow!
    var view: LunaFramebufferView!

    // CPU renderer + framebuffer
    let renderer = LunaCPURenderer()
    var framebuffer = LunaFramebuffer(width: 900, height: 600)

    // Vsync clock
    private let displayLink = LunaDisplayLink()

    // Start time for animation
    private let t0: Double = CACurrentMediaTime()

    /// CPU-only HiDPI performance knob:
    /// - 1.0 = full device-pixel render (crispest, slowest on Retina)
    /// - 0.5 = half-res render (much faster), upscaled for display
    ///
    /// For CPU fallback on 120Hz Retina, 0.5 is usually the practical default.
    private let cpuHiDPIQuality: CGFloat = 0.5

    func applicationDidFinishLaunching(_ notification: Notification) {

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Luna-UI Test Harness (CPUFramebuffer + DisplayLink)"
        window.center()
        window.delegate = self

        view = LunaFramebufferView(frame: window.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true

        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        // Wire displayLink to call tick() on the main thread.
        // (LunaDisplayLink guarantees onFrame runs on main.)
        displayLink.onFrame = { [weak self] in
            guard let self else { return }
            self.tick()
        }

        // Start vsync ticking.
        displayLink.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        shutdownAndExit()
    }

    func applicationWillTerminate(_ notification: Notification) {
        displayLink.stop()
    }

    private func shutdownAndExit() {
        // Stop the vsync clock first so no more ticks occur during teardown.
        displayLink.stop()

        // Clear presenter source to reduce any in-flight updates.
        view.framebuffer = nil

        NSApplication.shared.terminate(nil)
    }

    /// Render one frame.
    ///
    /// Called on the main thread, scheduled by CVDisplayLink.
    private func tick() {

        guard window != nil, window.isVisible else { return }

        let t = CACurrentMediaTime() - t0

        // Real backing scale: points -> device pixels
        let backingScale: CGFloat = window.backingScaleFactor

        // Effective render scale may be reduced for CPU performance
        let effectiveScale: CGFloat = backingScale * cpuHiDPIQuality

        // View bounds are in points
        let pointW = view.bounds.width
        let pointH = view.bounds.height

        // Framebuffer size in pixels
        let pixelW = max(1, Int((pointW * effectiveScale).rounded(.toNearestOrAwayFromZero)))
        let pixelH = max(1, Int((pointH * effectiveScale).rounded(.toNearestOrAwayFromZero)))

        // Compositor scale should match the real screen scale (crisp presentation)
        view.layer?.contentsScale = backingScale

        if pixelW != framebuffer.width || pixelH != framebuffer.height {
            framebuffer.resize(width: pixelW, height: pixelH)
        }

        let dl = buildTestDisplayList(
            t: t,
            widthPx: framebuffer.width,
            heightPx: framebuffer.height,
            pixelsPerPoint: Double(effectiveScale)
        )

        renderer.render(displayList: dl, into: &framebuffer)

        // Present
        view.framebuffer = framebuffer
        view.needsDisplay = true
    }
}

let app = NSApplication.shared
let delegate = TestApp()
app.delegate = delegate
app.run()
#endif

// -----------------------------------------------------------------------------
// Linux host (SDL loop for now)
// -----------------------------------------------------------------------------
#if os(Linux)
import SDL2

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

    // HiDPI-correct pixel size from renderer output
    let (pixelW, pixelH) = presenter.getOutputPixelSize(
        fallbackWidth: framebuffer.width,
        fallbackHeight: framebuffer.height
    )

    if pixelW != framebuffer.width || pixelH != framebuffer.height {
        framebuffer.resize(width: pixelW, height: pixelH)
        presenter.ensureTexture(width: Int32(pixelW), height: Int32(pixelH))
    }

    // Linux "points" are not formalized yet; treat pixelsPerPoint = 1.0 for now.
    let dl = buildTestDisplayList(
        t: t,
        widthPx: framebuffer.width,
        heightPx: framebuffer.height,
        pixelsPerPoint: 1.0
    )

    renderer.render(displayList: dl, into: &framebuffer)
    presenter.present(framebuffer: framebuffer)

    SDL_Delay(1)
}

SDL_DestroyWindow(window)
SDL_Quit()
#endif
