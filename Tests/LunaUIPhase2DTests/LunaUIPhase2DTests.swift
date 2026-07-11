// SPDX-License-Identifier: MPL-2.0
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
            theme: .lunaDefaultDark
        )

        XCTAssertEqual(widget.bounds, bounds)
        XCTAssertEqual(widget.hitTest(LunaPointI(x: 322, y: 74)), widgetID)
        XCTAssertEqual(widget.buildAccessibilityNode().bounds, bounds.asAccessibilityRect)
    }

    func testModalReflowUpdatesDrawHitTestAndAccessibilityBounds() {
        var manager = LunaModalOverlayManager(style: LunaControlVisualStyle(theme: .lunaDefaultDark))
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
        XCTAssertNotEqual(after.hitTest(LunaPointI(x: beforeChoice.bounds.x + 1, y: beforeChoice.bounds.y + 1)), beforeChoice.id)

        let child = after.buildAccessibilityChildren().first { $0.id == afterChoice.id }
        XCTAssertEqual(child?.bounds, afterChoice.bounds.asAccessibilityRect)
    }

    func testModalManagerPointerRoutingUsesReflowedChoiceBounds() {
        var manager = LunaModalOverlayManager(style: LunaControlVisualStyle(theme: .lunaDefaultDark))
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

extension LunaUIPhase2DTests {
    func testUniversalBoundedTextEllipsizesSingleLineInsideBounds() {
        let bounds = LunaRectI(x: 10, y: 20, w: 42, h: 12) // 7 debug-font chars at scale 1.
        let layout = LunaBoundedTextLayout.layout(
            "This label is far too long",
            in: bounds,
            metrics: .body,
            overflow: .ellipsizeTail
        )

        XCTAssertEqual(layout.lines.count, 1)
        XCTAssertTrue(layout.didClip)
        XCTAssertTrue(layout.lines[0].text.hasSuffix("..."))
        XCTAssertEqual(layout.lines[0].fullText, "This label is far too long")
        XCTAssertLessThanOrEqual(layout.lines[0].bounds.x + layout.lines[0].bounds.w, bounds.x + bounds.w)
    }

    func testUniversalBoundedTextWrapsAndClipsWithinVerticalBounds() {
        let bounds = LunaRectI(x: 4, y: 8, w: 60, h: 24) // Two body lines.
        let layout = LunaBoundedTextLayout.layout(
            "This body text should wrap into more than two lines and then clip the last visible line",
            in: bounds,
            metrics: .body,
            overflow: .wrap
        )

        XCTAssertEqual(layout.lines.count, 2)
        XCTAssertTrue(layout.didClip)
        for line in layout.lines {
            XCTAssertGreaterThanOrEqual(line.bounds.x, bounds.x)
            XCTAssertLessThanOrEqual(line.bounds.x + line.bounds.w, bounds.x + bounds.w)
            XCTAssertLessThanOrEqual(line.bounds.y + line.bounds.h, bounds.y + bounds.h)
        }
    }

    func testSemanticWidgetTitleAndSubtitleUseBoundedTextLayout() {
        let widget = LunaSemanticActionWidget(
            id: "layout.semantic.text",
            bounds: LunaRectI(x: 20, y: 30, w: 96, h: 56),
            title: "A very long semantic widget title",
            subtitle: "A very long semantic widget subtitle",
            primaryCommand: "luna.semantic.text",
            theme: .lunaDefaultDark
        )

        let text = widget.textLayout()
        XCTAssertTrue(text.title.text.hasSuffix("..."))
        XCTAssertEqual(text.title.fullText, widget.title)
        XCTAssertTrue(text.subtitle?.text.hasSuffix("...") ?? false)
        XCTAssertEqual(text.subtitle?.fullText, widget.subtitle)
        XCTAssertLessThanOrEqual(text.title.bounds.x + text.title.bounds.w, widget.bounds.x + widget.bounds.w)
        XCTAssertLessThanOrEqual(text.subtitle!.bounds.x + text.subtitle!.bounds.w, widget.bounds.x + widget.bounds.w)

        let a11y = widget.buildAccessibilityNode()
        XCTAssertEqual(a11y.label, widget.title)
        XCTAssertEqual(a11y.value, widget.subtitle)
        XCTAssertEqual(a11y.bounds, widget.bounds.asAccessibilityRect)
    }

    func testModalChoiceLabelUsesUniversalBoundedTextLayout() {
        let overlay = LunaModalOverlay(
            request: .confirm(
                LunaConfirmRequest(
                    id: "layout.choice.label",
                    title: "Choice Label",
                    message: "Choice labels must not draw outside their button bounds.",
                    buttons: ["A very long cancel label", "A very long default label"],
                    commandOnChoice: "luna.choice"
                )
            ),
            viewportSize: LunaSizeI(width: 310, height: 300)
        )

        for choice in overlay.choices {
            let label = overlay.visualLabel(for: choice)
            XCTAssertTrue(label.isClipped, "Expected long choice label to be clipped/ellipsized")
            XCTAssertEqual(label.fullText, choice.label)
            XCTAssertLessThanOrEqual(label.bounds.x, choice.bounds.x + choice.bounds.w)
            XCTAssertLessThanOrEqual(label.bounds.x + label.bounds.w, choice.bounds.x + choice.bounds.w)
        }

        let children = overlay.buildAccessibilityChildren()
        for choice in overlay.choices {
            let node = children.first { $0.id == choice.id }
            XCTAssertEqual(node?.label, choice.label)
            XCTAssertEqual(node?.bounds, choice.bounds.asAccessibilityRect)
        }
    }
}

extension LunaUIPhase2DTests {
    func testNoticeButtonStaysInsidePanelInEmergencyNarrowViewport() {
        let overlay = LunaModalOverlay(
            request: .notice(
                LunaNoticeRequest(
                    id: "layout.responsive.ok",
                    title: "Narrow OK",
                    message: "This notice is deliberately long enough to stress the emergency narrow modal layout."
                )
            ),
            viewportSize: LunaSizeI(width: 78, height: 520)
        )

        let ok = overlay.choices[0]
        XCTAssertGreaterThanOrEqual(ok.bounds.x, overlay.panelBounds.x)
        XCTAssertLessThanOrEqual(ok.bounds.x + ok.bounds.w, overlay.panelBounds.x + overlay.panelBounds.w)
        XCTAssertGreaterThanOrEqual(ok.bounds.y, overlay.panelBounds.y)
        XCTAssertLessThanOrEqual(ok.bounds.y + ok.bounds.h, overlay.panelBounds.y + overlay.panelBounds.h)

        let label = overlay.visualLabel(for: ok)
        XCTAssertLessThanOrEqual(label.bounds.x + label.bounds.w, ok.bounds.x + ok.bounds.w)
        XCTAssertEqual(overlay.hitTest(LunaPointI(x: ok.bounds.x + max(0, ok.bounds.w / 2), y: ok.bounds.y + max(0, ok.bounds.h / 2))), ok.id)
        XCTAssertEqual(overlay.buildAccessibilityChildren().first { $0.id == ok.id }?.bounds, ok.bounds.asAccessibilityRect)
    }

    func testSingleButtonUsesFullContentWidthWhenPanelIsTooNarrowForPreferredButton() {
        let overlay = LunaModalOverlay(
            request: .notice(LunaNoticeRequest(id: "layout.responsive.full-width", title: "Narrow", message: "Body")),
            viewportSize: LunaSizeI(width: 120, height: 320)
        )

        let content = LunaModalOverlay.modalContentBounds(in: overlay.panelBounds)
        let ok = overlay.choices[0]

        if content.w < 104 {
            XCTAssertEqual(ok.bounds.x, content.x)
            XCTAssertEqual(ok.bounds.w, content.w)
        }
        XCTAssertLessThanOrEqual(ok.bounds.x + ok.bounds.w, content.x + content.w)
    }

    func testMultiButtonConfirmStacksVerticallyWhenTooNarrowForHorizontalMinimums() {
        let overlay = LunaModalOverlay(
            request: .confirm(
                LunaConfirmRequest(
                    id: "layout.responsive.stack",
                    title: "Stack",
                    message: "Very narrow multi-button modal",
                    buttons: ["Cancel", "Don't Save", "Save"],
                    commandOnChoice: "luna.stack.choice"
                )
            ),
            viewportSize: LunaSizeI(width: 96, height: 420)
        )

        let content = LunaModalOverlay.modalContentBounds(in: overlay.panelBounds)
        XCTAssertEqual(overlay.choices.count, 3)

        for choice in overlay.choices {
            XCTAssertEqual(choice.bounds.x, content.x)
            XCTAssertEqual(choice.bounds.w, content.w)
            XCTAssertGreaterThanOrEqual(choice.bounds.x, overlay.panelBounds.x)
            XCTAssertLessThanOrEqual(choice.bounds.x + choice.bounds.w, overlay.panelBounds.x + overlay.panelBounds.w)
        }

        let yPositions = overlay.choices.map(\.bounds.y)
        XCTAssertEqual(yPositions, yPositions.sorted(), "Stacked choices should run top-to-bottom without horizontal spill")
    }

    func testEmergencyNarrowMessageDoesNotWrapIntoSingleCharacterColumn() {
        let overlay = LunaModalOverlay(
            request: .notice(
                LunaNoticeRequest(
                    id: "layout.responsive.no-column",
                    title: "Message",
                    message: "Emergency narrow body text should ellipsize rather than wrap into a useless one character column."
                )
            ),
            viewportSize: LunaSizeI(width: 72, height: 520)
        )

        let text = overlay.textLayout()
        XCTAssertLessThanOrEqual(text.messageLines.count, 1)
        if let line = text.messageLines.first {
            XCTAssertTrue(line.isClipped)
        }
    }
}
