// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIConvergenceC1BTests: XCTestCase {
    private func view(
        text: String,
        width: Int = 280,
        height: Int = 180,
        scrollTopVisualRow: Int? = 0
    ) -> LunaStaticTextView {
        LunaStaticTextView(
            id: "editor",
            bounds: LunaRectI(x: 0, y: 0, w: width, h: height),
            document: LunaStaticTextDocument(text: text),
            scrollTopVisualRow: scrollTopVisualRow,
            theme: .highContrastProof,
            wrapMode: .soft,
            isFocused: true,
            isEditable: true,
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 0))
        )
    }

    private func point(
        in view: LunaStaticTextView,
        visualRow: Int,
        visualCharacter: Int
    ) throws -> LunaPointI {
        let row = try XCTUnwrap(view.layout().visibleLines[safe: visualRow])
        return LunaPointI(
            x: row.textBounds.x + visualCharacter * view.metrics.glyphMetrics.advance + 1,
            y: row.rowBounds.y + max(1, row.rowBounds.h / 2)
        )
    }

    func testSingleClickAndShiftClickPreserveDirectionAwareAnchor() throws {
        let textView = view(text: "alpha beta")
        var state = LunaTextSelectionInteractionState()
        let firstPoint = try point(in: textView, visualRow: 0, visualCharacter: 1)

        let first = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: firstPoint, clickCount: 1),
            in: textView,
            currentCaret: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            currentSelection: nil,
            state: &state,
            timestampNanoseconds: 1
        )
        XCTAssertEqual(first.selection, LunaTextRange(
            anchor: LunaTextLocation(lineIndex: 0, utf8Column: 1),
            focus: LunaTextLocation(lineIndex: 0, utf8Column: 1)
        ))
        XCTAssertTrue(state.wantsPointerCapture)

        _ = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(phase: .up, location: firstPoint, clickCount: 1),
            in: textView,
            currentCaret: first.selection!.focus,
            currentSelection: nil,
            state: &state,
            timestampNanoseconds: 2
        )
        XCTAssertFalse(state.wantsPointerCapture)

        let existing = LunaTextRange(
            anchor: LunaTextLocation(lineIndex: 0, utf8Column: 1),
            focus: LunaTextLocation(lineIndex: 0, utf8Column: 3)
        )
        let laterPoint = try point(in: textView, visualRow: 0, visualCharacter: 8)
        let extended = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
                location: laterPoint,
                clickCount: 1,
                modifiers: LunaKeyboardModifiers(shift: true)
            ),
            in: textView,
            currentCaret: existing.focus,
            currentSelection: existing,
            state: &state,
            timestampNanoseconds: 3
        )
        XCTAssertEqual(extended.selection?.anchor, existing.anchor)
        XCTAssertGreaterThan(extended.selection?.focus.utf8Column ?? 0, existing.focus.utf8Column)
    }

    func testDoubleClickSelectsUnicodeWordOnExactUTF8Boundaries() throws {
        let textView = view(text: "héllo world")
        var state = LunaTextSelectionInteractionState()
        let click = try point(in: textView, visualRow: 0, visualCharacter: 2)

        let result = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: click, clickCount: 2),
            in: textView,
            currentCaret: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            currentSelection: nil,
            state: &state,
            timestampNanoseconds: 1
        )

        XCTAssertEqual(state.granularity, .word)
        XCTAssertEqual(result.selection, LunaTextRange(
            anchor: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            focus: LunaTextLocation(lineIndex: 0, utf8Column: 6)
        ))
    }

    func testTripleClickSelectsLogicalLineIncludingNewline() throws {
        let textView = view(text: "one\ntwo")
        var state = LunaTextSelectionInteractionState()
        let click = try point(in: textView, visualRow: 0, visualCharacter: 1)

        let result = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: click, clickCount: 3),
            in: textView,
            currentCaret: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            currentSelection: nil,
            state: &state,
            timestampNanoseconds: 1
        )

        XCTAssertEqual(state.granularity, .line)
        XCTAssertEqual(result.selection, LunaTextRange(
            anchor: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            focus: LunaTextLocation(lineIndex: 1, utf8Column: 0)
        ))
        XCTAssertEqual(textView.document.accessibilityRange(for: result.selection!).utf8Length, 4)
    }

    func testDragSelectionCrossesSoftWrappedContinuationRows() throws {
        let text = String(repeating: "wrapped selection ", count: 12)
        let textView = view(text: text, width: 180, height: 180)
        let layout = textView.layout()
        XCTAssertGreaterThan(layout.visibleLines.count, 2)

        var state = LunaTextSelectionInteractionState()
        let start = try point(in: textView, visualRow: 0, visualCharacter: 0)
        let end = try point(in: textView, visualRow: 2, visualCharacter: 4)
        _ = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: start),
            in: textView,
            currentCaret: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            currentSelection: nil,
            state: &state,
            timestampNanoseconds: 1
        )
        let drag = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(phase: .moved, location: end, clickCount: 0),
            in: textView,
            currentCaret: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            currentSelection: nil,
            state: &state,
            timestampNanoseconds: 2
        )

        XCTAssertTrue(drag.didChangeSelection)
        XCTAssertEqual(drag.selection?.anchor, LunaTextLocation(lineIndex: 0, utf8Column: 0))
        XCTAssertGreaterThan(drag.selection?.focus.utf8Column ?? 0, layout.visibleLines[1].endUTF8Column)
        XCTAssertTrue(state.wantsPointerCapture)
    }

    func testEdgeAutoscrollRequestsVisualRowsAndCancelsCleanly() throws {
        let textView = view(
            text: (0..<60).map { "line \($0) selection target" }.joined(separator: "\n"),
            width: 220,
            height: 120
        )
        var state = LunaTextSelectionInteractionState()
        let start = try point(in: textView, visualRow: 0, visualCharacter: 0)
        _ = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: start),
            in: textView,
            currentCaret: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            currentSelection: nil,
            state: &state,
            timestampNanoseconds: 1
        )

        let viewport = textView.layout().textViewportBounds
        let outside = LunaPointI(x: viewport.x + 20, y: viewport.y + viewport.h + 40)
        let moved = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(phase: .moved, location: outside, clickCount: 0),
            in: textView,
            currentCaret: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            currentSelection: nil,
            state: &state,
            timestampNanoseconds: 60_000_001
        )
        XCTAssertGreaterThan(moved.requestedVisualRowDelta, 0)
        XCTAssertTrue(state.wantsContinuousUpdates)

        let next = LunaTextSelectionInteraction.advanceAutoscroll(
            in: textView,
            state: &state,
            timestampNanoseconds: 120_000_002
        )
        XCTAssertGreaterThan(next.requestedVisualRowDelta, 0)

        state.cancel()
        XCTAssertFalse(state.wantsPointerCapture)
        XCTAssertFalse(state.wantsContinuousUpdates)
    }

    func testDoubleClickDragExpandsByWholeWordsInReverseDirection() throws {
        let textView = view(text: "alpha beta gamma")
        var state = LunaTextSelectionInteractionState()
        let beta = try point(in: textView, visualRow: 0, visualCharacter: 8)
        let alpha = try point(in: textView, visualRow: 0, visualCharacter: 2)

        _ = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: beta, clickCount: 2),
            in: textView,
            currentCaret: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            currentSelection: nil,
            state: &state,
            timestampNanoseconds: 1
        )
        let dragged = LunaTextSelectionInteraction.handlePointerEvent(
            LunaPointerEvent(phase: .moved, location: alpha, clickCount: 0),
            in: textView,
            currentCaret: LunaTextLocation(lineIndex: 0, utf8Column: 0),
            currentSelection: nil,
            state: &state,
            timestampNanoseconds: 2
        )

        XCTAssertEqual(dragged.selection?.anchor, LunaTextLocation(lineIndex: 0, utf8Column: 10))
        XCTAssertEqual(dragged.selection?.focus, LunaTextLocation(lineIndex: 0, utf8Column: 0))
    }

    func testWordRangeKeepsWordWhitespaceAndPunctuationRunsSeparate() {
        let document = LunaStaticTextDocument(text: "name  += value")
        XCTAssertEqual(
            document.wordRange(at: LunaTextLocation(lineIndex: 0, utf8Column: 1)),
            LunaTextRange(
                anchor: LunaTextLocation(lineIndex: 0, utf8Column: 0),
                focus: LunaTextLocation(lineIndex: 0, utf8Column: 4)
            )
        )
        XCTAssertEqual(
            document.wordRange(at: LunaTextLocation(lineIndex: 0, utf8Column: 4)),
            LunaTextRange(
                anchor: LunaTextLocation(lineIndex: 0, utf8Column: 4),
                focus: LunaTextLocation(lineIndex: 0, utf8Column: 6)
            )
        )
        XCTAssertEqual(
            document.wordRange(at: LunaTextLocation(lineIndex: 0, utf8Column: 6)),
            LunaTextRange(
                anchor: LunaTextLocation(lineIndex: 0, utf8Column: 6),
                focus: LunaTextLocation(lineIndex: 0, utf8Column: 8)
            )
        )
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
