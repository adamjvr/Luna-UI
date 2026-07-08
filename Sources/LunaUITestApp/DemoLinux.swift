//
//  DemoLinux.swift
//  LunaUITestApp
//
//  Linux CPU-only demo host.
//
//  Phase 2C rebuilds the demo around the current Luna architecture:
//  - SDL initialization/window creation remains in the Linux host shell.
//  - SDL input decoding is sealed inside LunaHostSDL/LunaSDLInputTranslator.
//  - The demo scene receives only LunaHostInputEvent values.
//  - Widgets, modals, commands, theme/style, and rendering are exercised through
//    Luna's platform-neutral APIs.
//

#if os(Linux)

import Foundation
import SDL2

import LunaCore
import LunaInput
import LunaRender
import LunaTheme
import LunaHostSDL
import LunaUI

/// Top-level entry for Linux.
private func lunaDemoLogError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func runLinuxDemo() {
    guard SDL_Init(UInt32(SDL_INIT_VIDEO)) == 0 else {
        let err = String(cString: SDL_GetError())
        lunaDemoLogError("SDL_Init failed: \(err)")
        return
    }
    defer { SDL_Quit() }

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

    var fb = LunaFramebuffer(width: Int(winW), height: Int(winH))
    let presenter = LunaSDLPresenter(window: window)
    var inputTranslator = LunaSDLInputTranslator()

    // Shared demo scene (pure Luna, no platform event decoding).
    var demo = LunaCPUDemoScene(theme: .mothUserPalette)

    let targetFPS: UInt32 = 60
    let targetFrameMS: UInt32 = 1000 / targetFPS

    var running = true
    while running {
        for event in inputTranslator.pollEvents() {
            switch event {
            case .quit:
                running = false

            case .windowResized(let size):
                if size.width != fb.width || size.height != fb.height {
                    fb = LunaFramebuffer(width: size.width, height: size.height)
                    demo.handleWindowResize(size)
                }

            case .pointer(let pointerEvent):
                let result = demo.handlePointerEvent(
                    pointerEvent,
                    framebufferSize: LunaSizeI(width: fb.width, height: fb.height)
                )
                if let command = result.requestedCommand {
                    print("Luna demo requested command: \(command.rawValue)")
                }

            case .keyboard(let keyboardEvent):
                _ = demo.handleKeyboardEvent(
                    keyboardEvent,
                    framebufferSize: LunaSizeI(width: fb.width, height: fb.height)
                )
            }
        }

        demo.render(into: &fb)
        presenter.present(framebuffer: fb)
        SDL_Delay(targetFrameMS)
    }
}

#endif
