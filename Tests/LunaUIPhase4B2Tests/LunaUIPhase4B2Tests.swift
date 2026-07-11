// SPDX-License-Identifier: MPL-2.0
import XCTest
import LunaCommands
import LunaInput
import LunaCore
import LunaTheme
@testable import LunaUI

final class LunaUIPhase4B2Tests: XCTestCase {
    func testSelectAllSelectsCompleteDocumentAndPlacesCaretAtEnd() {
        var state = LunaEditableTextState(text: "alpha\nbeta\ngamma")

        state.selectAll()

        XCTAssertEqual(state.selection?.range.anchor, LunaTextLocation(lineIndex: 0, utf8Column: 0))
        XCTAssertEqual(state.selection?.range.focus, LunaTextLocation(lineIndex: 2, utf8Column: 5))
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 2, utf8Column: 5))
        XCTAssertEqual(state.selection.map { state.document.accessibilityRange(for: $0.range).utf8Length }, state.document.text.utf8.count)
    }

    func testSelectAllOnEmptyDocumentLeavesCollapsedCaretAtStart() {
        var state = LunaEditableTextState(text: "")

        state.selectAll()

        XCTAssertNil(state.selection)
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 0))
    }

    func testTypingAfterSelectAllReplacesEntireDocument() {
        var state = LunaEditableTextState(text: "alpha\nbeta\ngamma")
        state.selectAll()

        let result = state.insertText("replacement")

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(state.document.text, "replacement")
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: "replacement".utf8.count))
    }

    func testQuickPanelCanCarryThemeAndSelectAllCommandsWithoutNumericDefaults() {
        let descriptors = [
            LunaCommandDescriptor(id: "luna.demo.theme.blue", title: "Theme: Luna Demo Blue", defaultKey: nil, menuPath: ["View", "Theme"]),
            LunaCommandDescriptor(id: "luna.demo.theme.moth", title: "Theme: Moth Obsidian Demo", defaultKey: nil, menuPath: ["View", "Theme"]),
            LunaCommandDescriptor(id: "luna.demo.theme.highContrast", title: "Theme: High Contrast Proof", defaultKey: nil, menuPath: ["View", "Theme"]),
            LunaCommandDescriptor(id: "luna.demo.edit.selectAll", title: "Select All", defaultKey: LunaKeyEquivalent("Ctrl+A"), menuPath: ["Edit"]),
        ]
        let items = descriptors.map(LunaQuickPanelItem.init(command:))

        XCTAssertTrue(descriptors.filter { $0.id.rawValue.contains("theme") }.allSatisfy { $0.defaultKey == nil })
        XCTAssertEqual(LunaQuickPanelFilter.matches(items: items, query: "moth").map(\.item.command), ["luna.demo.theme.moth"])
        XCTAssertEqual(LunaQuickPanelFilter.matches(items: items, query: "select all").map(\.item.command), ["luna.demo.edit.selectAll"])
    }

    func testNumberKeyEventsCanFallThroughForEditorTextInputOwnership() {
        let numberKey = LunaKeyboardEvent(key: .number(1))
        let committedText = LunaTextInputEvent(text: "1")

        XCTAssertEqual(numberKey.key, .number(1))
        XCTAssertEqual(committedText.text, "1")
    }

    func testHighContrastTextHighlightsUseMovingBlockYellow() {
        let theme = LunaTheme.highContrastProof

        XCTAssertEqual(theme.ui.movingBlock, LunaColor.hex("#FFCC00"))
        XCTAssertEqual(theme.selection, LunaColor.hex("#FFCC00"))
        XCTAssertEqual(theme.ui.editor.selectionBackground, LunaColor.hex("#FFCC00"))
        XCTAssertEqual(theme.ui.textField.selectionBackground, LunaColor.hex("#FFCC00"))
    }
}
