// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import LunaUI

final class LunaC25BSingleShapeWrapIndexTests: XCTestCase {
    func testRecordLookupUsesHalfOpenRanges() {
        let index = LunaStaticTextWrapIndex(
            sourceUTF8Length: 12,
            viewportWidth: 40,
            records: [
                LunaStaticTextWrapRecord(visualRowIndex: 0, utf8Range: 0..<4),
                LunaStaticTextWrapRecord(visualRowIndex: 1, utf8Range: 4..<9),
                LunaStaticTextWrapRecord(visualRowIndex: 2, utf8Range: 9..<12),
            ],
            diagnostics: LunaStaticTextWrapBuildDiagnostics(
                graphemeBoundaryCount: 13,
                widthProbeCount: 8,
                emittedRecordCount: 3
            )
        )

        XCTAssertEqual(index.visualRowIndex(containingUTF8Column: 0), 0)
        XCTAssertEqual(index.visualRowIndex(containingUTF8Column: 4), 1)
        XCTAssertEqual(index.visualRowIndex(containingUTF8Column: 11), 2)
        XCTAssertEqual(index.visualRowIndex(containingUTF8Column: 12), 2)
    }

    func testEmptyLineStillHasOneVisualRow() {
        let index = LunaStaticTextWrapIndex(
            sourceUTF8Length: 0,
            viewportWidth: 80,
            records: [LunaStaticTextWrapRecord(visualRowIndex: 0, utf8Range: 0..<0)],
            diagnostics: LunaStaticTextWrapBuildDiagnostics(
                graphemeBoundaryCount: 1,
                widthProbeCount: 0,
                emittedRecordCount: 1
            )
        )

        XCTAssertEqual(index.visualRowCount, 1)
        XCTAssertEqual(index.visualRowIndex(containingUTF8Column: 0), 0)
    }

    func testRecordsPreserveContiguousCoverage() {
        let index = LunaStaticTextWrapIndex(
            sourceUTF8Length: 10,
            viewportWidth: 24,
            records: [
                LunaStaticTextWrapRecord(visualRowIndex: 0, utf8Range: 0..<3),
                LunaStaticTextWrapRecord(visualRowIndex: 1, utf8Range: 3..<7),
                LunaStaticTextWrapRecord(visualRowIndex: 2, utf8Range: 7..<10),
            ],
            diagnostics: LunaStaticTextWrapBuildDiagnostics(
                graphemeBoundaryCount: 11,
                widthProbeCount: 7,
                emittedRecordCount: 3
            )
        )

        XCTAssertEqual(index.records.first?.startUTF8Column, 0)
        XCTAssertEqual(index.records.last?.endUTF8Column, index.sourceUTF8Length)
        for pair in zip(index.records, index.records.dropFirst()) {
            XCTAssertEqual(pair.0.endUTF8Column, pair.1.startUTF8Column)
        }
    }
}
