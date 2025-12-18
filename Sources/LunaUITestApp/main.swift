// main.swift
// Luna-UI Test Harness 
//
// This harness proves:
// - Cross-platform window hosting works (macOS AppKit, Linux SDL2)
// - A shared CPU framebuffer can be rendered and presented on both OSes
// - A backend-agnostic "display list" can drive rendering
//
// This is the first real step toward Luna-UI being a pixel-identical Sublime clone.

import LunaUI
import LunaRender
import LunaHost

// -----------------------------------------------------------------------------
// Shared test scene generator
// -----------------------------------------------------------------------------

/// Build a simple display list for v0.1:
/// - clear background
/// - draw a moving rectangle
func buildTestDisplayList(frameIndex: Int, width: Int, height: Int) -> LunaDisplayList {

    // Background: near-black with a subtle tint.
    let bg = LunaRGBA8(r: 18, g: 18, b: 22, a: 255)

    // Moving rect: bright accent color.
    let accent = LunaRGBA8(r: 110, g: 200, b: 255, a: 255)

    // Simple horizontal motion
    let rectW = max(40, width / 6)
    let rectH = max(40, height / 6)

    let travel = max(1, width - rectW - 20)
    let x = 10 + (frameIndex * 6) % travel
    let y = max(10, height / 3)

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

/// IMPORTANT (Swift 6):
/// Mark the whole AppKit host as MainActor so we can touch NSView/NSWindow safely.
/// Also use a selector-based Timer to avoid @Sendable closure warnings.
@MainActor
final class TestApp: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var view: LunaFramebufferView!

    // CPU renderer + framebuffer
    let renderer = LunaCPURenderer()
    var framebuffer = LunaFramebuffer(width: 900, height: 600)

    // Simple frame counter
    var frameIndex: Int = 0

    // A timer to drive redraws ~60fps
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Luna-UI Test Harness (CPU Framebuffer)"
        window.center()

        view = LunaFramebufferView(frame: window.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        window.contentView = view

        window.makeKeyAndOrderFront(nil)

        // Drive redraws using a selector-based timer.
        // This avoids @Sendable closures entirely.
        timer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    /// Called ~60fps by the selector-based timer.
    @objc private func tick() {

        // Resize framebuffer to match view size in pixels.
        // NOTE: For v0.1 we ignore backing scale. We'll handle DPI later.
        let w = Int(self.view.bounds.width)
        let h = Int(self.view.bounds.height)

        if w != self.framebuffer.width || h != self.framebuffer.height {
            self.framebuffer.resize(width: w, height: h)
        }

        // Build display list and render.
        let dl = buildTestDisplayList(
            frameIndex: self.frameIndex,
            width: self.framebuffer.width,
            height: self.framebuffer.height
        )

        self.renderer.render(displayList: dl, into: &self.framebuffer)

        // Hand the framebuffer to the view and invalidate.
        self.view.framebuffer = self.framebuffer
        self.view.needsDisplay = true

        self.frameIndex += 1
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

// Initialize SDL
if SDL_Init(SDL_INIT_VIDEO) != 0 {
    fatalError("SDL_Init failed: \(String(cString: SDL_GetError()))")
}

// Create window (avoid SDL position macros; Swift cannot import them reliably)
guard let window = SDL_CreateWindow(
    "Luna-UI Test Harness (CPU Framebuffer)",
    0,
    0,
    900,
    600,
    UInt32(SDL_WINDOW_SHOWN.rawValue | SDL_WINDOW_RESIZABLE.rawValue)
) else {
    fatalError("SDL_CreateWindow failed: \(String(cString: SDL_GetError()))")
}

// Presenter uploads framebuffer to an SDL texture and presents.
let presenter = LunaSDLPresenter(window: window)

// CPU renderer + framebuffer
let renderer = LunaCPURenderer()
var framebuffer = LunaFramebuffer(width: 900, height: 600)

var event = SDL_Event()
var running = true
var frameIndex = 0

while running {

    while SDL_PollEvent(&event) != 0 {

        if event.type == SDL_QUIT.rawValue {
            running = false
        }

        // Handle resize events so framebuffer matches window size.
        if event.type == SDL_WINDOWEVENT.rawValue {
            if event.window.event == UInt8(SDL_WINDOWEVENT_SIZE_CHANGED.rawValue) {
                let newW = Int(event.window.data1)
                let newH = Int(event.window.data2)
                framebuffer.resize(width: newW, height: newH)

                // Recreate texture to match new size.
                presenter.ensureTexture(width: Int32(newW), height: Int32(newH))
            }
        }
    }

    // Build display list and render into framebuffer
    let dl = buildTestDisplayList(frameIndex: frameIndex, width: framebuffer.width, height: framebuffer.height)
    renderer.render(displayList: dl, into: &framebuffer)

    // Present framebuffer to the screen
    presenter.present(framebuffer: framebuffer)

    frameIndex += 1

    // ~60fps
    SDL_Delay(16)
}

// Shutdown
SDL_DestroyWindow(window)
SDL_Quit()
#endif
