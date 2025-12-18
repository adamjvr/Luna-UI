// main.swift
// Luna-UI Test Harness (CPU framebuffer)
//
// Fixes in this version:
// - Motion speed is defined in *points/second* (perceived consistent across displays)
// - Converted to *pixels/second* using the same effective scale used for the framebuffer
// - HiDPI correctness: framebuffer sized in device pixels (optionally reduced for CPU)
// - Clean shutdown: stop timer on window close (avoid segfault)

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
/// IMPORTANT:
/// - We want *visual* speed to be stable across displays.
/// - Visual speed should be "points per second", not "pixels per second".
func buildTestDisplayList(
    t: Double,
    widthPx: Int,
    heightPx: Int,
    pixelsPerPoint: Double
) -> LunaDisplayList {

    let bg = LunaRGBA8(r: 18, g: 18, b: 22, a: 255)
    let accent = LunaRGBA8(r: 110, g: 200, b: 255, a: 255)

    // Rectangle sizing in pixels (simple demo).
    let rectW = max(40, widthPx / 6)
    let rectH = max(40, heightPx / 6)

    // Define motion speed in *points per second* (perceived consistent).
    let speedPointsPerSec: Double = 360.0

    // Convert to pixels/sec using effective scale.
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
// macOS host
// -----------------------------------------------------------------------------
#if os(macOS)
import AppKit
import QuartzCore // CACurrentMediaTime()

@MainActor
final class TestApp: NSObject, NSApplicationDelegate, NSWindowDelegate {

    var window: NSWindow!
    var view: LunaFramebufferView!

    let renderer = LunaCPURenderer()
    var framebuffer = LunaFramebuffer(width: 900, height: 600)

    var timer: Timer?
    private let t0: Double = CACurrentMediaTime()

    /// CPU-only HiDPI performance knob:
    /// - 1.0 = full device-pixel render (crispest, slowest on Retina)
    /// - 0.5 = half-res render (much faster), upscaled for display
    private let cpuHiDPIQuality: CGFloat = 0.5

    func applicationDidFinishLaunching(_ notification: Notification) {

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Luna-UI Test Harness (CPUFramebuffer)"
        window.center()
        window.delegate = self

        view = LunaFramebufferView(frame: window.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true

        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        timer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        view.framebuffer = nil
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    @objc private func tick() {

        guard window != nil, window.isVisible else { return }

        let t = CACurrentMediaTime() - t0

        // backing scale: points -> device pixels
        let backingScale: CGFloat = window.backingScaleFactor

        // effective render scale (may be reduced for CPU performance)
        let effectiveScale: CGFloat = backingScale * cpuHiDPIQuality

        // view size in points
        let pointW = view.bounds.width
        let pointH = view.bounds.height

        // framebuffer size in pixels
        let pixelW = max(1, Int((pointW * effectiveScale).rounded(.toNearestOrAwayFromZero)))
        let pixelH = max(1, Int((pointH * effectiveScale).rounded(.toNearestOrAwayFromZero)))

        // compositor scale should still match the real backing scale
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
// Linux host
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

    // Pixel size from renderer output (HiDPI-correct)
    let (pixelW, pixelH) = presenter.getOutputPixelSize(
        fallbackWidth: framebuffer.width,
        fallbackHeight: framebuffer.height
    )

    if pixelW != framebuffer.width || pixelH != framebuffer.height {
        framebuffer.resize(width: pixelW, height: pixelH)
        presenter.ensureTexture(width: Int32(pixelW), height: Int32(pixelH))
    }

    // We don’t currently have a robust “points” concept on Linux yet.
    // For now treat pixelsPerPoint = 1.0 (we’ll formalize DPI later).
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
