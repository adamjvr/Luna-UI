// main.swift
// Luna-UI Test Harness
//
// macOS:
// - CPU backend: LunaCPURenderer -> LunaFramebufferView
// - GPU backend: LunaMetalView (Metal) consumes LunaDisplayList directly
// - Press 'G' to toggle CPU <-> GPU
//
// IMPORTANT FIX:
// - When launched from `swift run`, Terminal often remains the active app.
// - If the process is not a "regular" app (activation policy), it may never become key.
// - We explicitly set: NSApp.setActivationPolicy(.regular)
// - We also force: activate + makeKey + makeFirstResponder
//
// Linux remains CPU/SDL for now.

import LunaUI
import LunaRender
import LunaHost

// -----------------------------------------------------------------------------
// Shared test scene generator (TIME-BASED, POINTS-BASED SPEED)
// -----------------------------------------------------------------------------

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

    // Perceived speed (points/sec)
    let speedPointsPerSec: Double = 360.0
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

// MARK: - Key capturing view (real responder-chain keyDown)

@MainActor
final class KeyCatcherView: NSView {

    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Ask to receive keys whenever we attach to a window.
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}

// MARK: - App Delegate

@MainActor
final class TestApp: NSObject, NSApplicationDelegate, NSWindowDelegate {

    enum BackendMode {
        case cpu
        case gpu

        var labelText: String { self == .cpu ? "CPU" : "GPU" }
    }

    var window: NSWindow!
    var rootContainer: KeyCatcherView!

    // CPU presentation
    var cpuView: LunaFramebufferView!
    let cpuRenderer = LunaCPURenderer()
    var cpuFramebuffer = LunaFramebuffer(width: 900, height: 600)

    // GPU presentation
    var gpuView: LunaMetalView!

    // Overlay label
    var overlayLabel: NSTextField!

    // Frame clock
    private let displayLink = LunaDisplayLink()
    private let t0: Double = CACurrentMediaTime()

    // Current backend
    private var mode: BackendMode = .cpu

    // CPU-only HiDPI performance knob
    private let cpuHiDPIQuality: CGFloat = 0.5

    func applicationDidFinishLaunching(_ notification: Notification) {

        // 1) CRITICAL: make this a foreground "regular" app so it can take focus.
        // Without this, `swift run` launched apps often never become key/active.
        NSApp.setActivationPolicy(.regular)

        // 2) Create window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.delegate = self

        // 3) Root container that captures keys
        rootContainer = KeyCatcherView(frame: window.contentView!.bounds)
        rootContainer.autoresizingMask = [.width, .height]
        window.contentView = rootContainer

        rootContainer.onKeyDown = { [weak self] ev in
            guard let self else { return }
            self.handleKeyDown(ev)
        }

        // 4) Create both render views
        cpuView = LunaFramebufferView(frame: rootContainer.bounds)
        cpuView.autoresizingMask = [.width, .height]
        cpuView.wantsLayer = true

        gpuView = LunaMetalView(frame: rootContainer.bounds, device: nil)
        gpuView.autoresizingMask = [.width, .height]
        gpuView.drawsOnPresent = true

        // Start in CPU mode
        rootContainer.addSubview(cpuView)

        // Overlay label
        overlayLabel = NSTextField(labelWithString: "")
        overlayLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        overlayLabel.textColor = .white
        overlayLabel.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        overlayLabel.isBezeled = false
        overlayLabel.isEditable = false
        overlayLabel.isSelectable = false
        overlayLabel.translatesAutoresizingMaskIntoConstraints = false

        rootContainer.addSubview(overlayLabel)

        NSLayoutConstraint.activate([
            overlayLabel.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor, constant: 10),
            overlayLabel.topAnchor.constraint(equalTo: rootContainer.topAnchor, constant: 10),
        ])

        // 5) Show window and FORCE focus
        window.makeKeyAndOrderFront(nil)

        // Activate (steal focus from Terminal)
        NSApp.activate(ignoringOtherApps: true)

        // Make the window key and route keys to our rootContainer
        window.makeKey()
        window.makeFirstResponder(rootContainer)

        // 6) Update UI
        applyBackendUI()

        // 7) Start vsync clock
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

    // MARK: - Key handling

    private func handleKeyDown(_ ev: NSEvent) {

        // DEBUG: prove keys are hitting the app
        if let chars = ev.charactersIgnoringModifiers {
            print("[LunaUITestApp] keyDown: '\(chars)'  isActive=\(NSApp.isActive)  keyWindow=\(window.isKeyWindow)")
            fflush(stdout)
        }

        // If for some reason we lost focus, try to reclaim it.
        if !NSApp.isActive || !window.isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            window.makeFirstResponder(rootContainer)
        }

        if ev.charactersIgnoringModifiers?.lowercased() == "g" {
            toggleBackend()
        }
    }

    private func toggleBackend() {
        mode = (mode == .cpu) ? .gpu : .cpu

        switch mode {
        case .cpu:
            gpuView.removeFromSuperview()
            if cpuView.superview == nil {
                rootContainer.addSubview(cpuView, positioned: .below, relativeTo: overlayLabel)
            }

        case .gpu:
            cpuView.removeFromSuperview()
            if gpuView.superview == nil {
                rootContainer.addSubview(gpuView, positioned: .below, relativeTo: overlayLabel)
            }
        }

        applyBackendUI()

        // Keep keys routed correctly after the swap.
        window.makeFirstResponder(rootContainer)
    }

    private func applyBackendUI() {
        switch mode {
        case .cpu:
            window.title = "Luna-UI Test Harness — CPUFramebuffer (press G for GPU)"
        case .gpu:
            window.title = "Luna-UI Test Harness — Metal GPU (press G for CPU)"
        }

        overlayLabel.stringValue = "Backend: \(mode.labelText)   (press G to toggle)"

        print("[LunaUITestApp] Backend: \(mode.labelText)")
        fflush(stdout)
    }

    // MARK: - Frame tick

    private func tick() {

        guard window.isVisible else { return }

        let t = CACurrentMediaTime() - t0
        let backingScale: CGFloat = window.backingScaleFactor

        let bounds = rootContainer.bounds
        let pointW = bounds.width
        let pointH = bounds.height

        switch mode {

        case .cpu:
            let effectiveScale: CGFloat = backingScale * cpuHiDPIQuality

            let pixelW = max(1, Int((pointW * effectiveScale).rounded(.toNearestOrAwayFromZero)))
            let pixelH = max(1, Int((pointH * effectiveScale).rounded(.toNearestOrAwayFromZero)))

            cpuView.layer?.contentsScale = backingScale

            if pixelW != cpuFramebuffer.width || pixelH != cpuFramebuffer.height {
                cpuFramebuffer.resize(width: pixelW, height: pixelH)
            }

            let dl = buildTestDisplayList(
                t: t,
                widthPx: cpuFramebuffer.width,
                heightPx: cpuFramebuffer.height,
                pixelsPerPoint: Double(effectiveScale)
            )

            cpuRenderer.render(displayList: dl, into: &cpuFramebuffer)
            cpuView.framebuffer = cpuFramebuffer
            cpuView.needsDisplay = true

        case .gpu:
            let effectiveScale: CGFloat = backingScale

            let pixelW = max(1, Int((pointW * effectiveScale).rounded(.toNearestOrAwayFromZero)))
            let pixelH = max(1, Int((pointH * effectiveScale).rounded(.toNearestOrAwayFromZero)))

            gpuView.layer?.contentsScale = backingScale

            let dl = buildTestDisplayList(
                t: t,
                widthPx: pixelW,
                heightPx: pixelH,
                pixelsPerPoint: Double(effectiveScale)
            )

            gpuView.present(displayList: dl, drawablePixelWidth: pixelW, drawablePixelHeight: pixelH)
        }
    }
}

let app = NSApplication.shared
let delegate = TestApp()
app.delegate = delegate
app.run()
#endif

// -----------------------------------------------------------------------------
// Linux host (CPU + SDL for now)
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

    let (pixelW, pixelH) = presenter.getOutputPixelSize(
        fallbackWidth: framebuffer.width,
        fallbackHeight: framebuffer.height
    )

    if pixelW != framebuffer.width || pixelH != framebuffer.height {
        framebuffer.resize(width: pixelW, height: pixelH)
        presenter.ensureTexture(width: Int32(pixelW), height: Int32(pixelH))
    }

    let dl = buildTestDisplayList(t: t, widthPx: framebuffer.width, heightPx: framebuffer.height, pixelsPerPoint: 1.0)

    renderer.render(displayList: dl, into: &framebuffer)
    presenter.present(framebuffer: framebuffer)

    SDL_Delay(1)
}

SDL_DestroyWindow(window)
SDL_Quit()
#endif
