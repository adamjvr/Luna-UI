// main.swift
//
// Luna-UI Test Harness
// - Shows a window with the moving square (CPU presenter for now)
// - One-time LunaText shaping smoke test at startup (ligatures + complex scripts)
//
// Press Ctrl+C in terminal to quit on Linux; close window on macOS.

import Foundation
import LunaUI
import LunaRender
import LunaHost
import LunaText

// MARK: - LunaText smoke test

func runLunaTextSmokeTest() {
    print("------------------------------------------------------------")
    print("[LunaText] Smoke test: shaping (ligatures + complex scripts)")
    print("------------------------------------------------------------")

    // Pick a font path per platform.
    // These are common defaults; adjust later to your bundled fonts strategy.
    #if os(Linux)
    let fontPathCandidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
    ]
    #else
    let fontPathCandidates = [
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/SFNS.ttf",
    ]
    #endif

    let fontPath = fontPathCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? fontPathCandidates[0]

    do {
        let shaper = try LunaTextShaper(font: LunaFontDescriptor(filePath: fontPath, pointSize: 16))

        struct Case {
            let label: String
            let text: String
            let dir: LunaTextDirection
            let lang: String?
            let script: String?
        }

        let cases: [Case] = [
            Case(label: "Ligatures (Latin)", text: "office -> fi fl ffi", dir: .ltr, lang: "en", script: "Latn"),
            Case(label: "Arabic (RTL)", text: "مرحبا بالعالم", dir: .rtl, lang: "ar", script: "Arab"),
            Case(label: "Devanagari", text: "हिन्दी भाषा", dir: .ltr, lang: "hi", script: "Deva"),
        ]

        for c in cases {
            let run = shaper.shape(c.text, direction: c.dir, language: c.lang, script: c.script)
            print("")
            print("[LunaText] \(c.label)")
            print("  font: \(fontPath)")
            print("  text: \(c.text)")
            print("  glyphCount: \(run.glyphs.count)")

            // Print first N glyphs so we see it’s non-trivial and clustered.
            let N = min(12, run.glyphs.count)
            for i in 0..<N {
                let g = run.glyphs[i]
                print("   [\(i)] gid=\(g.glyphID) cluster=\(g.cluster) adv=(\(g.xAdvance),\(g.yAdvance)) off=(\(g.xOffset),\(g.yOffset))")
            }
            if run.glyphs.count > N {
                print("   ... (\(run.glyphs.count - N) more)")
            }
        }

        print("")
        print("------------------------------------------------------------")
        print("[LunaText] Smoke test complete.")
        print("------------------------------------------------------------")

    } catch {
        print("[LunaText] Smoke test FAILED: \(error)")
    }
}

// MARK: - Shared test display list

func buildTestDisplayList(t: Double, widthPx: Int, heightPx: Int, pixelsPerPoint: Double) -> LunaDisplayList {
    let bg = LunaRGBA8(r: 18, g: 18, b: 22, a: 255)
    let accent = LunaRGBA8(r: 110, g: 200, b: 255, a: 255)

    let rectW = max(40, widthPx / 6)
    let rectH = max(40, heightPx / 6)

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

// Run the shaping test once at startup.
runLunaTextSmokeTest()

// MARK: - Platform hosts

#if os(macOS)
import AppKit
import QuartzCore

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
        let backingScale = window.backingScaleFactor
        let bounds = root.bounds

        let pixelW = max(1, Int((bounds.width * backingScale).rounded()))
        let pixelH = max(1, Int((bounds.height * backingScale).rounded()))

        if pixelW != cpuFramebuffer.width || pixelH != cpuFramebuffer.height {
            cpuFramebuffer.resize(width: pixelW, height: pixelH)
        }

        let dl = buildTestDisplayList(t: t, widthPx: cpuFramebuffer.width, heightPx: cpuFramebuffer.height, pixelsPerPoint: Double(backingScale))
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
