// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIConvergenceC1ATests: XCTestCase {
    private func workspace(axis: LunaSplitAxis = .horizontal) -> LunaPaneWorkspaceState {
        LunaPaneWorkspaceState(
            root: .split(
                id: "root",
                axis: axis,
                fraction: 0.5,
                first: .pane("first"),
                second: .pane("second")
            ),
            activePaneID: "first"
        )
    }

    private func container(
        state: LunaPaneWorkspaceState,
        interaction: LunaPaneContainerInteractionState = LunaPaneContainerInteractionState()
    ) -> LunaPaneContainer {
        LunaPaneContainer(
            id: "panes",
            bounds: LunaRectI(x: 0, y: 0, w: 411, h: 240),
            state: state,
            interactionState: interaction,
            theme: .highContrastProof,
            metrics: LunaPaneContainerMetrics(
                dividerThickness: 11,
                dividerRuleThickness: 1,
                minimumPaneExtent: 40,
                activePaneBorderThickness: 2
            )
        )
    }

    func testDividerUsesWideSemanticControlAndThinCenteredRule() throws {
        let layout = container(state: workspace()).layout()
        let divider = try XCTUnwrap(layout.dividerFrames.first)
        XCTAssertEqual(divider.bounds.w, 11)
        XCTAssertEqual(divider.centerRuleBounds(thickness: 1).w, 1)
        XCTAssertEqual(
            divider.centerRuleBounds(thickness: 1).x,
            divider.bounds.x + 5
        )
    }

    func testCursorIntentMatchesDividerAxis() throws {
        let horizontal = container(state: workspace(axis: .horizontal))
        let vertical = container(state: workspace(axis: .vertical))
        let horizontalDivider = try XCTUnwrap(horizontal.layout().dividerFrames.first)
        let verticalDivider = try XCTUnwrap(vertical.layout().dividerFrames.first)

        XCTAssertEqual(horizontal.cursorIntent(at: LunaPointI(x: horizontalDivider.bounds.x + horizontalDivider.bounds.w / 2, y: horizontalDivider.bounds.y + horizontalDivider.bounds.h / 2)), .resizeHorizontal)
        XCTAssertEqual(vertical.cursorIntent(at: LunaPointI(x: verticalDivider.bounds.x + verticalDivider.bounds.w / 2, y: verticalDivider.bounds.y + verticalDivider.bounds.h / 2)), .resizeVertical)
        XCTAssertNil(horizontal.cursorIntent(at: LunaPointI(x: 5, y: 5)))
    }

    func testHoverUpdatesWithoutStartingPointerCapture() throws {
        var state = workspace()
        var interaction = LunaPaneContainerInteractionState()
        let widget = container(state: state)
        let divider = try XCTUnwrap(widget.layout().dividerFrames.first)

        let result = widget.handlePointerEvent(
            LunaPointerEvent(phase: .moved, location: LunaPointI(x: divider.bounds.x + divider.bounds.w / 2, y: divider.bounds.y + divider.bounds.h / 2)),
            state: &state,
            interactionState: &interaction
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertTrue(result.didChangeState)
        XCTAssertEqual(interaction.hoveredSplitID, "root")
        XCTAssertNil(interaction.draggedSplitID)
        XCTAssertFalse(interaction.wantsPointerCapture)
    }

    func testDividerDragRetainsOwnershipOutsideOriginalBoundsUntilMouseUp() throws {
        var state = workspace()
        var interaction = LunaPaneContainerInteractionState()
        var widget = container(state: state)
        let divider = try XCTUnwrap(widget.layout().dividerFrames.first)

        let down = widget.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
                location: LunaPointI(x: divider.bounds.x + divider.bounds.w / 2, y: divider.bounds.y + divider.bounds.h / 2),
                button: .primary
            ),
            state: &state,
            interactionState: &interaction
        )
        XCTAssertEqual(down.resizedSplitID, "root")
        XCTAssertEqual(interaction.draggedSplitID, "root")
        XCTAssertTrue(interaction.wantsPointerCapture)

        widget = container(state: state, interaction: interaction)
        let move = widget.handlePointerEvent(
            LunaPointerEvent(
                phase: .moved,
                location: LunaPointI(x: 380, y: -40),
                button: .primary
            ),
            state: &state,
            interactionState: &interaction
        )
        XCTAssertTrue(move.didConsumeEvent)
        XCTAssertEqual(move.resizedSplitID, "root")
        XCTAssertEqual(interaction.draggedSplitID, "root")
        XCTAssertTrue(interaction.wantsPointerCapture)

        widget = container(state: state, interaction: interaction)
        let up = widget.handlePointerEvent(
            LunaPointerEvent(
                phase: .up,
                location: LunaPointI(x: 380, y: -40),
                button: .primary
            ),
            state: &state,
            interactionState: &interaction
        )
        XCTAssertTrue(up.didConsumeEvent)
        XCTAssertNil(interaction.draggedSplitID)
        XCTAssertFalse(interaction.wantsPointerCapture)
    }

    func testAccessibilityDividerBoundsMatchInteractiveControlBounds() throws {
        let widget = container(state: workspace())
        let divider = try XCTUnwrap(widget.layout().dividerFrames.first)
        let node = try XCTUnwrap(widget.buildAccessibilityChildren().first { $0.id == divider.nodeID })
        XCTAssertEqual(node.bounds, divider.bounds.asAccessibilityRect)
    }
}
