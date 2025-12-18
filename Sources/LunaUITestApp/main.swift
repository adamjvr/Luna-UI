// main.swift
// Cross-platform Luna-UI test harness

#if os(macOS)
import AppKit
import LunaUI

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

SDL_Init(SDL_INIT_VIDEO)

let window = SDL_CreateWindow(
    "Luna-UI Test Harness",
    SDL_WINDOWPOS_CENTERED,
    SDL_WINDOWPOS_CENTERED,
    900,
    600,
    SDL_WINDOW_SHOWN.rawValue
)

var event = SDL_Event()
var running = true

while running {
    while SDL_PollEvent(&event) != 0 {
        if event.type == SDL_QUIT.rawValue {
            running = false
        }
    }
    SDL_Delay(16)
}

SDL_DestroyWindow(window)
SDL_Quit()
#endif
