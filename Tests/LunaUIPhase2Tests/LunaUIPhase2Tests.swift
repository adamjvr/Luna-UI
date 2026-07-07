import XCTest
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaRender
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

        XCTAssertGreaterThanOrEqual(displayList.commands.count, 5)
        XCTAssertEqual(overlay.hitTest(LunaPointI(x: overlay.choices[0].bounds.x + 1, y: overlay.choices[0].bounds.y + 1)), overlay.choices[0].id)

        let tree = overlay.accessibilityTree()
        XCTAssertTrue(tree.validate().errors.isEmpty)
        XCTAssertEqual(tree[overlay.id]?.role, .dialog)
        XCTAssertEqual(tree[overlay.choices[0].id]?.role, .button)
        XCTAssertEqual(tree[overlay.choices[0].id]?.label, "OK")
    }

    func testConfirmChoiceQueuesCommandAndDismisses() {
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
        let result = manager.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
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

    func testListChoiceQueuesCommandAndDismisses() {
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
        let result = manager.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
                location: LunaPointI(x: beta.bounds.x + 3, y: beta.bounds.y + 3),
                button: .primary
            ),
            context: &context
        )

        XCTAssertEqual(result.choiceIndex, 1)
        XCTAssertEqual(result.choiceLabel, "Beta")
        XCTAssertEqual(result.requestedCommand, "luna.phase2.list.pick")
        XCTAssertTrue(result.didDismiss)
        XCTAssertNil(manager.active)
        XCTAssertEqual(context.requestedCommands, ["luna.phase2.list.pick"])
    }

    func testPromptSubmitQueuesCommandAndDismisses() {
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
        let result = manager.handlePointerEvent(
            LunaPointerEvent(
                phase: .down,
                location: LunaPointI(x: submit.bounds.x + 2, y: submit.bounds.y + 2),
                button: .primary
            ),
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
    }
}
