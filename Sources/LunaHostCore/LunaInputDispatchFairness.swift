// SPDX-License-Identifier: MPL-2.0
//
// LunaInputDispatchFairness.swift
//
// Bounded semantic-event dispatch between Luna's persistent input scheduler and
// one synchronous application scene. Raw native acquisition remains independent:
// this cursor limits only application event handling so a ready semantic batch
// cannot monopolize the UI lane and starve presentation.

import LunaInput

/// Maximum work allowed in one synchronous semantic-dispatch slice.
///
/// At least one event is always processed when a cursor has pending work. This
/// guarantees progress even when the first event itself exceeds the time budget.
public struct LunaInputDispatchBudget: Hashable, Sendable {
    public var maximumSemanticEventCount: Int
    public var maximumDispatchNanoseconds: UInt64

    public init(
        maximumSemanticEventCount: Int = 32,
        maximumDispatchNanoseconds: UInt64 = 2_000_000
    ) {
        self.maximumSemanticEventCount = max(1, maximumSemanticEventCount)
        self.maximumDispatchNanoseconds = max(1, maximumDispatchNanoseconds)
    }

    public static let interactive = LunaInputDispatchBudget()
}

/// Result requested by the application after handling one semantic event.
public enum LunaInputDispatchDecision: Hashable, Sendable {
    /// Continue until the cursor reaches its event/time budget or completes.
    case continueDispatch

    /// Stop the current slice immediately. Unprocessed events remain in order in
    /// the cursor. The SDL host uses this when an accepted quit ends its run loop.
    case stopDispatch
}

/// Measured outcome of one semantic-dispatch slice.
public struct LunaInputDispatchStats: Hashable, Sendable {
    public var processedEventCount: Int
    public var remainingEventCount: Int
    public var dispatchNanoseconds: UInt64
    public var didReachEventLimit: Bool
    public var didReachTimeLimit: Bool
    public var didStopEarly: Bool
    public var didCompleteBatch: Bool

    public init(
        processedEventCount: Int = 0,
        remainingEventCount: Int = 0,
        dispatchNanoseconds: UInt64 = 0,
        didReachEventLimit: Bool = false,
        didReachTimeLimit: Bool = false,
        didStopEarly: Bool = false,
        didCompleteBatch: Bool = false
    ) {
        self.processedEventCount = max(0, processedEventCount)
        self.remainingEventCount = max(0, remainingEventCount)
        self.dispatchNanoseconds = dispatchNanoseconds
        self.didReachEventLimit = didReachEventLimit
        self.didReachTimeLimit = didReachTimeLimit
        self.didStopEarly = didStopEarly
        self.didCompleteBatch = didCompleteBatch
    }

    public var didDeferWork: Bool { remainingEventCount > 0 }
}

/// One bounded presentation opportunity cut from a scheduled semantic batch.
public struct LunaScheduledInputDispatchSlice: Hashable, Sendable {
    public var oldestEventNanoseconds: UInt64
    public var newestEventNanoseconds: UInt64
    public var stats: LunaInputDispatchStats

    public init(
        oldestEventNanoseconds: UInt64,
        newestEventNanoseconds: UInt64,
        stats: LunaInputDispatchStats
    ) {
        self.oldestEventNanoseconds = oldestEventNanoseconds
        self.newestEventNanoseconds = newestEventNanoseconds
        self.stats = stats
    }
}

/// Ordered continuation over one `LunaScheduledInputBatch`.
///
/// The cursor never reorders or merges events. New native input remains in the
/// scheduler until this cursor completes, so later acquisition cannot overtake
/// an already-ready semantic batch.
public struct LunaScheduledInputDispatchCursor: Sendable {
    private let batch: LunaScheduledInputBatch
    private var readIndex: Int

    /// Scheduler/coalescing diagnostics plus accumulated dispatch-slice metrics.
    public private(set) var inputStats: LunaInputCoalescingStats

    public init(batch: LunaScheduledInputBatch) {
        self.batch = batch
        self.readIndex = 0
        self.inputStats = batch.stats
        self.inputStats.deferredSemanticEventCount = batch.events.count
    }

    public var hasPendingEvents: Bool {
        readIndex < batch.events.count
    }

    public var processedEventCount: Int {
        min(readIndex, batch.events.count)
    }

    public var remainingEventCount: Int {
        max(0, batch.events.count - readIndex)
    }

    public var oldestEventNanoseconds: UInt64 {
        batch.oldestEventNanoseconds
    }

    public var newestEventNanoseconds: UInt64 {
        batch.newestEventNanoseconds
    }

    /// Dispatch one bounded slice in exact batch order.
    ///
    /// `nowNanoseconds` is injectable so the budget and progress rules are fully
    /// deterministic in tests. The closure is synchronous and nonescaping.
    @discardableResult
    public mutating func dispatchNextSlice(
        budget: LunaInputDispatchBudget = .interactive,
        nowNanoseconds: () -> UInt64 = LunaMonotonicClock.nowNanoseconds,
        _ handleEvent: (LunaHostInputEvent) -> LunaInputDispatchDecision
    ) -> LunaScheduledInputDispatchSlice {
        guard hasPendingEvents else {
            let stats = LunaInputDispatchStats(
                remainingEventCount: 0,
                didCompleteBatch: true
            )
            return LunaScheduledInputDispatchSlice(
                oldestEventNanoseconds: batch.oldestEventNanoseconds,
                newestEventNanoseconds: batch.newestEventNanoseconds,
                stats: stats
            )
        }

        let startedAt = nowNanoseconds()
        var endedAt = startedAt
        var processed = 0
        var reachedEventLimit = false
        var reachedTimeLimit = false
        var stoppedEarly = false

        repeat {
            let event = batch.events[readIndex]
            readIndex += 1
            processed += 1

            let decision = handleEvent(event)
            endedAt = nowNanoseconds()

            if decision == .stopDispatch {
                stoppedEarly = true
                break
            }

            guard hasPendingEvents else { break }

            let elapsed = endedAt >= startedAt ? endedAt - startedAt : 0
            if processed >= budget.maximumSemanticEventCount {
                reachedEventLimit = true
                break
            }
            if elapsed >= budget.maximumDispatchNanoseconds {
                reachedTimeLimit = true
                break
            }
        } while hasPendingEvents

        let elapsed = endedAt >= startedAt ? endedAt - startedAt : 0
        let stats = LunaInputDispatchStats(
            processedEventCount: processed,
            remainingEventCount: remainingEventCount,
            dispatchNanoseconds: elapsed,
            didReachEventLimit: reachedEventLimit,
            didReachTimeLimit: reachedTimeLimit,
            didStopEarly: stoppedEarly,
            didCompleteBatch: !hasPendingEvents
        )
        inputStats.recordDispatchSlice(stats)

        return LunaScheduledInputDispatchSlice(
            oldestEventNanoseconds: batch.oldestEventNanoseconds,
            newestEventNanoseconds: batch.newestEventNanoseconds,
            stats: stats
        )
    }
}
