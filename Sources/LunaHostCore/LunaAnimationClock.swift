// SPDX-License-Identifier: MPL-2.0
// LunaAnimationClock.swift
//
// Small host/runtime animation timing primitive.
//
// Luna widgets remain synchronous and deterministic. This type belongs in
// LunaHostCore because hosts and demo harnesses need a shared, testable way to
// advance animation time without making widget rendering depend directly on
// wall-clock calls or frame counts.

import Foundation

/// Timing data produced by one animation-clock advance.
public struct LunaAnimationFrame: Hashable, Sendable {
    public var frameIndex: UInt64
    public var timestampNanoseconds: UInt64
    public var rawDeltaSeconds: Double
    public var deltaSeconds: Double
    public var elapsedSeconds: Double
    public var wasDeltaClamped: Bool

    public init(
        frameIndex: UInt64,
        timestampNanoseconds: UInt64,
        rawDeltaSeconds: Double,
        deltaSeconds: Double,
        elapsedSeconds: Double,
        wasDeltaClamped: Bool
    ) {
        self.frameIndex = frameIndex
        self.timestampNanoseconds = timestampNanoseconds
        self.rawDeltaSeconds = rawDeltaSeconds
        self.deltaSeconds = deltaSeconds
        self.elapsedSeconds = elapsedSeconds
        self.wasDeltaClamped = wasDeltaClamped
    }

    public var deltaMilliseconds: Double { deltaSeconds * 1_000.0 }
    public var rawDeltaMilliseconds: Double { rawDeltaSeconds * 1_000.0 }

    public var statusText: String {
        let marker = wasDeltaClamped ? " clamped" : ""
        return String(format: "anim %.2f ms%@ | phase %.2f s", deltaMilliseconds, marker, elapsedSeconds)
    }
}

/// A monotonic animation clock with large-delta clamping.
///
/// The clock intentionally advances a logical animation phase instead of asking
/// each animated proof surface to derive positions from absolute process time.
/// That makes demo/stress animations resilient to modal dialogs, window stalls,
/// debugger pauses, or short scheduling spikes: the next rendered proof frame
/// advances by a bounded amount instead of jumping across the panel.
public struct LunaAnimationClock: Hashable, Sendable {
    public var defaultDeltaSeconds: Double
    public var maximumDeltaSeconds: Double

    public private(set) var frameIndex: UInt64
    public private(set) var elapsedSeconds: Double
    public private(set) var lastTimestampNanoseconds: UInt64?
    public private(set) var latestFrame: LunaAnimationFrame?

    public init(
        defaultDeltaSeconds: Double = 1.0 / 60.0,
        maximumDeltaSeconds: Double = 1.0 / 30.0,
        startTimeNanoseconds: UInt64? = nil
    ) {
        self.defaultDeltaSeconds = max(0.0, defaultDeltaSeconds)
        self.maximumDeltaSeconds = max(self.defaultDeltaSeconds, maximumDeltaSeconds)
        self.frameIndex = 0
        self.elapsedSeconds = 0.0
        self.lastTimestampNanoseconds = startTimeNanoseconds
        self.latestFrame = nil
    }

    /// Reset logical animation phase, usually after toggling a mode or recreating
    /// a scene. The next `advance` call will use `defaultDeltaSeconds` instead of
    /// attempting to integrate from old/stale timestamps.
    public mutating func reset(atNanoseconds timestampNanoseconds: UInt64? = nil) {
        frameIndex = 0
        elapsedSeconds = 0.0
        lastTimestampNanoseconds = timestampNanoseconds
        latestFrame = nil
    }

    /// Advance the logical animation phase and return the measured frame data.
    @discardableResult
    public mutating func advance(toNanoseconds nowNanoseconds: UInt64 = LunaMonotonicClock.nowNanoseconds()) -> LunaAnimationFrame {
        let rawDeltaSeconds: Double
        if let lastTimestampNanoseconds {
            let deltaNanoseconds = nowNanoseconds >= lastTimestampNanoseconds
                ? nowNanoseconds - lastTimestampNanoseconds
                : 0
            rawDeltaSeconds = Double(deltaNanoseconds) / 1_000_000_000.0
        } else {
            rawDeltaSeconds = defaultDeltaSeconds
        }

        let clampedDeltaSeconds = min(max(0.0, rawDeltaSeconds), maximumDeltaSeconds)
        let wasClamped = rawDeltaSeconds > maximumDeltaSeconds

        frameIndex &+= 1
        elapsedSeconds += clampedDeltaSeconds
        lastTimestampNanoseconds = nowNanoseconds

        let frame = LunaAnimationFrame(
            frameIndex: frameIndex,
            timestampNanoseconds: nowNanoseconds,
            rawDeltaSeconds: rawDeltaSeconds,
            deltaSeconds: clampedDeltaSeconds,
            elapsedSeconds: elapsedSeconds,
            wasDeltaClamped: wasClamped
        )
        latestFrame = frame
        return frame
    }

    public var statusText: String {
        latestFrame?.statusText ?? "anim -- ms | phase 0.00 s"
    }
}
