// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import LunaUI

final class LunaEditableFieldStateTests: XCTestCase {
    func testMovementAndDeletionRespectExtendedGraphemeBoundaries() {
        var field = LunaEditableFieldState(text: "Ae\u{301}B")
        field.moveBackward()
        XCTAssertEqual(field.caretUTF8Offset, 4)

        XCTAssertTrue(field.deleteBackward())
        XCTAssertEqual(field.text, "AB")
        XCTAssertEqual(field.caretUTF8Offset, 1)
    }

    func testSelectionReplacementUsesUTF8OffsetsAndCollapsesCaret() {
        var field = LunaEditableFieldState(text: "café")
        field.setCaret(utf8Offset: 0)
        field.setCaret(utf8Offset: 5, extendingSelection: true)

        XCTAssertEqual(field.selectedText, "café")
        XCTAssertTrue(field.replaceSelection(with: "Καφές"))
        XCTAssertEqual(field.text, "Καφές")
        XCTAssertFalse(field.hasSelection)
        XCTAssertEqual(field.caretUTF8Offset, "Καφές".utf8.count)
    }

    func testArrowWithoutShiftCollapsesDirectionalSelectionEdge() {
        var field = LunaEditableFieldState(text: "abcd")
        field.setCaret(utf8Offset: 1)
        field.setCaret(utf8Offset: 3, extendingSelection: true)

        field.moveBackward()
        XCTAssertEqual(field.caretUTF8Offset, 1)
        XCTAssertFalse(field.hasSelection)

        field.setCaret(utf8Offset: 1)
        field.setCaret(utf8Offset: 3, extendingSelection: true)
        field.moveForward()
        XCTAssertEqual(field.caretUTF8Offset, 3)
        XCTAssertFalse(field.hasSelection)
    }

    func testFindPanelFocusedFieldOwnsSelectionEditing() {
        let document = LunaStaticTextDocument(text: "cat dog cat")
        var panel = LunaFindPanelState(queryText: "cat", replaceText: "fox")
        panel.queryFieldState.selectAll()
        XCTAssertEqual(panel.selectedTextInFocusedField, "cat")

        XCTAssertTrue(panel.replaceSelectionInFocusedField(with: "dog"))
        panel.refreshResults(in: document)
        XCTAssertEqual(panel.queryText, "dog")
        XCTAssertEqual(panel.results.count, 1)

        panel.focusNextField()
        panel.selectAllInFocusedField()
        XCTAssertEqual(panel.selectedTextInFocusedField, "fox")
    }

    func testInvalidRegexProducesVisibleErrorState() {
        let document = LunaStaticTextDocument(text: "abc")
        let query = LunaFindQuery(
            text: "[",
            options: LunaFindOptions(usesRegularExpression: true)
        )
        let result = LunaFindScanner.results(in: document, query: query)

        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertTrue(result.statusText.contains("Invalid regular expression"))
    }
}
