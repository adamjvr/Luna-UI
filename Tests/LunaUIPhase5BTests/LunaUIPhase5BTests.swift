// SPDX-License-Identifier: MPL-2.0
import XCTest
import LunaCommands
import LunaInput
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase5BTests: XCTestCase {
    struct Host {
        var log: [String] = []
        var canSelectAll = true
        var sidebarVisible = true
        var activeDocumentID = "one"
    }

    private func makeRuntime() -> LunaCommandRuntime<Host> {
        var runtime = LunaCommandRuntime<Host>()
        runtime.register(
            LunaCommandDescriptor(id: "demo.selectAll", title: "Select All", defaultKey: LunaKeyEquivalent("A", modifiers: [.primary]), menuPath: ["Edit"]),
            handler: { command, host, context in
                host.log.append("\(command.rawValue):\(context.activeDocumentID ?? "none")")
                return .handled("selected")
            },
            availability: { command, host, _ in
                command == "demo.selectAll" ? LunaCommandAvailability(isEnabled: host.canSelectAll) : .enabled
            }
        )
        runtime.register(
            LunaCommandDescriptor(id: "demo.sidebar.toggle", title: "Toggle Sidebar", defaultKey: LunaKeyEquivalent("B", modifiers: [.primary]), menuPath: ["View"]),
            handler: { _, host, _ in
                host.sidebarVisible.toggle()
                return .handled(host.sidebarVisible ? "shown" : "hidden")
            },
            availability: { _, host, _ in
                LunaCommandAvailability(isChecked: host.sidebarVisible)
            }
        )
        runtime.register(
            LunaCommandDescriptor(id: "demo.hidden", title: "Hidden", defaultKey: LunaKeyEquivalent("H", modifiers: [.primary])),
            handler: { _, host, _ in
                host.log.append("hidden")
                return .handled("hidden")
            },
            availability: { _, _, _ in .hidden }
        )
        return runtime
    }

    func testRuntimeExecutesRegisteredHandlerAgainstMutableHost() {
        var host = Host()
        let runtime = makeRuntime()
        let result = runtime.execute("demo.selectAll", host: &host, context: LunaCommandContext(activeDocumentID: "one"))

        XCTAssertTrue(result.didHandle)
        XCTAssertEqual(result.statusMessage, "selected")
        XCTAssertEqual(host.log, ["demo.selectAll:one"])
    }

    func testDisabledCommandDoesNotExecute() {
        var host = Host(canSelectAll: false)
        let runtime = makeRuntime()
        let result = runtime.execute("demo.selectAll", host: &host, context: LunaCommandContext(activeDocumentID: "one"))

        XCTAssertFalse(result.didHandle)
        XCTAssertTrue(host.log.isEmpty)
    }

    func testKeyBindingMatchesPrimaryShortcutAndRejectsBareKey() {
        let runtime = makeRuntime()
        let host = Host()
        let context = LunaCommandContext(focusedSurface: "editor", activeDocumentID: "one")

        let controlA = LunaKeyboardEvent(key: .other("a"), modifiers: LunaKeyboardModifiers(control: true))
        XCTAssertEqual(runtime.command(matching: controlA.lunaCommandKeyStroke, host: host, context: context), "demo.selectAll")

        let bareA = LunaKeyboardEvent(key: .other("a"))
        XCTAssertNil(runtime.command(matching: bareA.lunaCommandKeyStroke, host: host, context: context))
    }

    func testUnavailableKeyBindingIsSkipped() {
        let runtime = makeRuntime()
        let host = Host(canSelectAll: false)
        let controlA = LunaKeyboardEvent(key: .other("a"), modifiers: LunaKeyboardModifiers(control: true))

        XCTAssertNil(runtime.command(matching: controlA.lunaCommandKeyStroke, host: host, context: LunaCommandContext()))
    }

    func testSurfaceProjectionCarriesDynamicCheckedAndEnabledState() {
        let runtime = makeRuntime()
        let visibleHost = Host(sidebarVisible: true)
        let hiddenHost = Host(sidebarVisible: false)

        let checked = runtime.surfaceItem(for: "demo.sidebar.toggle", host: visibleHost)!
        let unchecked = runtime.surfaceItem(for: "demo.sidebar.toggle", host: hiddenHost)!

        XCTAssertEqual(checked.title, "Toggle Sidebar")
        XCTAssertTrue(checked.isChecked)
        XCTAssertFalse(unchecked.isChecked)
        XCTAssertEqual(checked.keyEquivalent?.key, "B")
    }

    func testPaletteDescriptorsRespectVisibility() {
        let runtime = makeRuntime()
        let host = Host()
        let descriptors = runtime.paletteDescriptors(host: host)

        XCTAssertTrue(descriptors.contains { $0.id == "demo.selectAll" })
        XCTAssertFalse(descriptors.contains { $0.id == "demo.hidden" })
    }

    func testLegacyDisplayStringKeyEquivalentStillMatches() {
        let legacy = LunaKeyEquivalent("Ctrl+P")
        let stroke = LunaKeyboardEvent(key: .other("p"), modifiers: LunaKeyboardModifiers(control: true)).lunaCommandKeyStroke

        XCTAssertTrue(legacy.matches(stroke))
    }

    func testCommandContextTargetDocumentFallsBackToActiveDocument() {
        let activeOnly = LunaCommandContext(activeDocumentID: "active")
        XCTAssertEqual(activeOnly.targetOrActiveDocumentID, "active")
        XCTAssertNil(activeOnly.explicitTargetDocumentID)

        let targeted = activeOnly.withAttributes([
            LunaCommandContextAttributeKey.targetDocumentID: "clicked-tab",
            LunaCommandContextAttributeKey.targetShellTabID: "clicked-tab",
        ])
        XCTAssertEqual(targeted.activeDocumentID, "active")
        XCTAssertEqual(targeted.explicitTargetDocumentID, "clicked-tab")
        XCTAssertEqual(targeted.targetOrActiveDocumentID, "clicked-tab")
        XCTAssertEqual(targeted.value(for: LunaCommandContextAttributeKey.targetShellTabID), "clicked-tab")
    }

}
