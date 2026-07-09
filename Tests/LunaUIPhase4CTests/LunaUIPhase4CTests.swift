import XCTest
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase4CTests: XCTestCase {
    private func makeMenus() -> [LunaMenuDefinition] {
        [
            LunaMenuDefinition(id: "file", title: "File", items: [
                .command(id: "file.new", title: "New File", command: "demo.file.new", keyEquivalent: LunaKeyEquivalent("N", modifiers: [.primary])),
                .separator(id: "file.sep"),
                .command(id: "file.disabled", title: "Disabled", command: "demo.disabled", isEnabled: false),
            ]),
            LunaMenuDefinition(id: "edit", title: "Edit", items: [
                .command(id: "edit.selectAll", title: "Select All", command: "demo.edit.selectAll", keyEquivalent: LunaKeyEquivalent("A", modifiers: [.primary])),
                .submenu(id: "edit.convert", title: "Convert Case", children: [
                    .command(id: "edit.convert.upper", title: "Upper Case", command: "demo.convert.upper"),
                    .command(id: "edit.convert.lower", title: "Lower Case", command: "demo.convert.lower", isChecked: true),
                ]),
            ]),
        ]
    }

    func testMenuBarLaysOutTopLevelMenusAndDropdownRows() {
        var state = LunaMenuBarState()
        state.open(menuIndex: 1, menus: makeMenus())
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 24), menus: makeMenus(), state: state, theme: .lunaDefaultDark)
        let layout = menu.layout()

        XCTAssertEqual(layout.topLevelFrames.map(\.title), ["File", "Edit"])
        XCTAssertEqual(layout.dropdowns.count, 1)
        XCTAssertEqual(layout.dropdowns.first?.rows.map(\.item.title), ["Select All", "Convert Case"])
        XCTAssertEqual(layout.dropdowns.first?.rows.first?.item.keyEquivalent?.lunaMenuDisplayString, "Ctrl+A")
    }

    func testPointerClickTopLevelOpensDropdown() {
        var state = LunaMenuBarState()
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 24), menus: makeMenus(), state: state, theme: .lunaDefaultDark)
        let editFrame = menu.layout().topLevelFrames[1]

        let result = menu.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: editFrame.bounds.x + 2, y: editFrame.bounds.y + 2)),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertEqual(state.activeMenuIndex, 1)
        XCTAssertEqual(state.highlightedPath, LunaMenuItemPath(menuIndex: 1, itemIndices: [0]))
    }

    func testPointerClickCommandRowRequestsCommandAndCloses() {
        var state = LunaMenuBarState()
        state.open(menuIndex: 1, menus: makeMenus())
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 24), menus: makeMenus(), state: state, theme: .lunaDefaultDark)
        let row = menu.layout().dropdowns[0].rows[0]

        let result = menu.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: row.bounds.x + 4, y: row.bounds.y + 4)),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertTrue(result.didDismiss)
        XCTAssertEqual(result.requestedCommand, "demo.edit.selectAll")
        XCTAssertFalse(state.isOpen)
    }

    func testDisabledRowsConsumeWithoutActivating() {
        var state = LunaMenuBarState()
        state.open(menuIndex: 0, menus: makeMenus())
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 24), menus: makeMenus(), state: state, theme: .lunaDefaultDark)
        let disabled = menu.layout().dropdowns[0].rows.first { $0.item.title == "Disabled" }!

        let result = menu.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: disabled.bounds.x + 3, y: disabled.bounds.y + 3)),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertNil(result.requestedCommand)
        XCTAssertTrue(state.isOpen)
    }

    func testKeyboardNavigationAndActivation() {
        var state = LunaMenuBarState()
        state.open(menuIndex: 1, menus: makeMenus())
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 24), menus: makeMenus(), state: state, theme: .lunaDefaultDark)

        _ = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowDown), state: &state)
        XCTAssertEqual(state.highlightedPath, LunaMenuItemPath(menuIndex: 1, itemIndices: [1]))

        _ = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowRight), state: &state)
        XCTAssertEqual(state.highlightedPath, LunaMenuItemPath(menuIndex: 1, itemIndices: [1, 0]))

        let result = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .enter), state: &state)
        XCTAssertEqual(result.requestedCommand, "demo.convert.upper")
        XCTAssertFalse(state.isOpen)
    }


    func testKeyboardNavigationWrapsRowsWithinMenuLevel() {
        var state = LunaMenuBarState()
        state.open(menuIndex: 1, menus: makeMenus())
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 24), menus: makeMenus(), state: state, theme: .lunaDefaultDark)

        _ = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowUp), state: &state)
        XCTAssertEqual(state.highlightedPath, LunaMenuItemPath(menuIndex: 1, itemIndices: [1]))

        _ = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowDown), state: &state)
        XCTAssertEqual(state.highlightedPath, LunaMenuItemPath(menuIndex: 1, itemIndices: [0]))
    }

    func testDropdownClampsToAvailableMenuBarWidth() {
        let menus = [
            LunaMenuDefinition(id: "a", title: "A", items: [.command(id: "a.one", title: "One", command: "demo.one")]),
            LunaMenuDefinition(id: "b", title: "B", items: [.command(id: "b.one", title: "One", command: "demo.one")]),
            LunaMenuDefinition(id: "c", title: "C", items: [.command(id: "c.one", title: "One", command: "demo.one")]),
            LunaMenuDefinition(id: "d", title: "D", items: [.command(id: "d.one", title: "One", command: "demo.one")]),
            LunaMenuDefinition(id: "wide", title: "Wide", items: [
                .command(id: "wide.long", title: "A Very Long Menu Item Title That Forces The Dropdown Wider", command: "demo.long")
            ]),
        ]
        var state = LunaMenuBarState()
        state.open(menuIndex: 4, menus: menus)
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 400, h: 24), menus: menus, state: state, theme: .lunaDefaultDark)
        let dropdown = menu.layout().dropdowns[0]

        XCTAssertLessThanOrEqual(dropdown.bounds.x + dropdown.bounds.w, menu.bounds.x + menu.bounds.w)
    }

    func testEscapeDismissesOpenMenu() {
        var state = LunaMenuBarState()
        state.open(menuIndex: 0, menus: makeMenus())
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 24), menus: makeMenus(), state: state, theme: .lunaDefaultDark)

        let result = menu.handleKeyboardEvent(LunaKeyboardEvent(key: .escape), state: &state)

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertTrue(result.didDismiss)
        XCTAssertFalse(state.isOpen)
    }

    func testMenuBuildsThemeDrivenDisplayList() {
        var state = LunaMenuBarState()
        state.open(menuIndex: 0, menus: makeMenus())
        let theme = LunaTheme.highContrastProof
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 24), menus: makeMenus(), state: state, theme: theme)
        var displayList = LunaDisplayList()

        menu.buildDisplayList(into: &displayList)

        XCTAssertTrue(displayList.commands.contains(.rect(menu.bounds, theme.ui.chrome.menuBarBackground.asRenderColor)))
        XCTAssertTrue(displayList.commands.contains { command in
            if case .rect(_, let color) = command { return color == theme.ui.menu.background.asRenderColor }
            return false
        })
    }

    func testMenuTextLayoutsUseCompactMenuMetrics() {
        var state = LunaMenuBarState()
        state.open(menuIndex: 1, menus: makeMenus())
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 24), menus: makeMenus(), state: state, theme: .lunaDefaultDark)
        let layout = menu.layout()
        let metrics = menu.metrics.glyphMetrics

        let editTop = layout.topLevelFrames[1]
        let topTextBounds = LunaRectI(
            x: editTop.bounds.x + 8,
            y: editTop.bounds.y + max(0, (editTop.bounds.h - metrics.glyphHeight) / 2),
            w: max(1, editTop.bounds.w - 16),
            h: metrics.lineHeight
        )
        XCTAssertEqual(LunaBoundedTextLayout.layout(editTop.title, in: topTextBounds, metrics: metrics).firstLine?.text, "Edit")

        let selectAllRow = layout.dropdowns[0].rows[0]
        XCTAssertEqual(LunaBoundedTextLayout.layout(selectAllRow.item.title, in: selectAllRow.titleBounds, metrics: metrics).firstLine?.text, "Select All")
        XCTAssertEqual(
            LunaBoundedTextLayout.layout(selectAllRow.item.keyEquivalent?.lunaMenuDisplayString ?? "", in: selectAllRow.shortcutBounds, metrics: metrics, alignment: .trailing).firstLine?.text,
            "Ctrl+A"
        )
    }

    func testMenuAccessibilityExposesMenuAndMenuItems() {
        var state = LunaMenuBarState()
        state.open(menuIndex: 1, menus: makeMenus())
        state.highlight(LunaMenuItemPath(menuIndex: 1, itemIndices: [1, 1]), menus: makeMenus())
        let menu = LunaMenuBar(id: "menu", bounds: LunaRectI(x: 0, y: 0, w: 800, h: 24), menus: makeMenus(), state: state, theme: .lunaDefaultDark)

        let root = menu.buildAccessibilityNode()
        let children = menu.buildAccessibilityChildren()

        XCTAssertEqual(root.role, .menuBar)
        XCTAssertTrue(children.contains { $0.role == .menu && $0.label == "Edit" })
        XCTAssertTrue(children.contains { $0.role == .menuItem && $0.label == "Checked, Lower Case" && $0.isFocused })
    }
}
