// LunaStaticTextView.swift
//
// Phase 3A: static, accessible text-view primitive.
//
// This is the first editor-shaped Luna widget. It is deliberately read-only:
// Phase 3A proves text-surface layout, theme-driven paint geometry, line/gutter
// semantics, hit testing, and accessibility ranges before editable input,
// caret motion, selection mutation, real glyph runs, or scrollbars are added.

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

/// Read-only document model for Phase 3A.
///
/// The model intentionally stores only plain lines and stable byte ranges. Real
/// editor storage, mutation, syntax scopes, folds, bidi, shaping, and soft wrap
/// belong in later phases; this gives Luna a correct semantic text surface now.
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

/// Simple static-text-view metrics while LunaDisplayList still lacks real glyph
/// commands. These values intentionally match the existing demo 5x7 debug font.
public struct LunaStaticTextViewMetrics: Hashable, Sendable {
    public var contentInsets: LunaInsetsI
    public var gutterWidth: Int
    public var gutterPadding: Int
    public var lineHeight: Int
    public var glyphMetrics: LunaDebugTextMetrics

    public init(
        contentInsets: LunaInsetsI = LunaInsetsI(top: 8, right: 10, bottom: 8, left: 0),
        gutterWidth: Int = 52,
        gutterPadding: Int = 6,
        lineHeight: Int = LunaDebugTextMetrics.body.lineHeight,
        glyphMetrics: LunaDebugTextMetrics = .body
    ) {
        self.contentInsets = contentInsets
        self.gutterWidth = max(0, gutterWidth)
        self.gutterPadding = max(0, gutterPadding)
        self.lineHeight = max(1, lineHeight)
        self.glyphMetrics = glyphMetrics
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
    public var isCurrentLine: Bool

    public init(
        nodeID: LunaNodeID,
        line: LunaStaticTextLine,
        lineNumberText: String,
        lineNumberBounds: LunaRectI,
        textBounds: LunaRectI,
        rowBounds: LunaRectI,
        visualText: LunaBoundedTextLine,
        isCurrentLine: Bool
    ) {
        self.nodeID = nodeID
        self.line = line
        self.lineNumberText = lineNumberText
        self.lineNumberBounds = lineNumberBounds
        self.textBounds = textBounds
        self.rowBounds = rowBounds
        self.visualText = visualText
        self.isCurrentLine = isCurrentLine
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

    /// Phase 3B caret geometry. Nil when the caret line is scrolled outside the
    /// current static viewport or no caret was supplied.
    public var caretRect: LunaRectI?

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
        caretRect: LunaRectI? = nil,
        selectionRects: [LunaStaticTextSelectionRect] = []
    ) {
        self.bounds = bounds
        self.gutterBounds = gutterBounds
        self.textViewportBounds = textViewportBounds
        self.visibleLines = visibleLines
        self.firstVisibleLineIndex = max(0, firstVisibleLineIndex)
        self.maxVisibleLineCount = max(0, maxVisibleLineCount)
        self.caretRect = caretRect
        self.selectionRects = selectionRects
    }
}

/// Read-only editor-shaped widget for Phase 3A.
///
/// This widget owns the correct Luna contract now:
/// drawing bounds, hit-test bounds, and accessibility bounds come from the same
/// computed layout; text has stable line node IDs and byte ranges; colors come
/// from `LunaTheme`; and visual line text is clipped/ellipsized inside the text
/// viewport instead of pretending it has infinite width.
public struct LunaStaticTextView: LunaWidget, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI
    public var document: LunaStaticTextDocument
    public var scrollTopLine: Int
    public var currentLineIndex: Int?
    public var theme: LunaTheme
    public var metrics: LunaStaticTextViewMetrics
    public var isFocused: Bool

    /// Optional non-editable caret state introduced in Phase 3B.
    public var caret: LunaStaticTextCaret?

    /// Optional static selection state introduced in Phase 3B.
    public var selection: LunaStaticTextSelection?

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        document: LunaStaticTextDocument,
        scrollTopLine: Int = 0,
        currentLineIndex: Int? = nil,
        theme: LunaTheme = .lunaDefaultDark,
        metrics: LunaStaticTextViewMetrics = .demo,
        isFocused: Bool = false,
        caret: LunaStaticTextCaret? = nil,
        selection: LunaStaticTextSelection? = nil
    ) {
        self.id = id
        self.bounds = bounds
        self.document = document
        self.scrollTopLine = max(0, scrollTopLine)
        self.currentLineIndex = currentLineIndex
        self.theme = theme
        self.metrics = metrics
        self.isFocused = isFocused
        self.caret = caret.map { LunaStaticTextCaret(location: document.clampedLocation($0.location)) }
        if let selection, !selection.isCollapsed {
            self.selection = LunaStaticTextSelection(range: document.clampedRange(selection.range))
        } else {
            self.selection = nil
        }
    }

    public var lineNodeIDPrefix: LunaNodeID { id.child("line") }

    public func lineNodeID(for lineIndex: Int) -> LunaNodeID {
        lineNodeIDPrefix.child(lineIndex + 1)
    }

    public func layout() -> LunaStaticTextViewLayout {
        guard !bounds.isEmpty else {
            return LunaStaticTextViewLayout(
                bounds: bounds,
                gutterBounds: LunaRectI(x: bounds.x, y: bounds.y, w: 0, h: 0),
                textViewportBounds: LunaRectI(x: bounds.x, y: bounds.y, w: 0, h: 0),
                visibleLines: [],
                firstVisibleLineIndex: 0,
                maxVisibleLineCount: 0
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

        let gutterBounds = LunaRectI(
            x: bounds.x,
            y: bounds.y,
            w: gutterW,
            h: bounds.h
        )
        let textViewportBounds = LunaRectI(
            x: bounds.x + gutterW + metrics.gutterPadding,
            y: bodyY,
            w: max(0, bounds.w - gutterW - metrics.gutterPadding - rightInset),
            h: bodyH
        )

        let firstLine = min(max(0, scrollTopLine), max(0, document.lineCount - 1))
        let availableLines = max(0, document.lineCount - firstLine)
        let count = min(maxVisible, availableLines)
        let numberWidth = max(0, gutterW - metrics.gutterPadding * 2)
        var visible: [LunaStaticTextVisibleLine] = []
        visible.reserveCapacity(count)
        let effectiveCurrentLineIndex = caret?.location.lineIndex ?? currentLineIndex

        for visualIndex in 0..<count {
            let lineIndex = firstLine + visualIndex
            guard let line = document[line: lineIndex] else { continue }
            let rowY = bodyY + visualIndex * lineHeight
            let rowBounds = LunaRectI(x: bounds.x, y: rowY, w: bounds.w, h: lineHeight)
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
            let visualText = LunaBoundedTextLayout.layout(
                line.text,
                in: textBounds,
                metrics: metrics.glyphMetrics,
                overflow: .ellipsizeTail
            ).firstLine ?? LunaBoundedTextLine(text: "", fullText: line.text, bounds: textBounds, isClipped: !line.text.isEmpty)

            visible.append(
                LunaStaticTextVisibleLine(
                    nodeID: lineNodeID(for: lineIndex),
                    line: line,
                    lineNumberText: String(line.lineNumber),
                    lineNumberBounds: lineNumberBounds,
                    textBounds: textBounds,
                    rowBounds: rowBounds,
                    visualText: visualText,
                    isCurrentLine: effectiveCurrentLineIndex == lineIndex
                )
            )
        }

        let computedSelectionRects = self.selection.map { self.selectionRects(for: $0, visibleLines: visible) } ?? []
        let computedCaretRect = self.caret.flatMap { self.caretRect(for: $0, visibleLines: visible) }

        return LunaStaticTextViewLayout(
            bounds: bounds,
            gutterBounds: gutterBounds,
            textViewportBounds: textViewportBounds,
            visibleLines: visible,
            firstVisibleLineIndex: firstLine,
            maxVisibleLineCount: maxVisible,
            caretRect: computedCaretRect,
            selectionRects: computedSelectionRects
        )
    }

    /// Calculate the caret insertion rectangle for a visible line.
    public func caretRect(for caret: LunaStaticTextCaret, visibleLines: [LunaStaticTextVisibleLine]? = nil) -> LunaRectI? {
        let location = document.clampedLocation(caret.location)
        let lines = visibleLines ?? layout().visibleLines
        guard let visible = lines.first(where: { $0.line.index == location.lineIndex }) else { return nil }
        let x = clampedTextX(forUTF8Column: location.utf8Column, in: visible)
        return LunaRectI(x: x, y: visible.rowBounds.y, w: max(1, metrics.glyphMetrics.scale), h: visible.rowBounds.h)
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

            let startColumn = lineIndex == range.anchor.lineIndex ? range.anchor.utf8Column : 0
            let endColumn = lineIndex == range.focus.lineIndex ? range.focus.utf8Column : visible.line.utf8Length
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
            column = 0
        } else {
            let relativeX = max(0, point.x - visible.textBounds.x)
            let nearestInsertionColumn = (relativeX + metrics.glyphMetrics.advance / 2) / metrics.glyphMetrics.advance
            column = min(max(0, nearestInsertionColumn), visible.line.utf8Length)
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
        let clampedColumn = min(max(0, column), visible.line.utf8Length)
        let unclipped = visible.textBounds.x + clampedColumn * metrics.glyphMetrics.advance
        return max(visible.textBounds.x, min(visible.textBounds.x + visible.textBounds.w, unclipped))
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        guard !bounds.isEmpty else { return }

        let layout = layout()
        let style = LunaEditorVisualStyle(theme: theme)
        displayList.append(.rect(bounds, style.background))

        if !layout.gutterBounds.isEmpty {
            displayList.append(.rect(layout.gutterBounds, style.gutterBackground))
        }

        for line in layout.visibleLines where line.isCurrentLine {
            displayList.append(.rect(line.rowBounds, style.currentLineBackground))
        }

        for selectionRect in layout.selectionRects {
            displayList.append(.rect(selectionRect.bounds, style.selectionBackground))
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
            children: layout.visibleLines.map(\.nodeID),
            actions: [.focus],
            textRange: LunaAccessibilityTextRange(utf8Offset: 0, utf8Length: document.text.utf8.count),
            caretTextRange: caret.map { document.accessibilityCaretRange(for: $0) },
            selectedTextRange: selection.map { document.accessibilityRange(for: $0.range) }
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        let focusedLineIndex = caret?.location.lineIndex
        return layout().visibleLines.map { visible in
            LunaAccessibilityNode(
                id: visible.nodeID,
                role: .textRun,
                label: visible.line.text,
                value: String(visible.line.lineNumber),
                bounds: visible.rowBounds.asAccessibilityRect,
                isEnabled: true,
                isFocused: focusedLineIndex == visible.line.index,
                children: [],
                actions: [],
                textRange: visible.line.textRange
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
