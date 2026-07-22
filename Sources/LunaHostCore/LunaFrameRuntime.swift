// SPDX-License-Identifier: MPL-2.0
// LunaFrameRuntime.swift
//
// Frame pacing, invalidation, and host-runtime boundary primitives.
//
// These types deliberately live in LunaHostCore, not in LunaUI widgets. Luna's
// widgets stay synchronous and deterministic; host runtimes use these values to
// decide when a new frame is needed, how frame timing should be measured, and how
// completed async/app-service work should request UI-thread application.

import Foundation
import LunaRender

// MARK: - Monotonic clock

public enum LunaMonotonicClock {
    public static func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

// MARK: - Invalidation

public enum LunaInvalidationReason: Hashable, Sendable, CustomStringConvertible {
    case initial
    case input
    case textInput
    case documentChanged
    case selectionChanged
    case scrollChanged
    case overlayChanged
    case commandExecuted
    case themeChanged
    case workspaceChanged
    case windowResized
    case caretBlink
    case animation
    case asyncResult
    case accessibilityChanged
    case explicit(String)

    public var description: String {
        switch self {
        case .initial: return "initial"
        case .input: return "input"
        case .textInput: return "textInput"
        case .documentChanged: return "documentChanged"
        case .selectionChanged: return "selectionChanged"
        case .scrollChanged: return "scrollChanged"
        case .overlayChanged: return "overlayChanged"
        case .commandExecuted: return "commandExecuted"
        case .themeChanged: return "themeChanged"
        case .workspaceChanged: return "workspaceChanged"
        case .windowResized: return "windowResized"
        case .caretBlink: return "caretBlink"
        case .animation: return "animation"
        case .asyncResult: return "asyncResult"
        case .accessibilityChanged: return "accessibilityChanged"
        case .explicit(let value): return "explicit(\(value))"
        }
    }
}

public struct LunaFrameInvalidationSet: Hashable, Sendable, CustomStringConvertible {
    public private(set) var reasons: Set<LunaInvalidationReason>

    public init(_ reasons: Set<LunaInvalidationReason> = []) {
        self.reasons = reasons
    }

    public init(_ reason: LunaInvalidationReason) {
        self.reasons = [reason]
    }

    public var isEmpty: Bool { reasons.isEmpty }
    public var needsFrame: Bool { !reasons.isEmpty }

    public mutating func insert(_ reason: LunaInvalidationReason) {
        reasons.insert(reason)
    }

    public mutating func formUnion(_ other: LunaFrameInvalidationSet) {
        reasons.formUnion(other.reasons)
    }

    public mutating func removeAll(keepingCapacity keepCapacity: Bool = true) {
        reasons.removeAll(keepingCapacity: keepCapacity)
    }

    public func union(_ reason: LunaInvalidationReason) -> LunaFrameInvalidationSet {
        var copy = self
        copy.insert(reason)
        return copy
    }

    public var description: String {
        guard !reasons.isEmpty else { return "none" }
        return reasons.map(\.description).sorted().joined(separator: ",")
    }
}

public struct LunaFrameRequest: Hashable, Sendable {
    public var invalidations: LunaFrameInvalidationSet
    public var wantsContinuousFrames: Bool
    public var requestedAtNanoseconds: UInt64

    public init(
        invalidations: LunaFrameInvalidationSet = LunaFrameInvalidationSet(),
        wantsContinuousFrames: Bool = false,
        requestedAtNanoseconds: UInt64 = LunaMonotonicClock.nowNanoseconds()
    ) {
        self.invalidations = invalidations
        self.wantsContinuousFrames = wantsContinuousFrames
        self.requestedAtNanoseconds = requestedAtNanoseconds
    }

    public var shouldRender: Bool {
        wantsContinuousFrames || invalidations.needsFrame
    }
}

// MARK: - Timing

public struct LunaFrameTimingSample: Hashable, Sendable {
    public var frameIndex: UInt64
    public var startedAtNanoseconds: UInt64
    public var inputNanoseconds: UInt64
    public var updateNanoseconds: UInt64
    public var renderNanoseconds: UInt64
    public var presentNanoseconds: UInt64
    /// Time from acquisition of the oldest semantic event dispatched for this
    /// frame through completion of presentation. Zero for non-input-driven frames.
    public var inputToPresentNanoseconds: UInt64
    public var totalNanoseconds: UInt64
    public var invalidations: LunaFrameInvalidationSet

    public init(
        frameIndex: UInt64,
        startedAtNanoseconds: UInt64,
        inputNanoseconds: UInt64 = 0,
        updateNanoseconds: UInt64 = 0,
        renderNanoseconds: UInt64 = 0,
        presentNanoseconds: UInt64 = 0,
        inputToPresentNanoseconds: UInt64 = 0,
        totalNanoseconds: UInt64,
        invalidations: LunaFrameInvalidationSet = LunaFrameInvalidationSet()
    ) {
        self.frameIndex = frameIndex
        self.startedAtNanoseconds = startedAtNanoseconds
        self.inputNanoseconds = inputNanoseconds
        self.updateNanoseconds = updateNanoseconds
        self.renderNanoseconds = renderNanoseconds
        self.presentNanoseconds = presentNanoseconds
        self.inputToPresentNanoseconds = inputToPresentNanoseconds
        self.totalNanoseconds = totalNanoseconds
        self.invalidations = invalidations
    }

    public var totalMilliseconds: Double { Double(totalNanoseconds) / 1_000_000.0 }
    public var inputMilliseconds: Double { Double(inputNanoseconds) / 1_000_000.0 }
    public var renderMilliseconds: Double { Double(renderNanoseconds) / 1_000_000.0 }
    public var presentMilliseconds: Double { Double(presentNanoseconds) / 1_000_000.0 }
    public var inputToPresentMilliseconds: Double {
        Double(inputToPresentNanoseconds) / 1_000_000.0
    }

    public var framesPerSecond: Double {
        guard totalNanoseconds > 0 else { return 0 }
        return 1_000_000_000.0 / Double(totalNanoseconds)
    }
}

public struct LunaFrameTimingStats: Hashable, Sendable {
    public private(set) var sampleCount: UInt64
    public private(set) var latest: LunaFrameTimingSample?
    public private(set) var worstRecent: LunaFrameTimingSample?
    public private(set) var movingAverageTotalNanoseconds: Double
    public private(set) var movingAverageInputNanoseconds: Double
    public private(set) var movingAverageRenderNanoseconds: Double
    public private(set) var movingAveragePresentNanoseconds: Double
    public private(set) var movingAverageInputToPresentNanoseconds: Double
    public var smoothingFactor: Double

    public init(smoothingFactor: Double = 0.12) {
        self.sampleCount = 0
        self.latest = nil
        self.worstRecent = nil
        self.movingAverageTotalNanoseconds = 0
        self.movingAverageInputNanoseconds = 0
        self.movingAverageRenderNanoseconds = 0
        self.movingAveragePresentNanoseconds = 0
        self.movingAverageInputToPresentNanoseconds = 0
        self.smoothingFactor = min(1.0, max(0.001, smoothingFactor))
    }

    public mutating func record(_ sample: LunaFrameTimingSample) {
        sampleCount &+= 1
        latest = sample

        if let currentWorst = worstRecent {
            worstRecent = sample.totalNanoseconds >= currentWorst.totalNanoseconds ? sample : currentWorst
        } else {
            worstRecent = sample
        }

        if sampleCount == 1 {
            movingAverageTotalNanoseconds = Double(sample.totalNanoseconds)
            movingAverageInputNanoseconds = Double(sample.inputNanoseconds)
            movingAverageRenderNanoseconds = Double(sample.renderNanoseconds)
            movingAveragePresentNanoseconds = Double(sample.presentNanoseconds)
            movingAverageInputToPresentNanoseconds = Double(sample.inputToPresentNanoseconds)
        } else {
            let alpha = smoothingFactor
            movingAverageTotalNanoseconds = (Double(sample.totalNanoseconds) * alpha) + (movingAverageTotalNanoseconds * (1.0 - alpha))
            movingAverageInputNanoseconds = (Double(sample.inputNanoseconds) * alpha) + (movingAverageInputNanoseconds * (1.0 - alpha))
            movingAverageRenderNanoseconds = (Double(sample.renderNanoseconds) * alpha) + (movingAverageRenderNanoseconds * (1.0 - alpha))
            movingAveragePresentNanoseconds = (Double(sample.presentNanoseconds) * alpha) + (movingAveragePresentNanoseconds * (1.0 - alpha))
            if sample.inputToPresentNanoseconds > 0 {
                if movingAverageInputToPresentNanoseconds == 0 {
                    movingAverageInputToPresentNanoseconds = Double(sample.inputToPresentNanoseconds)
                } else {
                    movingAverageInputToPresentNanoseconds = (Double(sample.inputToPresentNanoseconds) * alpha)
                        + (movingAverageInputToPresentNanoseconds * (1.0 - alpha))
                }
            }
        }
    }

    public mutating func resetWorstRecent() {
        worstRecent = latest
    }

    public var movingAverageFrameMilliseconds: Double {
        movingAverageTotalNanoseconds / 1_000_000.0
    }

    public var movingAverageInputMilliseconds: Double {
        movingAverageInputNanoseconds / 1_000_000.0
    }

    public var movingAverageRenderMilliseconds: Double {
        movingAverageRenderNanoseconds / 1_000_000.0
    }

    public var movingAveragePresentMilliseconds: Double {
        movingAveragePresentNanoseconds / 1_000_000.0
    }

    public var movingAverageInputToPresentMilliseconds: Double {
        movingAverageInputToPresentNanoseconds / 1_000_000.0
    }

    public var movingAverageFramesPerSecond: Double {
        guard movingAverageTotalNanoseconds > 0 else { return 0 }
        return 1_000_000_000.0 / movingAverageTotalNanoseconds
    }

    public var statusText: String {
        guard sampleCount > 0 else { return "fps -- | frame -- ms" }
        return String(
            format: "fps %.1f | input %.2f | render %.2f | present %.2f | latency %.2f ms",
            movingAverageFramesPerSecond,
            movingAverageInputMilliseconds,
            movingAverageRenderMilliseconds,
            movingAveragePresentMilliseconds,
            movingAverageInputToPresentMilliseconds
        )
    }
}

// MARK: - Frame pacing

public struct LunaFramePacer: Hashable, Sendable {
    public var targetFramesPerSecond: Double
    public var usesExternalVSync: Bool
    public var idleSleepMilliseconds: UInt32
    public private(set) var lastFrameEndedAtNanoseconds: UInt64?

    public init(
        targetFramesPerSecond: Double = 60,
        usesExternalVSync: Bool = true,
        idleSleepMilliseconds: UInt32 = 4
    ) {
        self.targetFramesPerSecond = max(1, targetFramesPerSecond)
        self.usesExternalVSync = usesExternalVSync
        self.idleSleepMilliseconds = max(1, idleSleepMilliseconds)
        self.lastFrameEndedAtNanoseconds = nil
    }

    public var targetFrameNanoseconds: UInt64 {
        UInt64((1_000_000_000.0 / targetFramesPerSecond).rounded())
    }

    public mutating func markFrameEnded(atNanoseconds now: UInt64 = LunaMonotonicClock.nowNanoseconds()) {
        lastFrameEndedAtNanoseconds = now
    }

    public func sleepMillisecondsBeforeNextFrame(nowNanoseconds now: UInt64 = LunaMonotonicClock.nowNanoseconds()) -> UInt32 {
        guard !usesExternalVSync else { return 0 }
        guard let lastFrameEndedAtNanoseconds else { return 0 }
        let elapsed = now >= lastFrameEndedAtNanoseconds ? now - lastFrameEndedAtNanoseconds : 0
        guard elapsed < targetFrameNanoseconds else { return 0 }
        let remaining = targetFrameNanoseconds - elapsed
        return UInt32(max(0, remaining / 1_000_000))
    }

    public func sleepMillisecondsWhenIdle() -> UInt32 {
        idleSleepMilliseconds
    }
}

// MARK: - Runtime tick

public struct LunaRuntimeTick: Hashable, Sendable {
    public var tickIndex: UInt64
    public var timestampNanoseconds: UInt64
    public var invalidations: LunaFrameInvalidationSet

    public init(
        tickIndex: UInt64,
        timestampNanoseconds: UInt64 = LunaMonotonicClock.nowNanoseconds(),
        invalidations: LunaFrameInvalidationSet = LunaFrameInvalidationSet()
    ) {
        self.tickIndex = tickIndex
        self.timestampNanoseconds = timestampNanoseconds
        self.invalidations = invalidations
    }
}
