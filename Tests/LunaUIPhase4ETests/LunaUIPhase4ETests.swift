import XCTest
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase4ETests: XCTestCase {
    private func makeDefinition() -> LunaContextMenuDefinition {
        LunaContextMenuDefinition(
            id: "editor",
            title: "Editor Context",
            items: [
                .command(id: "copy", title: "Copy", command: "demo.copy", keyEquivalent: LunaKeyEquivalent("C", modifiers: [.primary])),
                .command(id: "disabled", title: "Disabled", command: "demo.disabled", isEnabled: false),
                .separator(id: "sep"),
                .submenu(id: "convert", title: "Convert Case", children: [
                    .command(id: "upper", title: "Upper Case", command: "demo.upper"),
                    .command(id: "lower", title: "Lower Case", command: "demo.lower", isChecked: true),
                ]),
            ],
            sourceNodeID: "editor.text",
            accessibilityLabel: "Editor Context Menu"
        )
    }

    private func openedState(at point: LunaPointI = LunaPointI(x: 40, y: 50)) -> LunaContextMenuState {
        var state = LunaContextMenuState()
        state.open(makeDefinition(), at: point)
        return state
    }

    func testOpenContextMenuStoresDefinitionOriginAndFirstEnabledRow() {
        let state = openedState(at: LunaPointI(x: 12, y: 20))

        XCTAssertTrue(state.isOpen)
        XCTAssertEqual(state.definition?.id, "editor")
        XCTAssertEqual(state.origin, LunaPointI(x: 12, y: 20))
        XCTAssertEqual(state.highlightedPath, LunaMenuItemPath(menuIndex: 0, itemIndices: [0]))
    }

    func testLayoutBuildsFloatingDropdownRowsAndClampsToBounds() {
        let state = openedState(at: LunaPointI(x: 760, y: 560))
        let menu = LunaContextMenu(id: "context", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)
        let layout = menu.layout()

        XCTAssertEqual(layout.dropdowns.count, 1)
        XCTAssertEqual(layout.dropdowns[0].rows.map(\.item.title), ["Copy", "Disabled", "", "Convert Case"])
        XCTAssertLessThanOrEqual(layout.dropdowns[0].bounds.x + layout.dropdowns[0].bounds.w, 800)
        XCTAssertLessThanOrEqual(layout.dropdowns[0].bounds.y + layout.dropdowns[0].bounds.h, 600)
        XCTAssertEqual(layout.dropdowns[0].rows[0].item.keyEquivalent?.lunaMenuDisplayString, "Ctrl+C")
    }

    func testPointerClickCommandRowRequestsCommandAndCloses() {
        var state = openedState()
        let menu = LunaContextMenu(id: "context", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)
        let row = menu.layout().dropdowns[0].rows[0]

        let result = menu.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: row.bounds.x + 4, y: row.bounds.y + 4)),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertTrue(result.didDismiss)
        XCTAssertEqual(result.requestedCommand, "demo.copy")
        XCTAssertFalse(state.isOpen)
    }

    func testDisabledRowConsumesWithoutActivating() {
        var state = openedState()
        let menu = LunaContextMenu(id: "context", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)
        let row = menu.layout().dropdowns[0].rows.first { $0.item.title == "Disabled" }!

        let result = menu.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: row.bounds.x + 4, y: row.bounds.y + 4)),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertNil(result.requestedCommand)
        XCTAssertTrue(state.isOpen)
    }

    func testOutsideClickDismissesAndConsumes() {
        var state = openedState()
        let menu = LunaContextMenu(id: "context", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)

        let result = menu.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: 5, y: 5)),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertTrue(result.didDismiss)
        XCTAssertFalse(state.isOpen)
    }

    func testKeyboardNavigationSubmenuAndActivation() {
        var state = openedState()
        let menu = LunaContextMenu(id: "context", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)

        _ = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowDown), state: &state)
        XCTAssertEqual(state.highlightedPath, LunaMenuItemPath(menuIndex: 0, itemIndices: [1]))
        _ = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowDown), state: &state)
        XCTAssertEqual(state.highlightedPath, LunaMenuItemPath(menuIndex: 0, itemIndices: [3]))
        _ = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowRight), state: &state)
        XCTAssertEqual(state.highlightedPath, LunaMenuItemPath(menuIndex: 0, itemIndices: [3, 0]))

        let result = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .enter), state: &state)

        XCTAssertEqual(result.requestedCommand, "demo.upper")
        XCTAssertFalse(state.isOpen)
    }

    func testEscapeDismissesContextMenu() {
        var state = openedState()
        let menu = LunaContextMenu(id: "context", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)

        let result = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .escape), state: &state)

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertTrue(result.didDismiss)
        XCTAssertFalse(state.isOpen)
    }

    func testDisplayListUsesMenuThemeTokens() {
        let state = openedState()
        let theme = LunaTheme.highContrastProof
        let menu = LunaContextMenu(id: "context", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: theme)
        var displayList = LunaDisplayList()

        menu.buildDisplayList(into: &displayList)

        XCTAssertTrue(displayList.commands.contains { command in
            if case .rect(_, let color) = command { return color == theme.ui.menu.background.asRenderColor }
            return false
        })
        XCTAssertTrue(displayList.commands.contains { command in
            if case .rect(_, let color) = command { return color == theme.ui.menu.rowHoveredBackground.asRenderColor }
            return false
        })
    }

    func testAccessibilityExposesMenuItemsAndCheckedState() {
        var state = openedState()
        state.highlight(LunaMenuItemPath(menuIndex: 0, itemIndices: [3, 1]))
        let menu = LunaContextMenu(id: "context", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 600), state: state, theme: .lunaDefaultDark)

        let root = menu.buildAccessibilityNode()
        let children = menu.buildAccessibilityChildren()

        XCTAssertEqual(root.role, .menu)
        XCTAssertEqual(root.label, "Editor Context Menu")
        XCTAssertTrue(children.contains { $0.role == .menuItem && $0.label == "Copy" })
        XCTAssertTrue(children.contains { $0.role == .menuItem && $0.label == "Checked, Lower Case" && $0.isFocused })
    }
}
