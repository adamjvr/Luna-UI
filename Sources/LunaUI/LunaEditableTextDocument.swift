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

    /// Set or clear the current user selection while keeping the caret at the
    /// focus end of the range.
    ///
    /// This is the product-neutral selection primitive used by pointer drag,
    /// Shift-click, Shift+Arrow, find-result sync, and future app commands. The
    /// range keeps anchor/focus direction for extension behavior, while the text
    /// view normalizes it when calculating rectangles.
    public mutating func setSelection(_ range: LunaTextRange?) {
        guard let range else {
            selection = nil
            return
        }

        let anchor = document.clampedLocation(range.anchor)
        let focus = document.clampedLocation(range.focus)
        caret = LunaStaticTextCaret(location: focus)
        if anchor == focus {
            selection = nil
        } else {
            selection = LunaStaticTextSelection(range: LunaTextRange(anchor: anchor, focus: focus))
        }
    }

    /// Select the entire document and place the caret at the focus/end edge.
    ///
    /// This is the product-neutral primitive behind app commands such as
    /// Select All. It lives on editable state, not the demo, so future Moth and
    /// other Luna consumers can use the same text-range behavior without
    /// reimplementing document endpoint math.
    public mutating func selectAll() {
        let lastLineIndex = max(0, document.staticDocument.lineCount - 1)
        let lastLineLength = document.staticDocument[line: lastLineIndex]?.utf8Length ?? 0
        setSelection(
            LunaTextRange(
                anchor: LunaTextLocation(lineIndex: 0, utf8Column: 0),
                focus: LunaTextLocation(lineIndex: lastLineIndex, utf8Column: lastLineLength)
            )
        )
    }

    /// Begin a user selection gesture. A simple click calls this and then usually
    /// leaves the range collapsed; drag and Shift-click extend from the same
    /// anchor through `extendSelection(to:)`.
    public mutating func beginSelection(at location: LunaTextLocation, clearSelection: Bool = true) {
        let clamped = document.clampedLocation(location)
        caret = LunaStaticTextCaret(location: clamped)
        if clearSelection { selection = nil }
    }

    /// Extend the current selection to a new focus location. If there is no
    /// active range yet, the current caret becomes the anchor.
    public mutating func extendSelection(to focusLocation: LunaTextLocation) {
        let focus = document.clampedLocation(focusLocation)
        let anchor = selection?.range.anchor ?? caret.location
        setSelection(LunaTextRange(anchor: anchor, focus: focus))
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

    /// Replace an explicit text range and update caret/selection/revision state.
    ///
    /// Phase 4B uses this for find/replace. Keeping the operation on the editable
    /// state rather than mutating `document` directly preserves the single place
    /// that advances edit revisions and collapses selections after text changes.
    @discardableResult
    public mutating func replaceRange(_ range: LunaTextRange, with replacement: String) -> LunaTextEditResult {
        let result = document.replace(range, with: replacement)
        apply(result)
        return result
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

    public mutating func moveCaretBackward(extendingSelection: Bool = false) {
        if extendingSelection {
            extendSelection(to: document.locationBefore(caret.location))
            return
        }

        if let selection, !selection.isCollapsed {
            setCaret(selection.range.normalized.anchor)
            return
        }

        setCaret(document.locationBefore(caret.location))
    }

    public mutating func moveCaretForward(extendingSelection: Bool = false) {
        if extendingSelection {
            extendSelection(to: document.locationAfter(caret.location))
            return
        }

        if let selection, !selection.isCollapsed {
            setCaret(selection.range.normalized.focus)
            return
        }

        setCaret(document.locationAfter(caret.location))
    }

    private mutating func apply(_ result: LunaTextEditResult) {
        caret = result.newCaret
        selection = result.newSelection
        if result.didChange { editRevision += 1 }
    }
}
