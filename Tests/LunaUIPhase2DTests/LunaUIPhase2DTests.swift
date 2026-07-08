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

extension LunaUIPhase2DTests {
    func testModalTitleEllipsizesInsideNarrowPanel() {
        let overlay = LunaModalOverlay(
            request: .notice(
                LunaNoticeRequest(
                    id: "layout.title.wrap",
                    title: "This is a deliberately long modal title that must not spill outside the panel",
                    message: "Short body"
                )
            ),
            viewportSize: LunaSizeI(width: 300, height: 260)
        )

        let text = overlay.textLayout()
        XCTAssertLessThanOrEqual(text.title.bounds.x, overlay.panelBounds.x + overlay.panelBounds.w)
        XCTAssertLessThanOrEqual(text.title.bounds.x + text.title.bounds.w, overlay.panelBounds.x + overlay.panelBounds.w)
        XCTAssertTrue(text.title.text.hasSuffix("..."), "Expected narrow modal title to be ellipsized")
        XCTAssertEqual(text.title.fullText, overlay.title, "Accessibility/semantic text keeps the full title")
    }

    func testModalMessageWrapsInsidePanelAndAvoidsChoiceBounds() {
        let message = "Hover OK and then resize this modal very small. The body message should wrap to multiple visual lines without covering the OK button."
        let overlay = LunaModalOverlay(
            request: .notice(
                LunaNoticeRequest(
                    id: "layout.message.wrap",
                    title: "Wrapped Body",
                    message: message
                )
            ),
            viewportSize: LunaSizeI(width: 320, height: 420)
        )

        let text = overlay.textLayout()
        XCTAssertGreaterThan(text.messageLines.count, 1, "Expected body text to wrap at narrow modal width")

        let buttonTop = overlay.choices.map(\.bounds.y).min()!
        for line in text.messageLines {
            XCTAssertGreaterThanOrEqual(line.bounds.x, overlay.panelBounds.x)
            XCTAssertLessThanOrEqual(line.bounds.x + line.bounds.w, overlay.panelBounds.x + overlay.panelBounds.w)
            XCTAssertLessThan(line.bounds.y + line.bounds.h, buttonTop, "Message line should not overlap button row")
            XCTAssertLessThanOrEqual(line.text.count, LunaModalOverlay.characterCapacity(width: line.bounds.w, scale: LunaModalOverlay.bodyScale))
        }
    }

    func testModalAccessibilityMessageBoundsFollowWrappedMessageRegion() {
        let overlay = LunaModalOverlay(
            request: .notice(
                LunaNoticeRequest(
                    id: "layout.message.a11y",
                    title: "A11y",
                    message: "This is a long enough message to use the modal message region instead of the old fixed thirty two pixel text box."
                )
            ),
            viewportSize: LunaSizeI(width: 330, height: 420)
        )

        let text = overlay.textLayout()
        let children = overlay.buildAccessibilityChildren()
        let messageNode = children.first { $0.id == overlay.id.child("message") }

        XCTAssertEqual(messageNode?.bounds, text.messageRegion.asAccessibilityRect)
        XCTAssertEqual(messageNode?.label, overlay.message)
    }

    func testContentAwareModalGrowsTallerWhenNarrowTextWraps() {
        let message = "This long notice message should require more vertical room once the modal panel becomes narrow enough to wrap the content into several lines."
        let wide = LunaModalOverlay(
            request: .notice(LunaNoticeRequest(id: "layout.wide", title: "Notice", message: message)),
            viewportSize: LunaSizeI(width: 900, height: 500)
        )
        let narrow = LunaModalOverlay(
            request: .notice(LunaNoticeRequest(id: "layout.narrow", title: "Notice", message: message)),
            viewportSize: LunaSizeI(width: 320, height: 500)
        )

        XCTAssertGreaterThanOrEqual(narrow.textLayout().messageLines.count, wide.textLayout().messageLines.count)
        XCTAssertGreaterThan(narrow.panelBounds.h, wide.panelBounds.h)
    }
}
