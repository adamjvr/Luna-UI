// SPDX-License-Identifier: MPL-2.0
// LunaDocumentBuffer.swift
//
// Product-neutral document / buffer identity primitives.
//
// Phase 5A introduces the first bridge between Luna's editor chrome surfaces and
// real app-owned document identity. Luna still does not perform file I/O, choose
// save policy, own project semantics, or become Moth Text. It provides stable
// IDs, descriptors, open-buffer state, active-document routing helpers, dirty
// state derived from text revisions, and shell-tab projection helpers that an
// application can feed into `LunaEditorShell`.

import Foundation
import LunaCommands
import LunaCore

// MARK: - Document identity and metadata

public struct LunaDocumentID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaDocumentID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct LunaDocumentDescriptor: Hashable, Sendable {
    public var id: LunaDocumentID
    public var title: String
    public var displayPath: String?
    public var syntaxName: String?
    public var isPinned: Bool
    public var isClosable: Bool
    public var accessibilityLabel: String

    public init(
        id: LunaDocumentID,
        title: String,
        displayPath: String? = nil,
        syntaxName: String? = nil,
        isPinned: Bool = false,
        isClosable: Bool = true,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.displayPath = displayPath
        self.syntaxName = syntaxName
        self.isPinned = isPinned
        self.isClosable = isClosable
        self.accessibilityLabel = accessibilityLabel ?? title
    }
}

// MARK: - Open buffer state

public struct LunaDocumentBuffer: Hashable, Sendable {
    public var descriptor: LunaDocumentDescriptor
    public var textState: LunaEditableTextState
    public var scrollState: LunaStaticTextScrollState
    public private(set) var savedEditRevision: Int

    public init(
        descriptor: LunaDocumentDescriptor,
        textState: LunaEditableTextState,
        scrollState: LunaStaticTextScrollState = LunaStaticTextScrollState(),
        savedEditRevision: Int? = nil
    ) {
        self.descriptor = descriptor
        self.textState = textState
        self.scrollState = scrollState
        self.savedEditRevision = max(0, savedEditRevision ?? textState.editRevision)
    }

    public init(
        descriptor: LunaDocumentDescriptor,
        text: String,
        caret: LunaStaticTextCaret = LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 0)),
        selection: LunaStaticTextSelection? = nil,
        scrollState: LunaStaticTextScrollState = LunaStaticTextScrollState(),
        savedEditRevision: Int? = nil
    ) {
        let state = LunaEditableTextState(text: text, caret: caret, selection: selection)
        self.init(
            descriptor: descriptor,
            textState: state,
            scrollState: scrollState,
            savedEditRevision: savedEditRevision
        )
    }

    public var id: LunaDocumentID { descriptor.id }
    public var isDirty: Bool { textState.editRevision != savedEditRevision }

    public mutating func markClean() {
        savedEditRevision = textState.editRevision
    }

    public mutating func replaceTextState(_ nextState: LunaEditableTextState) {
        textState = nextState
    }

    public mutating func replaceScrollState(_ nextState: LunaStaticTextScrollState) {
        scrollState = nextState
    }

    public func shellTab(
        activateCommand: LunaCommandID? = nil,
        closeCommand: LunaCommandID? = nil
    ) -> LunaShellTab {
        LunaShellTab(
            id: LunaShellTabID(rawValue: descriptor.id.rawValue),
            title: descriptor.title,
            detail: descriptor.displayPath,
            isDirty: isDirty,
            isPinned: descriptor.isPinned,
            isClosable: descriptor.isClosable,
            activateCommand: activateCommand,
            closeCommand: closeCommand,
            accessibilityLabel: descriptor.accessibilityLabel
        )
    }
}

// MARK: - Open document store

public struct LunaDocumentStore: Hashable, Sendable {
    public var openDocuments: [LunaDocumentBuffer]
    public var activeDocumentID: LunaDocumentID?

    public init(openDocuments: [LunaDocumentBuffer], activeDocumentID: LunaDocumentID? = nil) {
        self.openDocuments = openDocuments
        self.activeDocumentID = activeDocumentID ?? openDocuments.first?.id
        normalize()
    }

    public var isEmpty: Bool { openDocuments.isEmpty }

    public var activeDocumentIndex: Int? {
        guard let activeDocumentID else { return nil }
        return openDocuments.firstIndex { $0.id == activeDocumentID }
    }

    public var activeDocument: LunaDocumentBuffer? {
        guard let activeDocumentIndex else { return nil }
        return openDocuments[activeDocumentIndex]
    }

    public var activeDescriptor: LunaDocumentDescriptor? { activeDocument?.descriptor }
    public var activeTextState: LunaEditableTextState? { activeDocument?.textState }
    public var activeStaticDocument: LunaStaticTextDocument? { activeDocument?.textState.document.staticDocument }
    public var activeScrollState: LunaStaticTextScrollState? { activeDocument?.scrollState }
    public var activeShellTabID: LunaShellTabID? { activeDocumentID.map { LunaShellTabID(rawValue: $0.rawValue) } }

    public mutating func normalize() {
        guard !openDocuments.isEmpty else {
            activeDocumentID = nil
            return
        }

        if let activeDocumentID, openDocuments.contains(where: { $0.id == activeDocumentID }) {
            return
        }
        activeDocumentID = openDocuments.first?.id
    }

    @discardableResult
    public mutating func activate(_ id: LunaDocumentID) -> Bool {
        guard openDocuments.contains(where: { $0.id == id }) else { return false }
        activeDocumentID = id
        return true
    }

    @discardableResult
    public mutating func activate(shellTabID: LunaShellTabID) -> Bool {
        activate(LunaDocumentID(rawValue: shellTabID.rawValue))
    }

    public mutating func replaceActiveTextState(_ nextState: LunaEditableTextState) {
        guard let activeDocumentIndex else { return }
        openDocuments[activeDocumentIndex].replaceTextState(nextState)
    }

    public mutating func replaceActiveScrollState(_ nextState: LunaStaticTextScrollState) {
        guard let activeDocumentIndex else { return }
        openDocuments[activeDocumentIndex].replaceScrollState(nextState)
    }

    public mutating func markActiveClean() {
        guard let activeDocumentIndex else { return }
        openDocuments[activeDocumentIndex].markClean()
    }

    @discardableResult
    public mutating func close(_ id: LunaDocumentID) -> LunaDocumentBuffer? {
        guard let index = openDocuments.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = openDocuments.remove(at: index)
        if activeDocumentID == id {
            if openDocuments.indices.contains(index) {
                activeDocumentID = openDocuments[index].id
            } else {
                activeDocumentID = openDocuments.last?.id
            }
        }
        normalize()
        return removed
    }

    public func document(with id: LunaDocumentID) -> LunaDocumentBuffer? {
        openDocuments.first { $0.id == id }
    }

    public func shellTabs(
        activateCommand: (LunaDocumentID) -> LunaCommandID? = { _ in nil },
        closeCommand: (LunaDocumentID) -> LunaCommandID? = { _ in nil }
    ) -> [LunaShellTab] {
        openDocuments.map { document in
            document.shellTab(
                activateCommand: activateCommand(document.id),
                closeCommand: closeCommand(document.id)
            )
        }
    }

    public func statusSegments(
        status: String,
        syntaxFallback: String = "Plain Text",
        leadingDocumentSegmentID: LunaStatusSegmentID = "document",
        dirtySegmentID: LunaStatusSegmentID = "dirty",
        revisionSegmentID: LunaStatusSegmentID = "revision",
        syntaxSegmentID: LunaStatusSegmentID = "syntax",
        scrollSegmentID: LunaStatusSegmentID = "scroll",
        positionSegmentID: LunaStatusSegmentID = "position"
    ) -> [LunaStatusSegment] {
        let descriptor = activeDescriptor
        let text = activeTextState
        let document = text?.document.staticDocument
        let caret = text?.caret ?? LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 0))
        let lineCount = document?.lineCount ?? 1
        let scrollTop = activeScrollState?.scrollTopLine ?? 0
        let isDirty = activeDocument?.isDirty ?? false
        let title = descriptor?.title ?? "No Document"
        let syntax = descriptor?.syntaxName ?? syntaxFallback

        return [
            LunaStatusSegment(id: "status", title: "Status:", value: status, placement: .leading),
            LunaStatusSegment(id: leadingDocumentSegmentID, title: "Doc", value: title, placement: .leading, emphasis: isDirty ? .accent : .normal),
            LunaStatusSegment(id: dirtySegmentID, title: isDirty ? "Modified" : "Saved", placement: .leading, emphasis: isDirty ? .accent : .muted),
            LunaStatusSegment(id: revisionSegmentID, title: "Rev", value: "\(text?.editRevision ?? 0)", placement: .leading, emphasis: .muted),
            LunaStatusSegment(id: syntaxSegmentID, title: syntax, placement: .trailing),
            LunaStatusSegment(id: scrollSegmentID, title: "Top", value: "\(scrollTop + 1)/\(max(1, lineCount))", placement: .trailing, emphasis: .muted),
            LunaStatusSegment(id: positionSegmentID, title: "Ln", value: "\(caret.location.lineIndex + 1), Col \(caret.location.utf8Column)", placement: .trailing),
        ]
    }

    public mutating func syncShellState(_ state: inout LunaEditorShellState, sidebarItemForDocument: (LunaDocumentID) -> LunaSidebarItemID? = { LunaSidebarItemID(rawValue: $0.rawValue) }) {
        normalize()
        if let activeDocumentID {
            state.tabStrip.activeTabID = LunaShellTabID(rawValue: activeDocumentID.rawValue)
            if let sidebarID = sidebarItemForDocument(activeDocumentID) {
                state.sidebar.selectedItemID = sidebarID
            }
        } else {
            state.tabStrip.activeTabID = nil
            state.sidebar.selectedItemID = nil
        }
    }
}
