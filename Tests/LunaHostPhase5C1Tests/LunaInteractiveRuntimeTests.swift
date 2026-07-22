// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput

final class LunaInteractiveRuntimeTests: XCTestCase {
    private let policy = LunaInteractivePresentationPolicy(
        maximumCoalescedInputLatencyNanoseconds: 8_000_000,
        maximumCoalescedTextUTF8ByteCount: 64
    )

    func testRawAcquisitionBoundariesDoNotBecomeDispatchBoundaries() {
        var scheduler = LunaInteractiveInputScheduler()

        scheduler.ingest(
            [.textInput(LunaTextInputEvent(text: "abc"))],
            acquiredAtNanoseconds: 1_000,
            pollingStats: LunaInputPollingStats(
                rawEventCount: 96,
                translatedEventCount: 1,
                pollingNanoseconds: 2_000_000,
                didReachEventLimit: true
            )
        )

        XCTAssertNil(
            scheduler.nextDispatchBatch(
                nowNanoseconds: 2_000,
                sourceIsIdle: false,
                policy: policy
            )
        )
        XCTAssertTrue(scheduler.hasPendingInput)
    }

    func testMotionStormAndClickDispatchWithoutIntermediateBatches() throws {
        var scheduler = LunaInteractiveInputScheduler()
        var timestamp: UInt64 = 1_000

        for chunk in 0..<5 {
            let motions = (0..<100).map { index in
                LunaHostInputEvent.pointer(
                    LunaPointerEvent(
                        phase: .moved,
                        location: LunaPointI(x: chunk * 100 + index, y: index)
                    )
                )
            }
            scheduler.ingest(
                motions,
                acquiredAtNanoseconds: timestamp,
                pollingStats: LunaInputPollingStats(
                    rawEventCount: motions.count,
                    translatedEventCount: motions.count,
                    didReachEventLimit: true
                )
            )
            timestamp += 1_000
            XCTAssertNil(
                scheduler.nextDispatchBatch(
                    nowNanoseconds: timestamp,
                    sourceIsIdle: false,
                    policy: policy
                )
            )
        }

        scheduler.ingest(
            .pointer(
                LunaPointerEvent(
                    phase: .down,
                    location: LunaPointI(x: 499, y: 99)
                )
            ),
            acquiredAtNanoseconds: timestamp
        )

        let batch = try XCTUnwrap(
            scheduler.nextDispatchBatch(
                nowNanoseconds: timestamp,
                sourceIsIdle: false,
                policy: policy
            )
        )

        XCTAssertEqual(batch.events.count, 2)
        XCTAssertTrue(batch.containsOrderingBarrier)
        XCTAssertEqual(batch.stats.receivedPointerMotionCount, 500)
        XCTAssertEqual(batch.stats.emittedPointerMotionCount, 1)
        XCTAssertEqual(batch.stats.coalescedPointerMotionCount, 499)

        guard case .pointer(let motion) = batch.events[0],
              case .pointer(let down) = batch.events[1]
        else {
            return XCTFail("Expected latest motion immediately followed by click")
        }
        XCTAssertEqual(motion.phase, .moved)
        XCTAssertEqual(motion.location, LunaPointI(x: 499, y: 99))
        XCTAssertEqual(down.phase, .down)
    }

    func testTextAcrossAcquisitionPassesMergesBeforeCommandBarrier() throws {
        var scheduler = LunaInteractiveInputScheduler()

        for index in 0..<20 {
            scheduler.ingest(
                [.textInput(LunaTextInputEvent(text: String(index % 10)))],
                acquiredAtNanoseconds: UInt64(index + 1),
                pollingStats: LunaInputPollingStats(
                    rawEventCount: 96,
                    translatedEventCount: 1,
                    didReachEventLimit: true
                )
            )
            XCTAssertNil(
                scheduler.nextDispatchBatch(
                    nowNanoseconds: UInt64(index + 1),
                    sourceIsIdle: false,
                    policy: LunaInteractivePresentationPolicy(
                        maximumCoalescedInputLatencyNanoseconds: 1_000_000,
                        maximumCoalescedTextUTF8ByteCount: 1_000
                    )
                )
            )
        }

        scheduler.ingest(
            .keyboard(
                LunaKeyboardEvent(
                    key: .other("s"),
                    modifiers: LunaKeyboardModifiers(control: true)
                )
            ),
            acquiredAtNanoseconds: 100
        )

        let batch = try XCTUnwrap(
            scheduler.nextDispatchBatch(
                nowNanoseconds: 100,
                sourceIsIdle: false,
                policy: policy
            )
        )
        XCTAssertEqual(batch.events.count, 2)
        guard case .textInput(let text) = batch.events[0],
              case .keyboard(let command) = batch.events[1]
        else {
            return XCTFail("Expected merged text followed by keyboard command")
        }
        XCTAssertEqual(text.text, "01234567890123456789")
        XCTAssertEqual(command.key, .other("s"))
        XCTAssertTrue(command.modifiers.control)
        XCTAssertEqual(batch.stats.emittedBarrierCount, 1)
    }

    func testCoalescedTextDispatchesAtLatencyDeadlineDuringSustainedInput() throws {
        var scheduler = LunaInteractiveInputScheduler()
        scheduler.ingest(
            [.textInput(LunaTextInputEvent(text: "abc"))],
            acquiredAtNanoseconds: 1_000,
            pollingStats: LunaInputPollingStats(
                rawEventCount: 96,
                translatedEventCount: 1,
                didReachEventLimit: true
            )
        )

        XCTAssertNil(
            scheduler.nextDispatchBatch(
                nowNanoseconds: 8_000_999,
                sourceIsIdle: false,
                policy: policy
            )
        )

        let batch = try XCTUnwrap(
            scheduler.nextDispatchBatch(
                nowNanoseconds: 8_001_000,
                sourceIsIdle: false,
                policy: policy
            )
        )
        XCTAssertEqual(batch.events, [.textInput(LunaTextInputEvent(text: "abc"))])
        XCTAssertFalse(batch.containsOrderingBarrier)
    }

    func testIdleSourceFlushesCoalescedTextImmediately() throws {
        var scheduler = LunaInteractiveInputScheduler()
        scheduler.ingest(
            [.textInput(LunaTextInputEvent(text: "ready"))],
            acquiredAtNanoseconds: 42
        )

        let batch = try XCTUnwrap(
            scheduler.nextDispatchBatch(
                nowNanoseconds: 42,
                sourceIsIdle: true,
                policy: policy
            )
        )
        XCTAssertEqual(batch.events, [.textInput(LunaTextInputEvent(text: "ready"))])
        XCTAssertFalse(scheduler.hasPendingInput)
    }

    func testConsecutiveResizeEventsCollapseWithoutCrossingOtherBarriers() throws {
        var scheduler = LunaInteractiveInputScheduler()
        scheduler.ingest(
            [
                .windowResized(LunaSizeI(width: 800, height: 600)),
                .windowResized(LunaSizeI(width: 900, height: 700)),
                .windowResized(LunaSizeI(width: 1_000, height: 800)),
            ],
            acquiredAtNanoseconds: 10
        )

        let batch = try XCTUnwrap(
            scheduler.nextDispatchBatch(
                nowNanoseconds: 10,
                sourceIsIdle: true,
                policy: policy
            )
        )
        XCTAssertEqual(batch.events, [.windowResized(LunaSizeI(width: 1_000, height: 800))])
    }


    func testRepeatedKeyboardBacklogWaitsForFreshCommandAcrossAcquisitionPasses() throws {
        var scheduler = LunaInteractiveInputScheduler()
        var timestamp: UInt64 = 1_000

        for _ in 0..<5 {
            let repeats = (0..<100).map { _ in
                LunaHostInputEvent.keyboard(
                    LunaKeyboardEvent(
                        key: .backspace,
                        modifiers: .none,
                        isRepeat: true
                    )
                )
            }
            scheduler.ingest(
                repeats,
                acquiredAtNanoseconds: timestamp,
                pollingStats: LunaInputPollingStats(
                    rawEventCount: repeats.count,
                    translatedEventCount: repeats.count,
                    didReachEventLimit: true
                )
            )
            timestamp += 1_000
            XCTAssertNil(
                scheduler.nextDispatchBatch(
                    nowNanoseconds: timestamp,
                    sourceIsIdle: false,
                    policy: policy
                )
            )
        }

        scheduler.ingest(
            .keyboard(
                LunaKeyboardEvent(
                    key: .arrowLeft,
                    modifiers: .none,
                    isRepeat: false
                )
            ),
            acquiredAtNanoseconds: timestamp
        )

        let batch = try XCTUnwrap(
            scheduler.nextDispatchBatch(
                nowNanoseconds: timestamp,
                sourceIsIdle: false,
                policy: policy
            )
        )
        XCTAssertEqual(batch.events.count, 501)
        XCTAssertTrue(batch.containsPromptDispatchEvent)
        XCTAssertEqual(batch.stats.acquisitionBatchCount, 5)
        guard case .keyboard(let finalEvent) = batch.events.last else {
            return XCTFail("Expected fresh navigation command after repeat backlog")
        }
        XCTAssertEqual(finalEvent.key, .arrowLeft)
        XCTAssertFalse(finalEvent.isRepeat)
    }

    func testSemanticWorkThresholdBoundsNonPromptRepeatBacklog() throws {
        var scheduler = LunaInteractiveInputScheduler()
        let repeats = (0..<12).map { _ in
            LunaHostInputEvent.keyboard(
                LunaKeyboardEvent(
                    key: .delete,
                    modifiers: .none,
                    isRepeat: true
                )
            )
        }
        scheduler.ingest(
            repeats,
            acquiredAtNanoseconds: 100,
            pollingStats: LunaInputPollingStats(
                rawEventCount: repeats.count,
                translatedEventCount: repeats.count,
                didReachEventLimit: true
            )
        )

        let thresholdPolicy = LunaInteractivePresentationPolicy(
            maximumCoalescedInputLatencyNanoseconds: 1_000_000,
            maximumCoalescedTextUTF8ByteCount: 1_000,
            maximumScheduledEventCount: 12
        )
        let batch = try XCTUnwrap(
            scheduler.nextDispatchBatch(
                nowNanoseconds: 100,
                sourceIsIdle: false,
                policy: thresholdPolicy
            )
        )
        XCTAssertEqual(batch.events, repeats)
        XCTAssertFalse(batch.containsPromptDispatchEvent)
        XCTAssertTrue(batch.containsOrderingBarrier)
    }

    func testCaptureLossIsImmediateControlBarrier() throws {
        var scheduler = LunaInteractiveInputScheduler()
        scheduler.ingest(
            [
                .pointer(LunaPointerEvent(phase: .moved, location: LunaPointI(x: 4, y: 5))),
                .pointerCaptureLost,
            ],
            acquiredAtNanoseconds: 5
        )

        let batch = try XCTUnwrap(
            scheduler.nextDispatchBatch(
                nowNanoseconds: 5,
                sourceIsIdle: false,
                policy: policy
            )
        )
        XCTAssertTrue(batch.containsOrderingBarrier)
        XCTAssertTrue(batch.containsImmediateControlEvent)
        XCTAssertEqual(batch.events.count, 2)
    }
}
