import XCTest
import LunaAccessibility
import LunaCore
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase3BTests: XCTestCase {
    private func metrics() -> LunaStaticTextViewMetrics {
        LunaStaticTextViewMetrics(
            contentInsets: LunaInsetsI(top: 0, right: 0, bottom: 0, left: 0),
            gutterWidth: 30,
            gutterPadding: 0,
            lineHeight: 12,
            glyphMetrics: .body
        )
    }

    func testTextLocationsClampAndMapToAbsoluteUTF8Offsets() {
        let doc = LunaStaticTextDocument(text: "alpha\nbeta\ngamma")

        XCTAssertEqual(doc.clampedLocation(LunaTextLocation(lineIndex: 99, utf8Column: 99)), LunaTextLocation(lineIndex: 2, utf8Column: 5))
        XCTAssertEqual(doc.clampedLocation(LunaTextLocation(lineIndex: 1, utf8Column: 99)), LunaTextLocation(lineIndex: 1, utf8Column: 4))
        XCTAssertEqual(doc.absoluteUTF8Offset(for: LunaTextLocation(lineIndex: 1, utf8Column: 2)), 8)
        XCTAssertEqual(doc.location(forAbsoluteUTF8Offset: 8), LunaTextLocation(lineIndex: 1, utf8Column: 2))
        XCTAssertEqual(doc.accessibilityCaretRange(for: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 2, utf8Column: 3))), LunaAccessibilityTextRange(utf8Offset: 14, utf8Length: 0))
    }

    func testCaretRectUsesLineAndColumnGeometry() throws {
        let view = LunaStaticTextView(
            id: "phase3b.text",
            bounds: LunaRectI(x: 10, y: 20, w: 220, h: 48),
            document: LunaStaticTextDocument(text: "alpha\nbeta\ngamma"),
            metrics: metrics(),
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 1, utf8Column: 2))
        )

        let layout = view.layout()
        XCTAssertEqual(layout.caretRect, LunaRectI(x: 52, y: 32, w: 1, h: 12))
        XCTAssertTrue(layout.visibleLines[1].isCurrentLine)
        XCTAssertFalse(layout.visibleLines[0].isCurrentLine)
    }

    func testCurrentLineFallsBackToExplicitCurrentLineWithoutCaret() {
        let view = LunaStaticTextView(
            id: "phase3b.text",
            bounds: LunaRectI(x: 0, y: 0, w: 180, h: 36),
            document: LunaStaticTextDocument(text: "alpha\nbeta\ngamma"),
            currentLineIndex: 2,
            metrics: metrics()
        )

        let layout = view.layout()
        XCTAssertNil(layout.caretRect)
        XCTAssertTrue(layout.visibleLines[2].isCurrentLine)
    }

    func testSingleLineSelectionRectClipsToVisibleTextBounds() throws {
        let view = LunaStaticTextView(
            id: "phase3b.text",
            bounds: LunaRectI(x: 0, y: 0, w: 66, h: 12),
            document: LunaStaticTextDocument(text: "abcdefghijklmnopqrstuvwxyz"),
            metrics: metrics(),
            selection: LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 0, utf8Column: 2),
                    focus: LunaTextLocation(lineIndex: 0, utf8Column: 20)
                )
            )
        )

        let rect = try XCTUnwrap(view.layout().selectionRects.first)
        XCTAssertEqual(rect.lineIndex, 0)
        XCTAssertEqual(rect.startUTF8Column, 2)
        XCTAssertEqual(rect.endUTF8Column, 20)
        XCTAssertEqual(rect.bounds, LunaRectI(x: 42, y: 0, w: 24, h: 12))
    }

    func testMultiLineSelectionProducesOneRectPerVisibleTouchedLine() {
        let view = LunaStaticTextView(
            id: "phase3b.text",
            bounds: LunaRectI(x: 0, y: 0, w: 180, h: 36),
            document: LunaStaticTextDocument(text: "alpha\nbeta\ngamma"),
            metrics: metrics(),
            selection: LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 0, utf8Column: 2),
                    focus: LunaTextLocation(lineIndex: 2, utf8Column: 3)
                )
            )
        )

        let rects = view.layout().selectionRects
        XCTAssertEqual(rects.map(\.lineIndex), [0, 1, 2])
        XCTAssertEqual(rects[0].bounds, LunaRectI(x: 42, y: 0, w: 18, h: 12))
        XCTAssertEqual(rects[1].bounds, LunaRectI(x: 30, y: 12, w: 24, h: 12))
        XCTAssertEqual(rects[2].bounds, LunaRectI(x: 30, y: 24, w: 18, h: 12))
    }

    func testTextHitTestingMapsPointsToLineAndColumn() throws {
        let view = LunaStaticTextView(
            id: "phase3b.text",
            bounds: LunaRectI(x: 10, y: 20, w: 220, h: 48),
            document: LunaStaticTextDocument(text: "alpha\nbeta\ngamma"),
            metrics: metrics()
        )

        let hit = try XCTUnwrap(view.textHitTest(LunaPointI(x: 10 + 30 + 12 + 7, y: 20 + 13)))
        XCTAssertEqual(hit.nodeID, view.lineNodeID(for: 1))
        XCTAssertEqual(hit.location, LunaTextLocation(lineIndex: 1, utf8Column: 3))
        XCTAssertTrue(hit.isInsideTextViewport)

        let gutterHit = try XCTUnwrap(view.textHitTest(LunaPointI(x: 12, y: 20 + 13)))
        XCTAssertEqual(gutterHit.location, LunaTextLocation(lineIndex: 1, utf8Column: 0))
        XCTAssertFalse(gutterHit.isInsideTextViewport)

        XCTAssertNil(view.textHitTest(LunaPointI(x: 240, y: 20)))
    }

    func testDisplayListDrawsSelectionAndCaretFromThemeEditorTokens() {
        var colors = LunaUIThemeColors.lunaDefaultDark
        colors.editor.selectionBackground = .hex("#010203")
        colors.editor.caret = .hex("#040506")

        let theme = LunaTheme(
            name: "Phase 3B Theme Proof",
            background: colors.editor.background,
            foreground: colors.editor.foreground,
            caret: colors.editor.caret,
            selection: colors.editor.selectionBackground,
            ui: colors
        )
        let view = LunaStaticTextView(
            id: "phase3b.text",
            bounds: LunaRectI(x: 0, y: 0, w: 180, h: 36),
            document: LunaStaticTextDocument(text: "alpha\nbeta"),
            theme: theme,
            metrics: metrics(),
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 4)),
            selection: LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 0, utf8Column: 1),
                    focus: LunaTextLocation(lineIndex: 0, utf8Column: 3)
                )
            )
        )

        let layout = view.layout()
        var displayList = LunaDisplayList()
        view.buildDisplayList(into: &displayList)

        XCTAssertTrue(displayList.commands.contains(.rect(layout.selectionRects[0].bounds, LunaRender.LunaRGBA8(r: 1, g: 2, b: 3, a: 255))))
        XCTAssertTrue(displayList.commands.contains(.rect(layout.caretRect!, LunaRender.LunaRGBA8(r: 4, g: 5, b: 6, a: 255))))
    }

    func testAccessibilityExposesCaretSelectionAndFocusedLine() throws {
        let view = LunaStaticTextView(
            id: "phase3b.text",
            bounds: LunaRectI(x: 0, y: 0, w: 180, h: 36),
            document: LunaStaticTextDocument(text: "alpha\nbeta\ngamma"),
            metrics: metrics(),
            isFocused: true,
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 1, utf8Column: 2)),
            selection: LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 0, utf8Column: 1),
                    focus: LunaTextLocation(lineIndex: 2, utf8Column: 3)
                )
            )
        )

        let root = view.buildAccessibilityNode()
        let children = view.buildAccessibilityChildren()

        XCTAssertEqual(root.caretTextRange, LunaAccessibilityTextRange(utf8Offset: 8, utf8Length: 0))
        XCTAssertEqual(root.selectedTextRange, LunaAccessibilityTextRange(utf8Offset: 1, utf8Length: 13))
        XCTAssertTrue(root.isFocused)
        XCTAssertEqual(children.filter(\.isFocused).map(\.id), [view.lineNodeID(for: 1)])
    }
}
