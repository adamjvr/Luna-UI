import XCTest
import LunaAccessibility
import LunaCommands
import LunaCore

final class LunaArchitectureTests: XCTestCase {
    func testNodeIDBuildsStableChildren() {
        let root: LunaNodeID = "editor"
        XCTAssertEqual(root.child("line").child(42).rawValue, "editor.line.42")
    }

    func testAccessibilityTreeValidationPassesForValidTree() {
        let root: LunaNodeID = "window"
        let editor: LunaNodeID = "editor"

        let tree = LunaAccessibilityTree(
            rootID: root,
            nodes: [
                root: LunaAccessibilityNode(
                    id: root,
                    role: .window,
                    label: "Luna Window",
                    children: [editor]
                ),
                editor: LunaAccessibilityNode(
                    id: editor,
                    role: .textArea,
                    label: "Editor",
                    bounds: LunaAccessibilityRect(x: 0, y: 0, width: 800, height: 600),
                    actions: [.focus]
                )
            ]
        )

        let diagnostics = tree.validate()
        XCTAssertTrue(diagnostics.errors.isEmpty)
    }

    func testAccessibilityTreeValidationCatchesMissingChild() {
        let root: LunaNodeID = "window"
        let missing: LunaNodeID = "missing"

        let tree = LunaAccessibilityTree(
            rootID: root,
            nodes: [
                root: LunaAccessibilityNode(
                    id: root,
                    role: .window,
                    label: "Luna Window",
                    children: [missing]
                )
            ]
        )

        let diagnostics = tree.validate()
        XCTAssertEqual(diagnostics.errors.count, 1)
        XCTAssertTrue(diagnostics.errors[0].contains("missing"))
    }

    func testCommandRegistryPreservesInsertionOrderAndReplacesDescriptors() {
        var registry = LunaCommandRegistry()
        let save: LunaCommandID = "app.file.save"
        let open: LunaCommandID = "app.file.open"

        registry.register(
            LunaCommandDescriptor(
                id: save,
                title: "Save",
                defaultKey: LunaKeyEquivalent("s", modifiers: [.primary]),
                menuPath: ["File"]
            )
        )
        registry.register(LunaCommandDescriptor(id: open, title: "Open", menuPath: ["File"]))
        registry.register(LunaCommandDescriptor(id: save, title: "Save File", menuPath: ["File"]))

        XCTAssertEqual(registry.all.map(\.id), [save, open])
        XCTAssertEqual(registry.descriptor(for: save)?.title, "Save File")
        XCTAssertTrue(registry.contains(open))
    }
}
