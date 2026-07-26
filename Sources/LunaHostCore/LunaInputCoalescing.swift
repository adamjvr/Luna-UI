// SPDX-License-Identifier: MPL-2.0
// LunaInputCoalescing.swift
//
// Host-runtime input acquisition and semantic scheduling helpers.
//
// Raw host polling boundaries are deliberately not presentation boundaries.
// Platform hosts may acquire input in bounded chunks for safety, while the
// persistent semantic scheduler below preserves compatible coalescing state
// across those chunks and emits work only at meaningful interaction boundaries.

import Foundation
import LunaInput

// MARK: - Raw input acquisition

/// Bounded raw-host acquisition policy.
///
/// The limit protects one pass through a native event queue from monopolizing the
/// host thread. Reaching either limit is only a signal to continue acquisition in
/// another pass; it must never, by itself, force a framebuffer presentation.
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

    /// Conservative native-queue signal. The host should immediately continue
    /// acquisition, not present a frame solely because this value is true.
    public var mayHavePendingEvents: Bool {
        didReachEventLimit || didReachTimeLimit
    }

    public var pollingMilliseconds: Double {
        Double(pollingNanoseconds) / 1_000_000.0
    }

    public mutating func accumulate(_ other: LunaInputPollingStats) {
        rawEventCount += other.rawEventCount
        translatedEventCount += other.translatedEventCount
        pollingNanoseconds &+= other.pollingNanoseconds
        didReachEventLimit = didReachEventLimit || other.didReachEventLimit
        didReachTimeLimit = didReachTimeLimit || other.didReachTimeLimit
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

// MARK: - Diagnostics

public struct LunaInputCoalescingStats: Hashable, Sendable {
    public var receivedEventCount: Int
    public var emittedEventCount: Int
    public var receivedPointerMotionCount: Int
    public var emittedPointerMotionCount: Int
    public var receivedTextInputEventCount: Int
    public var emittedTextInputEventCount: Int
    public var receivedTextInputUTF8ByteCount: Int
    public var emittedBarrierCount: Int
    public var acquisitionBatchCount: Int
    public var dispatchSliceCount: Int
    public var dispatchedSemanticEventCount: Int
    public var deferredSemanticEventCount: Int
    public var dispatchNanoseconds: UInt64
    public var dispatchEventLimitCount: Int
    public var dispatchTimeLimitCount: Int
    public var dispatchStoppedEarlyCount: Int
    public var polling: LunaInputPollingStats

    public init(
        receivedEventCount: Int = 0,
        emittedEventCount: Int = 0,
        receivedPointerMotionCount: Int = 0,
        emittedPointerMotionCount: Int = 0,
        receivedTextInputEventCount: Int = 0,
        emittedTextInputEventCount: Int = 0,
        receivedTextInputUTF8ByteCount: Int = 0,
        emittedBarrierCount: Int = 0,
        acquisitionBatchCount: Int = 0,
        dispatchSliceCount: Int = 0,
        dispatchedSemanticEventCount: Int = 0,
        deferredSemanticEventCount: Int = 0,
        dispatchNanoseconds: UInt64 = 0,
        dispatchEventLimitCount: Int = 0,
        dispatchTimeLimitCount: Int = 0,
        dispatchStoppedEarlyCount: Int = 0,
        polling: LunaInputPollingStats = LunaInputPollingStats()
    ) {
        self.receivedEventCount = max(0, receivedEventCount)
        self.emittedEventCount = max(0, emittedEventCount)
        self.receivedPointerMotionCount = max(0, receivedPointerMotionCount)
        self.emittedPointerMotionCount = max(0, emittedPointerMotionCount)
        self.receivedTextInputEventCount = max(0, receivedTextInputEventCount)
        self.emittedTextInputEventCount = max(0, emittedTextInputEventCount)
        self.receivedTextInputUTF8ByteCount = max(0, receivedTextInputUTF8ByteCount)
        self.emittedBarrierCount = max(0, emittedBarrierCount)
        self.acquisitionBatchCount = max(0, acquisitionBatchCount)
        self.dispatchSliceCount = max(0, dispatchSliceCount)
        self.dispatchedSemanticEventCount = max(0, dispatchedSemanticEventCount)
        self.deferredSemanticEventCount = max(0, deferredSemanticEventCount)
        self.dispatchNanoseconds = dispatchNanoseconds
        self.dispatchEventLimitCount = max(0, dispatchEventLimitCount)
        self.dispatchTimeLimitCount = max(0, dispatchTimeLimitCount)
        self.dispatchStoppedEarlyCount = max(0, dispatchStoppedEarlyCount)
        self.polling = polling
    }

    public var coalescedPointerMotionCount: Int {
        max(0, receivedPointerMotionCount - emittedPointerMotionCount)
    }

    public var mergedTextInputEventCount: Int {
        max(0, receivedTextInputEventCount - emittedTextInputEventCount)
    }

    public var statusText: String {
        let acquisition = String(
            format: "events %d/%d | barriers %d | text -%d | motion -%d | acquire %.2f ms/%d",
            emittedEventCount,
            receivedEventCount,
            emittedBarrierCount,
            mergedTextInputEventCount,
            coalescedPointerMotionCount,
            polling.pollingMilliseconds,
            acquisitionBatchCount
        )
        guard dispatchSliceCount > 0 else { return acquisition }

        let dispatchMilliseconds = Double(dispatchNanoseconds) / 1_000_000.0
        let dispatch = String(
            format: "dispatch %d/%d | slices %d | %.2f ms | deferred %d",
            dispatchedSemanticEventCount,
            emittedEventCount,
            dispatchSliceCount,
            dispatchMilliseconds,
            deferredSemanticEventCount
        )
        return "\(acquisition) | \(dispatch)"
    }

    public mutating func recordDispatchSlice(
        _ stats: LunaInputDispatchStats
    ) {
        dispatchSliceCount += 1
        dispatchedSemanticEventCount += stats.processedEventCount
        deferredSemanticEventCount = stats.remainingEventCount
        dispatchNanoseconds &+= stats.dispatchNanoseconds
        if stats.didReachEventLimit {
            dispatchEventLimitCount += 1
        }
        if stats.didReachTimeLimit {
            dispatchTimeLimitCount += 1
        }
        if stats.didStopEarly {
            dispatchStoppedEarlyCount += 1
        }
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

/// Compatibility helper for deterministic one-shot callers and older tests.
///
/// The SDL application runner uses `LunaInteractiveInputScheduler` so compatible
/// text or pointer state can remain coalesced across native acquisition passes.
public struct LunaHostInputCoalescer: Hashable, Sendable {
    public init() {}

    public func coalesce(
        _ events: [LunaHostInputEvent],
        pollingStats: LunaInputPollingStats = LunaInputPollingStats()
    ) -> LunaCoalescedInputBatch {
        var scheduler = LunaInteractiveInputScheduler()
        scheduler.ingest(
            events,
            acquiredAtNanoseconds: 0,
            pollingStats: pollingStats
        )
        let batch = scheduler.nextDispatchBatch(
            nowNanoseconds: 0,
            sourceIsIdle: true,
            policy: .interactive
        )
        return LunaCoalescedInputBatch(
            events: batch?.events ?? [],
            stats: batch?.stats ?? LunaInputCoalescingStats(polling: pollingStats)
        )
    }
}

// MARK: - Persistent semantic scheduling

/// Presentation-oriented limits for coalescible semantic input.
///
/// These limits decide when accumulated visible state should be applied. They are
/// independent from raw native acquisition limits. Ordered barriers such as clicks
/// and keyboard commands always dispatch promptly regardless of these thresholds.
public struct LunaInteractivePresentationPolicy: Hashable, Sendable {
    public var maximumCoalescedInputLatencyNanoseconds: UInt64
    public var maximumCoalescedTextUTF8ByteCount: Int
    public var maximumScheduledEventCount: Int

    public init(
        maximumCoalescedInputLatencyNanoseconds: UInt64 = 8_000_000,
        maximumCoalescedTextUTF8ByteCount: Int = 64,
        maximumScheduledEventCount: Int = 512
    ) {
        self.maximumCoalescedInputLatencyNanoseconds = max(1, maximumCoalescedInputLatencyNanoseconds)
        self.maximumCoalescedTextUTF8ByteCount = max(1, maximumCoalescedTextUTF8ByteCount)
        self.maximumScheduledEventCount = max(1, maximumScheduledEventCount)
    }

    public static let interactive = LunaInteractivePresentationPolicy()
}

public struct LunaScheduledInputBatch: Hashable, Sendable {
    public var events: [LunaHostInputEvent]
    public var oldestEventNanoseconds: UInt64
    public var newestEventNanoseconds: UInt64
    public var containsOrderingBarrier: Bool
    public var containsPromptDispatchEvent: Bool
    public var containsImmediateControlEvent: Bool
    public var stats: LunaInputCoalescingStats

    public init(
        events: [LunaHostInputEvent],
        oldestEventNanoseconds: UInt64,
        newestEventNanoseconds: UInt64,
        containsOrderingBarrier: Bool,
        containsPromptDispatchEvent: Bool,
        containsImmediateControlEvent: Bool,
        stats: LunaInputCoalescingStats
    ) {
        self.events = events
        self.oldestEventNanoseconds = oldestEventNanoseconds
        self.newestEventNanoseconds = newestEventNanoseconds
        self.containsOrderingBarrier = containsOrderingBarrier
        self.containsPromptDispatchEvent = containsPromptDispatchEvent
        self.containsImmediateControlEvent = containsImmediateControlEvent
        self.stats = stats
    }
}

/// Persistent, ordered input scheduler shared by Luna's native hosts.
///
/// The scheduler owns semantic coalescing across raw acquisition passes. It never
/// reorders an event across a click, command, navigation event, resize, focus loss,
/// capture loss, or termination request. Raw queue chunking is invisible above
/// this type and therefore cannot become an accidental frame boundary.
public struct LunaInteractiveInputScheduler: Sendable {
    private struct ScheduledEvent: Hashable, Sendable {
        var event: LunaHostInputEvent
        var firstTimestampNanoseconds: UInt64
        var latestTimestampNanoseconds: UInt64
        var isOrderingBarrier: Bool
        var requestsPromptDispatch: Bool
        var isImmediateControlEvent: Bool
    }

    private var queuedEvents: [ScheduledEvent] = []
    private var readIndex: Int = 0
    private var pendingPointerMotion: ScheduledEvent?
    private var pendingText = ""
    private var pendingTextFirstTimestamp: UInt64?
    private var pendingTextLatestTimestamp: UInt64?
    private var queuedPromptDispatchEventCount = 0

    private var receivedEventCount = 0
    private var receivedPointerMotionCount = 0
    private var receivedTextInputEventCount = 0
    private var receivedTextInputUTF8ByteCount = 0
    private var acquisitionBatchCount = 0
    private var accumulatedPollingStats = LunaInputPollingStats()

    public init() {}

    public var hasPendingInput: Bool {
        readIndex < queuedEvents.count
            || pendingPointerMotion != nil
            || !pendingText.isEmpty
    }

    public var oldestPendingEventNanoseconds: UInt64? {
        var candidate: UInt64?
        if readIndex < queuedEvents.count {
            candidate = queuedEvents[readIndex].firstTimestampNanoseconds
        }
        if let pointerTimestamp = pendingPointerMotion?.firstTimestampNanoseconds {
            candidate = min(candidate ?? pointerTimestamp, pointerTimestamp)
        }
        if let textTimestamp = pendingTextFirstTimestamp {
            candidate = min(candidate ?? textTimestamp, textTimestamp)
        }
        return candidate
    }

    public mutating func ingest(
        _ events: [LunaHostInputEvent],
        acquiredAtNanoseconds: UInt64,
        pollingStats: LunaInputPollingStats = LunaInputPollingStats()
    ) {
        acquisitionBatchCount += 1
        accumulatedPollingStats.accumulate(pollingStats)
        for event in events {
            ingest(event, acquiredAtNanoseconds: acquiredAtNanoseconds)
        }
    }

    public mutating func ingest(
        _ event: LunaHostInputEvent,
        acquiredAtNanoseconds: UInt64
    ) {
        receivedEventCount += 1

        switch event {
        case .pointer(let pointer) where pointer.phase == .moved:
            flushPendingText()
            receivedPointerMotionCount += 1
            if var pending = pendingPointerMotion {
                pending.event = event
                pending.latestTimestampNanoseconds = acquiredAtNanoseconds
                pendingPointerMotion = pending
            } else {
                pendingPointerMotion = ScheduledEvent(
                    event: event,
                    firstTimestampNanoseconds: acquiredAtNanoseconds,
                    latestTimestampNanoseconds: acquiredAtNanoseconds,
                    isOrderingBarrier: false,
                    requestsPromptDispatch: false,
                    isImmediateControlEvent: false
                )
            }

        case .textInput(let textInput) where !textInput.text.isEmpty:
            flushPendingPointerMotion()
            receivedTextInputEventCount += 1
            receivedTextInputUTF8ByteCount += textInput.text.utf8.count
            if pendingText.isEmpty {
                pendingTextFirstTimestamp = acquiredAtNanoseconds
            }
            pendingText.append(textInput.text)
            pendingTextLatestTimestamp = acquiredAtNanoseconds

        case .windowResized:
            flushPendingCoalescibleInput()
            let scheduled = makeScheduledEvent(
                event,
                timestampNanoseconds: acquiredAtNanoseconds
            )
            if readIndex < queuedEvents.count,
               case .windowResized = queuedEvents.last?.event,
               queuedEvents.last?.isOrderingBarrier == true {
                let earliest = queuedEvents.last?.firstTimestampNanoseconds
                    ?? acquiredAtNanoseconds
                queuedEvents[queuedEvents.count - 1] = ScheduledEvent(
                    event: event,
                    firstTimestampNanoseconds: earliest,
                    latestTimestampNanoseconds: acquiredAtNanoseconds,
                    isOrderingBarrier: true,
                    requestsPromptDispatch: false,
                    isImmediateControlEvent: false
                )
            } else {
                appendQueuedEvent(scheduled)
            }

        default:
            flushPendingCoalescibleInput()
            appendQueuedEvent(
                makeScheduledEvent(
                    event,
                    timestampNanoseconds: acquiredAtNanoseconds
                )
            )
        }
    }

    /// Produce the next semantically meaningful dispatch batch.
    ///
    /// A prompt interaction such as a click or fresh key command dispatches with
    /// all ordered state acquired around it. Repeated navigation/deletion events,
    /// scrolling, resize storms, and committed text may batch until the native
    /// source is idle, a semantic-work threshold is reached, or the oldest pending
    /// event reaches the presentation-latency deadline.
    public mutating func nextDispatchBatch(
        nowNanoseconds: UInt64,
        sourceIsIdle: Bool,
        policy: LunaInteractivePresentationPolicy = .interactive
    ) -> LunaScheduledInputBatch? {
        if queuedPromptDispatchEventCount > 0 {
            flushPendingCoalescibleInput()
            return dequeueAllReadyEvents()
        }

        let textThresholdReached = pendingText.utf8.count
            >= policy.maximumCoalescedTextUTF8ByteCount
        let semanticWorkThresholdReached = pendingSemanticEventCount
            >= policy.maximumScheduledEventCount
        let latencyDeadlineReached: Bool
        if let oldest = oldestPendingEventNanoseconds {
            let age = nowNanoseconds >= oldest ? nowNanoseconds - oldest : 0
            latencyDeadlineReached = age >= policy.maximumCoalescedInputLatencyNanoseconds
        } else {
            latencyDeadlineReached = false
        }

        guard sourceIsIdle
            || textThresholdReached
            || semanticWorkThresholdReached
            || latencyDeadlineReached
        else {
            return nil
        }

        flushPendingCoalescibleInput()
        return dequeueAllReadyEvents()
    }

    private var pendingSemanticEventCount: Int {
        let queuedCount = max(0, queuedEvents.count - readIndex)
        return queuedCount
            + (pendingPointerMotion == nil ? 0 : 1)
            + (pendingText.isEmpty ? 0 : 1)
    }

    private mutating func flushPendingCoalescibleInput() {
        flushPendingPointerMotion()
        flushPendingText()
    }

    private mutating func flushPendingPointerMotion() {
        guard let pendingPointerMotion else { return }
        appendQueuedEvent(pendingPointerMotion)
        self.pendingPointerMotion = nil
    }

    private mutating func flushPendingText() {
        guard !pendingText.isEmpty else { return }
        let first = pendingTextFirstTimestamp ?? 0
        let latest = pendingTextLatestTimestamp ?? first
        appendQueuedEvent(
            ScheduledEvent(
                event: .textInput(LunaTextInputEvent(text: pendingText)),
                firstTimestampNanoseconds: first,
                latestTimestampNanoseconds: latest,
                isOrderingBarrier: false,
                requestsPromptDispatch: false,
                isImmediateControlEvent: false
            )
        )
        pendingText.removeAll(keepingCapacity: true)
        pendingTextFirstTimestamp = nil
        pendingTextLatestTimestamp = nil
    }

    private func makeScheduledEvent(
        _ event: LunaHostInputEvent,
        timestampNanoseconds: UInt64
    ) -> ScheduledEvent {
        let prompt: Bool
        let immediate: Bool

        switch event {
        case .quit, .pointerCaptureLost:
            prompt = true
            immediate = true

        case .pointer(let pointer):
            // Pointer activation/release must not wait for a sustained motion,
            // scroll, or key-repeat stream. Motion itself is handled by the
            // coalescible branch above.
            prompt = pointer.phase == .down || pointer.phase == .up
            immediate = false

        case .keyboard(let keyboard):
            // A fresh key press and any modified key are prompt interactions.
            // Repeated unmodified navigation/deletion events remain ordered but
            // may batch until idle, the semantic-work threshold, or the latency
            // deadline so one repeat backlog cannot manufacture frame boundaries.
            let modifiers = keyboard.modifiers
            let hasModifier = modifiers.shift
                || modifiers.control
                || modifiers.option
                || modifiers.command
            prompt = !keyboard.isRepeat || hasModifier
            immediate = false

        case .windowResized, .scroll:
            // Resize storms collapse and scroll streams batch within the strict
            // latency policy. A following click/command remains prompt and flushes
            // all preceding state in order.
            prompt = false
            immediate = false

        case .textInput:
            // Non-empty text takes the coalescible branch; keep this fallback
            // ordered without turning an empty event into a prompt boundary.
            prompt = false
            immediate = false
        }

        return ScheduledEvent(
            event: event,
            firstTimestampNanoseconds: timestampNanoseconds,
            latestTimestampNanoseconds: timestampNanoseconds,
            isOrderingBarrier: true,
            requestsPromptDispatch: prompt,
            isImmediateControlEvent: immediate
        )
    }

    private mutating func appendQueuedEvent(_ event: ScheduledEvent) {
        queuedEvents.append(event)
        if event.requestsPromptDispatch {
            queuedPromptDispatchEventCount += 1
        }
    }

    private mutating func dequeueAllReadyEvents() -> LunaScheduledInputBatch? {
        guard readIndex < queuedEvents.count else { return nil }
        return dequeue(upToExclusiveIndex: queuedEvents.count)
    }

    private mutating func dequeue(
        upToExclusiveIndex endIndex: Int
    ) -> LunaScheduledInputBatch? {
        guard readIndex < endIndex else { return nil }
        let slice = queuedEvents[readIndex..<endIndex]
        let events = slice.map(\.event)
        let oldest = slice.map(\.firstTimestampNanoseconds).min() ?? 0
        let newest = slice.map(\.latestTimestampNanoseconds).max() ?? oldest
        let barrierCount = slice.reduce(into: 0) { count, item in
            if item.isOrderingBarrier { count += 1 }
        }
        let emittedPointerMotionCount = slice.reduce(into: 0) { count, item in
            if case .pointer(let pointer) = item.event, pointer.phase == .moved {
                count += 1
            }
        }
        let emittedTextInputEventCount = slice.reduce(into: 0) { count, item in
            if case .textInput = item.event { count += 1 }
        }
        let promptCount = slice.reduce(into: 0) { count, item in
            if item.requestsPromptDispatch { count += 1 }
        }
        let containsImmediate = slice.contains(where: \.isImmediateControlEvent)

        queuedPromptDispatchEventCount = max(
            0,
            queuedPromptDispatchEventCount - promptCount
        )
        readIndex = endIndex
        compactQueueIfNeeded()

        let stats = LunaInputCoalescingStats(
            receivedEventCount: receivedEventCount,
            emittedEventCount: events.count,
            receivedPointerMotionCount: receivedPointerMotionCount,
            emittedPointerMotionCount: emittedPointerMotionCount,
            receivedTextInputEventCount: receivedTextInputEventCount,
            emittedTextInputEventCount: emittedTextInputEventCount,
            receivedTextInputUTF8ByteCount: receivedTextInputUTF8ByteCount,
            emittedBarrierCount: barrierCount,
            acquisitionBatchCount: acquisitionBatchCount,
            polling: accumulatedPollingStats
        )
        resetDispatchDiagnostics()

        return LunaScheduledInputBatch(
            events: events,
            oldestEventNanoseconds: oldest,
            newestEventNanoseconds: newest,
            containsOrderingBarrier: barrierCount > 0,
            containsPromptDispatchEvent: promptCount > 0,
            containsImmediateControlEvent: containsImmediate,
            stats: stats
        )
    }

    private mutating func compactQueueIfNeeded() {
        guard readIndex > 0 else { return }
        if readIndex == queuedEvents.count {
            queuedEvents.removeAll(keepingCapacity: true)
            readIndex = 0
        } else if readIndex >= 64 && readIndex * 2 >= queuedEvents.count {
            queuedEvents.removeFirst(readIndex)
            readIndex = 0
        }
    }

    private mutating func resetDispatchDiagnostics() {
        receivedEventCount = 0
        receivedPointerMotionCount = 0
        receivedTextInputEventCount = 0
        receivedTextInputUTF8ByteCount = 0
        acquisitionBatchCount = 0
        accumulatedPollingStats = LunaInputPollingStats()
    }
}
