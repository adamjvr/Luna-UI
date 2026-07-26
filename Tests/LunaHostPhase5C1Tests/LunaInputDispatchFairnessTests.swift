// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput

final class LunaInputDispatchFairnessTests: XCTestCase {
    func testEventBudgetSlicesBatchWithoutReordering() {
        let events = (0..<7).map { index in
            LunaHostInputEvent.keyboard(
                LunaKeyboardEvent(
                    key: .number(index),
                    modifiers: .none,
                    isRepeat: true
                )
            )
        }
        var cursor = LunaScheduledInputDispatchCursor(batch: makeBatch(events))
        let budget = LunaInputDispatchBudget(
            maximumSemanticEventCount: 3,
            maximumDispatchNanoseconds: 1_000_000
        )
        var observed: [Int] = []

        let first = cursor.dispatchNextSlice(
            budget: budget,
            nowNanoseconds: { 0 }
        ) { event in
            if case .keyboard(let keyboard) = event,
               case .number(let value) = keyboard.key {
                observed.append(value)
            }
            return LunaInputDispatchDecision.continueDispatch
        }

        XCTAssertEqual(first.stats.processedEventCount, 3)
        XCTAssertEqual(first.stats.remainingEventCount, 4)
        XCTAssertTrue(first.stats.didReachEventLimit)
        XCTAssertFalse(first.stats.didCompleteBatch)

        _ = cursor.dispatchNextSlice(
            budget: budget,
            nowNanoseconds: { 0 }
        ) { event in
            if case .keyboard(let keyboard) = event,
               case .number(let value) = keyboard.key {
                observed.append(value)
            }
            return LunaInputDispatchDecision.continueDispatch
        }
        let final = cursor.dispatchNextSlice(
            budget: budget,
            nowNanoseconds: { 0 }
        ) { event in
            if case .keyboard(let keyboard) = event,
               case .number(let value) = keyboard.key {
                observed.append(value)
            }
            return LunaInputDispatchDecision.continueDispatch
        }

        XCTAssertEqual(observed, Array(0..<7))
        XCTAssertEqual(final.stats.processedEventCount, 1)
        XCTAssertEqual(final.stats.remainingEventCount, 0)
        XCTAssertTrue(final.stats.didCompleteBatch)
        XCTAssertFalse(cursor.hasPendingEvents)
    }

    func testElapsedTimeBudgetStopsAfterFirstExpensiveEvent() {
        let events = [
            LunaHostInputEvent.keyboard(
                LunaKeyboardEvent(key: .arrowLeft, isRepeat: true)
            ),
            LunaHostInputEvent.keyboard(
                LunaKeyboardEvent(key: .arrowRight, isRepeat: true)
            ),
        ]
        var cursor = LunaScheduledInputDispatchCursor(batch: makeBatch(events))
        let clock = TestClock([100, 103])
        var observed: [LunaKeyboardKey] = []

        let slice = cursor.dispatchNextSlice(
            budget: LunaInputDispatchBudget(
                maximumSemanticEventCount: 10,
                maximumDispatchNanoseconds: 2
            ),
            nowNanoseconds: clock.now
        ) { event in
            if case .keyboard(let keyboard) = event {
                observed.append(keyboard.key)
            }
            return LunaInputDispatchDecision.continueDispatch
        }

        XCTAssertEqual(observed, [.arrowLeft])
        XCTAssertEqual(slice.stats.processedEventCount, 1)
        XCTAssertEqual(slice.stats.remainingEventCount, 1)
        XCTAssertTrue(slice.stats.didReachTimeLimit)
        XCTAssertFalse(slice.stats.didReachEventLimit)
    }

    func testAtLeastOneEventProgressesWhenClockAlreadyExceedsBudget() {
        let event = LunaHostInputEvent.keyboard(
            LunaKeyboardEvent(key: .delete, isRepeat: true)
        )
        var cursor = LunaScheduledInputDispatchCursor(
            batch: makeBatch([event, event])
        )
        let clock = TestClock([1_000, 9_000])
        var count = 0

        let slice = cursor.dispatchNextSlice(
            budget: LunaInputDispatchBudget(
                maximumSemanticEventCount: 1,
                maximumDispatchNanoseconds: 1
            ),
            nowNanoseconds: clock.now
        ) { _ in
            count += 1
            return LunaInputDispatchDecision.continueDispatch
        }

        XCTAssertEqual(count, 1)
        XCTAssertEqual(slice.stats.processedEventCount, 1)
        XCTAssertEqual(slice.stats.remainingEventCount, 1)
        XCTAssertTrue(cursor.hasPendingEvents)
    }

    func testStopDecisionEndsCurrentSliceAndRetainsContinuation() {
        let events = [
            LunaHostInputEvent.keyboard(
                LunaKeyboardEvent(key: .arrowLeft, isRepeat: true)
            ),
            .quit,
            LunaHostInputEvent.keyboard(
                LunaKeyboardEvent(key: .arrowRight, isRepeat: true)
            ),
        ]
        var cursor = LunaScheduledInputDispatchCursor(batch: makeBatch(events))
        var observed: [LunaHostInputEvent] = []

        let slice = cursor.dispatchNextSlice(
            budget: LunaInputDispatchBudget(
                maximumSemanticEventCount: 10,
                maximumDispatchNanoseconds: 1_000
            ),
            nowNanoseconds: { 0 }
        ) { event in
            observed.append(event)
            return event == .quit
                ? LunaInputDispatchDecision.stopDispatch
                : LunaInputDispatchDecision.continueDispatch
        }

        XCTAssertEqual(observed.count, 2)
        XCTAssertEqual(slice.stats.processedEventCount, 2)
        XCTAssertEqual(slice.stats.remainingEventCount, 1)
        XCTAssertTrue(slice.stats.didStopEarly)
        XCTAssertTrue(cursor.hasPendingEvents)
    }

    func testCursorRetainsOriginalBatchLatencyMetadataAcrossSlices() {
        var cursor = LunaScheduledInputDispatchCursor(
            batch: LunaScheduledInputBatch(
                events: [
                    .textInput(LunaTextInputEvent(text: "a")),
                    .textInput(LunaTextInputEvent(text: "b")),
                ],
                oldestEventNanoseconds: 100,
                newestEventNanoseconds: 250,
                containsOrderingBarrier: false,
                containsPromptDispatchEvent: false,
                containsImmediateControlEvent: false,
                stats: LunaInputCoalescingStats(
                    receivedEventCount: 2,
                    emittedEventCount: 2
                )
            )
        )

        let slice = cursor.dispatchNextSlice(
            budget: LunaInputDispatchBudget(
                maximumSemanticEventCount: 1,
                maximumDispatchNanoseconds: 10
            ),
            nowNanoseconds: { 0 }
        ) { _ in
            LunaInputDispatchDecision.continueDispatch
        }

        XCTAssertEqual(slice.oldestEventNanoseconds, 100)
        XCTAssertEqual(slice.newestEventNanoseconds, 250)
        XCTAssertEqual(cursor.oldestEventNanoseconds, 100)
        XCTAssertEqual(cursor.newestEventNanoseconds, 250)
    }

    func testDispatchDiagnosticsAccumulateAcrossSlices() {
        let events = (0..<5).map { index in
            LunaHostInputEvent.keyboard(
                LunaKeyboardEvent(key: .number(index), isRepeat: true)
            )
        }
        var cursor = LunaScheduledInputDispatchCursor(batch: makeBatch(events))
        let budget = LunaInputDispatchBudget(
            maximumSemanticEventCount: 2,
            maximumDispatchNanoseconds: 1_000
        )

        while cursor.hasPendingEvents {
            _ = cursor.dispatchNextSlice(
                budget: budget,
                nowNanoseconds: { 10 }
            ) { _ in
                LunaInputDispatchDecision.continueDispatch
            }
        }

        XCTAssertEqual(cursor.inputStats.dispatchSliceCount, 3)
        XCTAssertEqual(cursor.inputStats.dispatchedSemanticEventCount, 5)
        XCTAssertEqual(cursor.inputStats.deferredSemanticEventCount, 0)
        XCTAssertEqual(cursor.inputStats.dispatchEventLimitCount, 2)
        XCTAssertEqual(cursor.inputStats.dispatchTimeLimitCount, 0)
    }

    func testBudgetClampsInvalidValues() {
        let budget = LunaInputDispatchBudget(
            maximumSemanticEventCount: 0,
            maximumDispatchNanoseconds: 0
        )
        XCTAssertEqual(budget.maximumSemanticEventCount, 1)
        XCTAssertEqual(budget.maximumDispatchNanoseconds, 1)
    }

    private func makeBatch(
        _ events: [LunaHostInputEvent]
    ) -> LunaScheduledInputBatch {
        LunaScheduledInputBatch(
            events: events,
            oldestEventNanoseconds: 10,
            newestEventNanoseconds: 20,
            containsOrderingBarrier: events.contains { event in
                switch event {
                case .textInput, .pointer:
                    return false
                default:
                    return true
                }
            },
            containsPromptDispatchEvent: false,
            containsImmediateControlEvent: events.contains(.quit),
            stats: LunaInputCoalescingStats(
                receivedEventCount: events.count,
                emittedEventCount: events.count
            )
        )
    }
}

private final class TestClock {
    private let values: [UInt64]
    private var index = 0

    init(_ values: [UInt64]) {
        self.values = values
    }

    func now() -> UInt64 {
        guard !values.isEmpty else { return 0 }
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}
