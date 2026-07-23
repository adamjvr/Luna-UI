// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaA1AuditTests: XCTestCase {
    private let metrics = LunaStaticTextViewMetrics(
        contentInsets: LunaInsetsI(top: 0, right: 0, bottom: 0, left: 0),
        gutterWidth: 0,
        gutterPadding: 0,
        lineHeight: 12,
        glyphMetrics: LunaDebugTextMetrics(scale: 1, advance: 6, lineHeight: 12),
        scrollbarLaneWidth: 8,
        scrollbarPadding: 1,
        scrollbarThumbMinHeight: 8
    )

    override func setUp() {
        super.setUp()
        LunaA1AuditRecorder.shared.reset()
    }

    func testRecorderResetAndSnapshotAreStable() throws {
        let recorder = LunaA1AuditRecorder.shared
        recorder.record(.geometryRequests, by: 7)
        recorder.recordDuration(label: "sample", nanoseconds: 42)

        let before = recorder.snapshot()
        XCTAssertEqual(before[.geometryRequests], 7)
        XCTAssertEqual(before.durationsNanoseconds["sample"], 42)
        XCTAssertNoThrow(try before.jsonData())

        recorder.reset()
        let after = recorder.snapshot()
        XCTAssertEqual(after[.geometryRequests], 0)
        XCTAssertTrue(after.durationsNanoseconds.isEmpty)
    }

    func testStaticTextAuditRecordsDocumentAndVisibleRowCounts() {
        let text = (0..<50).map { "line \($0)" }.joined(separator: "\n")
        let view = LunaStaticTextView(
            id: "a1.lines",
            bounds: LunaRectI(x: 0, y: 0, w: 300, h: 60),
            document: LunaStaticTextDocument(text: text),
            theme: .lunaDefaultDark,
            metrics: metrics,
            wrapMode: .none
        )

        let layout = LunaA1StaticTextAudit.layout(view)
        let snapshot = LunaA1AuditRecorder.shared.snapshot()

        XCTAssertEqual(snapshot[.staticTextLayoutPasses], 1)
        XCTAssertEqual(snapshot[.logicalLinesPresentedToLayout], 50)
        XCTAssertEqual(snapshot[.visualRowsProduced], UInt64(layout.totalVisualRowCount))
        XCTAssertEqual(snapshot[.visibleRowsProduced], UInt64(layout.visibleLines.count))
        XCTAssertGreaterThan(snapshot.durationsNanoseconds["luna.staticText.layout", default: 0], 0)
    }

    func testCountingGeometryProviderObservesSuffixRequestsFromSoftWrap() {
        let base = FixedGeometryProvider()
        let counting = LunaA1CountingGeometryProvider(base: base)
        let line = String(repeating: "abcdefghij ", count: 20)
        let view = LunaStaticTextView(
            id: "a1.wrap",
            bounds: LunaRectI(x: 0, y: 0, w: 72, h: 72),
            document: LunaStaticTextDocument(text: line),
            theme: .lunaDefaultDark,
            metrics: metrics,
            wrapMode: .soft,
            geometryProvider: counting
        )

        _ = LunaA1StaticTextAudit.layout(view)
        let snapshot = LunaA1AuditRecorder.shared.snapshot()
        XCTAssertGreaterThan(snapshot[.geometryRequests], 1)
        XCTAssertGreaterThan(snapshot[.suffixGeometryRequests], 0)
    }

    func testFramebufferWrappersReportExactByteAndPixelCounts() {
        var source = LunaFramebuffer(width: 20, height: 10)
        var destination = LunaFramebuffer(width: 1, height: 1)

        LunaA1FramebufferAudit.clear(
            &source,
            color: LunaRGBA8(r: 0, g: 0, b: 0)
        )
        LunaA1FramebufferAudit.fillRect(
            LunaRectI(x: 2, y: 3, w: 8, h: 4),
            color: LunaRGBA8(r: 255, g: 255, b: 255),
            in: &source
        )
        LunaA1FramebufferAudit.copyPixels(from: source, into: &destination)

        let snapshot = LunaA1AuditRecorder.shared.snapshot()
        XCTAssertEqual(snapshot[.framebufferClears], 1)
        XCTAssertEqual(snapshot[.framebufferClearBytes], 20 * 10 * 4)
        XCTAssertEqual(snapshot[.framebufferRectangleFills], 1)
        XCTAssertEqual(snapshot[.framebufferRectanglePixels], 8 * 4)
        XCTAssertEqual(snapshot[.framebufferCopies], 1)
        XCTAssertEqual(snapshot[.framebufferCopyBytes], 20 * 10 * 4)
        XCTAssertEqual(destination.width, 20)
        XCTAssertEqual(destination.height, 10)
    }
}

private struct FixedGeometryProvider: LunaStaticTextGeometryProvider, Sendable {
    func geometry(for request: LunaStaticTextGeometryRequest) -> LunaStaticTextRowGeometry {
        LunaStaticTextRowGeometry.fixedAdvance(sourceText: request.sourceText, advance: 6)
    }
}
