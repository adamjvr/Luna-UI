//
//  DemoLinux.swift
//  LunaUITestApp
//
//  Linux CPU-only demo host.
//
//  Uses SDL2 (via the SwiftPM system library target `CSDL2`) and the helper
//  presenter in `LunaHostSDL`.
//
//  The loop:
//  - Create window and `LunaSDLPresenter`
//  - Handle SDL events (quit, resize)
//  - Render a frame into a `LunaFramebuffer` using `LunaUIDemoShared`
//  - Present pixels using `LunaSDLPresenter.present(framebuffer:)`
//

#if os(Linux)

import CSDL2

import LunaRender
import LunaHostSDL

/// Top-level entry for Linux.
func runLinuxDemo() {
    // SDL init.
    guard SDL_Init(UInt32(SDL_INIT_VIDEO)) == 0 else {
        let err = String(cString: SDL_GetError())
        fputs("SDL_Init failed: \(err)\n", stderr)
        return
    }
    defer { SDL_Quit() }

    // Initial window size.
    var winW: Int32 = 960
    var winH: Int32 = 640

    guard let window = SDL_CreateWindow(
        "Luna-UI CPU Demo",
        Int32(SDL_WINDOWPOS_CENTERED_MASK),
        Int32(SDL_WINDOWPOS_CENTERED_MASK),
        winW,
        winH,
        UInt32(SDL_WINDOW_RESIZABLE)
    ) else {
        let err = String(cString: SDL_GetError())
        fputs("SDL_CreateWindow failed: \(err)\n", stderr)
        return
    }
    defer { SDL_DestroyWindow(window) }

    // CPU framebuffer.
    var fb = LunaFramebuffer(width: Int(winW), height: Int(winH))

    // Presenter (owns renderer + texture).
    func makePresenter(width: Int, height: Int) -> LunaSDLPresenter? {
        do {
            return try LunaSDLPresenter(window: window, width: width, height: height)
        } catch {
            fputs("LunaSDLPresenter init failed: \(error)\n", stderr)
            return nil
        }
    }

    guard var presenter = makePresenter(width: fb.width, height: fb.height) else { return }

    // Shared demo renderer (pure Swift, shared with macOS).
    var demo = LunaCPUDemoScene()

    // Frame counter + clock.
    var frameIndex: UInt64 = 0
    let startTicks = SDL_GetTicks()

    // Timing.
    let targetFPS: UInt32 = 60
    let targetFrameMS: UInt32 = 1000 / targetFPS

    var running = true
    while running {
        // -------- Events --------
        var event = SDL_Event()
        while SDL_PollEvent(&event) != 0 {
            switch SDL_EventType(rawValue: event.type) {
            case SDL_QUIT:
                running = false

            case SDL_WINDOWEVENT:
                // Handle resize.
                if event.window.event == UInt8(SDL_WINDOWEVENT_SIZE_CHANGED) {
                    let newW = max(1, Int(event.window.data1))
                    let newH = max(1, Int(event.window.data2))
                    if newW != fb.width || newH != fb.height {
                        fb = LunaFramebuffer(width: newW, height: newH)
                        // Recreate presenter so texture matches the new size.
                        if let newPresenter = makePresenter(width: newW, height: newH) {
                            presenter = newPresenter
                        }
                    }
                }

            default:
                break
            }
        }

        // -------- Render --------
        frameIndex &+= 1
        let nowTicks = SDL_GetTicks()
        let tSeconds = Double(nowTicks &- startTicks) / 1000.0
        demo.render(into: &fb, frameIndex: frameIndex, timeSeconds: tSeconds)
        presenter.present(framebuffer: fb)

        // -------- Throttle --------
        // This is a simple demo; we throttle with SDL_Delay.
        SDL_Delay(targetFrameMS)
    }
}

#endif
