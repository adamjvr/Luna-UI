// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import LunaUI

final class LunaC25CVisualRowIndexTests: XCTestCase {
    func testMixedRowCountsAndBinaryLookup() {
        let index = LunaStaticTextVisualRowIndex(visualRowCountsByLogicalLine: [1, 3, 2, 1])
        XCTAssertEqual(index.totalVisualRowCount, 7)
        XCTAssertEqual(index.span(forLogicalLine: 1)?.visualRowRange, 1..<4)
        XCTAssertEqual(index.address(forGlobalVisualRow: 3)?.logicalLineIndex, 1)
        XCTAssertEqual(index.address(forGlobalVisualRow: 3)?.wrappedSegmentIndex, 2)
        XCTAssertEqual(index.address(forGlobalVisualRow: 4)?.logicalLineIndex, 2)
    }

    func testViewportPlanningIsBounded() {
        let index = LunaStaticTextVisualRowIndex(unwrappedLogicalLineCount: 50_000)
        let plan = index.viewportPlan(requestedTopVisualRow: 20_000, maxVisibleVisualRowCount: 40, overscanVisualRowCount: 3)
        XCTAssertEqual(plan.visibleVisualRowRange, 20_000..<20_040)
        XCTAssertEqual(plan.materializedVisualRowRange, 19_997..<20_043)
        XCTAssertEqual(index.materializedAddresses(for: plan).count, 46)
        XCTAssertEqual(index.diagnostics.prefixEntryCount, 50_001)
    }

    func testEndClampAndZeroHeight() {
        let index = LunaStaticTextVisualRowIndex(visualRowCountsByLogicalLine: [1, 3, 2])
        XCTAssertEqual(index.address(forGlobalVisualRow: 999)?.globalVisualRowIndex, 5)
        let plan = index.viewportPlan(requestedTopVisualRow: 2, maxVisibleVisualRowCount: 0, overscanVisualRowCount: 10)
        XCTAssertTrue(plan.visibleVisualRowRange.isEmpty)
        XCTAssertTrue(plan.materializedVisualRowRange.isEmpty)
    }
}
