// SPDX-License-Identifier: MPL-2.0
//
// LunaSDLApplication.swift
//
// Reusable Linux SDL application runner for Luna consumers.
//
// The platform host owns SDL initialization, window lifetime, event polling,
// framebuffer presentation, frame pacing, and shutdown. Application code owns
// only a platform-neutral scene that consumes normalized Luna host events and
// renders into a Luna framebuffer.

#if os(Linux)

import Foundation
import SDL2

import LunaCore
import LunaHostCore
import LunaInput
import LunaRender

public struct LunaSDLApplicationConfiguration: Hashable, Sendable {
    public var title: String
    public var initialWidth: Int
    public var initialHeight: Int
    public var targetFramesPerSecond: Double
    public var usesVSync: Bool

    public init(
        title: String,
        initialWidth: Int = 960,
        initialHeight: Int = 640,
        targetFramesPerSecond: Double = 60,
        usesVSync: Bool = true
    ) {
        self.title = title
        self.initialWidth = max(1, initialWidth)
        self.initialHeight = max(1, initialHeight)
        self.targetFramesPerSecond = max(1, targetFramesPerSecond)
        self.usesVSync = usesVSync
    }
}

public protocol LunaSDLApplicationScene {
    var wantsContinuousRendering: Bool { get }

    mutating func handleHostEvent(
        _ event: LunaHostInputEvent,
        framebufferSize: LunaSizeI
    ) -> LunaFrameInvalidationSet

    mutating func updateFrameRuntimeDiagnostics(
        timingStats: LunaFrameTimingStats,
        invalidations: LunaFrameInvalidationSet,
        inputCoalescingStats: LunaInputCoalescingStats
    )

    mutating func render(into framebuffer: inout LunaFramebuffer)
}

public extension LunaSDLApplicationScene {
    var wantsContinuousRendering: Bool { false }

    mutating func updateFrameRuntimeDiagnostics(
        timingStats: LunaFrameTimingStats,
        invalidations: LunaFrameInvalidationSet,
        inputCoalescingStats: LunaInputCoalescingStats
    ) {}
}

@inline(__always)
private func lunaSDLLogError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Runs a complete Luna application using the Linux SDL host.
///
/// The function does not return until the user closes the window or SDL emits a
/// quit event. A zero result indicates normal shutdown. Non-zero values indicate
/// host initialization failure.
@discardableResult
public func runLunaSDLApplication<Scene: LunaSDLApplicationScene>(
    configuration: LunaSDLApplicationConfiguration,
    scene: inout Scene
) -> Int32 {
    guard SDL_Init(UInt32(SDL_INIT_VIDEO)) == 0 else {
        lunaSDLLogError("SDL_Init failed: \(String(cString: SDL_GetError()))")
        return 1
    }
    defer { SDL_Quit() }

    guard let window = SDL_CreateWindow(
        configuration.title,
        Int32(SDL_WINDOWPOS_CENTERED_MASK),
        Int32(SDL_WINDOWPOS_CENTERED_MASK),
        Int32(configuration.initialWidth),
        Int32(configuration.initialHeight),
        SDL_WINDOW_RESIZABLE.rawValue
    ) else {
        lunaSDLLogError("SDL_CreateWindow failed: \(String(cString: SDL_GetError()))")
        return 2
    }
    defer { SDL_DestroyWindow(window) }

    SDL_StartTextInput()
    defer { SDL_StopTextInput() }

    var framebuffer = LunaFramebuffer(
        width: configuration.initialWidth,
        height: configuration.initialHeight
    )
    let presenter = LunaSDLPresenter(window: window, useVSync: configuration.usesVSync)
    var inputTranslator = LunaSDLInputTranslator()
    let inputCoalescer = LunaHostInputCoalescer()

    var framePacer = LunaFramePacer(
        targetFramesPerSecond: configuration.targetFramesPerSecond,
        usesExternalVSync: presenter.usesVSync
    )
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

            if case .quit = event {
                running = false
                continue
            }

            if case .windowResized(let size) = event,
               size.width != framebuffer.width || size.height != framebuffer.height {
                framebuffer = LunaFramebuffer(width: size.width, height: size.height)
            }

            let size = LunaSizeI(width: framebuffer.width, height: framebuffer.height)
            pendingInvalidations.formUnion(
                scene.handleHostEvent(event, framebufferSize: size)
            )
        }

        let inputEnd = LunaMonotonicClock.nowNanoseconds()
        let inputNanoseconds = inputEnd >= inputStart ? inputEnd - inputStart : 0

        if !running { break }

        let frameRequest = LunaFrameRequest(
            invalidations: pendingInvalidations,
            wantsContinuousFrames: scene.wantsContinuousRendering
        )

        guard frameRequest.shouldRender else {
            SDL_Delay(didReceiveEvent ? 1 : framePacer.sleepMillisecondsWhenIdle())
            continue
        }

        var invalidationsForFrame = pendingInvalidations
        if scene.wantsContinuousRendering {
            invalidationsForFrame.insert(.animation)
        }
        pendingInvalidations.removeAll()

        frameIndex &+= 1
        let frameStart = LunaMonotonicClock.nowNanoseconds()
        scene.updateFrameRuntimeDiagnostics(
            timingStats: frameStats,
            invalidations: invalidationsForFrame,
            inputCoalescingStats: latestInputStats
        )

        let renderStart = LunaMonotonicClock.nowNanoseconds()
        scene.render(into: &framebuffer)
        let renderEnd = LunaMonotonicClock.nowNanoseconds()

        let presentStart = LunaMonotonicClock.nowNanoseconds()
        presenter.present(framebuffer: framebuffer)
        let presentEnd = LunaMonotonicClock.nowNanoseconds()

        frameStats.record(
            LunaFrameTimingSample(
                frameIndex: frameIndex,
                startedAtNanoseconds: frameStart,
                inputNanoseconds: inputNanoseconds,
                renderNanoseconds: renderEnd >= renderStart ? renderEnd - renderStart : 0,
                presentNanoseconds: presentEnd >= presentStart ? presentEnd - presentStart : 0,
                totalNanoseconds: presentEnd >= frameStart ? presentEnd - frameStart : 0,
                invalidations: invalidationsForFrame
            )
        )

        framePacer.markFrameEnded(atNanoseconds: presentEnd)
        let sleepMilliseconds = framePacer.sleepMillisecondsBeforeNextFrame()
        if sleepMilliseconds > 0 {
            SDL_Delay(sleepMilliseconds)
        }
    }

    return 0
}

#endif
