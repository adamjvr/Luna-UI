// SPDX-License-Identifier: MPL-2.0
//
// LunaEditableFieldState.swift
//
// Reusable compact text-field editing state. Offsets are UTF-8 byte offsets
// snapped to extended-grapheme boundaries, matching Luna/Moth text coordinates.
// Clipboard access remains outside this value so applications retain command and
// mutation policy.

import Foundation

public struct LunaEditableFieldState: Hashable, Sendable {
    public private(set) var text: String
    public private(set) var anchorUTF8Offset: Int
    public private(set) var caretUTF8Offset: Int

    public init(
        text: String = "",
        anchorUTF8Offset: Int? = nil,
        caretUTF8Offset: Int? = nil
    ) {
        self.text = text
        let end = text.utf8.count
        let caret = caretUTF8Offset ?? end
        let anchor = anchorUTF8Offset ?? caret
        self.caretUTF8Offset = 0
        self.anchorUTF8Offset = 0
        self.caretUTF8Offset = snappedOffset(caret, bias: .nearest)
        self.anchorUTF8Offset = snappedOffset(anchor, bias: .nearest)
    }

    public var hasSelection: Bool { anchorUTF8Offset != caretUTF8Offset }

    public var selectionUTF8Range: Range<Int>? {
        guard hasSelection else { return nil }
        return min(anchorUTF8Offset, caretUTF8Offset)..<max(anchorUTF8Offset, caretUTF8Offset)
    }

    public var selectedText: String? {
        guard let range = selectionUTF8Range else { return nil }
        return substring(utf8Range: range)
    }

    public mutating func setText(
        _ newText: String,
        caretAtEnd: Bool = true,
        selectingAll: Bool = false
    ) {
        text = newText
        let target = caretAtEnd ? newText.utf8.count : 0
        caretUTF8Offset = target
        anchorUTF8Offset = selectingAll ? (caretAtEnd ? 0 : newText.utf8.count) : target
    }

    public mutating func selectAll() {
        anchorUTF8Offset = 0
        caretUTF8Offset = text.utf8.count
    }

    public mutating func collapseSelection() {
        anchorUTF8Offset = caretUTF8Offset
    }

    public mutating func setCaret(
        utf8Offset: Int,
        extendingSelection: Bool = false
    ) {
        let snapped = snappedOffset(utf8Offset, bias: .nearest)
        if !extendingSelection {
            anchorUTF8Offset = snapped
        }
        caretUTF8Offset = snapped
    }

    public mutating func setCaret(
        characterIndex: Int,
        extendingSelection: Bool = false
    ) {
        let boundaries = graphemeBoundaries()
        let index = min(max(0, characterIndex), max(0, boundaries.count - 1))
        setCaret(utf8Offset: boundaries[index], extendingSelection: extendingSelection)
    }

    public func utf8Offset(forCharacterIndex characterIndex: Int) -> Int {
        let boundaries = graphemeBoundaries()
        let index = min(max(0, characterIndex), max(0, boundaries.count - 1))
        return boundaries[index]
    }

    public func characterIndex(forUTF8Offset offset: Int) -> Int {
        let snapped = snappedOffset(offset, bias: .nearest)
        let boundaries = graphemeBoundaries()
        return boundaries.firstIndex(of: snapped) ?? 0
    }

    public mutating func moveBackward(extendingSelection: Bool = false) {
        if hasSelection && !extendingSelection {
            setCaret(utf8Offset: selectionUTF8Range?.lowerBound ?? caretUTF8Offset)
            return
        }
        let boundaries = graphemeBoundaries()
        let current = characterIndex(forUTF8Offset: caretUTF8Offset)
        setCaret(
            utf8Offset: boundaries[max(0, current - 1)],
            extendingSelection: extendingSelection
        )
    }

    public mutating func moveForward(extendingSelection: Bool = false) {
        if hasSelection && !extendingSelection {
            setCaret(utf8Offset: selectionUTF8Range?.upperBound ?? caretUTF8Offset)
            return
        }
        let boundaries = graphemeBoundaries()
        let current = characterIndex(forUTF8Offset: caretUTF8Offset)
        setCaret(
            utf8Offset: boundaries[min(boundaries.count - 1, current + 1)],
            extendingSelection: extendingSelection
        )
    }

    public mutating func moveToStart(extendingSelection: Bool = false) {
        setCaret(utf8Offset: 0, extendingSelection: extendingSelection)
    }

    public mutating func moveToEnd(extendingSelection: Bool = false) {
        setCaret(utf8Offset: text.utf8.count, extendingSelection: extendingSelection)
    }

    @discardableResult
    public mutating func replaceSelection(with replacement: String) -> Bool {
        let range = selectionUTF8Range ?? caretUTF8Offset..<caretUTF8Offset
        let removed = substring(utf8Range: range)
        if range.isEmpty && replacement.isEmpty { return false }
        if removed == replacement && !range.isEmpty { return false }

        let lower = stringIndex(forUTF8Offset: range.lowerBound)
        let upper = stringIndex(forUTF8Offset: range.upperBound)
        text.replaceSubrange(lower..<upper, with: replacement)
        let next = range.lowerBound + replacement.utf8.count
        caretUTF8Offset = next
        anchorUTF8Offset = next
        return true
    }

    @discardableResult
    public mutating func deleteBackward() -> Bool {
        if hasSelection { return replaceSelection(with: "") }
        guard caretUTF8Offset > 0 else { return false }
        let boundaries = graphemeBoundaries()
        let current = characterIndex(forUTF8Offset: caretUTF8Offset)
        guard current > 0 else { return false }
        anchorUTF8Offset = boundaries[current - 1]
        return replaceSelection(with: "")
    }

    @discardableResult
    public mutating func deleteForward() -> Bool {
        if hasSelection { return replaceSelection(with: "") }
        let boundaries = graphemeBoundaries()
        let current = characterIndex(forUTF8Offset: caretUTF8Offset)
        guard current < boundaries.count - 1 else { return false }
        anchorUTF8Offset = boundaries[current + 1]
        return replaceSelection(with: "")
    }

    private enum SnapBias { case backward, forward, nearest }

    private func graphemeBoundaries() -> [Int] {
        var result = [0]
        result.reserveCapacity(text.count + 1)
        var offset = 0
        for character in text {
            offset += String(character).utf8.count
            result.append(offset)
        }
        return result
    }

    private func snappedOffset(_ requested: Int, bias: SnapBias) -> Int {
        let value = min(max(0, requested), text.utf8.count)
        let boundaries = graphemeBoundaries()
        var low = 0
        var high = boundaries.count
        while low < high {
            let middle = (low + high) / 2
            if boundaries[middle] < value {
                low = middle + 1
            } else {
                high = middle
            }
        }
        if low < boundaries.count, boundaries[low] == value { return value }
        let previous = boundaries[max(0, low - 1)]
        let next = boundaries[min(boundaries.count - 1, low)]
        switch bias {
        case .backward: return previous
        case .forward: return next
        case .nearest:
            return value - previous <= next - value ? previous : next
        }
    }

    private func stringIndex(forUTF8Offset offset: Int) -> String.Index {
        let snapped = snappedOffset(offset, bias: .nearest)
        let index = text.utf8.index(text.utf8.startIndex, offsetBy: snapped)
        return String.Index(index, within: text) ?? text.endIndex
    }

    private func substring(utf8Range: Range<Int>) -> String {
        let lower = stringIndex(forUTF8Offset: utf8Range.lowerBound)
        let upper = stringIndex(forUTF8Offset: utf8Range.upperBound)
        return String(text[lower..<upper])
    }
}
