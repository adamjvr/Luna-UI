// LunaEditableTextDocument.swift
//
// Phase 3D: editable text input foundation.
//
// This is intentionally *not* the final editor storage engine. It is a small,
// deterministic mutable text model that proves Luna can turn caret/selection
// coordinates into document mutations before we add ropes, piece tables, undo,
// syntax scopes, IME composition, or multi-cursor editing.

import Foundation
import LunaAccessibility

/// Bias used when converting UTF-8 byte offsets back into Swift String indices.
///
/// Luna editor coordinates are UTF-8 byte offsets so they can later map cleanly
/// onto rope/piece-table storage. Swift `String` mutation still requires valid
/// scalar boundaries, so this bias chooses how to snap if a byte coordinate lands
/// inside a multi-byte scalar. Phase 3D demo input is ASCII-first, but this keeps
/// the foundation from trapping on arbitrary UTF-8 text.
public enum LunaTextIndexSnapBias: Hashable, Sendable {
    case backward
    case forward
}

/// Result of a single editable text mutation.
public struct LunaTextEditResult: Hashable, Sendable {
    public var oldRange: LunaTextRange
    public var insertedText: String
    public var newCaret: LunaStaticTextCaret
    public var newSelection: LunaStaticTextSelection?
    public var didChange: Bool

    public init(
        oldRange: LunaTextRange,
        insertedText: String,
        newCaret: LunaStaticTextCaret,
        newSelection: LunaStaticTextSelection? = nil,
        didChange: Bool
    ) {
        self.oldRange = oldRange
        self.insertedText = insertedText
        self.newCaret = newCaret
        self.newSelection = newSelection
        self.didChange = didChange
    }
}

/// Small mutable text document used by Phase 3D.
///
/// The public read surface is still `LunaStaticTextDocument`, because rendering,
/// layout, accessibility, hit testing, caret geometry, and selection rectangles
/// already consume that stable line model. This wrapper owns mutation and then
/// regenerates the static line snapshot after every edit.
public struct LunaEditableTextDocument: Hashable, Sendable {
    public private(set) var text: String
    public private(set) var staticDocument: LunaStaticTextDocument

    public init(text: String) {
        self.text = text
        self.staticDocument = LunaStaticTextDocument(text: text)
    }

    public var lineCount: Int { staticDocument.lineCount }

    public func clampedLocation(_ location: LunaTextLocation) -> LunaTextLocation {
        staticDocument.clampedLocation(location)
    }

    public func accessibilityRange(for range: LunaTextRange) -> LunaAccessibilityTextRange {
        staticDocument.accessibilityRange(for: range)
    }

    /// Replace a normalized/clamped text range with the supplied string.
    @discardableResult
    public mutating func replace(_ range: LunaTextRange, with replacement: String) -> LunaTextEditResult {
        let oldDocument = staticDocument
        let clamped = oldDocument.clampedRange(range)
        let startOffset = oldDocument.absoluteUTF8Offset(for: clamped.anchor)
        let endOffset = oldDocument.absoluteUTF8Offset(for: clamped.focus)

        if startOffset == endOffset, replacement.isEmpty {
            let caret = LunaStaticTextCaret(location: oldDocument.clampedLocation(clamped.anchor))
            return LunaTextEditResult(
                oldRange: clamped,
                insertedText: replacement,
                newCaret: caret,
                didChange: false
            )
        }

        let startIndex = stringIndex(forUTF8Offset: startOffset, bias: .backward)
        let endIndex = stringIndex(forUTF8Offset: endOffset, bias: .forward)
        text.replaceSubrange(startIndex..<endIndex, with: replacement)
        staticDocument = LunaStaticTextDocument(text: text)

        let newCaretLocation = staticDocument.location(forAbsoluteUTF8Offset: startOffset + replacement.utf8.count)
        let caret = LunaStaticTextCaret(location: newCaretLocation)
        return LunaTextEditResult(
            oldRange: clamped,
            insertedText: replacement,
            newCaret: caret,
            newSelection: nil,
            didChange: true
        )
    }

    /// Insert text at a caret, or replace the current selection if one exists.
    @discardableResult
    public mutating func insertText(
        _ insertedText: String,
        caret: LunaStaticTextCaret,
        replacing selection: LunaStaticTextSelection? = nil
    ) -> LunaTextEditResult {
        let range = selection?.range ?? LunaTextRange(anchor: caret.location, focus: caret.location)
        return replace(range, with: insertedText)
    }

    /// Delete one UTF-8 byte before the caret, or replace the current selection
    /// with the empty string. This is ASCII-first but byte-stable; full grapheme
    /// cluster deletion belongs with the future real editor storage layer.
    @discardableResult
    public mutating func deleteBackward(
        caret: LunaStaticTextCaret,
        selection: LunaStaticTextSelection? = nil
    ) -> LunaTextEditResult {
        if let selection, !selection.isCollapsed {
            return replace(selection.range, with: "")
        }

        let clamped = staticDocument.clampedLocation(caret.location)
        let absolute = staticDocument.absoluteUTF8Offset(for: clamped)
        guard absolute > 0 else {
            return LunaTextEditResult(
                oldRange: LunaTextRange(anchor: clamped, focus: clamped),
                insertedText: "",
                newCaret: LunaStaticTextCaret(location: clamped),
                didChange: false
            )
        }

        let start = staticDocument.location(forAbsoluteUTF8Offset: absolute - 1)
        return replace(LunaTextRange(anchor: start, focus: clamped), with: "")
    }

    /// Delete one UTF-8 byte after the caret, or replace the current selection
    /// with the empty string.
    @discardableResult
    public mutating func deleteForward(
        caret: LunaStaticTextCaret,
        selection: LunaStaticTextSelection? = nil
    ) -> LunaTextEditResult {
        if let selection, !selection.isCollapsed {
            return replace(selection.range, with: "")
        }

        let clamped = staticDocument.clampedLocation(caret.location)
        let absolute = staticDocument.absoluteUTF8Offset(for: clamped)
        guard absolute < text.utf8.count else {
            return LunaTextEditResult(
                oldRange: LunaTextRange(anchor: clamped, focus: clamped),
                insertedText: "",
                newCaret: LunaStaticTextCaret(location: clamped),
                didChange: false
            )
        }

        let end = staticDocument.location(forAbsoluteUTF8Offset: absolute + 1)
        return replace(LunaTextRange(anchor: clamped, focus: end), with: "")
    }

    /// Return the nearest editor location one UTF-8 byte before the supplied location.
    public func locationBefore(_ location: LunaTextLocation) -> LunaTextLocation {
        let clamped = staticDocument.clampedLocation(location)
        let absolute = staticDocument.absoluteUTF8Offset(for: clamped)
        guard absolute > 0 else { return clamped }
        return staticDocument.location(forAbsoluteUTF8Offset: absolute - 1)
    }

    /// Return the nearest editor location one UTF-8 byte after the supplied location.
    public func locationAfter(_ location: LunaTextLocation) -> LunaTextLocation {
        let clamped = staticDocument.clampedLocation(location)
        let absolute = staticDocument.absoluteUTF8Offset(for: clamped)
        guard absolute < text.utf8.count else { return clamped }
        return staticDocument.location(forAbsoluteUTF8Offset: absolute + 1)
    }

    private func stringIndex(forUTF8Offset offset: Int, bias: LunaTextIndexSnapBias) -> String.Index {
        let utf8Count = text.utf8.count
        let clamped = min(max(0, offset), utf8Count)

        func exact(_ candidate: Int) -> String.Index? {
            let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: candidate)
            return utf8Index.samePosition(in: text)
        }

        if let exact = exact(clamped) { return exact }

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

/// Mutable editor surface state used by the Phase 3D demo and tests.
///
/// This glues the document model to caret/selection state. It deliberately has
/// no undo stack, no clipboard, no IME composition, and no multi-cursor support;
/// those are later editor phases built on top of this first mutation contract.
public struct LunaEditableTextState: Hashable, Sendable {
    public var document: LunaEditableTextDocument
    public var caret: LunaStaticTextCaret
    public var selection: LunaStaticTextSelection?
    public private(set) var editRevision: Int

    public init(
        text: String,
        caret: LunaStaticTextCaret = LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 0)),
        selection: LunaStaticTextSelection? = nil,
        editRevision: Int = 0
    ) {
        self.document = LunaEditableTextDocument(text: text)
        self.caret = LunaStaticTextCaret(location: self.document.clampedLocation(caret.location))
        self.selection = selection
        self.editRevision = max(0, editRevision)
    }

    public mutating func setCaret(_ location: LunaTextLocation, clearSelection: Bool = true) {
        caret = LunaStaticTextCaret(location: document.clampedLocation(location))
        if clearSelection { selection = nil }
    }

    @discardableResult
    public mutating func insertText(_ text: String) -> LunaTextEditResult {
        let result = document.insertText(text, caret: caret, replacing: selection)
        apply(result)
        return result
    }

    @discardableResult
    public mutating func insertNewline() -> LunaTextEditResult {
        insertText("\n")
    }

    @discardableResult
    public mutating func deleteBackward() -> LunaTextEditResult {
        let result = document.deleteBackward(caret: caret, selection: selection)
        apply(result)
        return result
    }

    @discardableResult
    public mutating func deleteForward() -> LunaTextEditResult {
        let result = document.deleteForward(caret: caret, selection: selection)
        apply(result)
        return result
    }

    public mutating func moveCaretBackward() {
        setCaret(document.locationBefore(caret.location))
    }

    public mutating func moveCaretForward() {
        setCaret(document.locationAfter(caret.location))
    }

    private mutating func apply(_ result: LunaTextEditResult) {
        caret = result.newCaret
        selection = result.newSelection
        if result.didChange { editRevision += 1 }
    }
}
