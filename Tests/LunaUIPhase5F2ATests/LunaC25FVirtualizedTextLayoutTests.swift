// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaC25FVirtualizedTextLayoutTests: XCTestCase {
    func testViewportGeometryWorkIsIndependentOfDocumentLength() {
        let small = makeContext(lineCount: 50)
        let large = makeContext(lineCount: 50_000)
        let smallCounter = GeometryCounter()
        let largeCounter = GeometryCounter()

        let smallViewport = small.viewport(
            requestedTopVisualRow: 0,
            maxVisibleVisualRowCount: 30,
            overscanVisualRowCount: 2,
            viewportWidth: 320,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: CountingGeometryProvider(counter: smallCounter)
        )
        let largeViewport = large.viewport(
            requestedTopVisualRow: 0,
            maxVisibleVisualRowCount: 30,
            overscanVisualRowCount: 2,
            viewportWidth: 320,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: CountingGeometryProvider(counter: largeCounter)
        )

        XCTAssertEqual(smallViewport.visibleRows.count, 30)
        XCTAssertEqual(largeViewport.visibleRows.count, 30)
        XCTAssertEqual(smallCounter.requestCount, largeCounter.requestCount)
        XCTAssertLessThanOrEqual(large.cachedLineCount, 34)
        XCTAssertLessThanOrEqual(largeViewport.diagnostics.fullLineGeometryRequestCount, 34)
        XCTAssertLessThanOrEqual(largeViewport.diagnostics.segmentGeometryRequestCount, 34)
    }

    func testRepeatedViewportReusesLineAndSegmentGeometry() {
        let context = makeContext(lineCount: 50_000)
        let counter = GeometryCounter()
        let provider = CountingGeometryProvider(counter: counter)

        _ = context.viewport(
            requestedTopVisualRow: 100,
            maxVisibleVisualRowCount: 24,
            overscanVisualRowCount: 2,
            viewportWidth: 280,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: provider
        )
        let requestsAfterFirstLayout = counter.requestCount

        let second = context.viewport(
            requestedTopVisualRow: 100,
            maxVisibleVisualRowCount: 24,
            overscanVisualRowCount: 2,
            viewportWidth: 280,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: provider
        )

        XCTAssertEqual(counter.requestCount, requestsAfterFirstLayout)
        XCTAssertEqual(second.diagnostics.fullLineGeometryRequestCount, 0)
        XCTAssertEqual(second.diagnostics.segmentGeometryRequestCount, 0)
        XCTAssertGreaterThan(second.diagnostics.cacheHitCount, 0)
    }

    func testLastPageBackfillsToACompleteViewport() {
        let context = makeContext(lineCount: 5_000)
        let counter = GeometryCounter()
        let provider = CountingGeometryProvider(counter: counter)
        let initialTotal = context.estimatedTotalVisualRowCount(
            viewportWidth: 300,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8
        )

        let viewport = context.viewport(
            requestedTopVisualRow: initialTotal,
            maxVisibleVisualRowCount: 32,
            overscanVisualRowCount: 2,
            viewportWidth: 300,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: provider
        )

        XCTAssertEqual(viewport.visibleRows.count, 32)
        XCTAssertEqual(
            viewport.firstVisibleVisualRowIndex,
            viewport.maxScrollTopVisualRow
        )
        XCTAssertEqual(viewport.visibleRows.last?.line.index, 4_999)
        XCTAssertLessThanOrEqual(context.cachedLineCount, 36)
    }

    func testOneLongLineUsesLocalWrappedSegmentAnchors() {
        let text = String(repeating: "abcdefghij", count: 100)
        let presentation = LunaStaticTextPresentationSnapshot(
            revision: 1,
            text: text
        )
        let context = LunaStaticTextVirtualizationContext(
            presentation: presentation
        )
        let provider = CountingGeometryProvider(counter: GeometryCounter())

        let first = context.viewport(
            requestedTopVisualRow: 0,
            maxVisibleVisualRowCount: 8,
            viewportWidth: 80,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: provider
        )
        let scrolledAnchor = context.anchor(
            forGlobalVisualRow: 5,
            viewportWidth: 80,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8
        )
        let second = context.viewport(
            requestedTopVisualRow: 5,
            maxVisibleVisualRowCount: 8,
            viewportWidth: 80,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: provider
        )

        XCTAssertGreaterThan(first.totalVisualRowCount, 8)
        XCTAssertEqual(scrolledAnchor.logicalLineIndex, 0)
        XCTAssertEqual(scrolledAnchor.wrappedSegmentIndex, 5)
        XCTAssertEqual(second.firstVisibleAnchor.logicalLineIndex, 0)
        XCTAssertEqual(second.firstVisibleAnchor.wrappedSegmentIndex, 5)
    }

    func testZeroHeightViewportPerformsNoGeometryWork() {
        let context = makeContext(lineCount: 50_000)
        let counter = GeometryCounter()

        let viewport = context.viewport(
            requestedTopVisualRow: 0,
            maxVisibleVisualRowCount: 0,
            viewportWidth: 300,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: CountingGeometryProvider(counter: counter)
        )

        XCTAssertTrue(viewport.visibleRows.isEmpty)
        XCTAssertEqual(counter.requestCount, 0)
        XCTAssertEqual(context.cachedLineCount, 0)
    }

    func testLocationLookupShapesOnlyTheTargetLine() {
        let context = makeContext(lineCount: 50_000)
        let counter = GeometryCounter()

        let globalRow = context.globalVisualRow(
            containing: LunaTextLocation(lineIndex: 40_000, utf8Column: 7),
            viewportWidth: 240,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: CountingGeometryProvider(counter: counter)
        )

        XCTAssertGreaterThan(globalRow, 0)
        XCTAssertEqual(context.cachedLineCount, 1)
        XCTAssertEqual(counter.requestCount, 1)
    }


    func testStaticTextViewUsesVirtualizedContextInsteadOfWholeDocumentTraversal() {
        let presentation = LunaStaticTextPresentationSnapshot(
            revision: 7,
            text: (0..<50_000).map { "row \($0) payload" }.joined(separator: "\n")
        )
        let context = LunaStaticTextVirtualizationContext(presentation: presentation)
        let counter = GeometryCounter()
        let view = LunaStaticTextView(
            id: LunaNodeID(rawValue: "c2.5f.virtualized"),
            bounds: LunaRectI(x: 0, y: 0, w: 640, h: 480),
            document: presentation.document,
            scrollTopLine: 25_000,
            theme: .lunaDefaultDark,
            metrics: LunaStaticTextViewMetrics(
                contentInsets: LunaInsetsI(top: 8, right: 10, bottom: 8, left: 0),
                gutterWidth: 52,
                gutterPadding: 6,
                lineHeight: 16,
                glyphMetrics: LunaDebugTextMetrics(
                    scale: 1,
                    advance: 8,
                    lineHeight: 16
                ),
                scrollbarLaneWidth: 8,
                scrollbarPadding: 1,
                scrollbarThumbMinHeight: 14
            ),
            wrapMode: .soft,
            geometryProvider: CountingGeometryProvider(counter: counter),
            virtualizationContext: context
        )

        let layout = view.layout()

        XCTAssertFalse(layout.visibleLines.isEmpty)
        XCTAssertLessThan(layout.visibleLines.count, 64)
        XCTAssertLessThan(counter.requestCount, 128)
        XCTAssertLessThan(context.cachedLineCount, 64)
        XCTAssertGreaterThanOrEqual(layout.firstVisibleLineIndex, 24_900)
    }

    func testWidthAndGeometryCachesRemainBoundedDuringResizeChurn() {
        let context = LunaStaticTextVirtualizationContext(
            presentation: LunaStaticTextPresentationSnapshot(
                revision: 1,
                text: (0..<5_000).map { "line \($0) abcdefghijklmnopqrstuvwxyz" }.joined(separator: "\n")
            ),
            maximumRetainedWidthCount: 3,
            maximumRetainedLineCount: 48,
            maximumRetainedSegmentGeometryCount: 96
        )
        let provider = CountingGeometryProvider(counter: GeometryCounter())

        for width in stride(from: 180, through: 480, by: 20) {
            _ = context.viewport(
                requestedTopVisualRow: width,
                maxVisibleVisualRowCount: 24,
                overscanVisualRowCount: 2,
                viewportWidth: width,
                wrapMode: .soft,
                estimatedGlyphAdvance: 8,
                geometryProvider: provider
            )
        }

        XCTAssertLessThanOrEqual(context.cachedWidthCount, 3)
        XCTAssertLessThanOrEqual(context.cachedLineCount, 48)
        XCTAssertLessThanOrEqual(context.cachedSegmentGeometryCount, 96)
    }

    private func makeContext(lineCount: Int) -> LunaStaticTextVirtualizationContext {
        let text = (0..<lineCount)
            .map { "line \($0) abcdefghijklmnopqrstuvwxyz" }
            .joined(separator: "\n")
        return LunaStaticTextVirtualizationContext(
            presentation: LunaStaticTextPresentationSnapshot(
                revision: 1,
                text: text
            )
        )
    }
}

private final class GeometryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0

    func record() {
        lock.withLock { requests += 1 }
    }

    var requestCount: Int {
        lock.withLock { requests }
    }
}

private struct CountingGeometryProvider: LunaStaticTextGeometryProvider {
    let counter: GeometryCounter

    func geometry(
        for request: LunaStaticTextGeometryRequest
    ) -> LunaStaticTextRowGeometry {
        counter.record()
        return LunaStaticTextRowGeometry.fixedAdvance(
            sourceText: request.sourceText,
            advance: 8
        )
    }
}
