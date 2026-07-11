// SPDX-License-Identifier: MPL-2.0
// LunaWorkspace.swift
//
// Product-neutral file / project / workspace adapter primitives.
//
// Phase 5C introduces Luna's boundary for file and project semantics without
// making Luna perform real filesystem I/O or become Moth Text. Luna owns typed
// IDs, descriptors, tree snapshots, UI projection helpers, save/open request and
// result contracts, and dirty-document close policy models. Applications own the
// adapter implementation: how paths resolve, how files save, which folders are
// ignored, how syntax is detected, and how dirty-document prompts are presented.

import Foundation
import LunaCommands
import LunaCore

// MARK: - Workspace identity

public struct LunaFileID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaFileID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct LunaProjectID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaProjectID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct LunaWorkspaceNodeID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaWorkspaceNodeID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

// MARK: - File and project descriptors

public struct LunaFileReference: Hashable, Sendable {
    public var id: LunaFileID
    public var projectID: LunaProjectID?
    public var path: String
    public var displayPath: String
    public var name: String
    public var isDirectory: Bool

    public init(
        id: LunaFileID,
        path: String,
        displayPath: String? = nil,
        name: String? = nil,
        projectID: LunaProjectID? = nil,
        isDirectory: Bool = false
    ) {
        precondition(!path.isEmpty, "LunaFileReference path cannot be empty")
        self.id = id
        self.projectID = projectID
        self.path = path
        self.displayPath = displayPath ?? path
        self.name = name ?? Self.defaultName(for: displayPath ?? path)
        self.isDirectory = isDirectory
    }

    private static func defaultName(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.split(separator: "/").last.map(String.init) ?? path
    }
}

public struct LunaFileDescriptor: Hashable, Sendable {
    public var reference: LunaFileReference
    public var syntaxName: String?
    public var isReadOnly: Bool
    public var isUntitled: Bool
    public var metadata: [String: String]

    public init(
        id: LunaFileID,
        path: String,
        displayPath: String? = nil,
        name: String? = nil,
        projectID: LunaProjectID? = nil,
        syntaxName: String? = nil,
        isReadOnly: Bool = false,
        isUntitled: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.reference = LunaFileReference(
            id: id,
            path: path,
            displayPath: displayPath,
            name: name,
            projectID: projectID,
            isDirectory: false
        )
        self.syntaxName = syntaxName
        self.isReadOnly = isReadOnly
        self.isUntitled = isUntitled
        self.metadata = metadata
    }

    public var id: LunaFileID { reference.id }
    public var projectID: LunaProjectID? { reference.projectID }
    public var title: String { reference.name }
    public var path: String { reference.path }
    public var displayPath: String { reference.displayPath }

    public func documentDescriptor(
        id documentID: LunaDocumentID? = nil,
        isPinned: Bool = false,
        isClosable: Bool = true
    ) -> LunaDocumentDescriptor {
        LunaDocumentDescriptor(
            id: documentID ?? LunaDocumentID(rawValue: reference.id.rawValue),
            title: title,
            displayPath: displayPath,
            syntaxName: syntaxName,
            isPinned: isPinned,
            isClosable: isClosable,
            accessibilityLabel: displayPath
        )
    }
}

public struct LunaProjectDescriptor: Hashable, Sendable {
    public var id: LunaProjectID
    public var title: String
    public var rootPath: String?
    public var displayPath: String?
    public var metadata: [String: String]

    public init(
        id: LunaProjectID,
        title: String,
        rootPath: String? = nil,
        displayPath: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.rootPath = rootPath
        self.displayPath = displayPath ?? rootPath
        self.metadata = metadata
    }
}

// MARK: - Project tree snapshots

public enum LunaProjectTreeNodeKind: String, Hashable, Sendable {
    case project
    case group
    case folder
    case file
    case custom
}

public struct LunaProjectTreeNode: Hashable, Sendable {
    public var id: LunaWorkspaceNodeID
    public var title: String
    public var subtitle: String?
    public var kind: LunaProjectTreeNodeKind
    public var projectID: LunaProjectID?
    public var fileID: LunaFileID?
    public var children: [LunaProjectTreeNode]
    public var isEnabled: Bool
    public var isSelectable: Bool
    public var accessibilityLabel: String

    public init(
        id: LunaWorkspaceNodeID,
        title: String,
        subtitle: String? = nil,
        kind: LunaProjectTreeNodeKind,
        projectID: LunaProjectID? = nil,
        fileID: LunaFileID? = nil,
        children: [LunaProjectTreeNode] = [],
        isEnabled: Bool = true,
        isSelectable: Bool? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.projectID = projectID
        self.fileID = fileID
        self.children = children
        self.isEnabled = isEnabled
        self.isSelectable = isSelectable ?? (kind == .file || kind == .custom)
        self.accessibilityLabel = accessibilityLabel ?? title
    }

    public var hasChildren: Bool { !children.isEmpty }

    public static func project(
        id: LunaWorkspaceNodeID,
        title: String,
        projectID: LunaProjectID,
        children: [LunaProjectTreeNode]
    ) -> LunaProjectTreeNode {
        LunaProjectTreeNode(id: id, title: title, kind: .project, projectID: projectID, children: children, isSelectable: false)
    }

    public static func folder(
        id: LunaWorkspaceNodeID,
        title: String,
        projectID: LunaProjectID? = nil,
        children: [LunaProjectTreeNode]
    ) -> LunaProjectTreeNode {
        LunaProjectTreeNode(id: id, title: title, kind: .folder, projectID: projectID, children: children, isSelectable: false)
    }

    public static func group(
        id: LunaWorkspaceNodeID,
        title: String,
        children: [LunaProjectTreeNode]
    ) -> LunaProjectTreeNode {
        LunaProjectTreeNode(id: id, title: title, kind: .group, children: children, isSelectable: false)
    }

    public static func file(
        id: LunaWorkspaceNodeID,
        title: String,
        fileID: LunaFileID,
        projectID: LunaProjectID? = nil,
        subtitle: String? = nil
    ) -> LunaProjectTreeNode {
        LunaProjectTreeNode(id: id, title: title, subtitle: subtitle, kind: .file, projectID: projectID, fileID: fileID)
    }
}

public struct LunaProjectTreeSnapshot: Hashable, Sendable {
    public var projects: [LunaProjectDescriptor]
    public var roots: [LunaProjectTreeNode]
    public var version: Int

    public init(
        projects: [LunaProjectDescriptor] = [],
        roots: [LunaProjectTreeNode] = [],
        version: Int = 0
    ) {
        self.projects = projects
        self.roots = roots
        self.version = max(0, version)
    }

    public var isEmpty: Bool { roots.isEmpty }

    public func node(with id: LunaWorkspaceNodeID) -> LunaProjectTreeNode? {
        Self.findNode(id, in: roots)
    }

    public func node(for fileID: LunaFileID) -> LunaProjectTreeNode? {
        Self.findNode(for: fileID, in: roots)
    }

    public func sidebarItems(commandForNode: (LunaProjectTreeNode) -> LunaCommandID? = { _ in nil }) -> [LunaSidebarItem] {
        roots.map { $0.sidebarItem(commandForNode: commandForNode) }
    }

    private static func findNode(_ id: LunaWorkspaceNodeID, in nodes: [LunaProjectTreeNode]) -> LunaProjectTreeNode? {
        for node in nodes {
            if node.id == id { return node }
            if let match = findNode(id, in: node.children) { return match }
        }
        return nil
    }

    private static func findNode(for fileID: LunaFileID, in nodes: [LunaProjectTreeNode]) -> LunaProjectTreeNode? {
        for node in nodes {
            if node.fileID == fileID { return node }
            if let match = findNode(for: fileID, in: node.children) { return match }
        }
        return nil
    }
}

public extension LunaProjectTreeNode {
    func sidebarItem(commandForNode: (LunaProjectTreeNode) -> LunaCommandID? = { _ in nil }) -> LunaSidebarItem {
        LunaSidebarItem(
            id: LunaSidebarItemID(rawValue: id.rawValue),
            title: title,
            subtitle: subtitle,
            kind: kind.sidebarKind,
            children: children.map { $0.sidebarItem(commandForNode: commandForNode) },
            isEnabled: isEnabled,
            isSelectable: isSelectable,
            activateCommand: commandForNode(self),
            accessibilityLabel: accessibilityLabel
        )
    }
}

public extension LunaProjectTreeNodeKind {
    var sidebarKind: LunaSidebarItemKind {
        switch self {
        case .project, .folder:
            return .folder
        case .group:
            return .section
        case .file:
            return .file
        case .custom:
            return .custom
        }
    }
}

// MARK: - Workspace state

public struct LunaWorkspaceState: Hashable, Sendable {
    public var snapshot: LunaProjectTreeSnapshot
    public var filesByID: [LunaFileID: LunaFileDescriptor]
    public var openFileIDs: [LunaFileID]
    public var activeFileID: LunaFileID?
    public var selectedNodeID: LunaWorkspaceNodeID?
    public var expandedNodeIDs: Set<LunaWorkspaceNodeID>

    public init(
        snapshot: LunaProjectTreeSnapshot = LunaProjectTreeSnapshot(),
        fileDescriptors: [LunaFileDescriptor] = [],
        openFileIDs: [LunaFileID] = [],
        activeFileID: LunaFileID? = nil,
        selectedNodeID: LunaWorkspaceNodeID? = nil,
        expandedNodeIDs: Set<LunaWorkspaceNodeID> = []
    ) {
        self.snapshot = snapshot
        self.filesByID = Dictionary(uniqueKeysWithValues: fileDescriptors.map { ($0.id, $0) })
        self.openFileIDs = openFileIDs
        self.activeFileID = activeFileID ?? openFileIDs.first
        self.selectedNodeID = selectedNodeID
        self.expandedNodeIDs = expandedNodeIDs
        normalize()
    }

    public var activeFileDescriptor: LunaFileDescriptor? {
        activeFileID.flatMap { filesByID[$0] }
    }

    public mutating func normalize() {
        let knownIDs = Set(filesByID.keys)
        openFileIDs = openFileIDs.filter { knownIDs.contains($0) }
        if let activeFileID, !openFileIDs.contains(activeFileID) {
            self.activeFileID = openFileIDs.first
        } else if activeFileID == nil {
            activeFileID = openFileIDs.first
        }
        if let selectedNodeID, snapshot.node(with: selectedNodeID) == nil {
            self.selectedNodeID = nil
        }
        expandedNodeIDs = expandedNodeIDs.filter { snapshot.node(with: $0) != nil }
    }

    public mutating func registerFile(_ descriptor: LunaFileDescriptor) {
        filesByID[descriptor.id] = descriptor
    }

    public func descriptor(for fileID: LunaFileID) -> LunaFileDescriptor? {
        filesByID[fileID]
    }

    @discardableResult
    public mutating func open(fileID: LunaFileID) -> Bool {
        guard filesByID[fileID] != nil else { return false }
        if !openFileIDs.contains(fileID) {
            openFileIDs.append(fileID)
        }
        activeFileID = fileID
        selectedNodeID = snapshot.node(for: fileID)?.id ?? selectedNodeID
        return true
    }

    @discardableResult
    public mutating func close(fileID: LunaFileID) -> Bool {
        guard let index = openFileIDs.firstIndex(of: fileID) else { return false }
        openFileIDs.remove(at: index)
        if activeFileID == fileID {
            if openFileIDs.indices.contains(index) {
                activeFileID = openFileIDs[index]
            } else {
                activeFileID = openFileIDs.last
            }
            selectedNodeID = activeFileID.flatMap { snapshot.node(for: $0)?.id }
        }
        normalize()
        return true
    }

    public func sidebarItems(commandForNode: (LunaProjectTreeNode) -> LunaCommandID? = { _ in nil }) -> [LunaSidebarItem] {
        snapshot.sidebarItems(commandForNode: commandForNode)
    }

    public func sidebarState(isVisible: Bool = true, sidebarWidth: Int = 236) -> LunaSidebarState {
        LunaSidebarState(
            selectedItemID: selectedNodeID.map { LunaSidebarItemID(rawValue: $0.rawValue) },
            expandedItemIDs: Set(expandedNodeIDs.map { LunaSidebarItemID(rawValue: $0.rawValue) })
        )
    }

    public mutating func syncFromActiveDocument(_ documentStore: LunaDocumentStore) {
        guard let documentID = documentStore.activeDocumentID else {
            activeFileID = nil
            selectedNodeID = nil
            return
        }
        let fileID = LunaFileID(rawValue: documentID.rawValue)
        if filesByID[fileID] != nil {
            _ = open(fileID: fileID)
        }
    }
}

// MARK: - Adapter contracts

public struct LunaWorkspaceOpenRequest: Hashable, Sendable {
    public var fileID: LunaFileID
    public var source: String?

    public init(fileID: LunaFileID, source: String? = nil) {
        self.fileID = fileID
        self.source = source
    }
}

public struct LunaWorkspaceOpenResult: Hashable, Sendable {
    public var file: LunaFileDescriptor?
    public var text: String?
    public var statusMessage: String?

    public init(
        file: LunaFileDescriptor? = nil,
        text: String? = nil,
        statusMessage: String? = nil
    ) {
        self.file = file
        self.text = text
        self.statusMessage = statusMessage
    }

    public var didOpen: Bool { file != nil && text != nil }
}

public enum LunaDocumentSaveKind: String, Hashable, Sendable {
    case save
    case saveAs
    case saveAll
}

public struct LunaDocumentSaveRequest: Hashable, Sendable {
    public var documentID: LunaDocumentID
    public var fileID: LunaFileID?
    public var title: String
    public var displayPath: String?
    public var text: String
    public var editRevision: Int
    public var kind: LunaDocumentSaveKind

    public init(
        documentID: LunaDocumentID,
        fileID: LunaFileID? = nil,
        title: String,
        displayPath: String? = nil,
        text: String,
        editRevision: Int,
        kind: LunaDocumentSaveKind = .save
    ) {
        self.documentID = documentID
        self.fileID = fileID
        self.title = title
        self.displayPath = displayPath
        self.text = text
        self.editRevision = max(0, editRevision)
        self.kind = kind
    }
}

public enum LunaDocumentSaveOutcome: String, Hashable, Sendable {
    case saved
    case noDestination
    case cancelled
    case failed
}

public struct LunaDocumentSaveResult: Hashable, Sendable {
    public var outcome: LunaDocumentSaveOutcome
    public var documentID: LunaDocumentID
    public var file: LunaFileDescriptor?
    public var savedEditRevision: Int?
    public var statusMessage: String?

    public init(
        outcome: LunaDocumentSaveOutcome,
        documentID: LunaDocumentID,
        file: LunaFileDescriptor? = nil,
        savedEditRevision: Int? = nil,
        statusMessage: String? = nil
    ) {
        self.outcome = outcome
        self.documentID = documentID
        self.file = file
        self.savedEditRevision = savedEditRevision
        self.statusMessage = statusMessage
    }

    public var didSave: Bool { outcome == .saved }

    public static func saved(
        _ request: LunaDocumentSaveRequest,
        file: LunaFileDescriptor? = nil,
        statusMessage: String? = nil
    ) -> LunaDocumentSaveResult {
        LunaDocumentSaveResult(
            outcome: .saved,
            documentID: request.documentID,
            file: file,
            savedEditRevision: request.editRevision,
            statusMessage: statusMessage ?? "Saved \(request.title)"
        )
    }
}

public protocol LunaWorkspaceAdapter {
    mutating func projectTreeSnapshot() -> LunaProjectTreeSnapshot
    mutating func openFile(_ request: LunaWorkspaceOpenRequest) -> LunaWorkspaceOpenResult
    mutating func saveDocument(_ request: LunaDocumentSaveRequest) -> LunaDocumentSaveResult
}

// MARK: - Dirty close policy

public enum LunaDocumentCloseDecision: Hashable, Sendable {
    case closeNow
    case requestSave
    case cancel
}

public struct LunaDocumentCloseRequest: Hashable, Sendable {
    public var documentID: LunaDocumentID
    public var title: String
    public var isDirty: Bool
    public var isClosable: Bool

    public init(documentID: LunaDocumentID, title: String, isDirty: Bool, isClosable: Bool = true) {
        self.documentID = documentID
        self.title = title
        self.isDirty = isDirty
        self.isClosable = isClosable
    }
}

public struct LunaDocumentCloseResolution: Hashable, Sendable {
    public var decision: LunaDocumentCloseDecision
    public var statusMessage: String?

    public init(decision: LunaDocumentCloseDecision, statusMessage: String? = nil) {
        self.decision = decision
        self.statusMessage = statusMessage
    }

    public var shouldClose: Bool { decision == .closeNow }
    public var needsUserPrompt: Bool { decision == .requestSave }
}

public struct LunaDirtyDocumentClosePolicy: Hashable, Sendable {
    public var promptsForDirtyDocuments: Bool

    public init(promptsForDirtyDocuments: Bool = true) {
        self.promptsForDirtyDocuments = promptsForDirtyDocuments
    }

    public func resolve(_ request: LunaDocumentCloseRequest) -> LunaDocumentCloseResolution {
        guard request.isClosable else {
            return LunaDocumentCloseResolution(decision: .cancel, statusMessage: "\(request.title) cannot be closed")
        }
        guard request.isDirty else {
            return LunaDocumentCloseResolution(decision: .closeNow, statusMessage: "Closed \(request.title)")
        }
        if promptsForDirtyDocuments {
            return LunaDocumentCloseResolution(decision: .requestSave, statusMessage: "Save changes to \(request.title)?")
        }
        return LunaDocumentCloseResolution(decision: .closeNow, statusMessage: "Closed dirty document \(request.title) without prompting")
    }
}

// MARK: - Document store workspace helpers

public extension LunaDocumentStore {
    @discardableResult
    mutating func openOrActivate(
        file: LunaFileDescriptor,
        text: String,
        isPinned: Bool = false,
        isClosable: Bool = true
    ) -> LunaDocumentID {
        let documentID = LunaDocumentID(rawValue: file.id.rawValue)
        if activate(documentID) {
            return documentID
        }
        let descriptor = file.documentDescriptor(id: documentID, isPinned: isPinned, isClosable: isClosable)
        openDocuments.append(LunaDocumentBuffer(descriptor: descriptor, text: text))
        activeDocumentID = documentID
        normalize()
        return documentID
    }

    func saveRequestForActiveDocument(kind: LunaDocumentSaveKind = .save) -> LunaDocumentSaveRequest? {
        guard let activeDocument else { return nil }
        return saveRequest(for: activeDocument.id, kind: kind)
    }

    func saveRequest(for documentID: LunaDocumentID, kind: LunaDocumentSaveKind = .save) -> LunaDocumentSaveRequest? {
        guard let document = document(with: documentID) else { return nil }
        return LunaDocumentSaveRequest(
            documentID: document.id,
            fileID: LunaFileID(rawValue: document.id.rawValue),
            title: document.descriptor.title,
            displayPath: document.descriptor.displayPath,
            text: document.textState.document.text,
            editRevision: document.textState.editRevision,
            kind: kind
        )
    }

    mutating func applySaveResult(_ result: LunaDocumentSaveResult) {
        guard result.didSave,
              let index = openDocuments.firstIndex(where: { $0.id == result.documentID }) else { return }
        if let file = result.file {
            let old = openDocuments[index].descriptor
            openDocuments[index].descriptor = file.documentDescriptor(
                id: old.id,
                isPinned: old.isPinned,
                isClosable: old.isClosable
            )
        }
        openDocuments[index].markClean()
    }

    func dirtyDocumentIDs() -> [LunaDocumentID] {
        openDocuments.filter(\.isDirty).map(\.id)
    }

    func closeRequest(for documentID: LunaDocumentID) -> LunaDocumentCloseRequest? {
        guard let document = document(with: documentID) else { return nil }
        return LunaDocumentCloseRequest(
            documentID: document.id,
            title: document.descriptor.title,
            isDirty: document.isDirty,
            isClosable: document.descriptor.isClosable
        )
    }
}
