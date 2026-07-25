// SPDX-License-Identifier: MPL-2.0
//
// LunaSDLApplication.swift
//
// Reusable Linux SDL application runner for Luna consumers.
//
// The platform host owns SDL initialization, window lifetime, event polling,
// framebuffer presentation, native cursor/capture state, frame pacing, and
// shutdown. Application code owns only a platform-neutral scene.

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
    public var inputPollingBudget: LunaInputPollingBudget
    public var inputPresentationPolicy: LunaInteractivePresentationPolicy

    public init(
        title: String,
        initialWidth: Int = 960,
        initialHeight: Int = 640,
        targetFramesPerSecond: Double = 60,
        usesVSync: Bool = true,
        inputPollingBudget: LunaInputPollingBudget = .interactive,
        inputPresentationPolicy: LunaInteractivePresentationPolicy = .interactive
    ) {
        self.title = title
        self.initialWidth = max(1, initialWidth)
        self.initialHeight = max(1, initialHeight)
        self.targetFramesPerSecond = max(1, targetFramesPerSecond)
        self.usesVSync = usesVSync
        self.inputPollingBudget = inputPollingBudget
        self.inputPresentationPolicy = inputPresentationPolicy
    }
}

public protocol LunaSDLApplicationScene {
    var wantsContinuousRendering: Bool { get }

    /// Platform-neutral native cursor requested by the scene's current semantic
    /// hover or drag target.
    var cursorIntent: LunaCursorIntent { get }

    /// Requests native pointer capture while a Luna drag owns pointer movement.
    /// Hosts may decline capture, so scene gesture state must remain safe if the
    /// platform cannot provide it.
    var wantsPointerCapture: Bool { get }

    /// Gives the application a synchronous opportunity to cancel native-window
    /// termination, for example while an unsaved-document confirmation is active.
    mutating func shouldTerminate() -> Bool

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

    /// Consume the report produced by the immediately preceding render call.
    mutating func takeFrameRenderReport() -> LunaFrameRenderReport?
}

public extension LunaSDLApplicationScene {
    var wantsContinuousRendering: Bool { false }
    var cursorIntent: LunaCursorIntent { .arrow }
    var wantsPointerCapture: Bool { false }
    mutating func shouldTerminate() -> Bool { true }

    mutating func updateFrameRuntimeDiagnostics(
        timingStats: LunaFrameTimingStats,
        invalidations: LunaFrameInvalidationSet,
        inputCoalescingStats: LunaInputCoalescingStats
    ) {}
    mutating func takeFrameRenderReport() -> LunaFrameRenderReport? { nil }
}

@inline(__always)
private func lunaSDLLogError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private final class LunaSDLCursorController {
    private let arrow = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW)
    private let text = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_IBEAM)
    private let resizeHorizontal = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZEWE)
    private let resizeVertical = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZENS)
    private let pointingHand = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_HAND)
    private let prohibited = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_NO)

    private var appliedIntent: LunaCursorIntent?
    private var captureIsApplied = false

    deinit {
        [arrow, text, resizeHorizontal, resizeVertical, pointingHand, prohibited]
            .compactMap { $0 }
            .forEach(SDL_FreeCursor)
    }

    func apply(cursorIntent: LunaCursorIntent, wantsPointerCapture: Bool) {
        if appliedIntent != cursorIntent {
            if let cursor = cursor(for: cursorIntent) {
                SDL_SetCursor(cursor)
                appliedIntent = cursorIntent
            }
        }

        if captureIsApplied != wantsPointerCapture {
            _ = SDL_CaptureMouse(wantsPointerCapture ? SDL_TRUE : SDL_FALSE)
            captureIsApplied = wantsPointerCapture
        }
    }

    func releaseCapture() {
        guard captureIsApplied else { return }
        _ = SDL_CaptureMouse(SDL_FALSE)
        captureIsApplied = false
    }

    private func cursor(for intent: LunaCursorIntent) -> OpaquePointer? {
        switch intent {
        case .arrow: return arrow
        case .text: return text
        case .resizeHorizontal: return resizeHorizontal
        case .resizeVertical: return resizeVertical
        case .pointingHand: return pointingHand
        case .prohibited: return prohibited
        }
    }
}

/// Runs a complete Luna application using the Linux SDL host.
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

    let cursorController = LunaSDLCursorController()
    defer { cursorController.releaseCapture() }
    cursorController.apply(
        cursorIntent: scene.cursorIntent,
        wantsPointerCapture: scene.wantsPointerCapture
    )

    var framebuffer = LunaFramebuffer(
        width: configuration.initialWidth,
        height: configuration.initialHeight
    )
    let presenter = LunaSDLPresenter(window: window, useVSync: configuration.usesVSync)
    var inputTranslator = LunaSDLInputTranslator()
    var inputScheduler = LunaInteractiveInputScheduler()

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
        var scheduledBatch: LunaScheduledInputBatch?
        var nativeSourceIsIdle = false
        var didAcquireRawEvent = false

        // Raw acquisition may require several bounded passes. Those passes are
        // safety boundaries only: they never force an intermediate presentation.
        // The persistent semantic scheduler decides when an ordered interaction
        // batch is ready, so a click or command cannot be stranded behind stale
        // motion/text solely because a native polling limit was reached.
        repeat {
            let acquisitionStartedAt = LunaMonotonicClock.nowNanoseconds()
            let polledInput = inputTranslator.pollEvents(
                budget: configuration.inputPollingBudget
            )
            didAcquireRawEvent = didAcquireRawEvent || polledInput.stats.rawEventCount > 0
            nativeSourceIsIdle = !polledInput.stats.mayHavePendingEvents
            inputScheduler.ingest(
                polledInput.events,
                acquiredAtNanoseconds: acquisitionStartedAt,
                pollingStats: polledInput.stats
            )
            scheduledBatch = inputScheduler.nextDispatchBatch(
                nowNanoseconds: LunaMonotonicClock.nowNanoseconds(),
                sourceIsIdle: nativeSourceIsIdle,
                policy: configuration.inputPresentationPolicy
            )
        } while scheduledBatch == nil && !nativeSourceIsIdle

        var oldestDispatchedInputNanoseconds: UInt64?
        var didReceiveSemanticEvent = false

        if let scheduledBatch {
            latestInputStats = scheduledBatch.stats
            oldestDispatchedInputNanoseconds = scheduledBatch.oldestEventNanoseconds

            for event in scheduledBatch.events {
                didReceiveSemanticEvent = true

                if case .quit = event {
                    if scene.shouldTerminate() {
                        running = false
                    } else {
                        pendingInvalidations.insert(.input)
                    }
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
                cursorController.apply(
                    cursorIntent: scene.cursorIntent,
                    wantsPointerCapture: scene.wantsPointerCapture
                )
            }
        }

        let inputEnd = LunaMonotonicClock.nowNanoseconds()
        let inputNanoseconds = inputEnd >= inputStart ? inputEnd - inputStart : 0

        if !running { break }

        let frameRequest = LunaFrameRequest(
            invalidations: pendingInvalidations,
            wantsContinuousFrames: scene.wantsContinuousRendering
        )

        guard frameRequest.shouldRender else {
            // Pending semantic state or a conservative native backlog is resumed
            // immediately. Sleep only when there is genuinely no input work,
            // invalidation, animation, or presentation deadline outstanding.
            if inputScheduler.hasPendingInput || !nativeSourceIsIdle {
                continue
            }
            SDL_Delay(
                (didAcquireRawEvent || didReceiveSemanticEvent)
                    ? 1
                    : framePacer.sleepMillisecondsWhenIdle()
            )
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
        let renderReport = scene.takeFrameRenderReport()
        let renderEnd = LunaMonotonicClock.nowNanoseconds()

        let presentStart = LunaMonotonicClock.nowNanoseconds()
        presenter.present(framebuffer: framebuffer)
        let presentEnd = LunaMonotonicClock.nowNanoseconds()

        let inputToPresentNanoseconds: UInt64
        if let oldestDispatchedInputNanoseconds,
           presentEnd >= oldestDispatchedInputNanoseconds {
            inputToPresentNanoseconds = presentEnd - oldestDispatchedInputNanoseconds
        } else {
            inputToPresentNanoseconds = 0
        }

        frameStats.record(
            LunaFrameTimingSample(
                frameIndex: frameIndex,
                startedAtNanoseconds: frameStart,
                inputNanoseconds: inputNanoseconds,
                renderNanoseconds: renderEnd >= renderStart ? renderEnd - renderStart : 0,
                presentNanoseconds: presentEnd >= presentStart ? presentEnd - presentStart : 0,
                inputToPresentNanoseconds: inputToPresentNanoseconds,
                totalNanoseconds: presentEnd >= frameStart ? presentEnd - frameStart : 0,
                invalidations: invalidationsForFrame,
                renderReport: renderReport
            )
        )

        framePacer.markFrameEnded(atNanoseconds: presentEnd)

        // VSync owns pacing when the presenter provides it. Without external
        // VSync, apply the software pacer only after the scheduler has no pending
        // semantic work; never sleep while a click, command, or text deadline is
        // waiting to be serviced.
        if !inputScheduler.hasPendingInput && nativeSourceIsIdle {
            let sleepMilliseconds = framePacer.sleepMillisecondsBeforeNextFrame()
            if sleepMilliseconds > 0 {
                SDL_Delay(sleepMilliseconds)
            }
        }
    }

    return 0
}

#endif
