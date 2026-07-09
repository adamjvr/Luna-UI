import XCTest
import LunaAccessibility
import LunaInput
import LunaCore
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase3DTests: XCTestCase {
    func testEditableDocumentInsertsTextAtCaretAndMovesCaret() {
        var document = LunaEditableTextDocument(text: "hello")
        let caret = LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 5))

        let result = document.insertText(" world", caret: caret)

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(document.text, "hello world")
        XCTAssertEqual(result.newCaret.location, LunaTextLocation(lineIndex: 0, utf8Column: 11))
        XCTAssertEqual(document.staticDocument.lineCount, 1)
    }

    func testEditableDocumentReplacesMultiLineSelectionAndCollapsesSelection() {
        var state = LunaEditableTextState(
            text: "zero\none\ntwo",
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 0)),
            selection: LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 0, utf8Column: 2),
                    focus: LunaTextLocation(lineIndex: 1, utf8Column: 2)
                )
            )
        )

        let result = state.insertText("XX")

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(state.document.text, "zeXXe\ntwo")
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 4))
        XCTAssertEqual(state.editRevision, 1)
    }

    func testBackspaceAtLineStartMergesWithPreviousLine() {
        var state = LunaEditableTextState(
            text: "abc\ndef",
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 1, utf8Column: 0))
        )

        let result = state.deleteBackward()

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(state.document.text, "abcdef")
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 3))
        XCTAssertEqual(state.document.staticDocument.lineCount, 1)
    }

    func testDeleteForwardAtLineEndMergesWithNextLine() {
        var state = LunaEditableTextState(
            text: "abc\ndef",
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 3))
        )

        let result = state.deleteForward()

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(state.document.text, "abcdef")
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 3))
    }

    func testInsertNewlineSplitsLineAndCaretMovesToNewLine() {
        var state = LunaEditableTextState(
            text: "abcdef",
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 3))
        )

        let result = state.insertNewline()

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(state.document.text, "abc\ndef")
        XCTAssertEqual(result.newCaret.location, LunaTextLocation(lineIndex: 1, utf8Column: 0))
        XCTAssertEqual(state.document.staticDocument.lines.map(\.text), ["abc", "def"])
    }

    func testCaretMovementUsesDocumentUTF8OffsetsAcrossNewline() {
        var state = LunaEditableTextState(
            text: "ab\ncd",
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 1, utf8Column: 0))
        )

        state.moveCaretBackward()
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 2))

        state.moveCaretForward()
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 1, utf8Column: 0))
    }

    func testEditableTextViewReportsEditableAccessibilityNode() {
        let document = LunaEditableTextDocument(text: "editable")
        let view = LunaStaticTextView(
            id: "phase3d.text",
            bounds: LunaRectI(x: 0, y: 0, w: 200, h: 40),
            document: document.staticDocument,
            theme: .lunaDefaultDark,
            isFocused: true,
            isEditable: true,
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 4))
        )

        let node = view.buildAccessibilityNode()

        XCTAssertEqual(node.role, .textArea)
        XCTAssertEqual(node.value, "editable")
        XCTAssertTrue(node.isEditable)
        XCTAssertEqual(node.caretTextRange, LunaAccessibilityTextRange(utf8Offset: 4, utf8Length: 0))
    }

    func testTextInputHostEventCarriesCommittedTextSeparatelyFromKeys() {
        let event = LunaHostInputEvent.textInput(LunaTextInputEvent(text: "abc"))

        XCTAssertEqual(event, .textInput(LunaTextInputEvent(text: "abc")))
    }
}
