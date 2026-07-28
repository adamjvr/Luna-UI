// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import LunaHostCore

final class LunaRuntimeWorkAttributionTests: XCTestCase {
    func testRecorderSeparatesRequestedAndActualVSync() {
        let recorder = LunaRuntimeWorkAttributionRecorder(environment: [:])
        recorder.recordRendererCapabilities(
            LunaSDLRendererCapabilities(
                rendererName: "software",
                querySucceeded: true,
                requestedFlags: 6,
                actualFlags: 1,
                isSoftware: true,
                vsyncWasRequested: true,
                hasPresentVSync: false
            )
        )
        let snapshot = recorder.snapshot
        XCTAssertEqual(snapshot.rendererCapabilities?.rendererName, "software")
        XCTAssertEqual(snapshot.rendererCapabilities?.vsyncWasRequested, true)
        XCTAssertEqual(snapshot.rendererCapabilities?.hasPresentVSync, false)
    }

    func testRecorderAttributesPollingDispatchFramesAndSleep() {
        let recorder = LunaRuntimeWorkAttributionRecorder(environment: [:])
        recorder.recordHostLoopIteration()
        recorder.recordPollingPass(
            rawEventCount: 9,
            translatedEventCount: 5,
            mayHavePendingEvents: true
        )
        recorder.recordDispatchSlice(
            LunaInputDispatchStats(
                processedEventCount: 3,
                remainingEventCount: 2,
                dispatchNanoseconds: 400,
                didReachEventLimit: true
            )
        )
        recorder.recordFrameRequest(
            hasInvalidations: true,
            wantsContinuousFrames: false
        )
        recorder.recordFrame(
            renderNanoseconds: 1_000,
            presentNanoseconds: 2_000,
            renderReport: LunaFrameRenderReport(
                path: .partialDamage,
                invalidationClass: .inputDriven
            )
        )
        recorder.recordIdleSleep(milliseconds: 8)
        recorder.recordSoftwarePacingSleep(milliseconds: 4)

        let snapshot = recorder.snapshot
        XCTAssertEqual(snapshot.hostLoopIterations, 1)
        XCTAssertEqual(snapshot.inputPollingPasses, 1)
        XCTAssertEqual(snapshot.rawNativeEventCount, 9)
        XCTAssertEqual(snapshot.translatedSemanticEventCount, 5)
        XCTAssertEqual(snapshot.semanticDispatchSlices, 1)
        XCTAssertEqual(snapshot.semanticEventsDispatched, 3)
        XCTAssertEqual(snapshot.maximumDeferredSemanticEvents, 2)
        XCTAssertEqual(snapshot.partialDamageFrameCount, 1)
        XCTAssertEqual(snapshot.totalRenderNanoseconds, 1_000)
        XCTAssertEqual(snapshot.totalPresentNanoseconds, 2_000)
        XCTAssertEqual(snapshot.idleSleepMilliseconds, 8)
        XCTAssertEqual(snapshot.softwarePacingSleepMilliseconds, 4)
    }
}
