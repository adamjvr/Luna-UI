// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaRender
@testable import LunaHostCore

final class LunaC25D2PartialDamageTests: XCTestCase {
    func testRectangularFramebufferRestoreClipsAndPreservesOutsidePixels() {
        let sourceColor = LunaRGBA8(r: 10, g: 20, b: 30, a: 255)
        let destinationColor = LunaRGBA8(r: 1, g: 2, b: 3, a: 255)

        var source = LunaFramebuffer(width: 8, height: 8)
        var destination = LunaFramebuffer(width: 8, height: 8)
        source.clear(sourceColor)
        destination.clear(destinationColor)

        let copiedPixels = destination.copyPixels(
            from: source,
            in: LunaRectI(x: 2, y: 3, w: 3, h: 2)
        )

        XCTAssertEqual(copiedPixels, 6)
        XCTAssertEqual(pixelBytes(in: destination, x: 2, y: 3), pixelBytes(in: source, x: 2, y: 3))
        XCTAssertEqual(pixelBytes(in: destination, x: 4, y: 4), pixelBytes(in: source, x: 4, y: 4))
        XCTAssertNotEqual(pixelBytes(in: destination, x: 1, y: 3), pixelBytes(in: source, x: 1, y: 3))
        XCTAssertNotEqual(pixelBytes(in: destination, x: 5, y: 4), pixelBytes(in: source, x: 5, y: 4))
    }

    func testRectangularRestoreReportsActualClippedPixels() {
        var source = LunaFramebuffer(width: 5, height: 5)
        var destination = LunaFramebuffer(width: 5, height: 5)
        source.clear(LunaRGBA8(r: 255, g: 255, b: 255, a: 255))
        destination.clear(LunaRGBA8(r: 0, g: 0, b: 0, a: 255))

        let copiedPixels = destination.copyPixels(
            from: source,
            in: LunaRectI(x: -2, y: 3, w: 5, h: 5)
        )

        XCTAssertEqual(copiedPixels, 6)
    }

    func testPartialDamageCountsAsAStaticCacheHit() {
        var stats = LunaFrameTimingStats()

        stats.record(
            LunaFrameTimingSample(
                frameIndex: 1,
                startedAtNanoseconds: 0,
                totalNanoseconds: 1,
                renderReport: LunaFrameRenderReport(
                    path: .partialDamage,
                    invalidationClass: .animationOnly,
                    cacheRestoreNanoseconds: 1,
                    dynamicSceneNanoseconds: 1,
                    damagedRegionCount: 3,
                    damagedPixelCount: 1_024
                )
            )
        )

        XCTAssertEqual(stats.renderPathCount(for: .partialDamage), 1)
        XCTAssertEqual(stats.cacheEligibleFrameCount, 1)
        XCTAssertEqual(stats.cachedAnimationHitRate, 1, accuracy: 0.0001)
        XCTAssertEqual(stats.latestRenderReport?.damagedRegionCount, 3)
        XCTAssertTrue(stats.latestRenderReport?.usedStaticAnimationCache == true)
    }

    private func pixelBytes(
        in framebuffer: LunaFramebuffer,
        x: Int,
        y: Int
    ) -> [UInt8] {
        framebuffer.withUnsafePixelBytes { base, stride in
            let first = base.advanced(by: y * stride + x * 4)
            return Array(UnsafeBufferPointer(start: first, count: 4))
        }
    }
}
