// SPDX-License-Identifier: MPL-2.0
import XCTest
import LunaAccessibility
import LunaCore
import LunaRender
import LunaTheme
import LunaUI

final class LunaUIPhase3ATests: XCTestCase {
    func testStaticTextDocumentSplitsLinesAndStoresUtf8Ranges() {
        let doc = LunaStaticTextDocument(text: "one\ntwo\n")

        XCTAssertEqual(doc.lineCount, 3)
        XCTAssertEqual(doc[line: 0]?.text, "one")
        XCTAssertEqual(doc[line: 0]?.utf8Offset, 0)
        XCTAssertEqual(doc[line: 0]?.utf8Length, 3)
        XCTAssertEqual(doc[line: 1]?.text, "two")
        XCTAssertEqual(doc[line: 1]?.utf8Offset, 4)
        XCTAssertEqual(doc[line: 1]?.utf8Length, 3)
        XCTAssertEqual(doc[line: 2]?.text, "")
        XCTAssertEqual(doc[line: 2]?.utf8Offset, 8)
        XCTAssertEqual(doc[line: 2]?.utf8Length, 0)
    }

    func testStaticTextViewLaysOutVisibleLinesInsideBounds() {
        let doc = LunaStaticTextDocument(text: "alpha\nbeta\ngamma\ndelta")
        let view = LunaStaticTextView(
            id: "phase3a.text",
            bounds: LunaRectI(x: 10, y: 20, w: 220, h: 56),
            document: doc,
            scrollTopLine: 1,
            currentLineIndex: 2,
            metrics: LunaStaticTextViewMetrics(
                contentInsets: LunaInsetsI(top: 4, right: 4, bottom: 4, left: 0),
                gutterWidth: 40,
                gutterPadding: 4,
                lineHeight: 12,
                glyphMetrics: .body
            )
        )

        let layout = view.layout()

        XCTAssertEqual(layout.firstVisibleLineIndex, 1)
        XCTAssertEqual(layout.maxVisibleLineCount, 4)
        XCTAssertEqual(layout.visibleLines.map { $0.line.text }, ["beta", "gamma", "delta"])
        XCTAssertEqual(layout.gutterBounds, LunaRectI(x: 10, y: 20, w: 40, h: 56))
        XCTAssertEqual(layout.textViewportBounds.x, 54)
        XCTAssertEqual(layout.visibleLines[0].rowBounds, LunaRectI(x: 10, y: 24, w: 220, h: 12))
        XCTAssertFalse(layout.visibleLines[0].isCurrentLine)
        XCTAssertTrue(layout.visibleLines[1].isCurrentLine)
    }

    func testStaticTextViewVisualTextEllipsizesInsteadOfOverflowing() throws {
        let doc = LunaStaticTextDocument(text: "abcdefghijklmnopqrstuvwxyz")
        let view = LunaStaticTextView(
            id: "phase3a.text",
            bounds: LunaRectI(x: 0, y: 0, w: 96, h: 28),
            document: doc,
            metrics: LunaStaticTextViewMetrics(
                contentInsets: LunaInsetsI(top: 0, right: 0, bottom: 0, left: 0),
                gutterWidth: 24,
                gutterPadding: 0,
                lineHeight: 12,
                glyphMetrics: .body
            )
        )

        let line = try XCTUnwrap(view.layout().visibleLines.first)

        XCTAssertEqual(line.textBounds.w, 72)
        XCTAssertEqual(line.visualText.text, "abcdefghi...")
        XCTAssertTrue(line.visualText.isClipped)
    }

    func testStaticTextViewDisplayListUsesThemeEditorTokens() {
        var colors = LunaUIThemeColors.lunaDefaultDark
        colors.editor.background = .hex("#010203")
        colors.editor.gutterBackground = .hex("#040506")
        colors.editor.currentLineBackground = .hex("#070809")
        colors.chrome.separator = .hex("#0A0B0C")
        colors.textField.focusedBorder = .hex("#0D0E0F")

        let theme = LunaTheme(
            name: "Phase 3A Theme Proof",
            background: colors.editor.background,
            foreground: colors.editor.foreground,
            caret: colors.editor.caret,
            selection: colors.editor.selectionBackground,
            ui: colors
        )
        let view = LunaStaticTextView(
            id: "phase3a.text",
            bounds: LunaRectI(x: 0, y: 0, w: 160, h: 44),
            document: LunaStaticTextDocument(text: "alpha\nbeta"),
            currentLineIndex: 1,
            theme: theme,
            isFocused: true
        )

        var list = LunaDisplayList()
        view.buildDisplayList(into: &list)

        XCTAssertTrue(list.commands.contains(.rect(view.bounds, LunaRender.LunaRGBA8(r: 1, g: 2, b: 3, a: 255))))
        XCTAssertTrue(list.commands.contains(.rect(view.layout().gutterBounds, LunaRender.LunaRGBA8(r: 4, g: 5, b: 6, a: 255))))
        XCTAssertTrue(list.commands.contains(.rect(view.layout().visibleLines[1].rowBounds, LunaRender.LunaRGBA8(r: 7, g: 8, b: 9, a: 255))))
        XCTAssertTrue(list.commands.contains(.rect(LunaRectI(x: 51, y: 0, w: 1, h: 44), LunaRender.LunaRGBA8(r: 10, g: 11, b: 12, a: 255))))
        XCTAssertTrue(list.commands.contains(.rect(LunaRectI(x: 0, y: 0, w: 160, h: 1), LunaRender.LunaRGBA8(r: 13, g: 14, b: 15, a: 255))))
    }

    func testStaticTextViewAccessibilityTreeUsesVisibleLineChildrenAndRanges() {
        let view = LunaStaticTextView(
            id: "phase3a.text",
            bounds: LunaRectI(x: 4, y: 5, w: 180, h: 42),
            document: LunaStaticTextDocument(text: "alpha\nbeta\ngamma"),
            scrollTopLine: 1
        )

        let root = view.buildAccessibilityNode()
        let children = view.buildAccessibilityChildren()

        XCTAssertEqual(root.role, .textArea)
        XCTAssertEqual(root.value, "alpha\nbeta\ngamma")
        XCTAssertEqual(root.bounds, LunaAccessibilityRect(x: 4, y: 5, width: 180, height: 42))
        XCTAssertEqual(root.children, children.map(\.id))
        XCTAssertEqual(children.first?.role, .textRun)
        XCTAssertEqual(children.first?.label, "beta")
        XCTAssertEqual(children.first?.value, "2")
        XCTAssertEqual(children.first?.textRange, LunaAccessibilityTextRange(utf8Offset: 6, utf8Length: 4))
    }

    func testStaticTextViewHitTestingReturnsLineIDs() throws {
        let view = LunaStaticTextView(
            id: "phase3a.text",
            bounds: LunaRectI(x: 10, y: 10, w: 200, h: 60),
            document: LunaStaticTextDocument(text: "alpha\nbeta\ngamma"),
            metrics: LunaStaticTextViewMetrics(
                contentInsets: LunaInsetsI(top: 0, right: 0, bottom: 0, left: 0),
                gutterWidth: 40,
                gutterPadding: 0,
                lineHeight: 12,
                glyphMetrics: .body
            )
        )
        let layout = view.layout()
        let secondLine = try XCTUnwrap(layout.visibleLines.dropFirst().first)

        XCTAssertEqual(view.hitTest(LunaPointI(x: secondLine.textBounds.x, y: secondLine.textBounds.y)), secondLine.nodeID)
        XCTAssertEqual(view.hitTest(LunaPointI(x: 12, y: 68)), view.id)
        XCTAssertNil(view.hitTest(LunaPointI(x: 250, y: 12)))
    }
}
