import XCTest
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaLayout
import LunaRender
import LunaTheme
import LunaUI

final class LunaUIPhase2DTests: XCTestCase {
    func testAnchoredLayoutReflowsWhenViewportChanges() {
        let spec = LunaAnchoredLayoutSpec(
            id: "layout.semantic-widget",
            anchor: .topRight,
            sizeRule: LunaLayoutSizeRule(
                preferred: LunaSizeI(width: 240, height: 56),
                minimum: LunaSizeI(width: 180, height: 56),
                maximum: LunaSizeI(width: 300, height: 56)
            ),
            margin: LunaInsetsI(top: 54, right: 18, bottom: 18, left: 18)
        )

        let small = spec.frame(in: LunaLayoutContext(viewport: LunaViewport(width: 640, height: 480))).bounds
        let large = spec.frame(in: LunaLayoutContext(viewport: LunaViewport(width: 1200, height: 800))).bounds

        XCTAssertEqual(small.y, 54)
        XCTAssertEqual(large.y, 54)
        XCTAssertGreaterThan(large.x, small.x)
        XCTAssertEqual(small.w, 240)
        XCTAssertEqual(large.w, 240)
    }

    func testLayoutResultProvidesSharedBoundsForWidgetHitTestAndAccessibility() {
        let widgetID: LunaNodeID = "layout.widget"
        let bounds = LunaRectI(x: 320, y: 72, w: 260, h: 56)
        var result = LunaLayoutResult()
        result.set(id: widgetID, bounds: bounds)

        let widget = LunaSemanticActionWidget(
            id: widgetID,
            bounds: result.frame(for: widgetID)!,
            title: "Layout Widget",
            primaryCommand: "luna.layout.widget",
            theme: .mothDefaultDark
        )

        XCTAssertEqual(widget.bounds, bounds)
        XCTAssertEqual(widget.hitTest(LunaPointI(x: 322, y: 74)), widgetID)
        XCTAssertEqual(widget.buildAccessibilityNode().bounds, bounds.asAccessibilityRect)
    }

    func testModalReflowUpdatesDrawHitTestAndAccessibilityBounds() {
        var manager = LunaModalOverlayManager(style: LunaMothDefaultDarkControlStyle(theme: .mothDefaultDark))
        _ = manager.open(
            .notice(
                LunaNoticeRequest(
                    id: "layout.notice",
                    title: "Resize Proof",
                    message: "Resize while open"
                )
            ),
            viewportSize: LunaSizeI(width: 640, height: 480)
        )

        guard let before = manager.active else {
            XCTFail("Expected active modal")
            return
        }
        let beforePanel = before.panelBounds
        let beforeChoice = before.choices[0]
        XCTAssertEqual(before.buildAccessibilityNode().bounds, beforePanel.asAccessibilityRect)
        XCTAssertEqual(before.hitTest(LunaPointI(x: beforeChoice.bounds.x + 1, y: beforeChoice.bounds.y + 1)), beforeChoice.id)

        manager.reflow(viewportSize: LunaSizeI(width: 1100, height: 700))

        guard let after = manager.active else {
            XCTFail("Expected active modal after reflow")
            return
        }
        let afterPanel = after.panelBounds
        let afterChoice = after.choices[0]

        XCTAssertNotEqual(afterPanel.x, beforePanel.x)
        XCTAssertNotEqual(afterPanel.y, beforePanel.y)
        XCTAssertEqual(after.buildAccessibilityNode().bounds, afterPanel.asAccessibilityRect)
        XCTAssertEqual(after.hitTest(LunaPointI(x: afterChoice.bounds.x + 1, y: afterChoice.bounds.y + 1)), afterChoice.id)
        XCTAssertNil(after.hitTest(LunaPointI(x: beforeChoice.bounds.x + 1, y: beforeChoice.bounds.y + 1)))

        let child = after.buildAccessibilityChildren().first { $0.id == afterChoice.id }
        XCTAssertEqual(child?.bounds, afterChoice.bounds.asAccessibilityRect)
    }

    func testModalManagerPointerRoutingUsesReflowedChoiceBounds() {
        var manager = LunaModalOverlayManager(style: LunaMothDefaultDarkControlStyle(theme: .mothDefaultDark))
        _ = manager.open(
            .notice(LunaNoticeRequest(id: "layout.pointer", title: "Pointer", message: "Reflowed hit test")),
            viewportSize: LunaSizeI(width: 520, height: 360)
        )
        let oldChoice = manager.active!.choices[0]
        manager.reflow(viewportSize: LunaSizeI(width: 1000, height: 700))
        let newChoice = manager.active!.choices[0]

        var context = LunaUIContext()
        let oldDown = manager.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: oldChoice.bounds.x + 2, y: oldChoice.bounds.y + 2), button: .primary),
            context: &context
        )
        XCTAssertTrue(oldDown.didConsumeEvent)
        XCTAssertNil(oldDown.hitNodeID)
        XCTAssertTrue(manager.hasActiveModal)

        let newDown = manager.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: newChoice.bounds.x + 2, y: newChoice.bounds.y + 2), button: .primary),
            context: &context
        )
        XCTAssertEqual(newDown.hitNodeID, newChoice.id)
    }
}
