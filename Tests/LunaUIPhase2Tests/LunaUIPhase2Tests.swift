import XCTest
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaRender
import LunaTheme
import LunaUI

final class LunaUIPhase2Tests: XCTestCase {
    func testContextQueuesAndManagerOpensLatestModalRequest() {
        var context = LunaUIContext()
        context.openNotice(
            LunaNoticeRequest(
                id: "phase2.notice",
                title: "Notice",
                message: "Hello overlay"
            )
        )

        XCTAssertEqual(context.modalRequests.count, 1)

        var manager = LunaModalOverlayManager()
        let opened = manager.openQueuedModals(
            from: &context,
            viewportSize: LunaSizeI(width: 800, height: 600)
        )

        XCTAssertEqual(opened.count, 1)
        XCTAssertTrue(context.modalRequests.isEmpty)
        XCTAssertEqual(manager.active?.id, "phase2.notice")
        XCTAssertEqual(manager.active?.kind, .notice)
        XCTAssertEqual(manager.active?.choices.map(\.label), ["OK"])
        XCTAssertEqual(manager.active?.focusedChoiceID, "phase2.notice.ok")
    }

    func testNoticeOverlayBuildsDisplayListAndAccessibilityTree() {
        let overlay = LunaModalOverlay(
            request: .notice(
                LunaNoticeRequest(
                    id: "phase2.notice.a11y",
                    title: "Phase 2",
                    message: "Accessible notice"
                )
            ),
            viewportSize: LunaSizeI(width: 800, height: 600)
        )

        var displayList = LunaDisplayList()
        overlay.buildDisplayList(into: &displayList)

        XCTAssertGreaterThanOrEqual(displayList.commands.count, 8)
        XCTAssertEqual(overlay.hitTest(LunaPointI(x: overlay.choices[0].bounds.x + 1, y: overlay.choices[0].bounds.y + 1)), overlay.choices[0].id)

        let tree = overlay.accessibilityTree()
        XCTAssertTrue(tree.validate().errors.isEmpty)
        XCTAssertEqual(tree[overlay.id]?.role, .dialog)
        XCTAssertEqual(tree[overlay.choices[0].id]?.role, .button)
        XCTAssertEqual(tree[overlay.choices[0].id]?.label, "OK")
        XCTAssertTrue(tree[overlay.choices[0].id]?.isFocused == true)
    }

    func testNoticeChoicePressStateThenMouseUpDismisses() {
        var manager = LunaModalOverlayManager()
        manager.open(
            .notice(
                LunaNoticeRequest(
                    id: "phase2b.notice",
                    title: "Notice",
                    message: "Press OK"
                )
            ),
            viewportSize: LunaSizeI(width: 800, height: 600)
        )

        guard let ok = manager.active?.choices.first else {
            XCTFail("missing OK choice")
            return
        }

        var context = LunaUIContext()
        let down = manager.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
                location: LunaPointI(x: ok.bounds.x + 2, y: ok.bounds.y + 2),
                button: .primary
            ),
            context: &context
        )

        XCTAssertTrue(down.didConsumeEvent)
        XCTAssertEqual(down.hitNodeID, ok.id)
        XCTAssertTrue(down.didChangeVisualState)
        XCTAssertEqual(manager.active?.pressedChoiceID, ok.id)
        XCTAssertEqual(manager.active?.focusedChoiceID, ok.id)
        XCTAssertNil(down.requestedCommand)
        XCTAssertNotNil(manager.active)

        let up = manager.handlePointerEvent(
            LunaPointerEvent(
                phase: .up,
                location: LunaPointI(x: ok.bounds.x + 2, y: ok.bounds.y + 2),
                button: .primary
            ),
            context: &context
        )

        XCTAssertEqual(up.choiceLabel, "OK")
        XCTAssertTrue(up.didDismiss)
        XCTAssertNil(manager.active)
        XCTAssertEqual(context.announcements.map(\.text), ["OK selected"])
    }

    func testConfirmChoiceQueuesCommandOnMouseUpAndDismisses() {
        var manager = LunaModalOverlayManager()
        manager.open(
            .confirm(
                LunaConfirmRequest(
                    id: "phase2.confirm",
                    title: "Confirm",
                    message: "Continue?",
                    buttons: ["Cancel", "Continue"],
                    commandOnChoice: "luna.phase2.confirm.choice"
                )
            ),
            viewportSize: LunaSizeI(width: 900, height: 700)
        )

        guard let continueChoice = manager.active?.choices.last else {
            XCTFail("missing confirm choice")
            return
        }

        var context = LunaUIContext()
        _ = manager.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
                location: LunaPointI(x: continueChoice.bounds.x + 2, y: continueChoice.bounds.y + 2),
                button: .primary
            ),
            context: &context
        )
        let result = manager.handlePointerEvent(
            LunaPointerEvent(
                phase: .up,
                location: LunaPointI(x: continueChoice.bounds.x + 2, y: continueChoice.bounds.y + 2),
                button: .primary
            ),
            context: &context
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertEqual(result.hitNodeID, continueChoice.id)
        XCTAssertEqual(result.choiceLabel, "Continue")
        XCTAssertEqual(result.choiceIndex, 1)
        XCTAssertEqual(result.requestedCommand, "luna.phase2.confirm.choice")
        XCTAssertTrue(result.didDismiss)
        XCTAssertNil(manager.active)
        XCTAssertEqual(context.requestedCommands, ["luna.phase2.confirm.choice"])
        XCTAssertEqual(context.announcements.map(\.text), ["Continue selected"])
    }

    func testMouseUpOutsidePressedChoiceCancelsPressWithoutDismiss() {
        var manager = LunaModalOverlayManager()
        manager.open(
            .notice(
                LunaNoticeRequest(
                    id: "phase2b.cancelpress",
                    title: "Notice",
                    message: "Cancel press"
                )
            ),
            viewportSize: LunaSizeI(width: 800, height: 600)
        )

        guard let ok = manager.active?.choices.first else {
            XCTFail("missing OK")
            return
        }

        var context = LunaUIContext()
        _ = manager.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: ok.bounds.x + 2, y: ok.bounds.y + 2)),
            context: &context
        )
        let upOutside = manager.handlePointerEvent(
            LunaPointerEvent(phase: .up, location: LunaPointI(x: 1, y: 1)),
            context: &context
        )

        XCTAssertTrue(upOutside.didConsumeEvent)
        XCTAssertFalse(upOutside.didDismiss)
        XCTAssertNotNil(manager.active)
        XCTAssertNil(manager.active?.pressedChoiceID)
        XCTAssertTrue(context.announcements.isEmpty)
    }

    func testHoverUpdatesChoiceVisualState() {
        var manager = LunaModalOverlayManager()
        manager.open(
            .list(
                LunaListRequest(
                    id: "phase2b.list",
                    title: "Pick One",
                    items: ["Alpha", "Beta", "Gamma"],
                    commandOnPick: "luna.phase2.list.pick"
                )
            ),
            viewportSize: LunaSizeI(width: 640, height: 480)
        )

        guard let beta = manager.active?.choices[1] else {
            XCTFail("missing beta")
            return
        }

        var context = LunaUIContext()
        let result = manager.handlePointerEvent(
            LunaPointerEvent(
                phase: .moved,
                location: LunaPointI(x: beta.bounds.x + 3, y: beta.bounds.y + 3),
                button: .primary
            ),
            context: &context
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertTrue(result.didChangeVisualState)
        XCTAssertEqual(manager.active?.hoveredChoiceID, beta.id)
        XCTAssertEqual(manager.active?.visualState(for: beta), .hovered)
        XCTAssertTrue(context.requestedRefresh)
    }

    func testListChoiceQueuesCommandAndDismissesOnMouseUp() {
        var manager = LunaModalOverlayManager()
        manager.open(
            .list(
                LunaListRequest(
                    id: "phase2.list",
                    title: "Pick One",
                    items: ["Alpha", "Beta", "Gamma"],
                    commandOnPick: "luna.phase2.list.pick"
                )
            ),
            viewportSize: LunaSizeI(width: 640, height: 480)
        )

        guard let beta = manager.active?.choices[1] else {
            XCTFail("missing list choice")
            return
        }

        var context = LunaUIContext()
        _ = manager.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: beta.bounds.x + 3, y: beta.bounds.y + 3)),
            context: &context
        )
        let result = manager.handlePointerEvent(
            LunaPointerEvent(phase: .up, location: LunaPointI(x: beta.bounds.x + 3, y: beta.bounds.y + 3)),
            context: &context
        )

        XCTAssertEqual(result.choiceIndex, 1)
        XCTAssertEqual(result.choiceLabel, "Beta")
        XCTAssertEqual(result.requestedCommand, "luna.phase2.list.pick")
        XCTAssertTrue(result.didDismiss)
        XCTAssertNil(manager.active)
        XCTAssertEqual(context.requestedCommands, ["luna.phase2.list.pick"])
    }

    func testPromptSubmitQueuesCommandAndDismissesOnMouseUp() {
        var manager = LunaModalOverlayManager()
        manager.open(
            .prompt(
                LunaPromptRequest(
                    id: "phase2.prompt",
                    title: "Go To Line",
                    placeholder: "Line number",
                    initialText: "42",
                    commandOnSubmit: "luna.phase2.prompt.submit"
                )
            ),
            viewportSize: LunaSizeI(width: 800, height: 600)
        )

        XCTAssertNotNil(manager.active?.fieldBounds)
        guard let submit = manager.active?.choices.first else {
            XCTFail("missing prompt submit choice")
            return
        }

        var context = LunaUIContext()
        _ = manager.handlePointerEvent(
            LunaPointerEvent(phase: .down, location: LunaPointI(x: submit.bounds.x + 2, y: submit.bounds.y + 2)),
            context: &context
        )
        let result = manager.handlePointerEvent(
            LunaPointerEvent(phase: .up, location: LunaPointI(x: submit.bounds.x + 2, y: submit.bounds.y + 2)),
            context: &context
        )

        XCTAssertEqual(result.requestedCommand, "luna.phase2.prompt.submit")
        XCTAssertTrue(result.didDismiss)
        XCTAssertEqual(context.requestedCommands, ["luna.phase2.prompt.submit"])
    }

    func testActiveModalConsumesBackgroundClickWithoutDismissing() {
        var manager = LunaModalOverlayManager()
        manager.open(
            .notice(
                LunaNoticeRequest(
                    id: "phase2.blocking.notice",
                    title: "Blocking",
                    message: "Background should not activate"
                )
            ),
            viewportSize: LunaSizeI(width: 800, height: 600)
        )

        var context = LunaUIContext()
        let result = manager.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
                location: LunaPointI(x: 5, y: 5),
                button: .primary
            ),
            context: &context
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertNil(result.hitNodeID)
        XCTAssertFalse(result.didDismiss)
        XCTAssertNotNil(manager.active)
        XCTAssertTrue(context.requestedCommands.isEmpty)
    }

    func testCompletionOverlayUsesListItemAccessibilityRoles() {
        let overlay = LunaModalOverlay(
            request: .completion(
                LunaCompletionRequest(
                    id: "phase2.completion",
                    anchor: "editor",
                    items: ["print", "private", "public"],
                    commandOnPick: "luna.phase2.completion.pick"
                )
            ),
            viewportSize: LunaSizeI(width: 800, height: 600)
        )

        let tree = overlay.accessibilityTree()
        XCTAssertTrue(tree.validate().errors.isEmpty)
        XCTAssertEqual(overlay.anchor, "editor")
        XCTAssertEqual(tree[overlay.choices[0].id]?.role, .listItem)
        XCTAssertEqual(tree[overlay.choices[0].id]?.label, "print")
        XCTAssertEqual(overlay.visualState(for: overlay.choices[0]), .selected)
    }

    func testKeyboardTabMovesFocusAndEnterActivatesChoice() {
        var manager = LunaModalOverlayManager()
        manager.open(
            .confirm(
                LunaConfirmRequest(
                    id: "phase2b.keyboard",
                    title: "Keyboard",
                    message: "Choose",
                    buttons: ["Cancel", "Continue"],
                    commandOnChoice: "luna.phase2b.keyboard.choice"
                )
            ),
            viewportSize: LunaSizeI(width: 800, height: 600)
        )

        XCTAssertEqual(manager.active?.focusedChoiceID, "phase2b.keyboard.choice.1")

        var context = LunaUIContext()
        let tabResult = manager.handleKeyboardEvent(
            LunaKeyboardEvent(key: .tab),
            context: &context
        )

        XCTAssertTrue(tabResult.didConsumeEvent)
        XCTAssertTrue(tabResult.didChangeVisualState)
        XCTAssertEqual(tabResult.choiceLabel, "Cancel")
        XCTAssertEqual(manager.active?.focusedChoiceID, "phase2b.keyboard.choice.0")

        let enterResult = manager.handleKeyboardEvent(
            LunaKeyboardEvent(key: .enter),
            context: &context
        )

        XCTAssertEqual(enterResult.choiceLabel, "Cancel")
        XCTAssertEqual(enterResult.requestedCommand, "luna.phase2b.keyboard.choice")
        XCTAssertTrue(enterResult.didDismiss)
        XCTAssertNil(manager.active)
    }

    func testKeyboardEscapeActivatesCancelChoiceWhenAvailable() {
        var manager = LunaModalOverlayManager()
        manager.open(
            .confirm(
                LunaConfirmRequest(
                    id: "phase2b.escape",
                    title: "Keyboard",
                    message: "Choose",
                    buttons: ["Cancel", "Continue"],
                    commandOnChoice: "luna.phase2b.escape.choice"
                )
            ),
            viewportSize: LunaSizeI(width: 800, height: 600)
        )

        var context = LunaUIContext()
        let result = manager.handleKeyboardEvent(
            LunaKeyboardEvent(key: .escape),
            context: &context
        )

        XCTAssertTrue(result.didConsumeEvent)
        XCTAssertEqual(result.choiceLabel, "Cancel")
        XCTAssertEqual(result.requestedCommand, "luna.phase2b.escape.choice")
        XCTAssertTrue(result.didDismiss)
        XCTAssertNil(manager.active)
    }
}

final class LunaUIPhase2CThemeTests: XCTestCase {
    func testHexColorParsingSupportsShortLongAndAlphaForms() throws {
        XCTAssertEqual(try LunaColor(hex: "#123"), LunaColor(r: 0x11, g: 0x22, b: 0x33, a: 0xFF))
        XCTAssertEqual(try LunaColor(hex: "#1234"), LunaColor(r: 0x11, g: 0x22, b: 0x33, a: 0x44))
        XCTAssertEqual(try LunaColor(hex: "#112233"), LunaColor(r: 0x11, g: 0x22, b: 0x33, a: 0xFF))
        XCTAssertEqual(try LunaColor(hex: "11223344"), LunaColor(r: 0x11, g: 0x22, b: 0x33, a: 0x44))
    }

    func testControlStyleCanBeBuiltFromThemeHexTokens() {
        var ui = LunaUIThemeColors.lunaDefaultDark
        ui.panelBackground = .hex("#101112")
        ui.controlColors.hoveredBackground = .hex("#ABCDEF")
        ui.controlColors.selectedForeground = .hex("#010203")

        let theme = LunaTheme(
            name: "Custom Theme",
            background: .hex("#202122"),
            foreground: .hex("#E0E1E2"),
            caret: .hex("#FFFFFF"),
            selection: .hex("#303132"),
            ui: ui
        )

        let style = LunaControlVisualStyle(theme: theme)
        XCTAssertEqual(style.panelBackground, LunaRender.LunaRGBA8(r: 0x10, g: 0x11, b: 0x12, a: 0xFF))
        XCTAssertEqual(style.background(for: .hovered), LunaRender.LunaRGBA8(r: 0xAB, g: 0xCD, b: 0xEF, a: 0xFF))
        XCTAssertEqual(style.foreground(for: .selected), LunaRender.LunaRGBA8(r: 0x01, g: 0x02, b: 0x03, a: 0xFF))
    }
}
