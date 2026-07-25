// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import LunaHostCore

final class LunaC25DFramePathDiagnosticsTests: XCTestCase {
    func testAnimationOnlyClassificationIsExact() {
        XCTAssertEqual(
            LunaFrameInvalidationClass(
                invalidations: LunaFrameInvalidationSet(.animation)
            ),
            .animationOnly
        )

        XCTAssertEqual(
            LunaFrameInvalidationClass(
                invalidations: LunaFrameInvalidationSet(
                    Set([.animation, .input])
                )
            ),
            .mixed
        )
    }

    func testTextEditBatchIsInputDriven() {
        let invalidations = LunaFrameInvalidationSet(
            Set([.textInput, .documentChanged, .selectionChanged])
        )

        XCTAssertEqual(
            LunaFrameInvalidationClass(invalidations: invalidations),
            .inputDriven
        )
    }

    func testResizeAndStateClassificationRemainDistinct() {
        XCTAssertEqual(
            LunaFrameInvalidationClass(
                invalidations: LunaFrameInvalidationSet(.windowResized)
            ),
            .resizeDriven
        )

        XCTAssertEqual(
            LunaFrameInvalidationClass(
                invalidations: LunaFrameInvalidationSet(
                    Set([.themeChanged, .overlayChanged])
                )
            ),
            .stateDriven
        )
    }

    func testTimingStatsRecordFramePathsAndCacheHitRate() {
        var stats = LunaFrameTimingStats()

        stats.record(
            LunaFrameTimingSample(
                frameIndex: 1,
                startedAtNanoseconds: 10,
                totalNanoseconds: 4_000_000,
                invalidations: LunaFrameInvalidationSet(.initial),
                renderReport: LunaFrameRenderReport(
                    path: .fullScene,
                    invalidationClass: .initial,
                    cacheMissReason: .cacheAbsent,
                    staticSceneNanoseconds: 3_000_000
                )
            )
        )

        stats.record(
            LunaFrameTimingSample(
                frameIndex: 2,
                startedAtNanoseconds: 20,
                totalNanoseconds: 1_000_000,
                invalidations: LunaFrameInvalidationSet(.animation),
                renderReport: LunaFrameRenderReport(
                    path: .cachedAnimation,
                    invalidationClass: .animationOnly,
                    cacheRestoreNanoseconds: 600_000,
                    dynamicSceneNanoseconds: 200_000
                )
            )
        )

        XCTAssertEqual(stats.renderPathCount(for: .fullScene), 1)
        XCTAssertEqual(stats.renderPathCount(for: .cachedAnimation), 1)
        XCTAssertEqual(stats.cacheMissCount(for: .cacheAbsent), 1)
        XCTAssertEqual(stats.cachedAnimationHitRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(stats.latestRenderReport?.path, .cachedAnimation)
    }

    func testNotApplicableFullFrameDoesNotDiluteCacheHitRate() {
        var stats = LunaFrameTimingStats()

        stats.record(
            LunaFrameTimingSample(
                frameIndex: 1,
                startedAtNanoseconds: 10,
                totalNanoseconds: 1,
                renderReport: LunaFrameRenderReport(
                    path: .fullScene,
                    invalidationClass: .inputDriven,
                    cacheMissReason: .notApplicable
                )
            )
        )

        XCTAssertEqual(stats.cachedAnimationHitRate, 0)
        XCTAssertEqual(stats.cacheEligibleFrameCount, 0)
    }
}
