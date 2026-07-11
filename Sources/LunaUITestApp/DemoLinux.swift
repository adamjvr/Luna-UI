// SPDX-License-Identifier: MPL-2.0
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
import LunaHostCore
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

    SDL_StartTextInput()
    defer { SDL_StopTextInput() }

    var fb = LunaFramebuffer(width: Int(winW), height: Int(winH))
    let presenter = LunaSDLPresenter(window: window)
    var inputTranslator = LunaSDLInputTranslator()
    let inputCoalescer = LunaHostInputCoalescer()

    let environment = ProcessInfo.processInfo.environment
    let arguments = Array(CommandLine.arguments.dropFirst())
    let launchOptions = LunaDemoLaunchOptions.parse(arguments: arguments, environment: environment)
    let demoMode = launchOptions.mode
    let logsCommandRequests = launchOptions.logsCommandRequests

    // Shared demo scene (pure Luna, no platform event decoding). Phase 5D/5D.1/5D.2
    // can seed the app-owned workspace adapter with real UTF-8 local files,
    // checked-in demo corpus fixtures, created empty files, and untitled buffers
    // without moving filesystem policy into LunaUI.
    var demo = LunaCPUDemoScene(
        theme: MothDemoTheme.theme,
        mode: demoMode,
        openLocalFilePaths: launchOptions.openFilePaths,
        createLocalFilePaths: launchOptions.createFilePaths,
        newUntitledDocumentCount: launchOptions.newUntitledDocumentCount,
        dialogService: launchOptions.dialogService,
        overwritesDemoSaveAsTarget: launchOptions.overwritesSaveAsTarget,
        overwritesCreatedLocalFiles: launchOptions.overwritesCreatedFiles
    )

    var framePacer = LunaFramePacer(targetFramesPerSecond: 60, usesExternalVSync: presenter.usesVSync)
    var frameStats = LunaFrameTimingStats()
    var latestInputStats = LunaInputCoalescingStats()
    var pendingInvalidations = LunaFrameInvalidationSet(.initial)
    var frameIndex: UInt64 = 0

    var running = true
    while running {
        let inputStart = LunaMonotonicClock.nowNanoseconds()
        var didReceiveEvent = false

        let rawInputEvents = inputTranslator.pollEvents()
        let inputBatch = inputCoalescer.coalesce(rawInputEvents)
        latestInputStats = inputBatch.stats

        for event in inputBatch.events {
            didReceiveEvent = true
            switch event {
            case .quit:
                running = false

            case .windowResized(let size):
                if size.width != fb.width || size.height != fb.height {
                    fb = LunaFramebuffer(width: size.width, height: size.height)
                    demo.handleWindowResize(size)
                    pendingInvalidations.insert(.windowResized)
                }

            case .pointer(let pointerEvent):
                let result = demo.handlePointerEvent(
                    pointerEvent,
                    framebufferSize: LunaSizeI(width: fb.width, height: fb.height)
                )

                // Do not redraw just because the pointer geometrically hit stable
                // chrome. Redraw only when routing changed visible state, activated
                // a command, or processed a non-motion phase such as click/release.
                let pointerNeedsFrame = pointerEvent.phase != .moved || result.didChangeVisualState || result.didRequestCommand
                if pointerNeedsFrame {
                    pendingInvalidations.insert(.input)
                }

                if let command = result.requestedCommand {
                    pendingInvalidations.insert(.commandExecuted)
                    if logsCommandRequests {
                        print("Luna demo requested command: \(command.rawValue)")
                    }
                }

            case .keyboard(let keyboardEvent):
                _ = demo.handleKeyboardEvent(
                    keyboardEvent,
                    framebufferSize: LunaSizeI(width: fb.width, height: fb.height)
                )
                pendingInvalidations.insert(.input)

            case .textInput(let textInputEvent):
                _ = demo.handleTextInput(
                    textInputEvent,
                    framebufferSize: LunaSizeI(width: fb.width, height: fb.height)
                )
                pendingInvalidations.insert(.textInput)
                pendingInvalidations.insert(.documentChanged)
            }
        }

        let inputEnd = LunaMonotonicClock.nowNanoseconds()
        let inputNanoseconds = inputEnd >= inputStart ? inputEnd - inputStart : 0

        if !running {
            break
        }

        let frameRequest = LunaFrameRequest(
            invalidations: pendingInvalidations,
            wantsContinuousFrames: demo.wantsContinuousRendering
        )

        guard frameRequest.shouldRender else {
            SDL_Delay(didReceiveEvent ? 1 : framePacer.sleepMillisecondsWhenIdle())
            continue
        }

        let invalidationsForFrame = pendingInvalidations
        pendingInvalidations.removeAll()

        frameIndex &+= 1
        let frameStart = LunaMonotonicClock.nowNanoseconds()
        demo.updateFrameRuntimeDiagnostics(
            timingStats: frameStats,
            invalidations: invalidationsForFrame,
            inputCoalescingStats: latestInputStats
        )

        let renderStart = LunaMonotonicClock.nowNanoseconds()
        demo.render(into: &fb)
        let renderEnd = LunaMonotonicClock.nowNanoseconds()

        let presentStart = LunaMonotonicClock.nowNanoseconds()
        presenter.present(framebuffer: fb)
        let presentEnd = LunaMonotonicClock.nowNanoseconds()

        let totalNanoseconds = presentEnd >= frameStart ? presentEnd - frameStart : 0
        let renderNanoseconds = renderEnd >= renderStart ? renderEnd - renderStart : 0
        let presentNanoseconds = presentEnd >= presentStart ? presentEnd - presentStart : 0

        frameStats.record(
            LunaFrameTimingSample(
                frameIndex: frameIndex,
                startedAtNanoseconds: frameStart,
                inputNanoseconds: inputNanoseconds,
                renderNanoseconds: renderNanoseconds,
                presentNanoseconds: presentNanoseconds,
                totalNanoseconds: totalNanoseconds,
                invalidations: invalidationsForFrame
            )
        )

        framePacer.markFrameEnded(atNanoseconds: presentEnd)
        let sleepMilliseconds = framePacer.sleepMillisecondsBeforeNextFrame()
        if sleepMilliseconds > 0 {
            SDL_Delay(sleepMilliseconds)
        }
    }
}


#endif
