// SPDX-License-Identifier: MPL-2.0
// LunaInputCoalescing.swift
//
// Host-runtime input polling and batching helpers.
//
// Widgets remain synchronous and deterministic. Platform hosts use these values
// to keep event storms frame-fair while preserving semantic ordering. Pointer
// motion may collapse to the most recent sample in a contiguous run, and adjacent
// committed text events may merge into one transaction. Every other event is a
// hard ordering barrier.

import Foundation
import LunaInput

// MARK: - Polling budget

/// Bounded host-input polling policy.
///
/// A platform host should stop polling as soon as either limit is reached, render
/// the accumulated invalidations, then resume polling on the next loop. This keeps
/// sustained key repeat, text input, or pointer storms from starving presentation.
public struct LunaInputPollingBudget: Hashable, Sendable {
    public var maximumRawEventCount: Int
    public var maximumPollingNanoseconds: UInt64

    public init(
        maximumRawEventCount: Int = 96,
        maximumPollingNanoseconds: UInt64 = 2_000_000
    ) {
        self.maximumRawEventCount = max(1, maximumRawEventCount)
        self.maximumPollingNanoseconds = max(1, maximumPollingNanoseconds)
    }

    public static let interactive = LunaInputPollingBudget()

    public func permitsAnotherEvent(
        afterProcessing rawEventCount: Int,
        elapsedNanoseconds: UInt64
    ) -> Bool {
        rawEventCount < maximumRawEventCount
            && elapsedNanoseconds < maximumPollingNanoseconds
    }
}

public struct LunaInputPollingStats: Hashable, Sendable {
    public var rawEventCount: Int
    public var translatedEventCount: Int
    public var pollingNanoseconds: UInt64
    public var didReachEventLimit: Bool
    public var didReachTimeLimit: Bool

    public init(
        rawEventCount: Int = 0,
        translatedEventCount: Int = 0,
        pollingNanoseconds: UInt64 = 0,
        didReachEventLimit: Bool = false,
        didReachTimeLimit: Bool = false
    ) {
        self.rawEventCount = max(0, rawEventCount)
        self.translatedEventCount = max(0, translatedEventCount)
        self.pollingNanoseconds = pollingNanoseconds
        self.didReachEventLimit = didReachEventLimit
        self.didReachTimeLimit = didReachTimeLimit
    }

    /// Conservative backlog signal. Reaching either budget means the host should
    /// present promptly and immediately continue polling without an added sleep.
    public var mayHavePendingEvents: Bool {
        didReachEventLimit || didReachTimeLimit
    }

    public var pollingMilliseconds: Double {
        Double(pollingNanoseconds) / 1_000_000.0
    }
}

public struct LunaPolledInputBatch: Hashable, Sendable {
    public var events: [LunaHostInputEvent]
    public var stats: LunaInputPollingStats

    public init(
        events: [LunaHostInputEvent] = [],
        stats: LunaInputPollingStats = LunaInputPollingStats()
    ) {
        self.events = events
        self.stats = stats
    }
}

// MARK: - Coalescing

public struct LunaInputCoalescingStats: Hashable, Sendable {
    public var receivedEventCount: Int
    public var emittedEventCount: Int
    public var receivedPointerMotionCount: Int
    public var emittedPointerMotionCount: Int
    public var receivedTextInputEventCount: Int
    public var emittedTextInputEventCount: Int
    public var receivedTextInputUTF8ByteCount: Int
    public var polling: LunaInputPollingStats

    public init(
        receivedEventCount: Int = 0,
        emittedEventCount: Int = 0,
        receivedPointerMotionCount: Int = 0,
        emittedPointerMotionCount: Int = 0,
        receivedTextInputEventCount: Int = 0,
        emittedTextInputEventCount: Int = 0,
        receivedTextInputUTF8ByteCount: Int = 0,
        polling: LunaInputPollingStats = LunaInputPollingStats()
    ) {
        self.receivedEventCount = max(0, receivedEventCount)
        self.emittedEventCount = max(0, emittedEventCount)
        self.receivedPointerMotionCount = max(0, receivedPointerMotionCount)
        self.emittedPointerMotionCount = max(0, emittedPointerMotionCount)
        self.receivedTextInputEventCount = max(0, receivedTextInputEventCount)
        self.emittedTextInputEventCount = max(0, emittedTextInputEventCount)
        self.receivedTextInputUTF8ByteCount = max(0, receivedTextInputUTF8ByteCount)
        self.polling = polling
    }

    public var coalescedPointerMotionCount: Int {
        max(0, receivedPointerMotionCount - emittedPointerMotionCount)
    }

    public var mergedTextInputEventCount: Int {
        max(0, receivedTextInputEventCount - emittedTextInputEventCount)
    }

    public var statusText: String {
        String(
            format: "events %d/%d | text -%d | motion -%d | poll %.2f ms%@",
            emittedEventCount,
            receivedEventCount,
            mergedTextInputEventCount,
            coalescedPointerMotionCount,
            polling.pollingMilliseconds,
            polling.mayHavePendingEvents ? " | backlog" : ""
        )
    }
}

public struct LunaCoalescedInputBatch: Hashable, Sendable {
    public var events: [LunaHostInputEvent]
    public var stats: LunaInputCoalescingStats

    public init(
        events: [LunaHostInputEvent] = [],
        stats: LunaInputCoalescingStats = LunaInputCoalescingStats()
    ) {
        self.events = events
        self.stats = stats
    }
}

public struct LunaHostInputCoalescer: Hashable, Sendable {
    public init() {}

    public func coalesce(
        _ events: [LunaHostInputEvent],
        pollingStats: LunaInputPollingStats = LunaInputPollingStats()
    ) -> LunaCoalescedInputBatch {
        guard !events.isEmpty else {
            return LunaCoalescedInputBatch(
                stats: LunaInputCoalescingStats(polling: pollingStats)
            )
        }

        var output: [LunaHostInputEvent] = []
        output.reserveCapacity(events.count)

        var pendingPointerMotion: LunaPointerEvent?
        var pendingTextInput = ""
        var receivedMotion = 0
        var emittedMotion = 0
        var receivedText = 0
        var emittedText = 0
        var receivedTextBytes = 0

        func flushPendingMotion() {
            if let pendingPointerMotion {
                output.append(.pointer(pendingPointerMotion))
                emittedMotion += 1
            }
            pendingPointerMotion = nil
        }

        func flushPendingText() {
            guard !pendingTextInput.isEmpty else { return }
            output.append(.textInput(LunaTextInputEvent(text: pendingTextInput)))
            emittedText += 1
            pendingTextInput.removeAll(keepingCapacity: true)
        }

        for event in events {
            switch event {
            case .pointer(let pointer) where pointer.phase == .moved:
                flushPendingText()
                receivedMotion += 1
                pendingPointerMotion = pointer

            case .textInput(let textInput) where !textInput.text.isEmpty:
                flushPendingMotion()
                receivedText += 1
                receivedTextBytes += textInput.text.utf8.count
                pendingTextInput.append(textInput.text)

            default:
                flushPendingMotion()
                flushPendingText()
                output.append(event)
            }
        }
        flushPendingMotion()
        flushPendingText()

        let stats = LunaInputCoalescingStats(
            receivedEventCount: events.count,
            emittedEventCount: output.count,
            receivedPointerMotionCount: receivedMotion,
            emittedPointerMotionCount: emittedMotion,
            receivedTextInputEventCount: receivedText,
            emittedTextInputEventCount: emittedText,
            receivedTextInputUTF8ByteCount: receivedTextBytes,
            polling: pollingStats
        )
        return LunaCoalescedInputBatch(events: output, stats: stats)
    }
}
