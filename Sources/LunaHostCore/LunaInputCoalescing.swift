// LunaInputCoalescing.swift
//
// Host-runtime input batching helpers.
//
// These values deliberately live in LunaHostCore rather than LunaUI widgets.
// Widget code remains synchronous and deterministic. Host loops may use this
// helper to keep pointer-motion storms from producing input latency by applying
// only the latest motion sample in a contiguous run while preserving all
// semantic events such as button transitions, keyboard input, text input,
// window resize, and quit.

import Foundation
import LunaInput

public struct LunaInputCoalescingStats: Hashable, Sendable {
    public var receivedEventCount: Int
    public var emittedEventCount: Int
    public var receivedPointerMotionCount: Int
    public var emittedPointerMotionCount: Int

    public init(
        receivedEventCount: Int = 0,
        emittedEventCount: Int = 0,
        receivedPointerMotionCount: Int = 0,
        emittedPointerMotionCount: Int = 0
    ) {
        self.receivedEventCount = max(0, receivedEventCount)
        self.emittedEventCount = max(0, emittedEventCount)
        self.receivedPointerMotionCount = max(0, receivedPointerMotionCount)
        self.emittedPointerMotionCount = max(0, emittedPointerMotionCount)
    }

    public var coalescedPointerMotionCount: Int {
        max(0, receivedPointerMotionCount - emittedPointerMotionCount)
    }

    public var statusText: String {
        "events \(emittedEventCount)/\(receivedEventCount) | motion -\(coalescedPointerMotionCount)"
    }
}

public struct LunaCoalescedInputBatch: Hashable, Sendable {
    public var events: [LunaHostInputEvent]
    public var stats: LunaInputCoalescingStats

    public init(events: [LunaHostInputEvent] = [], stats: LunaInputCoalescingStats = LunaInputCoalescingStats()) {
        self.events = events
        self.stats = stats
    }
}

public struct LunaHostInputCoalescer: Hashable, Sendable {
    public init() {}

    public func coalesce(_ events: [LunaHostInputEvent]) -> LunaCoalescedInputBatch {
        guard !events.isEmpty else {
            return LunaCoalescedInputBatch()
        }

        var output: [LunaHostInputEvent] = []
        output.reserveCapacity(events.count)

        var pendingPointerMotion: LunaHostInputEvent?
        var receivedMotion = 0
        var emittedMotion = 0

        func isPointerMotion(_ event: LunaHostInputEvent) -> Bool {
            if case .pointer(let pointer) = event, pointer.phase == .moved {
                return true
            }
            return false
        }

        func flushPendingMotion() {
            if let pendingPointerMotion {
                output.append(pendingPointerMotion)
                emittedMotion += 1
            }
            pendingPointerMotion = nil
        }

        for event in events {
            if isPointerMotion(event) {
                receivedMotion += 1
                pendingPointerMotion = event
            } else {
                flushPendingMotion()
                output.append(event)
            }
        }
        flushPendingMotion()

        let stats = LunaInputCoalescingStats(
            receivedEventCount: events.count,
            emittedEventCount: output.count,
            receivedPointerMotionCount: receivedMotion,
            emittedPointerMotionCount: emittedMotion
        )
        return LunaCoalescedInputBatch(events: output, stats: stats)
    }
}
