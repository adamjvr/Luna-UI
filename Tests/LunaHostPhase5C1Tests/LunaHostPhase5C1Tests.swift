// SPDX-License-Identifier: MPL-2.0
import XCTest
import LunaRender
import LunaCore
import LunaInput
@testable import LunaHostCore

final class LunaHostPhase5C1Tests: XCTestCase {
    func testInvalidationSetTracksReasonsAndDescription() {
        var invalidations = LunaFrameInvalidationSet(.initial)
        XCTAssertTrue(invalidations.needsFrame)
        invalidations.insert(.textInput)
        invalidations.insert(.documentChanged)

        XCTAssertTrue(invalidations.reasons.contains(.initial))
        XCTAssertTrue(invalidations.reasons.contains(.textInput))
        XCTAssertTrue(invalidations.description.contains("documentChanged"))

        invalidations.removeAll()
        XCTAssertFalse(invalidations.needsFrame)
        XCTAssertEqual(invalidations.description, "none")
    }

    func testFrameRequestRendersForInvalidationOrContinuousMode() {
        XCTAssertTrue(LunaFrameRequest(invalidations: LunaFrameInvalidationSet(.input)).shouldRender)
        XCTAssertTrue(LunaFrameRequest(wantsContinuousFrames: true).shouldRender)
        XCTAssertFalse(LunaFrameRequest().shouldRender)
    }

    func testFrameTimingStatsCalculatesMovingAverageAndFps() {
        var stats = LunaFrameTimingStats(smoothingFactor: 0.5)
        stats.record(
            LunaFrameTimingSample(
                frameIndex: 1,
                startedAtNanoseconds: 10,
                renderNanoseconds: 4_000_000,
                presentNanoseconds: 2_000_000,
                totalNanoseconds: 16_000_000,
                invalidations: LunaFrameInvalidationSet(.initial)
            )
        )
        stats.record(
            LunaFrameTimingSample(
                frameIndex: 2,
                startedAtNanoseconds: 20,
                renderNanoseconds: 8_000_000,
                presentNanoseconds: 2_000_000,
                totalNanoseconds: 32_000_000,
                invalidations: LunaFrameInvalidationSet(.input)
            )
        )

        XCTAssertEqual(stats.sampleCount, 2)
        XCTAssertEqual(stats.latest?.frameIndex, 2)
        XCTAssertEqual(stats.worstRecent?.frameIndex, 2)
        XCTAssertEqual(stats.movingAverageFrameMilliseconds, 24.0, accuracy: 0.001)
        XCTAssertEqual(stats.movingAverageRenderMilliseconds, 6.0, accuracy: 0.001)
        XCTAssertTrue(stats.statusText.contains("fps"))
    }

    func testAnimationClockUsesDefaultDeltaForFirstFrame() {
        var clock = LunaAnimationClock(defaultDeltaSeconds: 1.0 / 60.0, maximumDeltaSeconds: 1.0 / 30.0)
        let frame = clock.advance(toNanoseconds: 1_000_000_000)

        XCTAssertEqual(frame.frameIndex, 1)
        XCTAssertEqual(frame.deltaSeconds, 1.0 / 60.0, accuracy: 0.000_001)
        XCTAssertEqual(clock.elapsedSeconds, 1.0 / 60.0, accuracy: 0.000_001)
        XCTAssertFalse(frame.wasDeltaClamped)
        XCTAssertTrue(clock.statusText.contains("anim"))
    }

    func testAnimationClockClampsLargeDeltaAfterStall() {
        var clock = LunaAnimationClock(defaultDeltaSeconds: 1.0 / 60.0, maximumDeltaSeconds: 1.0 / 30.0, startTimeNanoseconds: 1_000_000_000)
        let frame = clock.advance(toNanoseconds: 2_000_000_000)

        XCTAssertEqual(frame.rawDeltaSeconds, 1.0, accuracy: 0.000_001)
        XCTAssertEqual(frame.deltaSeconds, 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertTrue(frame.wasDeltaClamped)
        XCTAssertEqual(clock.elapsedSeconds, 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertTrue(frame.statusText.contains("clamped"))
    }

    func testAnimationClockResetDropsStaleTimestamp() {
        var clock = LunaAnimationClock(defaultDeltaSeconds: 0.25, maximumDeltaSeconds: 0.5, startTimeNanoseconds: 10)
        _ = clock.advance(toNanoseconds: 1_000_000_010)
        clock.reset()
        let frame = clock.advance(toNanoseconds: 3_000_000_000)

        XCTAssertEqual(frame.frameIndex, 1)
        XCTAssertEqual(frame.deltaSeconds, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(clock.elapsedSeconds, 0.25, accuracy: 0.000_001)
    }

    func testFramePacerDoesNotDoubleThrottleWhenExternalVSyncIsUsed() {
        var pacer = LunaFramePacer(targetFramesPerSecond: 60, usesExternalVSync: true)
        pacer.markFrameEnded(atNanoseconds: 1_000_000_000)

        XCTAssertEqual(pacer.sleepMillisecondsBeforeNextFrame(nowNanoseconds: 1_001_000_000), 0)
    }

    func testFramePacerComputesDelayWhenItOwnsFrameTiming() {
        var pacer = LunaFramePacer(targetFramesPerSecond: 50, usesExternalVSync: false)
        pacer.markFrameEnded(atNanoseconds: 1_000_000_000)

        // 50 FPS == 20 ms budget. If only 5 ms elapsed, about 15 ms remains.
        XCTAssertEqual(pacer.sleepMillisecondsBeforeNextFrame(nowNanoseconds: 1_005_000_000), 15)
        XCTAssertEqual(pacer.sleepMillisecondsBeforeNextFrame(nowNanoseconds: 1_025_000_000), 0)
    }

    func testMutableFramebufferPixelAccessReportsStrideNotByteCount() {
        var framebuffer = LunaFramebuffer(width: 8, height: 4)
        let height = framebuffer.height
        let expectedStride = framebuffer.bytesPerRow
        let expectedTotalBytes = framebuffer.bytesPerRow * height

        framebuffer.withUnsafeMutablePixelBytes { base, strideBytes in
            XCTAssertEqual(strideBytes, expectedStride)
            XCTAssertNotEqual(strideBytes, expectedTotalBytes)

            // Write a pixel on the final scanline to prove callers must compute
            // bounds as stride * height when drawing beyond row zero.
            let lastRowOffset = strideBytes * (height - 1)
            base[lastRowOffset] = 0xAA
        }

        framebuffer.withUnsafePixelBytes { base, strideBytes in
            let lastRowOffset = strideBytes * (height - 1)
            XCTAssertEqual(base[lastRowOffset], 0xAA)
        }
    }

    func testRawFramebufferUploadAccessorReportsTotalByteCount() {
        let framebuffer = LunaFramebuffer(width: 7, height: 5)
        var observedByteCount = 0

        framebuffer.withUnsafePixelBytes { rawPointer, byteCount in
            XCTAssertNotNil(rawPointer)
            observedByteCount = byteCount
        }

        XCTAssertEqual(observedByteCount, framebuffer.bytesPerRow * framebuffer.height)
    }

    func testFramebufferCopyPixelsCopiesWholeBuffer() {
        var source = LunaFramebuffer(width: 4, height: 3)
        var destination = LunaFramebuffer(width: 1, height: 1)

        source.fillRect(LunaRectI(x: 0, y: 0, w: 4, h: 3), color: LunaRGBA8(r: 1, g: 2, b: 3, a: 255))
        source.withUnsafeMutablePixelBytes { base, strideBytes in
            base[strideBytes * 2 + 3 * 4 + 0] = 0x44
            base[strideBytes * 2 + 3 * 4 + 1] = 0x55
            base[strideBytes * 2 + 3 * 4 + 2] = 0x66
            base[strideBytes * 2 + 3 * 4 + 3] = 0xFF
        }

        destination.copyPixels(from: source)

        XCTAssertEqual(destination.width, source.width)
        XCTAssertEqual(destination.height, source.height)
        destination.withUnsafePixelBytes { base, strideBytes in
            let offset = strideBytes * 2 + 3 * 4
            XCTAssertEqual(base[offset + 0], 0x44)
            XCTAssertEqual(base[offset + 1], 0x55)
            XCTAssertEqual(base[offset + 2], 0x66)
            XCTAssertEqual(base[offset + 3], 0xFF)
        }
    }

    func testRuntimeTickCarriesInvalidationSnapshot() {
        let tick = LunaRuntimeTick(tickIndex: 7, timestampNanoseconds: 42, invalidations: LunaFrameInvalidationSet(.asyncResult))

        XCTAssertEqual(tick.tickIndex, 7)
        XCTAssertEqual(tick.timestampNanoseconds, 42)
        XCTAssertTrue(tick.invalidations.reasons.contains(.asyncResult))
    }
    func testInputCoalescerKeepsOnlyLatestContiguousPointerMotion() {
        let coalescer = LunaHostInputCoalescer()
        let batch = coalescer.coalesce([
            .pointer(LunaPointerEvent(phase: .moved, location: LunaPointI(x: 1, y: 1))),
            .pointer(LunaPointerEvent(phase: .moved, location: LunaPointI(x: 2, y: 2))),
            .pointer(LunaPointerEvent(phase: .moved, location: LunaPointI(x: 3, y: 3))),
        ])

        XCTAssertEqual(batch.events.count, 1)
        if case .pointer(let pointer)? = batch.events.first {
            XCTAssertEqual(pointer.location, LunaPointI(x: 3, y: 3))
        } else {
            XCTFail("Expected latest pointer motion")
        }
        XCTAssertEqual(batch.stats.receivedEventCount, 3)
        XCTAssertEqual(batch.stats.emittedEventCount, 1)
        XCTAssertEqual(batch.stats.coalescedPointerMotionCount, 2)
    }

    func testInputCoalescerPreservesButtonAndKeyboardBoundaries() {
        let coalescer = LunaHostInputCoalescer()
        let batch = coalescer.coalesce([
            .pointer(LunaPointerEvent(phase: .moved, location: LunaPointI(x: 1, y: 1))),
            .pointer(LunaPointerEvent(phase: .moved, location: LunaPointI(x: 2, y: 2))),
            .pointer(LunaPointerEvent(phase: .down, location: LunaPointI(x: 2, y: 2))),
            .pointer(LunaPointerEvent(phase: .moved, location: LunaPointI(x: 8, y: 8))),
            .pointer(LunaPointerEvent(phase: .up, location: LunaPointI(x: 8, y: 8))),
            .keyboard(LunaKeyboardEvent(key: .escape)),
        ])

        XCTAssertEqual(batch.events.count, 5)
        XCTAssertEqual(batch.stats.coalescedPointerMotionCount, 1)

        if case .pointer(let first)? = batch.events.first {
            XCTAssertEqual(first.phase, .moved)
            XCTAssertEqual(first.location, LunaPointI(x: 2, y: 2))
        } else {
            XCTFail("Expected flushed latest pre-click motion")
        }

        if case .pointer(let drag) = batch.events[2] {
            XCTAssertEqual(drag.phase, .moved)
            XCTAssertEqual(drag.location, LunaPointI(x: 8, y: 8))
        } else {
            XCTFail("Expected latest drag motion before button up")
        }
    }

}

extension LunaHostPhase5C1Tests {
    func testScriptedDialogServiceReturnsQueuedOpenSaveAndUnsavedResults() {
        var dialogs = LunaScriptedDialogService(
            unsavedDecisions: [.discard],
            openPathSelections: [["/tmp/input.txt"]],
            savePathSelections: ["/tmp/output.txt"],
            scriptedSelectionsAllowOverwrite: true
        )

        let open = dialogs.chooseFileToOpen(
            LunaFileDialogRequest(purpose: .open, title: "Open…")
        )
        XCTAssertEqual(open.outcome, .selected)
        XCTAssertEqual(open.selectedPaths, ["/tmp/input.txt"])
        XCTAssertFalse(open.allowsOverwrite)

        let save = dialogs.chooseFileToSave(
            LunaFileDialogRequest(purpose: .save, title: "Save As…", defaultFileName: "Untitled.txt")
        )
        XCTAssertEqual(save.outcome, .selected)
        XCTAssertEqual(save.firstSelectedPath, "/tmp/output.txt")
        XCTAssertTrue(save.allowsOverwrite)

        let close = dialogs.confirmUnsavedChanges(
            LunaUnsavedChangesDialogRequest(title: "Untitled-1.txt", isUntitled: true)
        )
        XCTAssertEqual(close.decision, .discard)
    }

    func testNoOpDialogServiceFailsSafelyWithoutFabricatingPathsOrDiscardingChanges() {
        var dialogs = LunaNoOpDialogService()

        let open = dialogs.chooseFileToOpen(LunaFileDialogRequest(purpose: .open, title: "Open…"))
        let save = dialogs.chooseFileToSave(LunaFileDialogRequest(purpose: .save, title: "Save As…"))
        let close = dialogs.confirmUnsavedChanges(LunaUnsavedChangesDialogRequest(title: "Dirty.txt"))

        XCTAssertEqual(open.outcome, .unavailable)
        XCTAssertTrue(open.selectedPaths.isEmpty)
        XCTAssertEqual(save.outcome, .unavailable)
        XCTAssertTrue(save.selectedPaths.isEmpty)
        XCTAssertEqual(close.decision, .cancel)
    }
}
