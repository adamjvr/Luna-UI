import XCTest
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaRender
import LunaTheme
import LunaUI

final class LunaUIPhase1Tests: XCTestCase {
    func testSemanticActionWidgetBuildsDisplayListHitTestAndAccessibilityNode() {
        let widget = LunaSemanticActionWidget(
            id: "phase1.demo.widget",
            bounds: LunaRectI(x: 10, y: 20, w: 180, h: 64),
            title: "Run Phase 1",
            subtitle: "Semantic widget proof",
            primaryCommand: "luna.phase1.run",
            isFocused: true
        )

        var displayList = LunaDisplayList()
        widget.buildDisplayList(into: &displayList)

        XCTAssertGreaterThanOrEqual(displayList.commands.count, 5)
        XCTAssertEqual(widget.hitTest(LunaPointI(x: 12, y: 22)), "phase1.demo.widget")
        XCTAssertNil(widget.hitTest(LunaPointI(x: 9, y: 22)))

        let node = widget.buildAccessibilityNode()
        XCTAssertEqual(node.id, "phase1.demo.widget")
        XCTAssertEqual(node.role, .button)
        XCTAssertEqual(node.label, "Run Phase 1")
        XCTAssertEqual(node.value, "Semantic widget proof")
        XCTAssertEqual(node.bounds, LunaAccessibilityRect(x: 10, y: 20, width: 180, height: 64))
        XCTAssertTrue(node.actions.contains(.press))
        XCTAssertTrue(node.isFocused)

        let tree = LunaAccessibilityTree(rootID: node.id, nodes: [node.id: node])
        XCTAssertTrue(tree.validate().errors.isEmpty)
    }

    func testSemanticActionWidgetActivationQueuesCommandAndAnnouncement() {
        var widget = LunaSemanticActionWidget(
            id: "phase1.activate",
            bounds: LunaRectI(x: 0, y: 0, w: 120, h: 40),
            title: "Activate",
            primaryCommand: "luna.phase1.activate"
        )
        var context = LunaUIContext()

        let command = widget.activate(context: &context)

        XCTAssertEqual(command, "luna.phase1.activate")
        XCTAssertEqual(context.requestedCommands, ["luna.phase1.activate"])
        XCTAssertEqual(context.announcements.map(\.text), ["Activate activated"])
        XCTAssertTrue(context.requestedRefresh)
    }

    func testDisabledSemanticActionWidgetDoesNotQueueCommand() {
        var widget = LunaSemanticActionWidget(
            id: "phase1.disabled",
            bounds: LunaRectI(x: 0, y: 0, w: 120, h: 40),
            title: "Disabled",
            primaryCommand: "luna.phase1.disabled",
            isEnabled: false
        )
        var context = LunaUIContext()

        let command = widget.activate(context: &context)

        XCTAssertNil(command)
        XCTAssertTrue(context.requestedCommands.isEmpty)
        XCTAssertEqual(context.announcements.map(\.text), ["Disabled is disabled"])
        XCTAssertFalse(context.requestedRefresh)
    }

    func testSemanticActionWidgetCanDeriveRenderColorsFromTheme() {
        let widget = LunaSemanticActionWidget(
            id: "phase1.theme",
            bounds: LunaRectI(x: 0, y: 0, w: 50, h: 20),
            title: "Theme",
            primaryCommand: "luna.phase1.theme",
            theme: .default
        )

        var displayList = LunaDisplayList()
        widget.buildDisplayList(into: &displayList)

        XCTAssertEqual(
            displayList.commands.first,
            .rect(LunaRectI(x: 0, y: 0, w: 50, h: 20), LunaRender.LunaRGBA8(r: 80, g: 120, b: 160, a: 180))
        )
    }
}

final class LunaUIPhase1BTests: XCTestCase {
    func testPrimaryPointerDownInsideActionWidgetRoutesActivation() {
        var widget = LunaSemanticActionWidget(
            id: "phase1b.pointer",
            bounds: LunaRectI(x: 20, y: 30, w: 120, h: 44),
            title: "Pointer",
            primaryCommand: "luna.phase1b.pointer"
        )
        var context = LunaUIContext()
        let event = LunaPointerEvent(
            phase: .down,
            location: LunaPointI(x: 24, y: 36),
            button: .primary
        )

        let result = widget.handlePointerEvent(event, context: &context)

        XCTAssertEqual(result.hitNodeID, "phase1b.pointer")
        XCTAssertEqual(result.requestedCommand, "luna.phase1b.pointer")
        XCTAssertEqual(result.announcementTexts, ["Pointer activated"])
        XCTAssertEqual(context.requestedCommands, ["luna.phase1b.pointer"])
        XCTAssertTrue(context.requestedRefresh)
    }

    func testPointerDownOutsideActionWidgetDoesNotRouteActivation() {
        var widget = LunaSemanticActionWidget(
            id: "phase1b.pointer.miss",
            bounds: LunaRectI(x: 20, y: 30, w: 120, h: 44),
            title: "Pointer",
            primaryCommand: "luna.phase1b.pointer.miss"
        )
        var context = LunaUIContext()
        let event = LunaPointerEvent(
            phase: .down,
            location: LunaPointI(x: 10, y: 36),
            button: .primary
        )

        let result = widget.handlePointerEvent(event, context: &context)

        XCTAssertNil(result.hitNodeID)
        XCTAssertNil(result.requestedCommand)
        XCTAssertTrue(result.announcementTexts.isEmpty)
        XCTAssertTrue(context.requestedCommands.isEmpty)
        XCTAssertFalse(context.requestedRefresh)
    }

    func testNonPrimaryPointerDoesNotActivateActionWidget() {
        var widget = LunaSemanticActionWidget(
            id: "phase1b.pointer.secondary",
            bounds: LunaRectI(x: 20, y: 30, w: 120, h: 44),
            title: "Pointer",
            primaryCommand: "luna.phase1b.pointer.secondary"
        )
        var context = LunaUIContext()
        let event = LunaPointerEvent(
            phase: .down,
            location: LunaPointI(x: 24, y: 36),
            button: .secondary
        )

        let result = widget.handlePointerEvent(event, context: &context)

        XCTAssertNil(result.hitNodeID)
        XCTAssertNil(result.requestedCommand)
        XCTAssertTrue(context.requestedCommands.isEmpty)
    }

}
