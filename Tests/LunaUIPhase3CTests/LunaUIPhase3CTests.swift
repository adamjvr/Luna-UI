import XCTest
import LunaAccessibility
import LunaCore
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase3CTests: XCTestCase {
    private func metrics() -> LunaStaticTextViewMetrics {
        LunaStaticTextViewMetrics(
            contentInsets: LunaInsetsI(top: 0, right: 0, bottom: 0, left: 0),
            gutterWidth: 30,
            gutterPadding: 0,
            lineHeight: 12,
            glyphMetrics: .body,
            scrollbarLaneWidth: 8,
            scrollbarPadding: 1,
            scrollbarThumbMinHeight: 6
        )
    }

    private func document(lineCount: Int = 10) -> LunaStaticTextDocument {
        LunaStaticTextDocument(text: (0..<lineCount).map { "line\($0)" }.joined(separator: "\n"))
    }

    func testScrollStateClampsAndScrollsByLogicalLines() {
        let doc = document(lineCount: 10)
        let state = LunaStaticTextScrollState(scrollTopLine: 99)
            .clamped(document: doc, maxVisibleLineCount: 4)

        XCTAssertEqual(state.scrollTopLine, 6)
        XCTAssertEqual(state.scrolled(byLineDelta: -2, document: doc, maxVisibleLineCount: 4).scrollTopLine, 4)
        XCTAssertEqual(state.scrolled(byLineDelta: 20, document: doc, maxVisibleLineCount: 4).scrollTopLine, 6)
        XCTAssertEqual(LunaStaticTextScrollState.maximumScrollTopLine(documentLineCount: 10, maxVisibleLineCount: 4), 6)
    }

    func testScrollStateEnsuresCaretLineVisible() {
        let doc = document(lineCount: 20)
        let state = LunaStaticTextScrollState(scrollTopLine: 5)

        XCTAssertEqual(
            state.ensuringVisible(LunaTextLocation(lineIndex: 3, utf8Column: 0), document: doc, maxVisibleLineCount: 5).scrollTopLine,
            3
        )
        XCTAssertEqual(
            state.ensuringVisible(LunaTextLocation(lineIndex: 12, utf8Column: 0), document: doc, maxVisibleLineCount: 5).scrollTopLine,
            8
        )
        XCTAssertEqual(
            state.ensuringVisible(LunaTextLocation(lineIndex: 7, utf8Column: 0), document: doc, maxVisibleLineCount: 5).scrollTopLine,
            5
        )
    }

    func testLayoutReportsVisibleRangeContentHeightAndScrollbarGeometry() {
        let view = LunaStaticTextView(
            id: "phase3c.text",
            bounds: LunaRectI(x: 10, y: 20, w: 160, h: 48),
            document: document(lineCount: 10),
            scrollTopLine: 3,
            metrics: metrics()
        )

        let layout = view.layout()

        XCTAssertEqual(layout.maxVisibleLineCount, 4)
        XCTAssertEqual(layout.firstVisibleLineIndex, 3)
        XCTAssertEqual(layout.visibleLineRange, LunaStaticTextVisibleLineRange(startLineIndex: 3, endLineIndexExclusive: 7))
        XCTAssertEqual(layout.visibleLines.map { $0.line.index }, [3, 4, 5, 6])
        XCTAssertEqual(layout.contentHeight, 120)
        XCTAssertEqual(layout.maxScrollTopLine, 6)
        XCTAssertEqual(layout.scrollbarLaneBounds, LunaRectI(x: 162, y: 20, w: 8, h: 48))
        XCTAssertNotNil(layout.scrollbarThumbBounds)
        XCTAssertEqual(layout.textViewportBounds.w, 122)
    }

    func testScrolledHitTestingMapsScreenRowsToScrolledDocumentLines() throws {
        let view = LunaStaticTextView(
            id: "phase3c.text",
            bounds: LunaRectI(x: 0, y: 0, w: 180, h: 36),
            document: document(lineCount: 10),
            scrollTopLine: 4,
            metrics: metrics()
        )

        let hit = try XCTUnwrap(view.textHitTest(LunaPointI(x: 30 + 12, y: 13)))
        XCTAssertEqual(hit.location.lineIndex, 5)
        XCTAssertEqual(hit.nodeID, view.lineNodeID(for: 5))
    }

    func testCaretAndSelectionDisappearWhenScrolledOutsideVisibleRange() {
        let view = LunaStaticTextView(
            id: "phase3c.text",
            bounds: LunaRectI(x: 0, y: 0, w: 180, h: 36),
            document: document(lineCount: 10),
            scrollTopLine: 4,
            metrics: metrics(),
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 1, utf8Column: 2)),
            selection: LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 0, utf8Column: 0),
                    focus: LunaTextLocation(lineIndex: 1, utf8Column: 3)
                )
            )
        )

        let layout = view.layout()
        XCTAssertNil(layout.caretRect)
        XCTAssertTrue(layout.selectionRects.isEmpty)
    }

    func testAccessibilityVisibleTextRangeTracksScrollOffset() {
        let doc = LunaStaticTextDocument(text: "zero\none\ntwo\nthree\nfour")
        let view = LunaStaticTextView(
            id: "phase3c.text",
            bounds: LunaRectI(x: 0, y: 0, w: 180, h: 24),
            document: doc,
            scrollTopLine: 2,
            metrics: metrics()
        )

        let root = view.buildAccessibilityNode()
        let children = view.buildAccessibilityChildren()

        XCTAssertEqual(children.map(\.label), ["two", "three"])
        XCTAssertEqual(root.visibleTextRange, LunaAccessibilityTextRange(utf8Offset: 9, utf8Length: 9))
        XCTAssertEqual(root.textRange, LunaAccessibilityTextRange(utf8Offset: 0, utf8Length: doc.text.utf8.count))
    }

    func testDisplayListDrawsScrollbarFromThemeTokens() throws {
        var colors = LunaUIThemeColors.lunaDefaultDark
        colors.editor.scrollbarTrack = .hex("#010203")
        colors.editor.scrollbarThumb = .hex("#040506")

        let theme = LunaTheme(
            name: "Phase 3C Theme Proof",
            background: colors.editor.background,
            foreground: colors.editor.foreground,
            caret: colors.editor.caret,
            selection: colors.editor.selectionBackground,
            ui: colors
        )
        let view = LunaStaticTextView(
            id: "phase3c.text",
            bounds: LunaRectI(x: 0, y: 0, w: 180, h: 36),
            document: document(lineCount: 10),
            scrollTopLine: 2,
            theme: theme,
            metrics: metrics()
        )

        let layout = view.layout()
        let thumb = try XCTUnwrap(layout.scrollbarThumbBounds)
        var list = LunaDisplayList()
        view.buildDisplayList(into: &list)

        XCTAssertTrue(list.commands.contains(.rect(layout.scrollbarLaneBounds, LunaRender.LunaRGBA8(r: 1, g: 2, b: 3, a: 255))))
        XCTAssertTrue(list.commands.contains(.rect(thumb, LunaRender.LunaRGBA8(r: 4, g: 5, b: 6, a: 255))))
    }
}
