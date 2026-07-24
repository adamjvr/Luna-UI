// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import LunaUI

final class LunaC25APresentationSnapshotTests: XCTestCase {
    func testUnwrappedPlanMaterializesOnlyViewportAndBoundedOverscan() {
        let text = (0..<50_000).map { "line \($0)" }.joined(separator: "\n")
        let snapshot = LunaStaticTextPresentationSnapshot(revision: 7, text: text)

        let plan = snapshot.unwrappedViewportPlan(
            requestedTopLine: 24_000,
            maxVisibleLineCount: 40,
            overscanLineCount: 3
        )

        XCTAssertEqual(snapshot.logicalLineCount, 50_000)
        XCTAssertEqual(plan.totalVisualRowCount, 50_000)
        XCTAssertEqual(plan.visibleLineRange, 24_000..<24_040)
        XCTAssertEqual(plan.materializedLineRange, 23_997..<24_043)
        XCTAssertEqual(plan.materializedLineCount, 46)
        XCTAssertLessThan(plan.materializedLineCount, snapshot.logicalLineCount / 100)

        let lines = snapshot.materializedLines(for: plan)
        XCTAssertEqual(lines.first?.index, 23_997)
        XCTAssertEqual(lines.last?.index, 24_042)
    }

    func testPlanClampsScrollPositionAtDocumentEnd() {
        let snapshot = LunaStaticTextPresentationSnapshot(
            revision: 1,
            text: (0..<100).map(String.init).joined(separator: "\n")
        )

        let plan = snapshot.unwrappedViewportPlan(
            requestedTopLine: 10_000,
            maxVisibleLineCount: 20,
            overscanLineCount: 2
        )

        XCTAssertEqual(plan.maxScrollTopLine, 80)
        XCTAssertEqual(plan.firstVisibleLineIndex, 80)
        XCTAssertEqual(plan.visibleLineRange, 80..<100)
        XCTAssertEqual(plan.materializedLineRange, 78..<100)
    }

    func testEmptyViewportPerformsNoMaterialization() {
        let snapshot = LunaStaticTextPresentationSnapshot(
            revision: 1,
            text: "alpha\nbeta"
        )

        let plan = snapshot.unwrappedViewportPlan(
            requestedTopLine: 1,
            maxVisibleLineCount: 0
        )

        XCTAssertTrue(plan.visibleLineRange.isEmpty)
        XCTAssertTrue(plan.materializedLineRange.isEmpty)
        XCTAssertEqual(plan.materializedLineCount, 0)
    }

    func testSnapshotPreservesRevisionAndReferenceIdentity() {
        let snapshot = LunaStaticTextPresentationSnapshot(revision: 42, text: "text")
        let alias = snapshot

        XCTAssertEqual(snapshot.revision, 42)
        XCTAssertTrue(snapshot === alias)
    }
}
