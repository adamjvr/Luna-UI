// main.swift
// Cross-platform Luna-UI test harness
//
// This file exists ONLY to validate that Luna-UI can be
// hosted on macOS and Linux. It intentionally does not
// render anything yet.

#if os(macOS)

import AppKit
import LunaUI

/// Minimal AppKit-based host for Luna-UI.
/// Opens a window and runs an event loop.
final class TestApp: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Luna-UI Test Harness"
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = TestApp()
app.delegate = delegate
app.run()

#endif


#if os(Linux)

import LunaUI
import SDL2

// Initialize SDL video subsystem
if SDL_Init(SDL_INIT_VIDEO) != 0 {
    fatalError("SDL_Init failed: \(String(cString: SDL_GetError()))")
}

// NOTE:
// We intentionally pass (0, 0) for the window position.
// SDL window position macros (CENTERED / UNDEFINED) are
// preprocessor macros and are NOT importable into Swift.
guard let window = SDL_CreateWindow(
    "Luna-UI Test Harness",
    0,   // x position
    0,   // y position
    900,
    600,
    UInt32(SDL_WINDOW_SHOWN.rawValue)
) else {
    fatalError("SDL_CreateWindow failed: \(String(cString: SDL_GetError()))")
}

var event = SDL_Event()
var running = true

// Basic event loop
while running {
    while SDL_PollEvent(&event) != 0 {
        if event.type == SDL_QUIT.rawValue {
            running = false
        }
    }

    // Cap loop ~60 FPS
    SDL_Delay(16)
}

// Clean shutdown
SDL_DestroyWindow(window)
SDL_Quit()

#endif
