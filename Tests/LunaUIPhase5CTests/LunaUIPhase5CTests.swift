// SPDX-License-Identifier: MPL-2.0
import XCTest
import Foundation
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


    func testLocalFileMetadataCanTravelThroughNeutralDescriptorWithoutLunaOwningDiskIO() {
        let file = LunaFileDescriptor(
            id: "local.readme.1234",
            path: "/repo/Luna-UI/README.md",
            displayPath: "README.md",
            name: "README.md",
            projectID: "local-files",
            syntaxName: "Markdown",
            metadata: [
                "adapter": "local-file",
                "local.path": "/repo/Luna-UI/README.md",
            ]
        )

        let descriptor = file.documentDescriptor()

        XCTAssertEqual(file.metadata["adapter"], "local-file")
        XCTAssertEqual(file.metadata["local.path"], "/repo/Luna-UI/README.md")
        XCTAssertEqual(descriptor.title, "README.md")
        XCTAssertEqual(descriptor.displayPath, "README.md")
        XCTAssertEqual(descriptor.syntaxName, "Markdown")
    }

    func testFailedSaveResultDoesNotMarkDirtyDocumentClean() {
        var store = LunaDocumentStore(openDocuments: [
            LunaDocumentBuffer(descriptor: makeFiles()[0].documentDescriptor(), text: "before")
        ], activeDocumentID: "main")
        store.openDocuments[0].textState.insertText(" after")
        XCTAssertTrue(store.openDocuments[0].isDirty)

        let request = store.saveRequestForActiveDocument()!
        let failed = LunaDocumentSaveResult(outcome: .failed, documentID: request.documentID, statusMessage: "Disk write failed")
        store.applySaveResult(failed)

        XCTAssertTrue(store.openDocuments[0].isDirty)
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


    func testPublicDomainDemoCorpusManifestMatchesCheckedInFiles() throws {
        let corpusRoot = Self.repositoryRoot.appendingPathComponent("Examples/PublicDomainDemoFiles", isDirectory: true)
        let manifestURL = corpusRoot.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifestObject = try JSONSerialization.jsonObject(with: manifestData)
        guard let manifest = manifestObject as? [String: Any],
              let entries = manifest["files"] as? [[String: Any]] else {
            return XCTFail("manifest.json should contain a files array")
        }

        XCTAssertEqual(manifest["encoding"] as? String, "UTF-8")
        XCTAssertEqual(entries.count, 13)

        var manifestPaths = Set<String>()
        for entry in entries {
            guard let path = entry["path"] as? String,
                  let expectedBytes = entry["bytes"] as? Int,
                  let expectedSHA256 = entry["sha256"] as? String else {
                return XCTFail("invalid manifest entry: \(entry)")
            }
            XCTAssertFalse(path.contains(".."), "manifest paths should stay inside the corpus")
            XCTAssertFalse(path.hasPrefix("/"), "manifest paths should be relative")
            XCTAssertEqual(expectedSHA256.count, 64, "SHA-256 should be recorded for \(path)")
            manifestPaths.insert(path)

            let fileURL = corpusRoot.appendingPathComponent(path)
            let fileData = try Data(contentsOf: fileURL)
            XCTAssertEqual(fileData.count, expectedBytes, "byte count should match manifest for \(path)")
            XCTAssertNotNil(String(data: fileData, encoding: .utf8), "fixture should be UTF-8: \(path)")
        }

        let discoveredTextFiles = try FileManager.default
            .subpathsOfDirectory(atPath: corpusRoot.path)
            .filter { $0.hasSuffix(".txt") }
        let unlistedTextFiles = Set(discoveredTextFiles).subtracting(manifestPaths)
        XCTAssertTrue(unlistedTextFiles.isEmpty, "all .txt demo fixtures should be listed in manifest: \(unlistedTextFiles.sorted())")
    }

    func testPublicDomainDemoCorpusReadmeDocumentsLaunchCommands() throws {
        let readmeURL = Self.repositoryRoot.appendingPathComponent("Examples/PublicDomainDemoFiles/README.md")
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)

        XCTAssertTrue(readme.contains("--open-demo-corpus=largest"))
        XCTAssertTrue(readme.contains("scripts/run-demo-corpus.sh"))
        XCTAssertTrue(readme.contains("scripts/verify-public-domain-demo-files.py"))
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
