//
//  DemoLinux.swift
//  LunaUITestApp
//
//  Linux CPU-only demo host.
//
//  Uses SDL2 (via the SwiftPM system library target `SDL2`) and the helper
//  presenter in `LunaHostSDL`.
//
//  The loop:
//  - Create window and `LunaSDLPresenter`
//  - Handle SDL events (quit, resize)
//  - Render a frame into a `LunaFramebuffer` using `LunaUIDemoShared`
//  - Present pixels using `LunaSDLPresenter.present(framebuffer:)`
//

#if os(Linux)

import Foundation
import SDL2

import LunaCore
import LunaRender
import LunaHostSDL

/// Top-level entry for Linux.
private func lunaDemoLogError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func runLinuxDemo() {
    // SDL init.
    guard SDL_Init(UInt32(SDL_INIT_VIDEO)) == 0 else {
        let err = String(cString: SDL_GetError())
        lunaDemoLogError("SDL_Init failed: \(err)")
        return
    }
    defer { SDL_Quit() }

    // Initial window size.
    let winW: Int32 = 960
    let winH: Int32 = 640

    guard let window = SDL_CreateWindow(
        "Luna-UI CPU Demo",
        Int32(SDL_WINDOWPOS_CENTERED_MASK),
        Int32(SDL_WINDOWPOS_CENTERED_MASK),
        winW,
        winH,
        SDL_WINDOW_RESIZABLE.rawValue
    ) else {
        let err = String(cString: SDL_GetError())
        lunaDemoLogError("SDL_CreateWindow failed: \(err)")
        return
    }
    defer { SDL_DestroyWindow(window) }

    // CPU framebuffer.
    var fb = LunaFramebuffer(width: Int(winW), height: Int(winH))

    // Presenter owns the SDL renderer + streaming texture. The texture is
    // resized lazily by `present(framebuffer:)`, so the presenter itself does
    // not need to be recreated when the window size changes.
    let presenter = LunaSDLPresenter(window: window)

    // Shared demo renderer (pure Swift, shared with macOS).
    var demo = LunaCPUDemoScene()

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
                if event.window.event == UInt8(SDL_WINDOWEVENT_SIZE_CHANGED.rawValue) {
                    let newW = max(1, Int(event.window.data1))
                    let newH = max(1, Int(event.window.data2))
                    if newW != fb.width || newH != fb.height {
                        fb = LunaFramebuffer(width: newW, height: newH)
                        // The presenter recreates its streaming texture on the next present.
                    }
                }

            case SDL_MOUSEBUTTONDOWN:
                // Phase 1B: translate SDL mouse input into Luna's platform-neutral
                // pointer activation path. SDL button 1 is the primary/left button.
                if event.button.button == 1 {
                    let result = demo.handlePointerDown(
                        at: LunaPointI(x: Int(event.button.x), y: Int(event.button.y)),
                        framebufferSize: LunaSizeI(width: fb.width, height: fb.height)
                    )

                    if let command = result.requestedCommand {
                        print("Luna demo requested command: \(command.rawValue)")
                    }
                }

            default:
                break
            }
        }

        // -------- Render --------
        demo.render(into: &fb)
        presenter.present(framebuffer: fb)

        // -------- Throttle --------
        // This is a simple demo; we throttle with SDL_Delay.
        SDL_Delay(targetFrameMS)
    }
}

#endif
