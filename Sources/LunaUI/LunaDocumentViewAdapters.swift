// SPDX-License-Identifier: MPL-2.0
// LunaDocumentViewAdapters.swift
//
// Phase 5E.2: product-neutral document/view adapter seams.
//
// Luna owns reusable editor anatomy, not a product's authoritative source buffer.
// These contracts let an application expose a stable, immutable text snapshot to
// Luna while keeping storage, transactions, undo, dirty-state policy, and shared
// document ownership in the application layer.

import Foundation

/// Stable identity for one presentation of a document.
///
/// A document may have any number of view identities. Each view retains its own
/// caret, selection, preferred column, and viewport state while observing the
/// same document revision.
public struct LunaDocumentViewID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaDocumentViewID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

/// Monotonic content revision supplied by the application-owned text storage.
public struct LunaDocumentContentRevision: Hashable, Sendable, RawRepresentable, Comparable, Codable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let initial = LunaDocumentContentRevision(rawValue: 0)

    public static func < (lhs: LunaDocumentContentRevision, rhs: LunaDocumentContentRevision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Half-open absolute UTF-8 byte range used at the storage adapter boundary.
///
/// Luna's visible text geometry continues to use line-relative `LunaTextRange`.
/// Absolute byte ranges are deliberately used at this lower seam because they
/// map cleanly to ropes, piece tables, gap buffers, memory mapped files, and
/// other application-owned storage implementations.
public struct LunaUTF8TextRange: Hashable, Sendable, Codable {
    public var startOffset: Int
    public var endOffset: Int

    public init(startOffset: Int, endOffset: Int) {
        let start = max(0, startOffset)
        self.startOffset = start
        self.endOffset = max(start, endOffset)
    }

    public init(startOffset: Int, length: Int) {
        self.init(startOffset: startOffset, endOffset: max(0, startOffset) + max(0, length))
    }

    public var length: Int { max(0, endOffset - startOffset) }
    public var isEmpty: Bool { length == 0 }

    public func clamped(toUTF8Count count: Int) -> LunaUTF8TextRange {
        let upper = max(0, count)
        let start = min(max(0, startOffset), upper)
        let end = min(max(start, endOffset), upper)
        return LunaUTF8TextRange(startOffset: start, endOffset: end)
    }
}

/// Immutable application-supplied text snapshot consumed by Luna components.
public struct LunaTextStorageSnapshot: Hashable, Sendable {
    public var documentID: LunaDocumentID
    public var revision: LunaDocumentContentRevision
    public var text: String

    public init(
        documentID: LunaDocumentID,
        revision: LunaDocumentContentRevision,
        text: String
    ) {
        self.documentID = documentID
        self.revision = revision
        self.text = text
    }

    public var utf8Count: Int { text.utf8.count }
    public var staticDocument: LunaStaticTextDocument { LunaStaticTextDocument(text: text) }
    public var fullRange: LunaUTF8TextRange { LunaUTF8TextRange(startOffset: 0, endOffset: utf8Count) }

    /// Read a UTF-8 byte range while safely snapping invalid scalar boundaries.
    public func text(in range: LunaUTF8TextRange) -> String {
        let clamped = range.clamped(toUTF8Count: utf8Count)
        let start = stringIndex(forUTF8Offset: clamped.startOffset, bias: .backward)
        let end = stringIndex(forUTF8Offset: clamped.endOffset, bias: .forward)
        return String(text[start..<end])
    }

    private func stringIndex(forUTF8Offset offset: Int, bias: LunaTextIndexSnapBias) -> String.Index {
        let clamped = min(max(0, offset), utf8Count)

        func exact(_ candidate: Int) -> String.Index? {
            let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: candidate)
            return utf8Index.samePosition(in: text)
        }

        if let index = exact(clamped) { return index }

        switch bias {
        case .backward:
            var candidate = clamped
            while candidate > 0 {
                candidate -= 1
                if let index = exact(candidate) { return index }
            }
            return text.startIndex

        case .forward:
            var candidate = clamped
            while candidate < utf8Count {
                candidate += 1
                if let index = exact(candidate) { return index }
            }
            return text.endIndex
        }
    }
}

/// Minimal read adapter implemented by product-owned document storage.
///
/// The adapter returns value snapshots so Luna never retains or mutates the
/// application's authoritative source buffer.
public protocol LunaTextStorageAdapter: Sendable {
    var documentID: LunaDocumentID { get }
    var contentRevision: LunaDocumentContentRevision { get }
    func textSnapshot() -> LunaTextStorageSnapshot
}

/// Why a document-backed view needs to redraw after synchronizing revisions.
public enum LunaDocumentViewInvalidationReason: Hashable, Sendable {
    case initialObservation
    case contentRevisionChanged
}

/// Revision transition observed by one independent document view.
public struct LunaDocumentViewInvalidation: Hashable, Sendable {
    public var viewID: LunaDocumentViewID
    public var documentID: LunaDocumentID
    public var previousRevision: LunaDocumentContentRevision?
    public var currentRevision: LunaDocumentContentRevision
    public var reason: LunaDocumentViewInvalidationReason

    public init(
        viewID: LunaDocumentViewID,
        documentID: LunaDocumentID,
        previousRevision: LunaDocumentContentRevision?,
        currentRevision: LunaDocumentContentRevision,
        reason: LunaDocumentViewInvalidationReason
    ) {
        self.viewID = viewID
        self.documentID = documentID
        self.previousRevision = previousRevision
        self.currentRevision = currentRevision
        self.reason = reason
    }
}

/// Reusable view-local presentation state for one document presentation.
///
/// This state deliberately contains no source text and no edit transaction
/// policy. Two values can point at the same `documentID` while remaining fully
/// independent presentations of that shared document.
public struct LunaDocumentViewPresentationState: Hashable, Sendable {
    public var id: LunaDocumentViewID
    public var documentID: LunaDocumentID
    public var caret: LunaStaticTextCaret
    public var selection: LunaStaticTextSelection?
    public var preferredUTF8Column: Int?
    public var scrollState: LunaStaticTextScrollState
    public private(set) var observedRevision: LunaDocumentContentRevision?

    public init(
        id: LunaDocumentViewID,
        documentID: LunaDocumentID,
        caret: LunaStaticTextCaret = LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 0)),
        selection: LunaStaticTextSelection? = nil,
        preferredUTF8Column: Int? = nil,
        scrollState: LunaStaticTextScrollState = LunaStaticTextScrollState(),
        observedRevision: LunaDocumentContentRevision? = nil
    ) {
        self.id = id
        self.documentID = documentID
        self.caret = caret
        self.selection = selection
        self.preferredUTF8Column = preferredUTF8Column.map { max(0, $0) }
        self.scrollState = scrollState
        self.observedRevision = observedRevision
    }

    /// Observe a new immutable snapshot and clamp only this view's presentation
    /// coordinates. Other views over the same document remain untouched.
    @discardableResult
    public mutating func synchronize(
        with snapshot: LunaTextStorageSnapshot,
        maxVisibleLineCount: Int? = nil
    ) -> LunaDocumentViewInvalidation? {
        precondition(snapshot.documentID == documentID, "Cannot synchronize a view with a different document")

        let previous = observedRevision
        guard previous != snapshot.revision else { return nil }

        let document = snapshot.staticDocument
        caret = LunaStaticTextCaret(location: document.clampedLocation(caret.location))
        if let selection, !selection.isCollapsed {
            let clamped = document.clampedRange(selection.range)
            self.selection = clamped.isCollapsed ? nil : LunaStaticTextSelection(range: clamped)
        } else {
            selection = nil
        }

        if let maxVisibleLineCount {
            scrollState = scrollState.clamped(document: document, maxVisibleLineCount: max(0, maxVisibleLineCount))
        } else {
            scrollState = LunaStaticTextScrollState(
                scrollTopLine: min(scrollState.scrollTopLine, max(0, document.lineCount - 1))
            )
        }

        observedRevision = snapshot.revision
        return LunaDocumentViewInvalidation(
            viewID: id,
            documentID: documentID,
            previousRevision: previous,
            currentRevision: snapshot.revision,
            reason: previous == nil ? .initialObservation : .contentRevisionChanged
        )
    }
}
