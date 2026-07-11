// SPDX-License-Identifier: MPL-2.0
import XCTest
import LunaAccessibility
import LunaInput
import LunaCore
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase4B1Tests: XCTestCase {
    private func metrics() -> LunaStaticTextViewMetrics {
        LunaStaticTextViewMetrics(
            contentInsets: LunaInsetsI(top: 0, right: 0, bottom: 0, left: 0),
            gutterWidth: 30,
            gutterPadding: 0,
            lineHeight: 12,
            glyphMetrics: .body
        )
    }

    func testEditableStateSetsDirectionalSelectionAndCaretAtFocus() {
        var state = LunaEditableTextState(
            text: "alpha\nbeta\ngamma",
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 1))
        )

        state.setSelection(
            LunaTextRange(
                anchor: LunaTextLocation(lineIndex: 2, utf8Column: 3),
                focus: LunaTextLocation(lineIndex: 0, utf8Column: 2)
            )
        )

        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 2))
        XCTAssertEqual(state.selection?.range.anchor, LunaTextLocation(lineIndex: 2, utf8Column: 3))
        XCTAssertEqual(state.selection?.range.focus, LunaTextLocation(lineIndex: 0, utf8Column: 2))
        XCTAssertEqual(state.selection?.range.normalized.anchor, LunaTextLocation(lineIndex: 0, utf8Column: 2))
        XCTAssertEqual(state.selection?.range.normalized.focus, LunaTextLocation(lineIndex: 2, utf8Column: 3))
    }

    func testCollapsedSelectionClearsSelectionButKeepsCaret() {
        var state = LunaEditableTextState(text: "alpha")

        state.setSelection(
            LunaTextRange(
                anchor: LunaTextLocation(lineIndex: 0, utf8Column: 2),
                focus: LunaTextLocation(lineIndex: 0, utf8Column: 2)
            )
        )

        XCTAssertNil(state.selection)
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 2))
    }

    func testBeginAndExtendSelectionUsesCaretAsAnchor() {
        var state = LunaEditableTextState(text: "abcdef")

        state.beginSelection(at: LunaTextLocation(lineIndex: 0, utf8Column: 1))
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 1))

        state.extendSelection(to: LunaTextLocation(lineIndex: 0, utf8Column: 4))
        XCTAssertEqual(state.selection?.range.anchor, LunaTextLocation(lineIndex: 0, utf8Column: 1))
        XCTAssertEqual(state.selection?.range.focus, LunaTextLocation(lineIndex: 0, utf8Column: 4))
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 4))
    }

    func testShiftArrowExtendsSelectionAndPlainArrowCollapsesIt() {
        var state = LunaEditableTextState(
            text: "abcdef",
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 3))
        )

        state.moveCaretForward(extendingSelection: true)
        XCTAssertEqual(state.selection?.range.anchor, LunaTextLocation(lineIndex: 0, utf8Column: 3))
        XCTAssertEqual(state.selection?.range.focus, LunaTextLocation(lineIndex: 0, utf8Column: 4))

        state.moveCaretForward(extendingSelection: true)
        XCTAssertEqual(state.selection?.range.focus, LunaTextLocation(lineIndex: 0, utf8Column: 5))

        state.moveCaretBackward()
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 3))
    }

    func testPlainRightArrowCollapsesSelectionToNormalizedFocus() {
        var state = LunaEditableTextState(text: "abcdef")
        state.setSelection(
            LunaTextRange(
                anchor: LunaTextLocation(lineIndex: 0, utf8Column: 5),
                focus: LunaTextLocation(lineIndex: 0, utf8Column: 2)
            )
        )

        state.moveCaretForward()

        XCTAssertNil(state.selection)
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 5))
    }

    func testSelectionReplacementAndDeletionReuseInteractiveSelection() {
        var state = LunaEditableTextState(text: "hello world")
        state.setSelection(
            LunaTextRange(
                anchor: LunaTextLocation(lineIndex: 0, utf8Column: 6),
                focus: LunaTextLocation(lineIndex: 0, utf8Column: 11)
            )
        )

        let replace = state.insertText("Luna")
        XCTAssertTrue(replace.didChange)
        XCTAssertEqual(state.document.text, "hello Luna")
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 10))

        state.setSelection(
            LunaTextRange(
                anchor: LunaTextLocation(lineIndex: 0, utf8Column: 5),
                focus: LunaTextLocation(lineIndex: 0, utf8Column: 10)
            )
        )
        let delete = state.deleteBackward()
        XCTAssertTrue(delete.didChange)
        XCTAssertEqual(state.document.text, "hello")
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 5))
    }

    func testUserSelectionStillRendersWithThemeSelectionColorSeparateFromFindHighlights() {
        var colors = LunaUIThemeColors.lunaDefaultDark
        colors.editor.selectionBackground = .hex("#003CFFAA")
        let theme = LunaTheme(
            name: "Phase 4B.1 Selection Proof",
            background: colors.editor.background,
            foreground: colors.editor.foreground,
            caret: colors.editor.caret,
            selection: colors.editor.selectionBackground,
            ui: colors
        )
        let view = LunaStaticTextView(
            id: "phase4b1.text",
            bounds: LunaRectI(x: 0, y: 0, w: 180, h: 24),
            document: LunaStaticTextDocument(text: "alpha beta"),
            theme: theme,
            metrics: metrics(),
            selection: LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 0, utf8Column: 0),
                    focus: LunaTextLocation(lineIndex: 0, utf8Column: 5)
                )
            ),
            highlights: [
                LunaStaticTextHighlight(
                    range: LunaTextRange(
                        anchor: LunaTextLocation(lineIndex: 0, utf8Column: 6),
                        focus: LunaTextLocation(lineIndex: 0, utf8Column: 10)
                    ),
                    color: .hex("#88899144")
                )
            ]
        )

        let layout = view.layout()
        var displayList = LunaDisplayList()
        view.buildDisplayList(into: &displayList)

        XCTAssertEqual(layout.selectionRects.count, 1)
        XCTAssertEqual(layout.highlightRects.count, 1)
        XCTAssertTrue(displayList.commands.contains(.rect(layout.selectionRects[0].bounds, LunaRender.LunaRGBA8(r: 0, g: 60, b: 255, a: 170))))
        XCTAssertTrue(displayList.commands.contains(.rect(layout.highlightRects[0].selectionRect.bounds, LunaRender.LunaRGBA8(r: 136, g: 137, b: 145, a: 68))))
    }

    func testPointerEventsCarryModifiersForShiftClickSelectionGestures() {
        let event = LunaPointerEvent(
            phase: .down,
            location: LunaPointI(x: 10, y: 20),
            button: .primary,
            clickCount: 1,
            modifiers: LunaKeyboardModifiers(shift: true)
        )

        XCTAssertTrue(event.modifiers.shift)
        XCTAssertFalse(event.modifiers.control)
    }
}
