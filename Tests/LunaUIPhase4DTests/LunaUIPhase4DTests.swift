import XCTest
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase4DTests: XCTestCase {
    private func makeTabs() -> [LunaShellTab] {
        [
            LunaShellTab(
                id: "main",
                title: "main.swift",
                detail: "Sources/App/main.swift",
                isDirty: true,
                activateCommand: "demo.tab.main",
                closeCommand: "demo.tab.close.main"
            ),
            LunaShellTab(
                id: "readme",
                title: "README.md",
                isClosable: false,
                activateCommand: "demo.tab.readme"
            ),
            LunaShellTab(
                id: "theme",
                title: "Theme.json",
                isPinned: true,
                activateCommand: "demo.tab.theme"
            ),
        ]
    }

    private func makeSidebarItems() -> [LunaSidebarItem] {
        [
            LunaSidebarItem(
                id: "project",
                title: "Luna-UI",
                kind: .folder,
                children: [
                    LunaSidebarItem(id: "sources", title: "Sources", kind: .folder, children: [
                        LunaSidebarItem(id: "shell", title: "LunaEditorShell.swift", kind: .file, activateCommand: "demo.sidebar.shell"),
                        LunaSidebarItem(id: "menu", title: "LunaMenu.swift", kind: .file, activateCommand: "demo.sidebar.menu"),
                    ], isSelectable: false),
                    LunaSidebarItem(id: "tests", title: "Tests", kind: .folder, isSelectable: false),
                    LunaSidebarItem(id: "package", title: "Package.swift", kind: .file, activateCommand: "demo.sidebar.package"),
                ],
                isSelectable: false
            )
        ]
    }

    private func makeStatusSegments() -> [LunaStatusSegment] {
        [
            LunaStatusSegment(id: "message", title: "Ready", placement: .leading),
            LunaStatusSegment(id: "branch", title: "main", placement: .leading, emphasis: .accent, command: "demo.status.branch"),
            LunaStatusSegment(id: "syntax", title: "Swift", placement: .trailing),
            LunaStatusSegment(id: "position", title: "Ln", value: "12, Col 4", placement: .trailing, emphasis: .muted),
        ]
    }

    private func makeShell(state: LunaEditorShellState? = nil) -> LunaEditorShell {
        var resolved = state ?? LunaEditorShellState(
            tabStrip: LunaTabStripState(activeTabID: "main"),
            sidebar: LunaSidebarState(selectedItemID: "package", expandedItemIDs: ["project", "sources"]),
            sidebarWidth: 220
        )
        resolved.normalize(tabs: makeTabs(), sidebarItems: makeSidebarItems())
        return LunaEditorShell(
            id: "shell",
            bounds: LunaRectI(x: 0, y: 24, w: 900, h: 520),
            tabs: makeTabs(),
            sidebarTitle: "Project",
            sidebarItems: makeSidebarItems(),
            statusSegments: makeStatusSegments(),
            state: resolved,
            theme: .lunaDefaultDark,
            metrics: .demo
        )
    }

    func testShellLaysOutTabsSidebarContentAndStatusBar() {
        let shell = makeShell()
        let layout = shell.layout()

        XCTAssertEqual(layout.tabStripBounds, LunaRectI(x: 0, y: 24, w: 900, h: 30))
        XCTAssertEqual(layout.statusBarBounds.h, 26)
        XCTAssertEqual(layout.sidebarBounds.w, 220)
        XCTAssertEqual(layout.editorContentBounds.x, layout.sidebarBounds.x + layout.sidebarBounds.w)
        XCTAssertEqual(layout.tabFrames.map(\.tab.title), ["main.swift", "README.md", "Theme.json"])
        XCTAssertTrue(layout.tabFrames[0].dirtyIndicatorBounds != nil)
        XCTAssertTrue(layout.tabFrames[0].closeButtonBounds != nil)
        XCTAssertNil(layout.tabFrames[1].closeButtonBounds)
        XCTAssertEqual(layout.sidebarRows.map(\.item.title), ["Luna-UI", "Sources", "LunaEditorShell.swift", "LunaMenu.swift", "Tests", "Package.swift"])
        XCTAssertEqual(Set(layout.statusSegments.map(\.segment.id)), Set(["message", "branch", "syntax", "position"]))
    }

    func testCollapsedSidebarHidesDescendantRowsButKeepsStableContentBounds() {
        let state = LunaEditorShellState(
            tabStrip: LunaTabStripState(activeTabID: "readme"),
            sidebar: LunaSidebarState(selectedItemID: nil, expandedItemIDs: ["project"]),
            sidebarWidth: 210
        )
        let shell = makeShell(state: state)
        let layout = shell.layout()

        XCTAssertEqual(layout.sidebarRows.map(\.item.title), ["Luna-UI", "Sources", "Tests", "Package.swift"])
        XCTAssertEqual(layout.editorContentBounds.x, layout.sidebarBounds.x + 210)
    }

    func testPointerDownOnTabSelectsActiveTabAndRequestsCommand() {
        var state = makeShell().state
        let shell = makeShell(state: state)
        let readme = shell.layout().tabFrames[1]

        let result = shell.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: readme.bounds.x + 4, y: readme.bounds.y + 4)),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertEqual(result.selectedTabID, "readme")
        XCTAssertEqual(result.requestedCommand, "demo.tab.readme")
        XCTAssertEqual(state.tabStrip.activeTabID, "readme")
    }

    func testPointerUpOnPressedCloseButtonRequestsCloseCommand() throws {
        var state = makeShell().state
        var shell = makeShell(state: state)
        let main = shell.layout().tabFrames[0]
        let close = try XCTUnwrap(main.closeButtonBounds)

        _ = shell.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: close.x + 1, y: close.y + 1)),
            state: &state
        )
        shell = makeShell(state: state)
        let result = shell.handlePointerEvent(
            LunaPointerEvent(phase: .up, location: LunaPointI(x: close.x + 1, y: close.y + 1)),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertEqual(result.closedTabID, "main")
        XCTAssertEqual(result.requestedCommand, "demo.tab.close.main")
    }

    func testSidebarDisclosureTogglesAndRowsSelectThroughState() throws {
        var state = LunaEditorShellState(
            tabStrip: LunaTabStripState(activeTabID: "main"),
            sidebar: LunaSidebarState(selectedItemID: nil, expandedItemIDs: ["project"]),
            sidebarWidth: 220
        )
        var shell = makeShell(state: state)
        let sources = try XCTUnwrap(shell.layout().sidebarRows.first { $0.item.id == "sources" })
        let disclosure = try XCTUnwrap(sources.disclosureBounds)

        let toggle = shell.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: disclosure.x + 1, y: disclosure.y + 1)),
            state: &state
        )
        XCTAssertEqual(toggle.toggledSidebarItemID, "sources")
        XCTAssertTrue(state.sidebar.expandedItemIDs.contains("sources"))

        shell = makeShell(state: state)
        let shellFile = try XCTUnwrap(shell.layout().sidebarRows.first { $0.item.id == "shell" })
        let select = shell.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: shellFile.titleBounds.x + 1, y: shellFile.titleBounds.y + 1)),
            state: &state
        )

        XCTAssertEqual(select.selectedSidebarItemID, "shell")
        XCTAssertEqual(select.requestedCommand, "demo.sidebar.shell")
        XCTAssertEqual(state.sidebar.selectedItemID, "shell")
    }

    func testStatusSegmentCanRequestACommand() throws {
        var state = makeShell().state
        let shell = makeShell(state: state)
        let branch = try XCTUnwrap(shell.layout().statusSegments.first { $0.segment.id == "branch" })

        let result = shell.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: branch.bounds.x + 2, y: branch.bounds.y + 2)),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertEqual(result.activatedStatusSegmentID, "branch")
        XCTAssertEqual(result.requestedCommand, "demo.status.branch")
    }

    func testShellBuildsThemeDrivenDisplayList() {
        let shell = makeShell()
        var displayList = LunaDisplayList()

        shell.buildDisplayList(into: &displayList)

        XCTAssertTrue(displayList.commands.contains(.rect(shell.layout().tabStripBounds, LunaTheme.lunaDefaultDark.ui.tabs.stripBackground.asRenderColor)))
        XCTAssertTrue(displayList.commands.contains(.rect(shell.layout().statusBarBounds, LunaTheme.lunaDefaultDark.ui.statusBar.background.asRenderColor)))
        XCTAssertTrue(displayList.commands.contains { command in
            if case .rect(_, let color) = command { return color == LunaTheme.lunaDefaultDark.ui.sidebar.background.asRenderColor }
            return false
        })
    }

    func testTextBoundsProduceVisibleLinesForDemoRenderer() throws {
        let shell = makeShell()
        let layout = shell.layout()
        let firstTab = try XCTUnwrap(layout.tabFrames.first)
        let firstRow = try XCTUnwrap(layout.sidebarRows.first)
        let firstStatus = try XCTUnwrap(layout.statusSegments.first)

        XCTAssertNotNil(LunaBoundedTextLayout.layout(firstTab.tab.title, in: firstTab.titleBounds, metrics: shell.metrics.glyphMetrics, overflow: .ellipsizeTail).firstLine)
        XCTAssertNotNil(LunaBoundedTextLayout.layout(firstRow.item.title, in: firstRow.titleBounds, metrics: shell.metrics.glyphMetrics, overflow: .ellipsizeTail).firstLine)
        XCTAssertNotNil(LunaBoundedTextLayout.layout(firstStatus.segment.visibleText, in: firstStatus.textBounds, metrics: shell.metrics.glyphMetrics, overflow: .ellipsizeTail).firstLine)
    }

    func testShellAccessibilityExposesTabSidebarAndStatusSemantics() {
        let shell = makeShell()
        let root = shell.buildAccessibilityNode()
        let children = shell.buildAccessibilityChildren()

        XCTAssertEqual(root.role, .group)
        XCTAssertTrue(children.contains { $0.id == shell.tabStripNodeID && $0.label == "Tabs" })
        XCTAssertTrue(children.contains { $0.label == "Modified, main.swift" && $0.role == .button && $0.isFocused })
        XCTAssertTrue(children.contains { $0.id == shell.sidebarNodeID && $0.role == .list && $0.label == "Project" })
        XCTAssertTrue(children.contains { $0.label == "Package.swift" && $0.role == .listItem && $0.isFocused })
        XCTAssertTrue(children.contains { $0.id == shell.statusBarNodeID && $0.role == .status })
        XCTAssertTrue(children.contains { $0.label == "main" && $0.role == .button })
    }
}
