import XCTest
import LunaCommands
import LunaCore
@testable import LunaUI

final class LunaUIPhase5CTests: XCTestCase {
    private let project = LunaProjectDescriptor(id: "project", title: "Luna-UI", rootPath: "/repo/Luna-UI")

    private func makeFiles() -> [LunaFileDescriptor] {
        [
            LunaFileDescriptor(id: "main", path: "/repo/Luna-UI/Sources/Main.swift", displayPath: "Sources/Main.swift", projectID: "project", syntaxName: "Swift"),
            LunaFileDescriptor(id: "readme", path: "/repo/Luna-UI/README.md", displayPath: "README.md", projectID: "project", syntaxName: "Markdown"),
        ]
    }

    private func makeSnapshot() -> LunaProjectTreeSnapshot {
        LunaProjectTreeSnapshot(
            projects: [project],
            roots: [
                .project(
                    id: "root",
                    title: "Luna-UI",
                    projectID: "project",
                    children: [
                        .folder(
                            id: "sources",
                            title: "Sources",
                            projectID: "project",
                            children: [
                                .file(id: "node.main", title: "Main.swift", fileID: "main", projectID: "project"),
                            ]
                        ),
                        .file(id: "node.readme", title: "README.md", fileID: "readme", projectID: "project"),
                    ]
                )
            ],
            version: 4
        )
    }

    func testFileDescriptorProjectsToDocumentDescriptorWithoutOwningFileIO() {
        let file = makeFiles()[0]
        let descriptor = file.documentDescriptor(isPinned: true, isClosable: false)

        XCTAssertEqual(descriptor.id, "main")
        XCTAssertEqual(descriptor.title, "Main.swift")
        XCTAssertEqual(descriptor.displayPath, "Sources/Main.swift")
        XCTAssertEqual(descriptor.syntaxName, "Swift")
        XCTAssertTrue(descriptor.isPinned)
        XCTAssertFalse(descriptor.isClosable)
    }

    func testProjectTreeSnapshotProjectsToSidebarItemsWithAppOwnedCommands() {
        let snapshot = makeSnapshot()
        let sidebar = snapshot.sidebarItems { node in
            node.fileID.map { LunaCommandID(rawValue: "demo.open.\($0.rawValue)") }
        }

        XCTAssertEqual(sidebar.first?.id, "root")
        XCTAssertEqual(sidebar.first?.kind, .folder)
        let sources = sidebar.first?.children.first
        XCTAssertEqual(sources?.id, "sources")
        XCTAssertEqual(sources?.children.first?.activateCommand, "demo.open.main")
        XCTAssertEqual(sidebar.first?.children.last?.activateCommand, "demo.open.readme")
    }

    func testWorkspaceStateTracksOpenActiveAndSelectedFileSeparatelyFromAdapter() {
        var workspace = LunaWorkspaceState(
            snapshot: makeSnapshot(),
            fileDescriptors: makeFiles(),
            openFileIDs: ["main"],
            activeFileID: "main",
            selectedNodeID: "node.main",
            expandedNodeIDs: ["root", "sources"]
        )

        XCTAssertTrue(workspace.open(fileID: "readme"))
        XCTAssertEqual(workspace.activeFileID, "readme")
        XCTAssertEqual(workspace.selectedNodeID, "node.readme")
        XCTAssertEqual(workspace.openFileIDs, ["main", "readme"])
        XCTAssertFalse(workspace.open(fileID: "missing"))
    }

    func testDocumentStoreBuildsSaveRequestsAndAppliesSaveResults() {
        let file = makeFiles()[0]
        var store = LunaDocumentStore(openDocuments: [
            LunaDocumentBuffer(descriptor: file.documentDescriptor(), text: "before")
        ], activeDocumentID: "main")

        store.openDocuments[0].textState.insertText(" after")
        XCTAssertTrue(store.openDocuments[0].isDirty)

        let request = store.saveRequestForActiveDocument()
        XCTAssertEqual(request?.documentID, "main")
        XCTAssertEqual(request?.fileID, "main")
        XCTAssertEqual(request?.text, " afterbefore")

        let result = LunaDocumentSaveResult.saved(request!, file: file)
        store.applySaveResult(result)
        XCTAssertFalse(store.openDocuments[0].isDirty)
    }

    func testDirtyClosePolicySeparatesPromptDecisionFromActualUI() {
        let policy = LunaDirtyDocumentClosePolicy(promptsForDirtyDocuments: true)
        let request = LunaDocumentCloseRequest(documentID: "main", title: "Main.swift", isDirty: true)

        let resolution = policy.resolve(request)

        XCTAssertTrue(resolution.needsUserPrompt)
        XCTAssertFalse(resolution.shouldClose)
        XCTAssertEqual(resolution.decision, .requestSave)
    }

    func testWorkspaceAdapterProtocolCanBeBackedByInMemoryFixture() {
        var adapter = InMemoryWorkspaceAdapter(snapshot: makeSnapshot(), files: makeFiles(), texts: ["main": "print(1)"])

        let snapshot = adapter.projectTreeSnapshot()
        let open = adapter.openFile(LunaWorkspaceOpenRequest(fileID: "main", source: "unit-test"))
        let missing = adapter.openFile(LunaWorkspaceOpenRequest(fileID: "missing"))
        let save = adapter.saveDocument(
            LunaDocumentSaveRequest(documentID: "main", fileID: "main", title: "Main.swift", text: "print(2)", editRevision: 2)
        )

        XCTAssertEqual(snapshot.version, 4)
        XCTAssertTrue(open.didOpen)
        XCTAssertEqual(open.text, "print(1)")
        XCTAssertFalse(missing.didOpen)
        XCTAssertTrue(save.didSave)
        XCTAssertEqual(adapter.texts["main"], "print(2)")
    }
    func testWorkspaceStateSyncClearsActiveFileWhenDocumentStoreIsEmpty() {
        var workspace = LunaWorkspaceState(
            snapshot: makeSnapshot(),
            fileDescriptors: makeFiles(),
            openFileIDs: ["main"],
            activeFileID: "main",
            selectedNodeID: "node.main",
            expandedNodeIDs: ["root", "sources"]
        )
        let documentStore = LunaDocumentStore(openDocuments: [])

        workspace.syncFromActiveDocument(documentStore)

        XCTAssertNil(workspace.activeFileID)
        XCTAssertNil(workspace.selectedNodeID)
        XCTAssertEqual(workspace.openFileIDs, ["main"])
    }

}

private struct InMemoryWorkspaceAdapter: LunaWorkspaceAdapter {
    var snapshot: LunaProjectTreeSnapshot
    var files: [LunaFileID: LunaFileDescriptor]
    var texts: [LunaFileID: String]

    init(snapshot: LunaProjectTreeSnapshot, files: [LunaFileDescriptor], texts: [LunaFileID: String]) {
        self.snapshot = snapshot
        self.files = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        self.texts = texts
    }

    mutating func projectTreeSnapshot() -> LunaProjectTreeSnapshot {
        snapshot
    }

    mutating func openFile(_ request: LunaWorkspaceOpenRequest) -> LunaWorkspaceOpenResult {
        guard let file = files[request.fileID], let text = texts[request.fileID] else {
            return LunaWorkspaceOpenResult(statusMessage: "Missing file")
        }
        return LunaWorkspaceOpenResult(file: file, text: text, statusMessage: "Opened \(file.title)")
    }

    mutating func saveDocument(_ request: LunaDocumentSaveRequest) -> LunaDocumentSaveResult {
        guard let fileID = request.fileID, let file = files[fileID] else {
            return LunaDocumentSaveResult(outcome: .noDestination, documentID: request.documentID, statusMessage: "No destination")
        }
        texts[fileID] = request.text
        return .saved(request, file: file)
    }

}
