// SPDX-License-Identifier: MPL-2.0
// LunaStaticTextView.swift
//
// Phase 3A/3B/3C/3D: accessible text-view primitive.
//
// This is the first editor-shaped Luna widget. Phase 3A-3C built the read-only
// display, caret, selection, and viewport contract. Phase 3D keeps rendering
// through this same surface while a separate editable document/state layer begins
// mutating text.

import Foundation
import LunaAccessibility
import LunaCore
import LunaRender
import LunaTheme

/// Stable text coordinate used by Luna editor surfaces.
///
/// Phase 3B intentionally stores the column as a UTF-8 byte offset within the
/// logical line instead of a Swift `String.Index`. That keeps this value usable
/// when the backing document becomes a rope or piece table. The current debug
/// renderer is monospaced/ASCII-first, but the semantic coordinate is already
/// byte-stable for future editor storage.
public struct LunaTextLocation: Hashable, Sendable, Comparable {
    public var lineIndex: Int
    public var utf8Column: Int

    public init(lineIndex: Int, utf8Column: Int) {
        self.lineIndex = max(0, lineIndex)
        self.utf8Column = max(0, utf8Column)
    }

    public static func < (lhs: LunaTextLocation, rhs: LunaTextLocation) -> Bool {
        if lhs.lineIndex != rhs.lineIndex { return lhs.lineIndex < rhs.lineIndex }
        return lhs.utf8Column < rhs.utf8Column
    }
}

/// Half-open text range between two Luna text locations.
///
/// `anchor` and `focus` preserve selection direction for future shift-click and
/// keyboard extension behavior. `normalized` is used for geometry and
/// accessibility so rectangles are emitted in document order regardless of drag
/// direction.
public struct LunaTextRange: Hashable, Sendable {
    public var anchor: LunaTextLocation
    public var focus: LunaTextLocation

    public init(anchor: LunaTextLocation, focus: LunaTextLocation) {
        self.anchor = anchor
        self.focus = focus
    }

    public var isCollapsed: Bool { anchor == focus }

    public var normalized: LunaTextRange {
        anchor <= focus ? self : LunaTextRange(anchor: focus, focus: anchor)
    }
}

/// Non-editable caret state for static/read-only text surfaces.
public struct LunaStaticTextCaret: Hashable, Sendable {
    public var location: LunaTextLocation

    public init(location: LunaTextLocation) {
        self.location = location
    }
}

/// Static selection state for read-only Phase 3B text geometry.
public struct LunaStaticTextSelection: Hashable, Sendable {
    public var range: LunaTextRange

    public init(range: LunaTextRange) {
        self.range = range
    }

    public var isCollapsed: Bool { range.isCollapsed }
}

/// Visual rectangle for the portion of a selection that touches one visible line.
public struct LunaStaticTextSelectionRect: Hashable, Sendable {
    public var lineIndex: Int
    public var startUTF8Column: Int
    public var endUTF8Column: Int
    public var bounds: LunaRectI

    public init(lineIndex: Int, startUTF8Column: Int, endUTF8Column: Int, bounds: LunaRectI) {
        self.lineIndex = max(0, lineIndex)
        self.startUTF8Column = max(0, startUTF8Column)
        self.endUTF8Column = max(0, endUTF8Column)
        self.bounds = bounds
    }
}

/// App-supplied text highlight range rendered behind text.
///
/// Phase 4B uses this for find-result highlights, but the type is intentionally
/// generic so later features can use the same text-view overlay path for search,
/// diagnostics, symbol references, or custom application annotations.
public struct LunaStaticTextHighlight: Hashable, Sendable {
    public var range: LunaTextRange
    public var color: LunaColor

    public init(range: LunaTextRange, color: LunaColor) {
        self.range = range.normalized
        self.color = color
    }
}

/// Visual rectangle for a generic text highlight.
public struct LunaStaticTextHighlightRect: Hashable, Sendable {
    public var range: LunaTextRange
    public var color: LunaColor
    public var selectionRect: LunaStaticTextSelectionRect

    public init(range: LunaTextRange, color: LunaColor, selectionRect: LunaStaticTextSelectionRect) {
        self.range = range.normalized
        self.color = color
        self.selectionRect = selectionRect
    }
}

/// Text-coordinate hit result from a point inside a static text view.
public struct LunaStaticTextHitResult: Hashable, Sendable {
    public var nodeID: LunaNodeID
    public var location: LunaTextLocation
    public var line: LunaStaticTextLine
    public var rowBounds: LunaRectI
    public var isInsideTextViewport: Bool

    public init(
        nodeID: LunaNodeID,
        location: LunaTextLocation,
        line: LunaStaticTextLine,
        rowBounds: LunaRectI,
        isInsideTextViewport: Bool
    ) {
        self.nodeID = nodeID
        self.location = location
        self.line = line
        self.rowBounds = rowBounds
        self.isInsideTextViewport = isInsideTextViewport
    }
}

/// Visible logical line range for a scrolled static text viewport.
///
/// The range is half-open: `startLineIndex..<endLineIndexExclusive`. It is a
/// concrete struct instead of exposing a raw `Range<Int>` so accessibility and
/// renderer snapshots can carry a stable value across module boundaries.
public struct LunaStaticTextVisibleLineRange: Hashable, Sendable {
    public var startLineIndex: Int
    public var endLineIndexExclusive: Int

    public init(startLineIndex: Int, endLineIndexExclusive: Int) {
        let start = max(0, startLineIndex)
        self.startLineIndex = start
        self.endLineIndexExclusive = max(start, endLineIndexExclusive)
    }

    public var count: Int { max(0, endLineIndexExclusive - startLineIndex) }
    public var isEmpty: Bool { count == 0 }

    public func contains(lineIndex: Int) -> Bool {
        lineIndex >= startLineIndex && lineIndex < endLineIndexExclusive
    }
}

/// Scroll state for the static/read-only text viewport.
///
/// Phase 3C introduced logical-line scrolling first. Soft-wrapped surfaces layer
/// an optional visual-row position while this value remains the stable document-
/// level fallback. C2.2 adds product-neutral wheel/scrollbar requests and lets
/// products retain precise fractional deltas; horizontal scrolling remains later.
public struct LunaStaticTextScrollState: Hashable, Sendable {
    public var scrollTopLine: Int

    public init(scrollTopLine: Int = 0) {
        self.scrollTopLine = max(0, scrollTopLine)
    }

    public static func maximumScrollTopLine(documentLineCount: Int, maxVisibleLineCount: Int) -> Int {
        guard documentLineCount > 0, maxVisibleLineCount > 0 else { return 0 }
        return max(0, documentLineCount - maxVisibleLineCount)
    }

    public func clamped(document: LunaStaticTextDocument, maxVisibleLineCount: Int) -> LunaStaticTextScrollState {
        let maxTop = Self.maximumScrollTopLine(
            documentLineCount: document.lineCount,
            maxVisibleLineCount: maxVisibleLineCount
        )
        return LunaStaticTextScrollState(scrollTopLine: min(max(0, scrollTopLine), maxTop))
    }

    public func scrolled(byLineDelta delta: Int, document: LunaStaticTextDocument, maxVisibleLineCount: Int) -> LunaStaticTextScrollState {
        LunaStaticTextScrollState(scrollTopLine: scrollTopLine + delta)
            .clamped(document: document, maxVisibleLineCount: maxVisibleLineCount)
    }

    public func ensuringVisible(
        _ location: LunaTextLocation,
        document: LunaStaticTextDocument,
        maxVisibleLineCount: Int
    ) -> LunaStaticTextScrollState {
        guard maxVisibleLineCount > 0 else { return clamped(document: document, maxVisibleLineCount: maxVisibleLineCount) }

        let target = document.clampedLocation(location).lineIndex
        let clampedTop = clamped(document: document, maxVisibleLineCount: maxVisibleLineCount).scrollTopLine
        if target < clampedTop {
            return LunaStaticTextScrollState(scrollTopLine: target)
                .clamped(document: document, maxVisibleLineCount: maxVisibleLineCount)
        }
        if target >= clampedTop + maxVisibleLineCount {
            return LunaStaticTextScrollState(scrollTopLine: target - maxVisibleLineCount + 1)
                .clamped(document: document, maxVisibleLineCount: maxVisibleLineCount)
        }
        return LunaStaticTextScrollState(scrollTopLine: clampedTop)
    }
}

/// One logical line in a static Luna text document.
///
/// Offsets are stored in UTF-8 bytes so this shape can later map cleanly onto
/// rope/piece-table editor buffers instead of depending on Swift `String.Index`
/// values for long-term document coordinates.
public struct LunaStaticTextLine: Hashable, Sendable {
    public var index: Int
    public var text: String
    public var utf8Offset: Int
    public var utf8Length: Int

    public init(index: Int, text: String, utf8Offset: Int, utf8Length: Int) {
        self.index = max(0, index)
        self.text = text
        self.utf8Offset = max(0, utf8Offset)
        self.utf8Length = max(0, utf8Length)
    }

    public var lineNumber: Int { index + 1 }
    public var textRange: LunaAccessibilityTextRange {
        LunaAccessibilityTextRange(utf8Offset: utf8Offset, utf8Length: utf8Length)
    }
}

/// Immutable line snapshot consumed by Luna text views.
///
/// Phase 3D adds `LunaEditableTextDocument` for mutation, but rendering, hit
/// testing, selection geometry, and accessibility still consume this stable
/// line snapshot. Real editor storage, syntax scopes, folds, bidi, shaping, and
/// soft wrap belong in later phases.
public struct LunaStaticTextDocument: Hashable, Sendable {
    public var text: String
    public var lines: [LunaStaticTextLine]

    public init(text: String) {
        self.text = text
        self.lines = Self.makeLines(from: text)
    }

    public var lineCount: Int { lines.count }

    public subscript(line index: Int) -> LunaStaticTextLine? {
        guard lines.indices.contains(index) else { return nil }
        return lines[index]
    }

    /// Clamp an arbitrary editor coordinate to this document's valid line and
    /// UTF-8 column range.
    public func clampedLocation(_ location: LunaTextLocation) -> LunaTextLocation {
        let lineIndex = min(max(0, location.lineIndex), max(0, lineCount - 1))
        let lineLength = self[line: lineIndex]?.utf8Length ?? 0
        return LunaTextLocation(lineIndex: lineIndex, utf8Column: min(max(0, location.utf8Column), lineLength))
    }

    /// Convert a line-relative text coordinate to an absolute UTF-8 byte offset.
    public func absoluteUTF8Offset(for location: LunaTextLocation) -> Int {
        let clamped = clampedLocation(location)
        guard let line = self[line: clamped.lineIndex] else { return 0 }
        return line.utf8Offset + clamped.utf8Column
    }

    /// Convert an absolute UTF-8 byte offset into the closest line-relative text
    /// coordinate. Newline bytes belong to the preceding line end.
    public func location(forAbsoluteUTF8Offset offset: Int) -> LunaTextLocation {
        let clampedOffset = min(max(0, offset), text.utf8.count)

        for line in lines {
            let lineStart = line.utf8Offset
            let lineEnd = line.utf8Offset + line.utf8Length
            if clampedOffset <= lineEnd {
                return LunaTextLocation(lineIndex: line.index, utf8Column: max(0, clampedOffset - lineStart))
            }
        }

        let last = lines.last ?? LunaStaticTextLine(index: 0, text: "", utf8Offset: 0, utf8Length: 0)
        return LunaTextLocation(lineIndex: last.index, utf8Column: last.utf8Length)
    }

    /// Normalize and clamp a range against this document.
    public func clampedRange(_ range: LunaTextRange) -> LunaTextRange {
        let normalized = range.normalized
        let start = clampedLocation(normalized.anchor)
        let end = clampedLocation(normalized.focus)
        return LunaTextRange(anchor: start, focus: end).normalized
    }

    public func accessibilityRange(for range: LunaTextRange) -> LunaAccessibilityTextRange {
        let clamped = clampedRange(range)
        let start = absoluteUTF8Offset(for: clamped.anchor)
        let end = absoluteUTF8Offset(for: clamped.focus)
        return LunaAccessibilityTextRange(utf8Offset: start, utf8Length: max(0, end - start))
    }

    public func accessibilityCaretRange(for caret: LunaStaticTextCaret) -> LunaAccessibilityTextRange {
        let offset = absoluteUTF8Offset(for: caret.location)
        return LunaAccessibilityTextRange(utf8Offset: offset, utf8Length: 0)
    }

    private static func makeLines(from text: String) -> [LunaStaticTextLine] {
        guard !text.isEmpty else {
            return [LunaStaticTextLine(index: 0, text: "", utf8Offset: 0, utf8Length: 0)]
        }

        var result: [LunaStaticTextLine] = []
        var start = text.startIndex
        var utf8Offset = 0
        var lineIndex = 0

        func appendLine(_ lineText: String, offset: Int) {
            result.append(
                LunaStaticTextLine(
                    index: lineIndex,
                    text: lineText,
                    utf8Offset: offset,
                    utf8Length: lineText.utf8.count
                )
            )
            lineIndex += 1
        }

        while start < text.endIndex {
            if let newline = text[start...].firstIndex(of: "\n") {
                let lineText = String(text[start..<newline])
                appendLine(lineText, offset: utf8Offset)
                utf8Offset += lineText.utf8.count + 1
                start = text.index(after: newline)
            } else {
                let lineText = String(text[start..<text.endIndex])
                appendLine(lineText, offset: utf8Offset)
                utf8Offset += lineText.utf8.count
                start = text.endIndex
            }
        }

        if text.last == "\n" {
            appendLine("", offset: text.utf8.count)
        }

        return result
    }
}

/// Horizontal overflow policy for Luna text surfaces.
///
/// `none` preserves the original one-logical-line-per-row behavior and
/// ellipsizes text that exceeds the viewport. `soft` creates visual continuation
/// rows whose width is derived from the current text viewport. The backing
/// document coordinates remain logical-line / UTF-8-column based.
public enum LunaStaticTextWrapMode: String, Hashable, Sendable, CaseIterable {
    case none
    case soft
}

/// Simple static-text-view metrics while LunaDisplayList still lacks real glyph
/// commands. These values intentionally match the existing demo 5x7 debug font.
public struct LunaStaticTextViewMetrics: Hashable, Sendable {
    public var contentInsets: LunaInsetsI
    public var gutterWidth: Int
    public var gutterPadding: Int
    public var lineHeight: Int
    public var glyphMetrics: LunaDebugTextMetrics
    public var scrollbarLaneWidth: Int
    public var scrollbarPadding: Int
    public var scrollbarThumbMinHeight: Int

    public init(
        contentInsets: LunaInsetsI = LunaInsetsI(top: 8, right: 10, bottom: 8, left: 0),
        gutterWidth: Int = 52,
        gutterPadding: Int = 6,
        lineHeight: Int = LunaDebugTextMetrics.body.lineHeight,
        glyphMetrics: LunaDebugTextMetrics = .body,
        scrollbarLaneWidth: Int = 8,
        scrollbarPadding: Int = 1,
        scrollbarThumbMinHeight: Int = 14
    ) {
        self.contentInsets = contentInsets
        self.gutterWidth = max(0, gutterWidth)
        self.gutterPadding = max(0, gutterPadding)
        self.lineHeight = max(1, lineHeight)
        self.glyphMetrics = glyphMetrics
        self.scrollbarLaneWidth = max(0, scrollbarLaneWidth)
        self.scrollbarPadding = max(0, scrollbarPadding)
        self.scrollbarThumbMinHeight = max(1, scrollbarThumbMinHeight)
    }

    public static let demo = LunaStaticTextViewMetrics()
}

/// One visible line after a document is laid out into a viewport rectangle.
public struct LunaStaticTextVisibleLine: Hashable, Sendable {
    public var nodeID: LunaNodeID
    public var line: LunaStaticTextLine
    public var lineNumberText: String
    public var lineNumberBounds: LunaRectI
    public var textBounds: LunaRectI
    public var rowBounds: LunaRectI
    public var visualText: LunaBoundedTextLine
    public var rowGeometry: LunaStaticTextRowGeometry
    public var isCurrentLine: Bool

    /// Zero-based visual continuation index within the logical line.
    public var wrappedSegmentIndex: Int

    /// UTF-8 columns in the logical line covered by this visual row.
    public var startUTF8Column: Int
    public var endUTF8Column: Int

    public init(
        nodeID: LunaNodeID,
        line: LunaStaticTextLine,
        lineNumberText: String,
        lineNumberBounds: LunaRectI,
        textBounds: LunaRectI,
        rowBounds: LunaRectI,
        visualText: LunaBoundedTextLine,
        rowGeometry: LunaStaticTextRowGeometry,
        isCurrentLine: Bool,
        wrappedSegmentIndex: Int = 0,
        startUTF8Column: Int = 0,
        endUTF8Column: Int? = nil
    ) {
        self.nodeID = nodeID
        self.line = line
        self.lineNumberText = lineNumberText
        self.lineNumberBounds = lineNumberBounds
        self.textBounds = textBounds
        self.rowBounds = rowBounds
        self.visualText = visualText
        self.rowGeometry = rowGeometry
        self.isCurrentLine = isCurrentLine
        self.wrappedSegmentIndex = max(0, wrappedSegmentIndex)
        self.startUTF8Column = min(max(0, startUTF8Column), line.utf8Length)
        self.endUTF8Column = min(max(self.startUTF8Column, endUTF8Column ?? line.utf8Length), line.utf8Length)
    }

    public var isFirstVisualRowForLine: Bool { wrappedSegmentIndex == 0 }

    public var accessibilityTextRange: LunaAccessibilityTextRange {
        LunaAccessibilityTextRange(
            utf8Offset: line.utf8Offset + startUTF8Column,
            utf8Length: max(0, endUTF8Column - startUTF8Column)
        )
    }
}

/// Complete static text-view layout for one frame.
public struct LunaStaticTextViewLayout: Hashable, Sendable {
    public var bounds: LunaRectI
    public var gutterBounds: LunaRectI
    public var textViewportBounds: LunaRectI
    public var visibleLines: [LunaStaticTextVisibleLine]
    public var firstVisibleLineIndex: Int
    public var maxVisibleLineCount: Int

    /// Visual-row metrics. These equal the logical-line metrics when wrapping is
    /// disabled and expand independently when soft wrapping is enabled.
    public var firstVisibleVisualRowIndex: Int
    public var totalVisualRowCount: Int
    public var maxScrollTopVisualRow: Int

    /// Phase 3C line-range and content metrics for the scrolled viewport.
    public var visibleLineRange: LunaStaticTextVisibleLineRange
    public var contentHeight: Int
    public var maxScrollTopLine: Int
    public var visibleTextRange: LunaAccessibilityTextRange

    /// Scrollbar lane and thumb geometry. The thumb is nil when the complete
    /// document fits inside the viewport; C2.2 interaction helpers consume these
    /// exact bounds for lane paging and captured thumb dragging.
    public var scrollbarLaneBounds: LunaRectI
    public var scrollbarThumbBounds: LunaRectI?

    /// Phase 3B caret geometry. Nil when the caret line is scrolled outside the
    /// current static viewport or no caret was supplied.
    public var caretRect: LunaRectI?

    /// Generic highlighted text geometry rendered beneath selection/caret.
    public var highlightRects: [LunaStaticTextHighlightRect]

    /// Phase 3B static selection geometry. Each rectangle is already clipped to
    /// the visible text viewport for its line.
    public var selectionRects: [LunaStaticTextSelectionRect]

    public init(
        bounds: LunaRectI,
        gutterBounds: LunaRectI,
        textViewportBounds: LunaRectI,
        visibleLines: [LunaStaticTextVisibleLine],
        firstVisibleLineIndex: Int,
        maxVisibleLineCount: Int,
        firstVisibleVisualRowIndex: Int = 0,
        totalVisualRowCount: Int? = nil,
        maxScrollTopVisualRow: Int = 0,
        visibleLineRange: LunaStaticTextVisibleLineRange? = nil,
        contentHeight: Int = 0,
        maxScrollTopLine: Int = 0,
        visibleTextRange: LunaAccessibilityTextRange = LunaAccessibilityTextRange(utf8Offset: 0, utf8Length: 0),
        scrollbarLaneBounds: LunaRectI? = nil,
        scrollbarThumbBounds: LunaRectI? = nil,
        caretRect: LunaRectI? = nil,
        highlightRects: [LunaStaticTextHighlightRect] = [],
        selectionRects: [LunaStaticTextSelectionRect] = []
    ) {
        self.bounds = bounds
        self.gutterBounds = gutterBounds
        self.textViewportBounds = textViewportBounds
        self.visibleLines = visibleLines
        self.firstVisibleLineIndex = max(0, firstVisibleLineIndex)
        self.maxVisibleLineCount = max(0, maxVisibleLineCount)
        self.firstVisibleVisualRowIndex = max(0, firstVisibleVisualRowIndex)
        self.totalVisualRowCount = max(0, totalVisualRowCount ?? visibleLines.count)
        self.maxScrollTopVisualRow = max(0, maxScrollTopVisualRow)
        self.visibleLineRange = visibleLineRange ?? LunaStaticTextVisibleLineRange(
            startLineIndex: max(0, firstVisibleLineIndex),
            endLineIndexExclusive: max(0, firstVisibleLineIndex) + visibleLines.count
        )
        self.contentHeight = max(0, contentHeight)
        self.maxScrollTopLine = max(0, maxScrollTopLine)
        self.visibleTextRange = visibleTextRange
        self.scrollbarLaneBounds = scrollbarLaneBounds ?? LunaRectI(x: bounds.x + max(0, bounds.w), y: bounds.y, w: 0, h: bounds.h)
        self.scrollbarThumbBounds = scrollbarThumbBounds
        self.caretRect = caretRect
        self.highlightRects = highlightRects
        self.selectionRects = selectionRects
    }
}

/// Editor-shaped widget for Phase 3A-3D.
///
/// This widget owns the correct Luna contract now:
/// drawing bounds, hit-test bounds, and accessibility bounds come from the same
/// computed layout; text has stable line node IDs and byte ranges; colors come
/// from `LunaTheme`; and visual line text is clipped/ellipsized inside the text
/// viewport instead of pretending it has infinite width. Phase 3D can mark the
/// same text surface editable for accessibility while mutation remains owned by
/// `LunaEditableTextDocument` / `LunaEditableTextState`.
public struct LunaStaticTextView: LunaWidget, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI
    public var document: LunaStaticTextDocument
    public var scrollTopLine: Int

    /// Optional visual-row scroll position used by soft-wrapped surfaces.
    /// When nil, Luna derives the first visual row from `scrollTopLine`, which
    /// preserves the original logical-line scrolling API for existing callers.
    public var scrollTopVisualRow: Int?

    public var currentLineIndex: Int?
    public var theme: LunaTheme
    public var metrics: LunaStaticTextViewMetrics
    public var wrapMode: LunaStaticTextWrapMode

    /// Optional production text geometry. When absent, Luna derives fixed-cell
    /// insertion positions from `metrics.glyphMetrics.advance`.
    public var geometryProvider: (any LunaStaticTextGeometryProvider)?

    /// Optional revision-stable viewport layout context. When supplied, layout,
    /// scrolling, and caret visibility shape only visible rows plus bounded
    /// overscan instead of traversing the complete document.
    public var virtualizationContext: LunaStaticTextVirtualizationContext?

    public var isFocused: Bool

    /// Whether the backing text model currently accepts edits.
    public var isEditable: Bool

    /// Optional caret state introduced in Phase 3B.
    public var caret: LunaStaticTextCaret?

    /// Optional static selection state introduced in Phase 3B.
    public var selection: LunaStaticTextSelection?

    /// Generic app-supplied highlighted ranges introduced in Phase 4B.
    public var highlights: [LunaStaticTextHighlight]

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        document: LunaStaticTextDocument,
        scrollTopLine: Int = 0,
        scrollTopVisualRow: Int? = nil,
        currentLineIndex: Int? = nil,
        theme: LunaTheme = .lunaDefaultDark,
        metrics: LunaStaticTextViewMetrics = .demo,
        wrapMode: LunaStaticTextWrapMode = .none,
        geometryProvider: (any LunaStaticTextGeometryProvider)? = nil,
        isFocused: Bool = false,
        isEditable: Bool = false,
        caret: LunaStaticTextCaret? = nil,
        selection: LunaStaticTextSelection? = nil,
        highlights: [LunaStaticTextHighlight] = [],
        virtualizationContext: LunaStaticTextVirtualizationContext? = nil
    ) {
        self.id = id
        self.bounds = bounds
        self.document = document
        self.scrollTopLine = max(0, scrollTopLine)
        self.scrollTopVisualRow = scrollTopVisualRow.map { max(0, $0) }
        self.currentLineIndex = currentLineIndex
        self.theme = theme
        self.metrics = metrics
        self.wrapMode = wrapMode
        self.geometryProvider = geometryProvider
        self.virtualizationContext = virtualizationContext
        self.isFocused = isFocused
        self.isEditable = isEditable
        self.caret = caret.map { LunaStaticTextCaret(location: document.clampedLocation($0.location)) }
        if let selection, !selection.isCollapsed {
            self.selection = LunaStaticTextSelection(range: document.clampedRange(selection.range))
        } else {
            self.selection = nil
        }
        self.highlights = highlights.map { LunaStaticTextHighlight(range: document.clampedRange($0.range), color: $0.color) }
    }

    public var lineNodeIDPrefix: LunaNodeID { id.child("line") }

    public func lineNodeID(for lineIndex: Int) -> LunaNodeID {
        lineNodeIDPrefix.child(lineIndex + 1)
    }

    public func lineNodeID(for lineIndex: Int, wrappedSegmentIndex: Int) -> LunaNodeID {
        let lineID = lineNodeID(for: lineIndex)
        return wrappedSegmentIndex == 0 ? lineID : lineID.child("wrap-\(wrappedSegmentIndex + 1)")
    }

    private struct VisualSegment: Hashable, Sendable {
        var line: LunaStaticTextLine
        var wrappedSegmentIndex: Int
        var text: String
        var geometry: LunaStaticTextRowGeometry
        var startUTF8Column: Int
        var endUTF8Column: Int
    }

    public func layout() -> LunaStaticTextViewLayout {
        if let virtualizationContext {
            return virtualizedLayout(using: virtualizationContext)
        }
        guard !bounds.isEmpty else {
            return LunaStaticTextViewLayout(
                bounds: bounds,
                gutterBounds: LunaRectI(x: bounds.x, y: bounds.y, w: 0, h: 0),
                textViewportBounds: LunaRectI(x: bounds.x, y: bounds.y, w: 0, h: 0),
                visibleLines: [],
                firstVisibleLineIndex: 0,
                maxVisibleLineCount: 0,
                firstVisibleVisualRowIndex: 0,
                totalVisualRowCount: 0,
                maxScrollTopVisualRow: 0,
                visibleLineRange: LunaStaticTextVisibleLineRange(startLineIndex: 0, endLineIndexExclusive: 0),
                contentHeight: 0,
                maxScrollTopLine: 0,
                visibleTextRange: LunaAccessibilityTextRange(utf8Offset: 0, utf8Length: 0),
                scrollbarLaneBounds: LunaRectI(x: bounds.x, y: bounds.y, w: 0, h: 0)
            )
        }

        let topInset = max(0, metrics.contentInsets.top)
        let rightInset = max(0, metrics.contentInsets.right)
        let bottomInset = max(0, metrics.contentInsets.bottom)
        let gutterW = min(bounds.w, max(0, metrics.gutterWidth))
        let bodyY = bounds.y + topInset
        let bodyH = max(0, bounds.h - topInset - bottomInset)
        let lineHeight = max(1, metrics.lineHeight)
        let maxVisible = max(0, bodyH / lineHeight)
        let baseTextWidth = max(0, bounds.w - gutterW - metrics.gutterPadding - rightInset)

        var segments = visualSegments(textViewportWidth: baseTextWidth)
        var laneW = maxVisible > 0 && segments.count > maxVisible
            ? min(bounds.w, metrics.scrollbarLaneWidth)
            : 0

        // The scrollbar consumes horizontal space and can therefore change the
        // soft-wrap breakpoints. Recompute exactly once with the final width.
        if laneW > 0 {
            segments = visualSegments(textViewportWidth: max(0, baseTextWidth - laneW))
            if segments.count <= maxVisible {
                laneW = 0
                segments = visualSegments(textViewportWidth: baseTextWidth)
            }
        }

        let totalVisualRows = segments.count
        let contentHeight = topInset + bottomInset + totalVisualRows * lineHeight
        let maxScrollTopVisualRow = max(0, totalVisualRows - maxVisible)

        let requestedLine = min(max(0, scrollTopLine), max(0, document.lineCount - 1))
        let visualRowForRequestedLine = segments.firstIndex { $0.line.index == requestedLine } ?? 0
        let requestedVisualRow = wrapMode == .soft
            ? (scrollTopVisualRow ?? visualRowForRequestedLine)
            : visualRowForRequestedLine
        let firstVisibleVisualRow = min(max(0, requestedVisualRow), maxScrollTopVisualRow)
        let visibleSegments = maxVisible > 0
            ? Array(segments.dropFirst(firstVisibleVisualRow).prefix(maxVisible))
            : []
        let firstVisibleLine = visibleSegments.first?.line.index ?? 0
        let maxScrollTopLine = segments.indices.contains(maxScrollTopVisualRow)
            ? segments[maxScrollTopVisualRow].line.index
            : 0

        let scrollbarLaneBounds = LunaRectI(
            x: bounds.x + bounds.w - laneW,
            y: bounds.y,
            w: laneW,
            h: bounds.h
        )
        let scrollbarThumbBounds = Self.scrollbarThumbBounds(
            lane: scrollbarLaneBounds,
            documentLineCount: totalVisualRows,
            maxVisibleLineCount: maxVisible,
            maxScrollTopLine: maxScrollTopVisualRow,
            scrollTopLine: firstVisibleVisualRow,
            metrics: metrics
        )

        let gutterBounds = LunaRectI(
            x: bounds.x,
            y: bounds.y,
            w: gutterW,
            h: bounds.h
        )
        let textViewportBounds = LunaRectI(
            x: bounds.x + gutterW + metrics.gutterPadding,
            y: bodyY,
            w: max(0, bounds.w - gutterW - metrics.gutterPadding - rightInset - laneW),
            h: bodyH
        )

        let numberWidth = max(0, gutterW - metrics.gutterPadding * 2)
        var visible: [LunaStaticTextVisibleLine] = []
        visible.reserveCapacity(visibleSegments.count)
        let effectiveCurrentLineIndex = caret?.location.lineIndex ?? currentLineIndex

        for (visualIndex, segment) in visibleSegments.enumerated() {
            let rowY = bodyY + visualIndex * lineHeight
            let rowBounds = LunaRectI(x: bounds.x, y: rowY, w: max(0, bounds.w - laneW), h: lineHeight)
            let lineNumberBounds = LunaRectI(
                x: bounds.x + metrics.gutterPadding,
                y: rowY,
                w: numberWidth,
                h: lineHeight
            )
            let textBounds = LunaRectI(
                x: textViewportBounds.x,
                y: rowY,
                w: textViewportBounds.w,
                h: lineHeight
            )

            let visualText: LunaBoundedTextLine
            switch wrapMode {
            case .none:
                visualText = LunaBoundedTextLayout.layout(
                    segment.geometry.renderedText,
                    in: textBounds,
                    metrics: metrics.glyphMetrics,
                    overflow: .ellipsizeTail
                ).firstLine ?? LunaBoundedTextLine(
                    text: "",
                    fullText: segment.line.text,
                    bounds: textBounds,
                    isClipped: !segment.text.isEmpty
                )
            case .soft:
                visualText = LunaBoundedTextLine(
                    text: segment.geometry.renderedText,
                    fullText: segment.line.text,
                    bounds: textBounds,
                    isClipped: false
                )
            }

            visible.append(
                LunaStaticTextVisibleLine(
                    nodeID: lineNodeID(
                        for: segment.line.index,
                        wrappedSegmentIndex: segment.wrappedSegmentIndex
                    ),
                    line: segment.line,
                    lineNumberText: segment.wrappedSegmentIndex == 0 ? String(segment.line.lineNumber) : "",
                    lineNumberBounds: lineNumberBounds,
                    textBounds: textBounds,
                    rowBounds: rowBounds,
                    visualText: visualText,
                    rowGeometry: segment.geometry,
                    isCurrentLine: effectiveCurrentLineIndex == segment.line.index,
                    wrappedSegmentIndex: segment.wrappedSegmentIndex,
                    startUTF8Column: segment.startUTF8Column,
                    endUTF8Column: segment.endUTF8Column
                )
            )
        }

        let visibleLineRange: LunaStaticTextVisibleLineRange
        if let first = visible.first, let last = visible.last {
            visibleLineRange = LunaStaticTextVisibleLineRange(
                startLineIndex: first.line.index,
                endLineIndexExclusive: last.line.index + 1
            )
        } else {
            visibleLineRange = LunaStaticTextVisibleLineRange(startLineIndex: 0, endLineIndexExclusive: 0)
        }

        let visibleTextRange = Self.visibleTextRange(for: visible, document: document)
        let computedHighlightRects = self.highlightRects(visibleLines: visible)
        let computedSelectionRects = self.selection.map { self.selectionRects(for: $0, visibleLines: visible) } ?? []
        let computedCaretRect = self.caret.flatMap { self.caretRect(for: $0, visibleLines: visible) }

        return LunaStaticTextViewLayout(
            bounds: bounds,
            gutterBounds: gutterBounds,
            textViewportBounds: textViewportBounds,
            visibleLines: visible,
            firstVisibleLineIndex: firstVisibleLine,
            maxVisibleLineCount: maxVisible,
            firstVisibleVisualRowIndex: firstVisibleVisualRow,
            totalVisualRowCount: totalVisualRows,
            maxScrollTopVisualRow: maxScrollTopVisualRow,
            visibleLineRange: visibleLineRange,
            contentHeight: contentHeight,
            maxScrollTopLine: maxScrollTopLine,
            visibleTextRange: visibleTextRange,
            scrollbarLaneBounds: scrollbarLaneBounds,
            scrollbarThumbBounds: scrollbarThumbBounds,
            caretRect: computedCaretRect,
            highlightRects: computedHighlightRects,
            selectionRects: computedSelectionRects
        )
    }

    private func visualSegments(textViewportWidth: Int) -> [VisualSegment] {
        document.lines.flatMap { line -> [VisualSegment] in
            switch wrapMode {
            case .none:
                let geometry = rowGeometry(
                    for: line.text,
                    utf8Range: 0..<line.utf8Length
                )
                return [VisualSegment(
                    line: line,
                    wrappedSegmentIndex: 0,
                    text: line.text,
                    geometry: geometry,
                    startUTF8Column: 0,
                    endUTF8Column: line.utf8Length
                )]
            case .soft:
                return softWrappedSegments(for: line, maximumWidth: max(0, textViewportWidth))
            }
        }
    }

    private func rowGeometry(
        for completeLineText: String,
        utf8Range: Range<Int>
    ) -> LunaStaticTextRowGeometry {
        let request = LunaStaticTextGeometryRequest(
            completeLineText: completeLineText,
            utf8Range: utf8Range
        )
        return geometryProvider?.geometry(for: request)
            ?? LunaStaticTextRowGeometry.fixedAdvance(
                sourceText: request.sourceText,
                advance: metrics.glyphMetrics.advance
            )
    }

    private func softWrappedSegments(
        for line: LunaStaticTextLine,
        maximumWidth: Int
    ) -> [VisualSegment] {
        guard !line.text.isEmpty else {
            let geometry = rowGeometry(for: "", utf8Range: 0..<0)
            return [VisualSegment(
                line: line,
                wrappedSegmentIndex: 0,
                text: "",
                geometry: geometry,
                startUTF8Column: 0,
                endUTF8Column: 0
            )]
        }

        let width = max(1, maximumWidth)
        var result: [VisualSegment] = []
        var startColumn = 0
        var segmentIndex = 0

        while startColumn < line.utf8Length {
            let remainingText = Self.substring(
                line.text,
                utf8Range: startColumn..<line.utf8Length
            )
            let remainingGeometry = rowGeometry(
                for: line.text,
                utf8Range: startColumn..<line.utf8Length
            )
            var localEnd = remainingGeometry.farthestUTF8Offset(fittingWidth: width)

            if localEnd <= 0 {
                localEnd = Self.firstGraphemeEndUTF8Offset(in: remainingText)
            }
            localEnd = min(max(1, localEnd), remainingText.utf8.count)

            if localEnd < remainingText.utf8.count,
               let whitespaceEnd = Self.preferredWhitespaceBreak(
                    in: remainingText,
                    fittingUTF8Length: localEnd
               ) {
                localEnd = whitespaceEnd
            }

            let segmentText = Self.substring(remainingText, utf8Range: 0..<localEnd)
            let endColumn = min(line.utf8Length, startColumn + localEnd)
            let geometry = localEnd == remainingText.utf8.count
                ? remainingGeometry
                : rowGeometry(
                    for: line.text,
                    utf8Range: startColumn..<endColumn
                )
            result.append(
                VisualSegment(
                    line: line,
                    wrappedSegmentIndex: segmentIndex,
                    text: segmentText,
                    geometry: geometry,
                    startUTF8Column: startColumn,
                    endUTF8Column: endColumn
                )
            )

            startColumn = endColumn
            segmentIndex += 1
        }

        return result
    }

    private static func firstGraphemeEndUTF8Offset(in text: String) -> Int {
        guard let character = text.first else { return 0 }
        return String(character).utf8.count
    }

    private static func preferredWhitespaceBreak(
        in text: String,
        fittingUTF8Length: Int
    ) -> Int? {
        var utf8Offset = 0
        var candidate: Int?
        for character in text {
            let next = utf8Offset + String(character).utf8.count
            guard next <= fittingUTF8Length else { break }
            if character == " " || character == "\t" {
                candidate = next
            }
            utf8Offset = next
        }
        guard let candidate, candidate > 0 else { return nil }
        return candidate
    }

    private static func substring(_ text: String, utf8Range: Range<Int>) -> String {
        let lower = min(max(0, utf8Range.lowerBound), text.utf8.count)
        let upper = min(max(lower, utf8Range.upperBound), text.utf8.count)
        let utf8Start = text.utf8.index(text.utf8.startIndex, offsetBy: lower)
        let utf8End = text.utf8.index(text.utf8.startIndex, offsetBy: upper)
        guard let start = String.Index(utf8Start, within: text),
              let end = String.Index(utf8End, within: text)
        else { return "" }
        return String(text[start..<end])
    }

    private static func scrollbarThumbBounds(
        lane: LunaRectI,
        documentLineCount: Int,
        maxVisibleLineCount: Int,
        maxScrollTopLine: Int,
        scrollTopLine: Int,
        metrics: LunaStaticTextViewMetrics
    ) -> LunaRectI? {
        guard !lane.isEmpty, documentLineCount > 0, maxVisibleLineCount > 0, documentLineCount > maxVisibleLineCount else {
            return nil
        }

        let pad = min(max(0, metrics.scrollbarPadding), max(0, lane.w / 2))
        let trackH = max(0, lane.h - pad * 2)
        guard trackH > 0 else { return nil }

        let proportional = (trackH * maxVisibleLineCount) / max(1, documentLineCount)
        let thumbH = min(trackH, max(metrics.scrollbarThumbMinHeight, proportional))
        let travel = max(0, trackH - thumbH)
        let yOffset: Int
        if maxScrollTopLine <= 0 {
            yOffset = 0
        } else {
            yOffset = Int((Double(travel) * Double(min(max(0, scrollTopLine), maxScrollTopLine)) / Double(maxScrollTopLine)).rounded(.toNearestOrAwayFromZero))
        }

        return LunaRectI(
            x: lane.x + pad,
            y: lane.y + pad + yOffset,
            w: max(1, lane.w - pad * 2),
            h: thumbH
        )
    }

    private static func visibleTextRange(
        for visibleLines: [LunaStaticTextVisibleLine],
        document: LunaStaticTextDocument
    ) -> LunaAccessibilityTextRange {
        guard let first = visibleLines.first, let last = visibleLines.last else {
            return LunaAccessibilityTextRange(utf8Offset: 0, utf8Length: 0)
        }

        let start = first.line.utf8Offset + first.startUTF8Column
        let end = last.line.utf8Offset + last.endUTF8Column
        return LunaAccessibilityTextRange(utf8Offset: start, utf8Length: max(0, end - start))
    }

    /// Return a copy of the view scrolled by visual rows when soft wrapping is
    /// enabled, or by logical lines for the original non-wrapped mode.
    public func scrolled(byLineDelta delta: Int) -> LunaStaticTextView {
        if let virtualizationContext {
            return virtualizedScrolled(
                byVisualRowDelta: delta,
                context: virtualizationContext
            )
        }
        let current = layout()
        var copy = self
        if wrapMode == .soft {
            let nextVisualRow = min(
                max(0, current.firstVisibleVisualRowIndex + delta),
                current.maxScrollTopVisualRow
            )
            copy.scrollTopVisualRow = nextVisualRow
            let segments = visualSegments(textViewportWidth: current.textViewportBounds.w)
            if segments.indices.contains(nextVisualRow) {
                copy.scrollTopLine = segments[nextVisualRow].line.index
            }
        } else {
            copy.scrollTopLine = min(max(0, scrollTopLine + delta), current.maxScrollTopLine)
            copy.scrollTopVisualRow = nil
        }
        return copy
    }

    /// Return a copy of the view with the supplied logical location visible.
    /// In soft-wrap mode this includes continuation rows within one long line.
    public func ensuringVisible(_ location: LunaTextLocation) -> LunaStaticTextView {
        if let virtualizationContext {
            return virtualizedEnsuringVisible(
                location,
                context: virtualizationContext
            )
        }
        let current = layout()
        let clampedLocation = document.clampedLocation(location)
        var copy = self

        if wrapMode == .soft {
            let segments = visualSegments(textViewportWidth: current.textViewportBounds.w)
            let targetVisualRow = Self.visualRowIndex(for: clampedLocation, in: segments)
            let currentTop = current.firstVisibleVisualRowIndex
            let currentBottom = currentTop + current.maxVisibleLineCount
            let nextTop: Int
            if targetVisualRow < currentTop {
                nextTop = targetVisualRow
            } else if targetVisualRow >= currentBottom {
                nextTop = targetVisualRow - max(0, current.maxVisibleLineCount - 1)
            } else {
                nextTop = currentTop
            }
            copy.scrollTopVisualRow = min(max(0, nextTop), current.maxScrollTopVisualRow)
            copy.scrollTopLine = clampedLocation.lineIndex
            return copy
        }

        let targetLine = clampedLocation.lineIndex
        if targetLine < current.visibleLineRange.startLineIndex {
            copy.scrollTopLine = targetLine
        } else if targetLine >= current.visibleLineRange.endLineIndexExclusive {
            copy.scrollTopLine = min(targetLine, current.maxScrollTopLine)
        }
        copy.scrollTopVisualRow = nil
        return copy
    }

    private static func visualRowIndex(
        for location: LunaTextLocation,
        in segments: [VisualSegment]
    ) -> Int {
        let lineSegments = segments.indices.filter { segments[$0].line.index == location.lineIndex }
        guard let first = lineSegments.first else { return 0 }
        if location.utf8Column >= segments[first].line.utf8Length {
            return lineSegments.last ?? first
        }
        return lineSegments.first {
            location.utf8Column >= segments[$0].startUTF8Column &&
                location.utf8Column < segments[$0].endUTF8Column
        } ?? (lineSegments.last ?? first)
    }

    /// Calculate the caret insertion rectangle for a visible line.
    public func caretRect(for caret: LunaStaticTextCaret, visibleLines: [LunaStaticTextVisibleLine]? = nil) -> LunaRectI? {
        let location = document.clampedLocation(caret.location)
        let lines = visibleLines ?? layout().visibleLines
        let candidates = lines.filter { $0.line.index == location.lineIndex }
        guard !candidates.isEmpty else { return nil }
        let visible: LunaStaticTextVisibleLine
        if location.utf8Column == candidates[0].line.utf8Length {
            visible = candidates.last!
        } else {
            visible = candidates.first {
                location.utf8Column >= $0.startUTF8Column && location.utf8Column < $0.endUTF8Column
            } ?? candidates.last!
        }
        let x = clampedTextX(forUTF8Column: location.utf8Column, in: visible)
        return LunaRectI(x: x, y: visible.rowBounds.y, w: max(1, metrics.glyphMetrics.scale), h: visible.rowBounds.h)
    }

    /// Calculate clipped visible rectangles for all generic app-supplied highlights.
    public func highlightRects(visibleLines: [LunaStaticTextVisibleLine]? = nil) -> [LunaStaticTextHighlightRect] {
        let lines = visibleLines ?? layout().visibleLines
        var rects: [LunaStaticTextHighlightRect] = []
        for highlight in highlights {
            let selection = LunaStaticTextSelection(range: document.clampedRange(highlight.range))
            for rect in selectionRects(for: selection, visibleLines: lines) {
                rects.append(LunaStaticTextHighlightRect(range: highlight.range, color: highlight.color, selectionRect: rect))
            }
        }
        return rects
    }

    /// Calculate clipped visible selection rectangles for the supplied selection.
    public func selectionRects(for selection: LunaStaticTextSelection, visibleLines: [LunaStaticTextVisibleLine]? = nil) -> [LunaStaticTextSelectionRect] {
        let range = document.clampedRange(selection.range)
        guard !range.isCollapsed else { return [] }

        let lines = visibleLines ?? layout().visibleLines
        var rects: [LunaStaticTextSelectionRect] = []

        for visible in lines {
            let lineIndex = visible.line.index
            guard lineIndex >= range.anchor.lineIndex, lineIndex <= range.focus.lineIndex else { continue }

            let logicalStart = lineIndex == range.anchor.lineIndex ? range.anchor.utf8Column : 0
            let logicalEnd = lineIndex == range.focus.lineIndex ? range.focus.utf8Column : visible.line.utf8Length
            let startColumn = max(logicalStart, visible.startUTF8Column)
            let endColumn = min(logicalEnd, visible.endUTF8Column)
            guard endColumn > startColumn else { continue }

            let x0 = clampedTextX(forUTF8Column: startColumn, in: visible)
            let x1 = clampedTextX(forUTF8Column: endColumn, in: visible)
            let clippedX0 = max(visible.textBounds.x, min(visible.textBounds.x + visible.textBounds.w, x0))
            let clippedX1 = max(visible.textBounds.x, min(visible.textBounds.x + visible.textBounds.w, x1))
            guard clippedX1 > clippedX0 else { continue }

            rects.append(
                LunaStaticTextSelectionRect(
                    lineIndex: lineIndex,
                    startUTF8Column: startColumn,
                    endUTF8Column: endColumn,
                    bounds: LunaRectI(x: clippedX0, y: visible.rowBounds.y, w: clippedX1 - clippedX0, h: visible.rowBounds.h)
                )
            )
        }

        return rects
    }

    /// Map a point inside the text-view bounds to a line-relative UTF-8 column.
    ///
    /// This is not editing yet. It is the geometric proof that pointer positions
    /// can become stable text coordinates without mutating the document.
    public func textHitTest(_ point: LunaPointI) -> LunaStaticTextHitResult? {
        guard bounds.contains(x: point.x, y: point.y) else { return nil }
        let layout = layout()
        guard let visible = layout.visibleLines.first(where: { $0.rowBounds.contains(x: point.x, y: point.y) }) else {
            return nil
        }

        let column: Int
        if point.x <= visible.textBounds.x {
            column = visible.startUTF8Column
        } else {
            let relativeX = max(0, point.x - visible.textBounds.x)
            let localColumn = visible.rowGeometry.closestUTF8Offset(toX: relativeX)
            column = min(
                visible.endUTF8Column,
                visible.startUTF8Column + localColumn
            )
        }

        let location = LunaTextLocation(lineIndex: visible.line.index, utf8Column: column)
        return LunaStaticTextHitResult(
            nodeID: visible.nodeID,
            location: location,
            line: visible.line,
            rowBounds: visible.rowBounds,
            isInsideTextViewport: visible.textBounds.contains(x: point.x, y: point.y)
        )
    }

    private func clampedTextX(forUTF8Column column: Int, in visible: LunaStaticTextVisibleLine) -> Int {
        let localColumn = min(
            max(0, column - visible.startUTF8Column),
            visible.rowGeometry.sourceText.utf8.count
        )
        let unclipped = visible.textBounds.x + visible.rowGeometry.x(forUTF8Offset: localColumn)
        return max(
            visible.textBounds.x,
            min(visible.textBounds.x + visible.textBounds.w, unclipped)
        )
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        guard !bounds.isEmpty else { return }

        let layout = layout()
        let style = LunaEditorVisualStyle(theme: theme)
        displayList.append(.rect(bounds, style.background))

        if !layout.gutterBounds.isEmpty {
            displayList.append(.rect(layout.gutterBounds, style.gutterBackground))
        }

        if !layout.scrollbarLaneBounds.isEmpty {
            displayList.append(.rect(layout.scrollbarLaneBounds, style.scrollbarTrack))
        }

        for line in layout.visibleLines where line.isCurrentLine {
            displayList.append(.rect(line.rowBounds, style.currentLineBackground))
        }

        for highlightRect in layout.highlightRects {
            displayList.append(.rect(highlightRect.selectionRect.bounds, highlightRect.color.asRenderColor))
        }

        for selectionRect in layout.selectionRects {
            displayList.append(.rect(selectionRect.bounds, style.selectionBackground))
        }

        if let thumb = layout.scrollbarThumbBounds {
            displayList.append(.rect(thumb, style.scrollbarThumb))
        }

        if let caretRect = layout.caretRect {
            displayList.append(.rect(caretRect, style.caret))
        }

        if layout.gutterBounds.w > 0 {
            let separator = LunaRectI(
                x: layout.gutterBounds.x + layout.gutterBounds.w - 1,
                y: layout.gutterBounds.y,
                w: 1,
                h: layout.gutterBounds.h
            )
            displayList.append(.rect(separator, theme.ui.chrome.separator.asRenderColor))
        }

        if isFocused {
            let focusColor = theme.ui.textField.focusedBorder.asRenderColor
            displayList.append(.rect(LunaRectI(x: bounds.x, y: bounds.y, w: bounds.w, h: 1), focusColor))
            displayList.append(.rect(LunaRectI(x: bounds.x, y: bounds.y + bounds.h - 1, w: bounds.w, h: 1), focusColor))
            displayList.append(.rect(LunaRectI(x: bounds.x, y: bounds.y, w: 1, h: bounds.h), focusColor))
            displayList.append(.rect(LunaRectI(x: bounds.x + bounds.w - 1, y: bounds.y, w: 1, h: bounds.h), focusColor))
        }
    }

    public func buildAccessibilityNode() -> LunaAccessibilityNode {
        let layout = layout()
        return LunaAccessibilityNode(
            id: id,
            role: .textArea,
            label: "Text view",
            value: document.text,
            bounds: bounds.asAccessibilityRect,
            isEnabled: true,
            isFocused: isFocused,
            isEditable: isEditable,
            children: layout.visibleLines.map(\.nodeID),
            actions: [.focus],
            textRange: LunaAccessibilityTextRange(utf8Offset: 0, utf8Length: document.text.utf8.count),
            caretTextRange: caret.map { document.accessibilityCaretRange(for: $0) },
            selectedTextRange: selection.map { document.accessibilityRange(for: $0.range) },
            visibleTextRange: layout.visibleTextRange
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        let focusedLineIndex = caret?.location.lineIndex
        return layout().visibleLines.map { visible in
            LunaAccessibilityNode(
                id: visible.nodeID,
                role: .textRun,
                label: visible.visualText.text,
                value: visible.lineNumberText,
                bounds: visible.rowBounds.asAccessibilityRect,
                isEnabled: true,
                isFocused: focusedLineIndex == visible.line.index,
                children: [],
                actions: [],
                textRange: visible.accessibilityTextRange
            )
        }
    }

    public func hitTest(_ point: LunaPointI) -> LunaNodeID? {
        guard bounds.contains(x: point.x, y: point.y) else { return nil }
        let layout = layout()
        for line in layout.visibleLines where line.rowBounds.contains(x: point.x, y: point.y) {
            return line.nodeID
        }
        return id
    }
}
