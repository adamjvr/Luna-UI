//
//  DemoMac.swift
//  LunaUITestApp
//
//  macOS CPU-only demo host.
//
//  This is intentionally a minimal AppKit shell:
//  - Creates an NSApplication + NSWindow
//  - Uses a `Timer` on the main thread to tick at ~60 Hz
//  - Each tick draws into a `LunaFramebuffer` via `LunaUIDemoShared`
//  - Then presents the pixels in a custom `NSView` (`MacCPUPresenterView`)
//
//  NO Metal. NO CAMetalLayer. NO CoreAnimation requirement.
//

#if os(macOS)

import AppKit
import LunaRender

/// Main entry for the macOS demo.
///
/// **Actor notes:**
/// AppKit is @MainActor. Keep everything on the main actor to avoid
/// Swift concurrency warnings and to match AppKit expectations.
@MainActor
func runMacDemo() {
    let app = NSApplication.shared

    let delegate = DemoMacAppDelegate()
    app.delegate = delegate

    // Make sure we are a regular GUI app with a Dock icon / menu bar.
    _ = app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)

    app.run()
}

@MainActor
final class DemoMacAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // MARK: - Window / view

    private var window: NSWindow?
    private var presenterView: MacCPUPresenterView?

    // MARK: - Demo state

    private var fb = LunaFramebuffer(width: 900, height: 600)
    /// Shared CPU demo logic (pure Swift, no AppKit dependencies).
    private var demo = LunaCPUDemoScene()
    private var frameIndex: UInt64 = 0

    // Timer that drives the demo at ~60 Hz.
    private var timer: Timer?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the presenter view.
        let view = MacCPUPresenterView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        self.presenterView = view

        // Create window.
        let win = NSWindow(
            contentRect: view.bounds,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Luna-UI CPU Demo"
        win.contentView = view
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        // Bring the app to the front (Terminal-launched apps can otherwise stay behind).
        NSApp.activate(ignoringOtherApps: true)
        win.orderFrontRegardless()
        self.window = win

        // Start the frame timer.
        // NOTE: Use the block-based timer API to avoid Obj-C selector issues.
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            // `Timer` callbacks are not actor-isolated. Hop onto the MainActor explicitly.
            Task { @MainActor in
                guard let self else { return }
                self.tickFrame()
            }
        }
        // Ensure the timer runs during window interactions.
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        // In case the hosting environment does not honor
        // `applicationShouldTerminateAfterLastWindowClosed` (or if more windows are
        // added later), explicitly terminate when this demo window closes.
        NSApp.terminate(nil)
    }

    // MARK: - Frame loop

    private func tickFrame() {
        frameIndex &+= 1

        guard let presenterView else { return }

        // Resize framebuffer to match view size.
        // This is a demo: we use view bounds in points (no backing scale).
        let size = presenterView.bounds.size
        let newW = max(1, Int(size.width.rounded(.toNearestOrAwayFromZero)))
        let newH = max(1, Int(size.height.rounded(.toNearestOrAwayFromZero)))
        if newW != fb.width || newH != fb.height {
            fb = LunaFramebuffer(width: newW, height: newH)
        }

        // Draw shared demo content into the framebuffer.
        // The demo scene owns its own frame counter + timing; we simply ask it to
        // render into the current framebuffer.
        demo.render(into: &fb)

        // Present.
        presenterView.present(framebuffer: fb)
    }
}

#endif
