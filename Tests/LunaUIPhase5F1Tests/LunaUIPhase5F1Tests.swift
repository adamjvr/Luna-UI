// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase5F1Tests: XCTestCase {
    private func twoPaneState() -> LunaPaneWorkspaceState {
        LunaPaneWorkspaceState(
            root: .split(
                id: "root",
                axis: .horizontal,
                fraction: 0.6,
                first: .pane("left"),
                second: .pane("right")
            ),
            activePaneID: "left"
        )
    }

    func testSplitLayoutProducesStablePaneAndDividerGeometry() {
        let container = LunaPaneContainer(
            id: "panes",
            bounds: LunaRectI(x: 10, y: 20, w: 405, h: 240),
            state: twoPaneState(),
            theme: .highContrastProof,
            metrics: LunaPaneContainerMetrics(dividerThickness: 5, minimumPaneExtent: 40)
        )
        let layout = container.layout()

        XCTAssertEqual(layout.paneFrames.map(\.paneID), ["left", "right"])
        XCTAssertEqual(layout.dividerFrames.map(\.splitID), ["root"])
        XCTAssertEqual(layout.paneFrames[0].bounds.w + layout.dividerFrames[0].bounds.w + layout.paneFrames[1].bounds.w, 405)
        XCTAssertEqual(layout.paneFrames[0].bounds.y, 20)
        XCTAssertEqual(layout.paneFrames[1].bounds.y, 20)
        XCTAssertFalse(layout.paneFrames[0].bounds.contains(
            x: layout.paneFrames[1].bounds.x,
            y: layout.paneFrames[1].bounds.y
        ))
    }

    func testPaneTraversalSupportsVisualDirectionAndWrappingOrder() {
        var state = twoPaneState()
        let container = LunaPaneContainer(
            id: "panes",
            bounds: LunaRectI(x: 0, y: 0, w: 500, h: 300),
            state: state,
            theme: .highContrastProof
        )
        let layout = container.layout()

        XCTAssertEqual(state.traverse(.right, layout: layout), "right")
        XCTAssertEqual(state.traverse(.left, layout: layout), "left")
        XCTAssertEqual(state.traverse(.previous), "right")
        XCTAssertEqual(state.traverse(.next), "left")
    }

    func testSplitInsertResizeAndRemovalRemainProductNeutral() {
        var state = LunaPaneWorkspaceState(root: .pane("only"))

        XCTAssertTrue(state.split(
            paneID: "only",
            newPaneID: "second",
            splitID: "split.1",
            axis: .vertical,
            placement: .after,
            fraction: 0.75
        ))
        XCTAssertEqual(state.paneIDs, ["only", "second"])
        XCTAssertEqual(state.activePaneID, "second")
        XCTAssertTrue(state.setSplitFraction(2.0, for: "split.1"))

        if case .split(_, _, let fraction, _, _) = state.root {
            XCTAssertEqual(fraction, state.maximumSplitFraction)
        } else {
            XCTFail("Expected split root")
        }

        XCTAssertTrue(state.remove(paneID: "second"))
        XCTAssertEqual(state.root, .pane("only"))
        XCTAssertEqual(state.activePaneID, "only")
        XCTAssertFalse(state.remove(paneID: "only"), "The final pane cannot be removed")
    }

    func testPaneCommandContextCarriesOnlyNeutralIdentifiers() {
        let state = twoPaneState()
        let context = state.commandContext(
            activeDocumentID: "document.7",
            source: "keyboard",
            targetPaneID: "right"
        )

        XCTAssertEqual(context.focusedSurface, "luna.pane.left")
        XCTAssertEqual(context.activeDocumentID, "document.7")
        XCTAssertEqual(context.value(for: LunaCommandContextAttributeKey.activePaneID), "left")
        XCTAssertEqual(context.value(for: LunaCommandContextAttributeKey.targetPaneID), "right")
    }

    func testPinnedTabsRemainVisibleAndActiveOverflowTabIsBroughtIntoView() {
        let tabs: [LunaShellTab] = [
            LunaShellTab(id: "pin", title: "P", isPinned: true),
            LunaShellTab(id: "one", title: "one.swift"),
            LunaShellTab(id: "two", title: "two.swift"),
            LunaShellTab(id: "three", title: "three.swift"),
            LunaShellTab(id: "four", title: "four.swift"),
        ]
        let shell = LunaEditorShell(
            id: "shell",
            bounds: LunaRectI(x: 0, y: 0, w: 250, h: 240),
            tabs: tabs,
            sidebarItems: [],
            statusSegments: [],
            state: LunaEditorShellState(
                tabStrip: LunaTabStripState(activeTabID: "four")
            ),
            theme: .highContrastProof
        )
        let layout = shell.layout()
        let visibleIDs = layout.tabFrames.map(\.tab.id)

        XCTAssertTrue(layout.hasTabOverflow)
        XCTAssertTrue(visibleIDs.contains("pin"), "Pinned tabs must remain visible")
        XCTAssertTrue(visibleIDs.contains("four"), "The active unpinned tab must be visible")
        XCTAssertNotNil(layout.tabOverflowButtonBounds)
        XCTAssertFalse(layout.hiddenTabIDs.contains("pin"))
        XCTAssertFalse(layout.hiddenTabIDs.contains("four"))
    }

    func testOverflowButtonTogglesReusablePresentationState() {
        let tabs = (0..<8).map { index in
            LunaShellTab(id: LunaShellTabID(rawValue: "tab.\(index)"), title: "file-\(index).swift")
        }
        var state = LunaEditorShellState(
            tabStrip: LunaTabStripState(activeTabID: tabs[0].id)
        )
        let shell = LunaEditorShell(
            id: "shell",
            bounds: LunaRectI(x: 0, y: 0, w: 260, h: 200),
            tabs: tabs,
            sidebarItems: [],
            statusSegments: [],
            state: state,
            theme: .highContrastProof
        )
        guard let overflow = shell.layout().tabOverflowButtonBounds else {
            return XCTFail("Expected overflow button")
        }

        let result = shell.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
                location: LunaPointI(x: overflow.x + 1, y: overflow.y + 1),
                button: .primary
            ),
            state: &state
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertTrue(result.didToggleTabOverflow)
        XCTAssertTrue(state.tabStrip.isOverflowPresented)
    }

    func testKeyboardTabTraversalWrapsAcrossPinnedAndRegularTabs() {
        let tabs: [LunaShellTab] = [
            LunaShellTab(id: "pin", title: "P", isPinned: true),
            LunaShellTab(id: "one", title: "One"),
            LunaShellTab(id: "two", title: "Two"),
        ]
        var state = LunaTabStripState(activeTabID: "two", isOverflowPresented: true)

        XCTAssertEqual(state.selectNextTab(in: tabs), "pin")
        XCTAssertFalse(state.isOverflowPresented)
        XCTAssertEqual(state.selectPreviousTab(in: tabs), "two")
    }
}
