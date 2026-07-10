import XCTest
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaUIPhase5ATests: XCTestCase {
    private func makeStore() -> LunaDocumentStore {
        LunaDocumentStore(
            openDocuments: [
                LunaDocumentBuffer(
                    descriptor: LunaDocumentDescriptor(id: "one", title: "One.swift", displayPath: "Sources/One.swift", syntaxName: "Swift", isClosable: false),
                    text: "let one = 1\n",
                    caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 0))
                ),
                LunaDocumentBuffer(
                    descriptor: LunaDocumentDescriptor(id: "two", title: "Two.json", displayPath: "Data/Two.json", syntaxName: "JSON", isPinned: true),
                    text: "{ \"two\": true }\n",
                    caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 2))
                ),
            ],
            activeDocumentID: "one"
        )
    }

    func testDocumentStoreNormalizesActiveDocument() {
        var store = LunaDocumentStore(
            openDocuments: [
                LunaDocumentBuffer(descriptor: LunaDocumentDescriptor(id: "first", title: "First"), text: "first"),
                LunaDocumentBuffer(descriptor: LunaDocumentDescriptor(id: "second", title: "Second"), text: "second"),
            ],
            activeDocumentID: "missing"
        )

        XCTAssertEqual(store.activeDocumentID, "first")
        XCTAssertEqual(store.activeDescriptor?.title, "First")

        XCTAssertTrue(store.activate("second"))
        XCTAssertEqual(store.activeDocumentID, "second")
        XCTAssertFalse(store.activate("missing"))
        XCTAssertEqual(store.activeDocumentID, "second")
    }

    func testDirtyStateComesFromEditableRevision() {
        var store = makeStore()
        XCTAssertFalse(store.activeDocument?.isDirty ?? true)

        var text = store.activeTextState!
        text.insertText("prefix ")
        store.replaceActiveTextState(text)

        XCTAssertTrue(store.activeDocument?.isDirty ?? false)
        XCTAssertEqual(store.activeTextState?.document.text.hasPrefix("prefix "), true)

        store.markActiveClean()
        XCTAssertFalse(store.activeDocument?.isDirty ?? true)
    }

    func testSwitchingDocumentsPreservesPerDocumentTextCaretAndScroll() {
        var store = makeStore()

        var one = store.activeTextState!
        one.insertText("edited ")
        store.replaceActiveTextState(one)
        store.replaceActiveScrollState(LunaStaticTextScrollState(scrollTopLine: 4))

        XCTAssertTrue(store.activate("two"))
        XCTAssertEqual(store.activeDescriptor?.title, "Two.json")
        XCTAssertEqual(store.activeTextState?.document.text, "{ \"two\": true }\n")
        XCTAssertEqual(store.activeTextState?.caret.location.utf8Column, 2)
        store.replaceActiveScrollState(LunaStaticTextScrollState(scrollTopLine: 1))

        XCTAssertTrue(store.activate("one"))
        XCTAssertEqual(store.activeTextState?.document.text.hasPrefix("edited "), true)
        XCTAssertEqual(store.activeScrollState?.scrollTopLine, 4)
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)

        XCTAssertTrue(store.activate("two"))
        XCTAssertEqual(store.activeScrollState?.scrollTopLine, 1)
        XCTAssertFalse(store.activeDocument?.isDirty ?? true)
    }

    func testDocumentsProjectIntoShellTabs() {
        var store = makeStore()
        var text = store.activeTextState!
        text.insertText("changed")
        store.replaceActiveTextState(text)

        let tabs = store.shellTabs(
            activateCommand: { LunaCommandID(rawValue: "demo.activate.\($0.rawValue)") },
            closeCommand: { LunaCommandID(rawValue: "demo.close.\($0.rawValue)") }
        )

        XCTAssertEqual(tabs.map(\.id), ["one", "two"])
        XCTAssertEqual(tabs[0].title, "One.swift")
        XCTAssertEqual(tabs[0].detail, "Sources/One.swift")
        XCTAssertTrue(tabs[0].isDirty)
        XCTAssertFalse(tabs[0].isClosable)
        XCTAssertTrue(tabs[1].isPinned)
        XCTAssertEqual(tabs[1].activateCommand, "demo.activate.two")
    }

    func testStoreSynchronizesEditorShellState() {
        var store = makeStore()
        var shellState = LunaEditorShellState(
            tabStrip: LunaTabStripState(activeTabID: "stale"),
            sidebar: LunaSidebarState(selectedItemID: "stale")
        )

        store.syncShellState(&shellState)
        XCTAssertEqual(shellState.tabStrip.activeTabID, "one")
        XCTAssertEqual(shellState.sidebar.selectedItemID, "one")

        XCTAssertTrue(store.activate("two"))
        store.syncShellState(&shellState)
        XCTAssertEqual(shellState.tabStrip.activeTabID, "two")
        XCTAssertEqual(shellState.sidebar.selectedItemID, "two")
    }

    func testStatusSegmentsReflectActiveDocumentMetadata() {
        var store = makeStore()
        var text = store.activeTextState!
        text.insertText("dirty")
        store.replaceActiveTextState(text)

        let segments = store.statusSegments(status: "Testing")

        XCTAssertTrue(segments.contains { $0.id == "document" && $0.value == "One.swift" && $0.emphasis == .accent })
        XCTAssertTrue(segments.contains { $0.id == "dirty" && $0.title == "Modified" && $0.emphasis == .accent })
        XCTAssertTrue(segments.contains { $0.id == "syntax" && $0.title == "Swift" })
        XCTAssertTrue(segments.contains { $0.id == "position" && $0.value?.contains("Ln") == false })
    }

    func testShellUsesDocumentBackedTabs() {
        var store = makeStore()
        var shellState = LunaEditorShellState(tabStrip: LunaTabStripState(activeTabID: store.activeShellTabID))
        store.syncShellState(&shellState)
        let shell = LunaEditorShell(
            id: "shell",
            bounds: LunaRectI(x: 0, y: 0, w: 900, h: 500),
            tabs: store.shellTabs(),
            sidebarTitle: "Project",
            sidebarItems: [],
            statusSegments: store.statusSegments(status: "Ready"),
            state: shellState,
            theme: .lunaDefaultDark
        )

        let layout = shell.layout()
        XCTAssertEqual(layout.tabFrames.map(\.tab.id), ["one", "two"])
        XCTAssertEqual(layout.tabFrames.first?.tab.title, "One.swift")
        XCTAssertFalse(layout.editorContentBounds.isEmpty)
    }
}
