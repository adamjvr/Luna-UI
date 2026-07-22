// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaUI
import LunaTheme
import LunaRender

final class LunaUIPhase5F2ATests: XCTestCase {
    private let textMetrics = LunaStaticTextViewMetrics(
        contentInsets: LunaInsetsI(top: 0, right: 0, bottom: 0, left: 0),
        gutterWidth: 0,
        gutterPadding: 0,
        lineHeight: 12,
        glyphMetrics: LunaDebugTextMetrics(scale: 1, advance: 6, lineHeight: 12),
        scrollbarLaneWidth: 0,
        scrollbarPadding: 0,
        scrollbarThumbMinHeight: 8
    )

    func testPaneContentFramesRemainInsideLeafBoundsAfterDividerResize() throws {
        var state = LunaPaneWorkspaceState(
            root: .split(
                id: "root",
                axis: .horizontal,
                fraction: 0.70,
                first: .pane("left"),
                second: .pane("right")
            ),
            activePaneID: "left"
        )
        let bounds = LunaRectI(x: 20, y: 30, w: 600, h: 300)
        let metrics = LunaPaneContentMetrics(
            headerHeight: 24,
            contentInsets: LunaInsetsI(top: 2, right: 3, bottom: 4, left: 5)
        )

        let before = LunaPaneContainer(
            id: "panes",
            bounds: bounds,
            state: state,
            theme: .lunaDefaultDark
        ).layout()
        let beforeFrames = before.contentFrames(metrics: metrics)
        XCTAssertEqual(beforeFrames.count, 2)

        for frame in beforeFrames {
            XCTAssertTrue(frame.paneBounds.contains(x: frame.contentBounds.x, y: frame.contentBounds.y))
            XCTAssertLessThanOrEqual(frame.contentBounds.x + frame.contentBounds.w, frame.paneBounds.x + frame.paneBounds.w)
            XCTAssertLessThanOrEqual(frame.contentBounds.y + frame.contentBounds.h, frame.paneBounds.y + frame.paneBounds.h)
            XCTAssertEqual(frame.headerBounds.y, frame.paneBounds.y)
            XCTAssertEqual(frame.contentBounds.y, frame.paneBounds.y + 24 + 2)
        }

        let leftWidthBefore = try XCTUnwrap(before.contentFrame(for: "left", metrics: metrics)).contentBounds.w
        XCTAssertTrue(state.setSplitFraction(0.40, for: "root"))
        let after = LunaPaneContainer(
            id: "panes",
            bounds: bounds,
            state: state,
            theme: .lunaDefaultDark
        ).layout()
        let leftWidthAfter = try XCTUnwrap(after.contentFrame(for: "left", metrics: metrics)).contentBounds.w
        XCTAssertLessThan(leftWidthAfter, leftWidthBefore)
    }

    func testSoftWrapRecomputesFromEachPaneWidth() {
        let document = LunaStaticTextDocument(
            text: "Pane-local text wrapping must respond to each leaf width without crossing the divider."
        )
        let wide = LunaStaticTextView(
            id: "wide",
            bounds: LunaRectI(x: 0, y: 0, w: 300, h: 120),
            document: document,
            theme: .lunaDefaultDark,
            metrics: textMetrics,
            wrapMode: .soft
        ).layout()
        let narrow = LunaStaticTextView(
            id: "narrow",
            bounds: LunaRectI(x: 310, y: 0, w: 120, h: 120),
            document: document,
            theme: .lunaDefaultDark,
            metrics: textMetrics,
            wrapMode: .soft
        ).layout()

        XCTAssertGreaterThan(narrow.totalVisualRowCount, wide.totalVisualRowCount)
        for line in wide.visibleLines {
            XCTAssertGreaterThanOrEqual(line.visualText.bounds.x, wide.textViewportBounds.x)
            XCTAssertLessThanOrEqual(
                line.visualText.bounds.x + line.visualText.bounds.w,
                wide.textViewportBounds.x + wide.textViewportBounds.w
            )
        }
        for line in narrow.visibleLines {
            XCTAssertGreaterThanOrEqual(line.visualText.bounds.x, narrow.textViewportBounds.x)
            XCTAssertLessThanOrEqual(
                line.visualText.bounds.x + line.visualText.bounds.w,
                narrow.textViewportBounds.x + narrow.textViewportBounds.w
            )
        }
        XCTAssertEqual(narrow.visibleLines.filter { !$0.lineNumberText.isEmpty }.count, 1)
    }

    func testWrappedHitTestingMapsBackToLogicalUTF8Columns() throws {
        let view = LunaStaticTextView(
            id: "wrapped",
            bounds: LunaRectI(x: 10, y: 20, w: 24, h: 48),
            document: LunaStaticTextDocument(text: "abcdefghij"),
            theme: .lunaDefaultDark,
            metrics: textMetrics,
            wrapMode: .soft
        )
        let layout = view.layout()
        XCTAssertEqual(layout.totalVisualRowCount, 3)
        XCTAssertEqual(layout.visibleLines.map { $0.startUTF8Column }, [0, 4, 8])
        XCTAssertEqual(layout.visibleLines.map { $0.endUTF8Column }, [4, 8, 10])

        let second = try XCTUnwrap(layout.visibleLines.dropFirst().first)
        let hit = try XCTUnwrap(view.textHitTest(
            LunaPointI(x: second.textBounds.x + 6, y: second.rowBounds.y + 2)
        ))
        XCTAssertEqual(hit.location, LunaTextLocation(lineIndex: 0, utf8Column: 5))
    }

    func testCaretAndSelectionUseWrappedVisualRows() throws {
        let view = LunaStaticTextView(
            id: "wrapped",
            bounds: LunaRectI(x: 0, y: 0, w: 24, h: 48),
            document: LunaStaticTextDocument(text: "abcdefghij"),
            theme: .lunaDefaultDark,
            metrics: textMetrics,
            wrapMode: .soft,
            isFocused: true,
            isEditable: true,
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 6)),
            selection: LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 0, utf8Column: 2),
                    focus: LunaTextLocation(lineIndex: 0, utf8Column: 9)
                )
            )
        )
        let layout = view.layout()
        let second = try XCTUnwrap(layout.visibleLines.dropFirst().first)
        let caret = try XCTUnwrap(layout.caretRect)

        XCTAssertEqual(caret.y, second.rowBounds.y)
        XCTAssertEqual(caret.x, second.textBounds.x + 12)
        XCTAssertEqual(layout.selectionRects.count, 3)
        XCTAssertEqual(layout.selectionRects.map(\.startUTF8Column), [2, 4, 8])
        XCTAssertEqual(layout.selectionRects.map(\.endUTF8Column), [4, 8, 9])
    }
    func testWrappedUnicodeHitTestingAndCaretStayOnUTF8Boundaries() throws {
        let view = LunaStaticTextView(
            id: "wrapped-unicode",
            bounds: LunaRectI(x: 0, y: 0, w: 18, h: 48),
            document: LunaStaticTextDocument(text: "aé🙂b"),
            theme: .lunaDefaultDark,
            metrics: textMetrics,
            wrapMode: .soft,
            isFocused: true,
            isEditable: true,
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 7))
        )
        let layout = view.layout()
        XCTAssertEqual(layout.visibleLines.map { $0.startUTF8Column }, [0, 7])
        XCTAssertEqual(layout.visibleLines.map { $0.endUTF8Column }, [7, 8])

        let first = try XCTUnwrap(layout.visibleLines.first)
        let hitAfterEAcute = try XCTUnwrap(view.textHitTest(
            LunaPointI(x: first.textBounds.x + 12, y: first.rowBounds.y + 2)
        ))
        XCTAssertEqual(hitAfterEAcute.location.utf8Column, 3)

        let second = try XCTUnwrap(layout.visibleLines.dropFirst().first)
        let caret = try XCTUnwrap(layout.caretRect)
        XCTAssertEqual(caret.y, second.rowBounds.y)
        XCTAssertEqual(caret.x, second.textBounds.x)
    }

    func testSoftWrappedSingleLineCanScrollThroughContinuationRows() throws {
        let view = LunaStaticTextView(
            id: "wrapped-scroll",
            bounds: LunaRectI(x: 0, y: 0, w: 24, h: 24),
            document: LunaStaticTextDocument(text: "abcdefghijklmnopqrst"),
            theme: .lunaDefaultDark,
            metrics: textMetrics,
            wrapMode: .soft
        )
        let initial = view.layout()
        XCTAssertEqual(initial.maxVisibleLineCount, 2)
        XCTAssertEqual(initial.totalVisualRowCount, 5)
        XCTAssertEqual(initial.maxScrollTopVisualRow, 3)

        let scrolled = view.scrolled(byLineDelta: 3)
        let scrolledLayout = scrolled.layout()
        XCTAssertEqual(scrolled.scrollTopVisualRow, 3)
        XCTAssertEqual(scrolledLayout.firstVisibleVisualRowIndex, 3)
        XCTAssertEqual(scrolledLayout.visibleLines.map(\.startUTF8Column), [12, 16])

        let caretVisible = view.ensuringVisible(
            LunaTextLocation(lineIndex: 0, utf8Column: 18)
        )
        XCTAssertEqual(caretVisible.layout().firstVisibleVisualRowIndex, 3)
    }

    func testInjectedShapedGeometryDrivesCaretSelectionAndHitTesting() throws {
        let provider = FractionalGeometryProvider(defaultAdvance26Dot6: 6 * 64 + 16)
        let text = String(repeating: "a", count: 24)
        let view = LunaStaticTextView(
            id: "fractional-geometry",
            bounds: LunaRectI(x: 10, y: 20, w: 260, h: 24),
            document: LunaStaticTextDocument(text: text),
            theme: .lunaDefaultDark,
            metrics: textMetrics,
            wrapMode: .soft,
            geometryProvider: provider,
            isFocused: true,
            isEditable: true,
            caret: LunaStaticTextCaret(
                location: LunaTextLocation(lineIndex: 0, utf8Column: 20)
            ),
            selection: LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 0, utf8Column: 4),
                    focus: LunaTextLocation(lineIndex: 0, utf8Column: 12)
                )
            )
        )

        let layout = view.layout()
        let row = try XCTUnwrap(layout.visibleLines.first)
        let caret = try XCTUnwrap(layout.caretRect)
        let expectedCaretX = row.textBounds.x + row.rowGeometry.x(forUTF8Offset: 20)
        XCTAssertEqual(caret.x, expectedCaretX)
        XCTAssertNotEqual(caret.x, row.textBounds.x + 20 * textMetrics.glyphMetrics.advance)

        let selection = try XCTUnwrap(layout.selectionRects.first)
        XCTAssertEqual(
            selection.bounds.x,
            row.textBounds.x + row.rowGeometry.x(forUTF8Offset: 4)
        )
        XCTAssertEqual(
            selection.bounds.w,
            row.rowGeometry.x(forUTF8Offset: 12)
                - row.rowGeometry.x(forUTF8Offset: 4)
        )

        let xBeforeBoundary = row.textBounds.x + row.rowGeometry.x(forUTF8Offset: 7) - 1
        let hit = try XCTUnwrap(
            view.textHitTest(LunaPointI(x: xBeforeBoundary, y: row.rowBounds.y + 2))
        )
        XCTAssertEqual(hit.location.utf8Column, 7)
    }

    func testGeometryRequestNormalizesToExtendedGraphemeBoundaries() {
        let text = "e\u{301}x"
        let request = LunaStaticTextGeometryRequest(
            completeLineText: text,
            utf8Range: 1..<text.utf8.count
        )

        XCTAssertEqual(request.utf8Range, 0..<text.utf8.count)
        XCTAssertEqual(request.sourceText, text)
    }

    func testSoftWrapUsesInjectedGeometryWidth() {
        let provider = FractionalGeometryProvider(
            defaultAdvance26Dot6: 4 * 64,
            wideCharacters: ["W": Int32(10 * 64)]
        )
        let view = LunaStaticTextView(
            id: "geometry-wrap",
            bounds: LunaRectI(x: 0, y: 0, w: 20, h: 72),
            document: LunaStaticTextDocument(text: "WWaaaa"),
            theme: .lunaDefaultDark,
            metrics: textMetrics,
            wrapMode: .soft,
            geometryProvider: provider
        )

        let layout = view.layout()
        XCTAssertEqual(layout.visibleLines.map { $0.visualText.text }, ["WW", "aaaa"])
        XCTAssertEqual(layout.visibleLines.map { $0.startUTF8Column }, [0, 2])
        XCTAssertEqual(layout.visibleLines.map { $0.endUTF8Column }, [2, 6])
    }

    func testPreciseWheelDeltasAccumulateWithoutMovingAnUnrelatedSurface() {
        let text = (0..<20).map { "line \($0)" }.joined(separator: "\n")
        let view = LunaStaticTextView(
            id: "wheel-scroll",
            bounds: LunaRectI(x: 100, y: 100, w: 160, h: 24),
            document: LunaStaticTextDocument(text: text),
            theme: .lunaDefaultDark,
            metrics: textMetrics,
            wrapMode: .soft
        )

        let outside = LunaStaticTextScrollInteraction.handleScrollEvent(
            LunaScrollEvent(
                location: LunaPointI(x: 10, y: 10),
                deltaY: 1,
                isPrecise: true
            ),
            in: view
        )
        XCTAssertFalse(outside.didConsumeEvent)

        let first = LunaStaticTextScrollInteraction.handleScrollEvent(
            LunaScrollEvent(
                location: LunaPointI(x: 120, y: 110),
                deltaY: 0.4,
                isPrecise: true
            ),
            in: view
        )
        XCTAssertTrue(first.didConsumeEvent)
        XCTAssertEqual(first.requestedScrollTopVisualRow, 0)
        XCTAssertEqual(first.fractionalRowRemainder, 0.4, accuracy: 0.0001)

        let second = LunaStaticTextScrollInteraction.handleScrollEvent(
            LunaScrollEvent(
                location: LunaPointI(x: 120, y: 110),
                deltaY: 0.7,
                isPrecise: true
            ),
            in: view,
            fractionalRowRemainder: first.fractionalRowRemainder
        )
        XCTAssertEqual(second.requestedScrollTopVisualRow, 1)
        XCTAssertEqual(second.fractionalRowRemainder, 0.1, accuracy: 0.0001)

        let conventional = LunaStaticTextScrollInteraction.handleScrollEvent(
            LunaScrollEvent(
                location: LunaPointI(x: 120, y: 110),
                deltaY: 1,
                isPrecise: false
            ),
            in: view,
            fractionalRowRemainder: second.fractionalRowRemainder
        )
        XCTAssertEqual(conventional.requestedScrollTopVisualRow, 3)
        XCTAssertEqual(conventional.fractionalRowRemainder, 0)
    }

    func testScrollbarLanePagingAndThumbDraggingProduceClampedVisualRows() throws {
        let text = (0..<40).map { "line \($0)" }.joined(separator: "\n")
        let metrics = LunaStaticTextViewMetrics(
            contentInsets: LunaInsetsI(top: 0, right: 0, bottom: 0, left: 0),
            gutterWidth: 0,
            gutterPadding: 0,
            lineHeight: 12,
            glyphMetrics: LunaDebugTextMetrics(scale: 1, advance: 6, lineHeight: 12),
            scrollbarLaneWidth: 10,
            scrollbarPadding: 1,
            scrollbarThumbMinHeight: 8
        )
        let view = LunaStaticTextView(
            id: "scrollbar",
            bounds: LunaRectI(x: 0, y: 0, w: 140, h: 60),
            document: LunaStaticTextDocument(text: text),
            theme: .lunaDefaultDark,
            metrics: metrics,
            wrapMode: .soft
        )
        let layout = view.layout()
        let thumb = try XCTUnwrap(layout.scrollbarThumbBounds)
        var state = LunaStaticTextScrollbarInteractionState()

        let page = LunaStaticTextScrollInteraction.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
                location: LunaPointI(
                    x: layout.scrollbarLaneBounds.x + 2,
                    y: min(layout.scrollbarLaneBounds.y + layout.scrollbarLaneBounds.h - 1, thumb.y + thumb.h + 4)
                )
            ),
            in: view,
            state: &state
        )
        XCTAssertTrue(page.didConsumeEvent)
        XCTAssertGreaterThan(page.requestedScrollTopVisualRow ?? 0, 0)

        let begin = LunaStaticTextScrollInteraction.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
                location: LunaPointI(x: thumb.x + 1, y: thumb.y + 1)
            ),
            in: view,
            state: &state
        )
        XCTAssertTrue(begin.didBeginDrag)
        XCTAssertTrue(state.isDragging)

        let drag = LunaStaticTextScrollInteraction.handlePointerEvent(
            LunaPointerEvent(
                phase: .moved,
                location: LunaPointI(
                    x: thumb.x + 1,
                    y: layout.scrollbarLaneBounds.y + layout.scrollbarLaneBounds.h
                )
            ),
            in: view,
            state: &state
        )
        XCTAssertEqual(drag.requestedScrollTopVisualRow, layout.maxScrollTopVisualRow)

        let end = LunaStaticTextScrollInteraction.handlePointerEvent(
            LunaPointerEvent(
                phase: .up,
                location: LunaPointI(x: thumb.x + 1, y: thumb.y + 1)
            ),
            in: view,
            state: &state
        )
        XCTAssertTrue(end.didEndDrag)
        XCTAssertFalse(state.isDragging)
    }

}


private struct FractionalGeometryProvider: LunaStaticTextGeometryProvider {
    var defaultAdvance26Dot6: Int32
    var wideCharacters: [Character: Int32]

    init(
        defaultAdvance26Dot6: Int32,
        wideCharacters: [Character: Int32] = [:]
    ) {
        self.defaultAdvance26Dot6 = defaultAdvance26Dot6
        self.wideCharacters = wideCharacters
    }

    func geometry(for request: LunaStaticTextGeometryRequest) -> LunaStaticTextRowGeometry {
        let sourceText = request.sourceText
        var positions = [LunaStaticTextInsertionPosition(utf8Offset: 0, x26Dot6: 0)]
        var utf8Offset = 0
        var x: Int32 = 0
        for character in sourceText {
            utf8Offset += String(character).utf8.count
            x += wideCharacters[character] ?? defaultAdvance26Dot6
            positions.append(
                LunaStaticTextInsertionPosition(utf8Offset: utf8Offset, x26Dot6: x)
            )
        }
        return LunaStaticTextRowGeometry(
            sourceText: sourceText,
            insertionPositions: positions,
            advance26Dot6: x
        )
    }
}
