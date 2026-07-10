import XCTest
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase4FTests: XCTestCase {
    private func makeItems() -> [LunaCompletionItem] {
        [
            LunaCompletionItem(id: "let", title: "let", annotation: "keyword", detail: "Create an immutable binding.", insertText: "let "),
            LunaCompletionItem(id: "var", title: "var", annotation: "keyword", detail: "Create a mutable binding.", insertText: "var "),
            LunaCompletionItem(id: "disabled", title: "disabled", annotation: "demo", detail: "Disabled item", isEnabled: false),
            LunaCompletionItem(id: "struct", title: "struct", annotation: "keyword", detail: "Declare a new type.", insertText: "struct "),
            LunaCompletionItem(id: "luna", title: "LunaCompletionPopup", annotation: "type", detail: "Product-neutral anchored completion surface.", insertText: "LunaCompletionPopup"),
            LunaCompletionItem(id: "command", title: "Run completion command", annotation: "command", detail: "Routes through LunaCommandID.", command: "demo.complete.command"),
        ]
    }

    private func openedState(anchor: LunaRectI = LunaRectI(x: 40, y: 42, w: 2, h: 18)) -> LunaCompletionPopupState {
        var state = LunaCompletionPopupState()
        state.open(items: makeItems(), anchorRect: anchor)
        return state
    }

    func testOpenStoresItemsAnchorAndFirstEnabledSelection() {
        let state = openedState()

        XCTAssertTrue(state.isOpen)
        XCTAssertEqual(state.items.count, 6)
        XCTAssertEqual(state.anchorRect, LunaRectI(x: 40, y: 42, w: 2, h: 18))
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertEqual(state.selectedItem?.title, "let")
    }

    func testOpenSkipsDisabledPreferredSelection() {
        var state = LunaCompletionPopupState()
        state.open(items: makeItems(), anchorRect: LunaRectI(x: 0, y: 0, w: 1, h: 1), preferredSelectedIndex: 2)

        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertEqual(state.selectedItem?.title, "let")
    }

    func testLayoutAnchorsBelowCaretAndBuildsRowsWithDetail() {
        let state = openedState()
        let popup = LunaCompletionPopup(id: "completion", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)
        let layout = popup.layout()

        XCTAssertFalse(layout.popupBounds.isEmpty)
        XCTAssertGreaterThanOrEqual(layout.popupBounds.y, state.anchorRect.y + state.anchorRect.h)
        XCTAssertEqual(layout.rows.map(\.item.title), makeItems().map(\.title))
        XCTAssertNotNil(layout.detailBounds)
    }

    func testLayoutClampsNearViewportBottom() {
        let state = openedState(anchor: LunaRectI(x: 760, y: 560, w: 2, h: 18))
        let popup = LunaCompletionPopup(id: "completion", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)
        let layout = popup.layout()

        XCTAssertLessThanOrEqual(layout.popupBounds.x + layout.popupBounds.w, 800)
        XCTAssertLessThanOrEqual(layout.popupBounds.y + layout.popupBounds.h, 600)
        XCTAssertLessThan(layout.popupBounds.y, state.anchorRect.y)
    }

    func testKeyboardNavigationSkipsDisabledRowsAndActivationReturnsInsertionText() {
        var state = openedState()
        let popup = LunaCompletionPopup(id: "completion", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)

        _ = popup.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowDown), state: &state)
        XCTAssertEqual(state.selectedIndex, 1)
        _ = popup.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowDown), state: &state)
        XCTAssertEqual(state.selectedIndex, 3)

        let result = popup.handleKeyboardEvent(LunaKeyboardEvent(key: .enter), state: &state)

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertTrue(result.didDismiss)
        XCTAssertEqual(result.selectedItem?.title, "struct")
        XCTAssertEqual(result.insertionText, "struct ")
        XCTAssertFalse(state.isOpen)
    }

    func testTabActivatesCompletion() {
        var state = openedState()
        let popup = LunaCompletionPopup(id: "completion", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)

        let result = popup.handleKeyboardEvent(LunaKeyboardEvent(key: .tab), state: &state)

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertEqual(result.insertionText, "let ")
        XCTAssertFalse(state.isOpen)
    }

    func testPointerHoverAndClickActivateRow() {
        var state = openedState()
        let popup = LunaCompletionPopup(id: "completion", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)
        let row = popup.layout().rows[1]

        let hover = popup.handlePointerEvent(
            LunaPointerEvent(phase: .moved, location: LunaPointI(x: row.bounds.x + 4, y: row.bounds.y + 4)),
            state: &state
        )
        XCTAssertTrue(hover.didConsumeEvent)
        XCTAssertEqual(state.selectedIndex, row.index)

        let click = popup.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: row.bounds.x + 4, y: row.bounds.y + 4)),
            state: &state
        )
        XCTAssertEqual(click.insertionText, "var ")
        XCTAssertFalse(state.isOpen)
    }

    func testOutsideClickDismissesAndConsumes() {
        var state = openedState()
        let popup = LunaCompletionPopup(id: "completion", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)

        let result = popup.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: 5, y: 5)),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertTrue(result.didDismiss)
        XCTAssertFalse(state.isOpen)
    }

    func testDisplayListUsesThemeTokens() {
        let state = openedState()
        let theme = LunaTheme.highContrastProof
        let popup = LunaCompletionPopup(id: "completion", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: theme)
        var displayList = LunaDisplayList()

        popup.buildDisplayList(into: &displayList)

        XCTAssertTrue(displayList.commands.contains { command in
            if case .rect(_, let color) = command { return color == theme.ui.panel.background.asRenderColor }
            return false
        })
        XCTAssertTrue(displayList.commands.contains { command in
            if case .rect(_, let color) = command { return color == theme.ui.menu.rowHoveredBackground.asRenderColor }
            return false
        })
    }

    func testTextLayoutProducesVisibleRowsAndDetail() {
        let state = openedState()
        let popup = LunaCompletionPopup(id: "completion", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)
        let text = popup.textLayout()

        XCTAssertEqual(text.rows.first?.title.text, "let")
        XCTAssertEqual(text.rows.first?.annotation?.text, "keyword")
        XCTAssertEqual(text.detail?.text, "Create an immutable binding.")
    }

    func testAccessibilityExposesListItemsAndFocusedSelection() {
        var state = openedState()
        state.moveSelection(by: 1, visibleRowCount: 8)
        let popup = LunaCompletionPopup(id: "completion", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)

        let root = popup.buildAccessibilityNode()
        let children = popup.buildAccessibilityChildren()

        XCTAssertEqual(root.role, .list)
        XCTAssertEqual(root.label, "Completion Suggestions")
        XCTAssertTrue(children.contains { $0.role == .listItem && $0.label == "var" && $0.isFocused })
        XCTAssertTrue(children.contains { $0.role == .status && $0.label == "Create a mutable binding." })
    }
}
