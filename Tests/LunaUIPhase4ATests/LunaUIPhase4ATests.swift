// SPDX-License-Identifier: MPL-2.0
import Testing
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme
import LunaUI

@Suite("Phase 4A quick panel")
struct LunaUIPhase4ATests {
    private func items() -> [LunaQuickPanelItem] {
        [
            LunaQuickPanelItem(id: "cmd.open-file", title: "Open File", subtitle: "File", command: "app.openFile"),
            LunaQuickPanelItem(id: "cmd.open-folder", title: "Open Folder", subtitle: "Project", command: "app.openFolder"),
            LunaQuickPanelItem(id: "cmd.save", title: "Save", subtitle: "File", command: "app.save"),
            LunaQuickPanelItem(id: "cmd.toggle-sidebar", title: "Toggle Sidebar", subtitle: "View", command: "app.toggleSidebar"),
        ]
    }

    @Test("filtering returns palette-visible items in stable order for empty query")
    func emptyQueryKeepsInsertionOrder() {
        let matches = LunaQuickPanelFilter.matches(items: items(), query: "")
        #expect(matches.map(\.item.title) == ["Open File", "Open Folder", "Save", "Toggle Sidebar"])
        #expect(matches.map(\.originalIndex) == [0, 1, 2, 3])
    }

    @Test("filtering matches title subtitle and command tokens")
    func filteringMatchesMultipleFields() {
        #expect(LunaQuickPanelFilter.matches(items: items(), query: "open").map(\.item.title) == ["Open File", "Open Folder"])
        #expect(LunaQuickPanelFilter.matches(items: items(), query: "project").map(\.item.title) == ["Open Folder"])
        #expect(LunaQuickPanelFilter.matches(items: items(), query: "sidebar").map(\.item.title) == ["Toggle Sidebar"])
    }

    @Test("disabled items remain searchable and report their command")
    func disabledItemsRemainSearchable() {
        let disabled = LunaQuickPanelItem(
            id: "cmd.find",
            title: "Find",
            subtitle: "Unavailable in this context",
            command: "app.find",
            isEnabled: false
        )
        let enabled = LunaQuickPanelItem(
            id: "cmd.find-in-files",
            title: "Find in Files",
            command: "app.findInFiles"
        )
        var state = LunaQuickPanelState(
            items: items() + [disabled, enabled],
            query: "find"
        )

        #expect(state.matches.map(\.item.title) == ["Find in Files", "Find"])
        state.selectedIndex = 1
        #expect(state.selectedMatch?.item.isEnabled == false)

        let result = state.handleKeyboardEvent(LunaKeyboardEvent(key: .enter))
        #expect(result.didConsumeEvent)
        #expect(result.didDismiss)
        #expect(result.requestedCommand == "app.find")
        #expect(result.selectedItem?.isEnabled == false)
    }

    @Test("state text input updates query and resets selection")
    func stateTextInput() {
        var state = LunaQuickPanelState(items: items(), selectedIndex: 2)
        let result = state.handleTextInput(LunaTextInputEvent(text: "open"))
        #expect(result.didConsumeEvent)
        #expect(result.didChangeState)
        #expect(state.query == "open")
        #expect(state.selectedIndex == 0)
        #expect(state.matches.count == 2)
    }

    @Test("keyboard navigation clamps and enter requests selected command")
    func keyboardNavigationAndEnter() {
        var state = LunaQuickPanelState(items: items(), query: "open")
        _ = state.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowDown))
        _ = state.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowDown))
        #expect(state.selectedIndex == 1)
        let result = state.handleKeyboardEvent(LunaKeyboardEvent(key: .enter))
        #expect(result.didConsumeEvent)
        #expect(result.didDismiss)
        #expect(result.requestedCommand == "app.openFolder")
        #expect(result.selectedItem?.title == "Open Folder")
    }

    @Test("backspace edits query and escape dismisses")
    func backspaceAndEscape() {
        var state = LunaQuickPanelState(items: items(), query: "save")
        let backspace = state.handleKeyboardEvent(LunaKeyboardEvent(key: .backspace))
        #expect(backspace.didConsumeEvent)
        #expect(backspace.didChangeState)
        #expect(state.query == "sav")

        let escape = state.handleKeyboardEvent(LunaKeyboardEvent(key: .escape))
        #expect(escape.didConsumeEvent)
        #expect(escape.didDismiss)
    }

    @Test("layout creates centered panel, input field, and rows")
    func layoutGeometry() {
        let state = LunaQuickPanelState(items: items(), query: "open")
        let panel = LunaQuickPanel(
            id: "quick",
            bounds: LunaRectI(x: 0, y: 0, w: 900, h: 600),
            state: state,
            theme: .lunaDefaultDark
        )
        let layout = panel.layout()
        #expect(layout.panelBounds.w <= panel.metrics.maxPanelWidth)
        #expect(layout.panelBounds.x > 0)
        #expect(layout.inputBounds.w > 0)
        #expect(layout.rows.count == 2)
        #expect(layout.rows[0].isSelected)
        #expect(layout.rows[0].bounds.y >= layout.listBounds.y)
    }

    @Test("display list uses theme-driven panel, text-field, and selected-row colors")
    func displayListUsesThemeTokens() {
        let state = LunaQuickPanelState(items: items(), query: "open")
        let panel = LunaQuickPanel(
            id: "quick",
            bounds: LunaRectI(x: 0, y: 0, w: 640, h: 480),
            state: state,
            theme: .highContrastProof
        )
        var displayList = LunaDisplayList()
        panel.buildDisplayList(into: &displayList)
        #expect(displayList.commands.contains(.rect(panel.bounds, LunaPanelVisualStyle(theme: .highContrastProof).overlayBackdrop)))
        #expect(displayList.commands.contains { command in
            if case .rect(_, LunaTextFieldVisualStyle(theme: .highContrastProof).background) = command { return true }
            return false
        })
        #expect(displayList.commands.contains { command in
            if case .rect(_, LunaMenuVisualStyle(theme: .highContrastProof).rowHoveredBackground) = command { return true }
            return false
        })
    }

    @Test("accessibility exposes editable query and focused selected row")
    func accessibilityTree() {
        var state = LunaQuickPanelState(items: items(), query: "open")
        _ = state.handleKeyboardEvent(LunaKeyboardEvent(key: .arrowDown))
        let panel = LunaQuickPanel(
            id: "quick",
            bounds: LunaRectI(x: 0, y: 0, w: 640, h: 480),
            state: state
        )
        let root = panel.buildAccessibilityNode()
        let children = panel.buildAccessibilityChildren()
        #expect(root.role == .dialog)
        #expect(root.children == [panel.inputNodeID, panel.listNodeID])
        #expect(children.contains { $0.id == panel.inputNodeID && $0.role == .textArea && $0.isEditable && $0.value == "open" })
        #expect(children.contains { $0.role == .listItem && $0.label == "Open Folder" && $0.isFocused })
    }

    @Test("hit testing returns row IDs before panel/backdrop")
    func hitTestingRows() {
        let state = LunaQuickPanelState(items: items(), query: "open")
        let panel = LunaQuickPanel(
            id: "quick",
            bounds: LunaRectI(x: 0, y: 0, w: 640, h: 480),
            state: state
        )
        let row = panel.layout().rows[0]
        let hit = panel.hitTest(LunaPointI(x: row.bounds.x + 2, y: row.bounds.y + 2))
        #expect(hit == row.nodeID)
        #expect(panel.rowIndex(for: hit!) == 0)
    }
}
