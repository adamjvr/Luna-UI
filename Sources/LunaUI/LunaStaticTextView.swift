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

    public init(
        bounds: LunaRectI,
        gutterBounds: LunaRectI,
        textViewportBounds: LunaRectI,
        visibleLines: [LunaStaticTextVisibleLine],
        firstVisibleLineIndex: Int,
        maxVisibleLineCount: Int
    ) {
        self.bounds = bounds
        self.gutterBounds = gutterBounds
        self.textViewportBounds = textViewportBounds
        self.visibleLines = visibleLines
        self.firstVisibleLineIndex = max(0, firstVisibleLineIndex)
        self.maxVisibleLineCount = max(0, maxVisibleLineCount)
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

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        document: LunaStaticTextDocument,
        scrollTopLine: Int = 0,
        currentLineIndex: Int? = nil,
        theme: LunaTheme = .lunaDefaultDark,
        metrics: LunaStaticTextViewMetrics = .demo,
        isFocused: Bool = false
    ) {
        self.id = id
        self.bounds = bounds
        self.document = document
        self.scrollTopLine = max(0, scrollTopLine)
        self.currentLineIndex = currentLineIndex
        self.theme = theme
        self.metrics = metrics
        self.isFocused = isFocused
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
                    isCurrentLine: currentLineIndex == lineIndex
                )
            )
        }

        return LunaStaticTextViewLayout(
            bounds: bounds,
            gutterBounds: gutterBounds,
            textViewportBounds: textViewportBounds,
            visibleLines: visible,
            firstVisibleLineIndex: firstLine,
            maxVisibleLineCount: maxVisible
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

        for line in layout.visibleLines where line.isCurrentLine {
            displayList.append(.rect(line.rowBounds, style.currentLineBackground))
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
            textRange: LunaAccessibilityTextRange(utf8Offset: 0, utf8Length: document.text.utf8.count)
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        layout().visibleLines.map { visible in
            LunaAccessibilityNode(
                id: visible.nodeID,
                role: .textRun,
                label: visible.line.text,
                value: String(visible.line.lineNumber),
                bounds: visible.rowBounds.asAccessibilityRect,
                isEnabled: true,
                isFocused: false,
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
