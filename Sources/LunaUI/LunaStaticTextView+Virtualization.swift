// SPDX-License-Identifier: MPL-2.0
//
// LunaStaticTextView+Virtualization.swift
//
// C2.5F integration of viewport-bounded shaping into LunaStaticTextView.

import Foundation
import LunaAccessibility
import LunaCore
import LunaRender

extension LunaStaticTextView {
    func virtualizedLayout(
        using context: LunaStaticTextVirtualizationContext
    ) -> LunaStaticTextViewLayout {
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
                visibleLineRange: LunaStaticTextVisibleLineRange(
                    startLineIndex: 0,
                    endLineIndexExclusive: 0
                ),
                contentHeight: 0,
                maxScrollTopLine: 0,
                visibleTextRange: LunaAccessibilityTextRange(
                    utf8Offset: 0,
                    utf8Length: 0
                ),
                scrollbarLaneBounds: LunaRectI(
                    x: bounds.x,
                    y: bounds.y,
                    w: 0,
                    h: 0
                )
            )
        }

        let topInset = max(0, metrics.contentInsets.top)
        let rightInset = max(0, metrics.contentInsets.right)
        let bottomInset = max(0, metrics.contentInsets.bottom)
        let gutterWidth = min(bounds.w, max(0, metrics.gutterWidth))
        let bodyY = bounds.y + topInset
        let bodyHeight = max(0, bounds.h - topInset - bottomInset)
        let lineHeight = max(1, metrics.lineHeight)
        let maxVisible = max(0, bodyHeight / lineHeight)
        let baseTextWidth = max(
            0,
            bounds.w - gutterWidth - metrics.gutterPadding - rightInset
        )
        let estimatedAdvance = max(1, metrics.glyphMetrics.advance)

        var textWidth = baseTextWidth
        var totalRows = context.estimatedTotalVisualRowCount(
            viewportWidth: textWidth,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: estimatedAdvance
        )
        var laneWidth = maxVisible > 0 && totalRows > maxVisible
            ? min(bounds.w, metrics.scrollbarLaneWidth)
            : 0

        if laneWidth > 0 {
            textWidth = max(0, baseTextWidth - laneWidth)
            totalRows = context.estimatedTotalVisualRowCount(
                viewportWidth: textWidth,
                wrapMode: wrapMode,
                estimatedGlyphAdvance: estimatedAdvance
            )
            if totalRows <= maxVisible {
                laneWidth = 0
                textWidth = baseTextWidth
                totalRows = context.estimatedTotalVisualRowCount(
                    viewportWidth: textWidth,
                    wrapMode: wrapMode,
                    estimatedGlyphAdvance: estimatedAdvance
                )
            }
        }

        let requestedTop: Int
        if let scrollTopVisualRow {
            requestedTop = scrollTopVisualRow
        } else {
            requestedTop = context.globalVisualRow(
                for: LunaStaticTextViewportAnchor(
                    logicalLineIndex: scrollTopLine,
                    wrappedSegmentIndex: 0
                ),
                viewportWidth: textWidth,
                wrapMode: wrapMode,
                estimatedGlyphAdvance: estimatedAdvance
            )
        }

        let viewport = context.viewport(
            requestedTopVisualRow: requestedTop,
            maxVisibleVisualRowCount: maxVisible,
            overscanVisualRowCount: 2,
            viewportWidth: textWidth,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: estimatedAdvance,
            geometryProvider: geometryProvider
        )
        totalRows = viewport.totalVisualRowCount

        let gutterBounds = LunaRectI(
            x: bounds.x,
            y: bounds.y,
            w: gutterWidth,
            h: bounds.h
        )
        let textViewportBounds = LunaRectI(
            x: bounds.x + gutterWidth + metrics.gutterPadding,
            y: bodyY,
            w: textWidth,
            h: bodyHeight
        )
        let scrollbarLaneBounds = LunaRectI(
            x: bounds.x + bounds.w - laneWidth,
            y: bounds.y,
            w: laneWidth,
            h: bounds.h
        )
        let scrollbarThumbBounds = Self.virtualizedScrollbarThumbBounds(
            lane: scrollbarLaneBounds,
            documentRowCount: totalRows,
            visibleRowCount: maxVisible,
            maximumTopRow: viewport.maxScrollTopVisualRow,
            topRow: viewport.firstVisibleVisualRowIndex,
            metrics: metrics
        )

        let numberWidth = max(
            0,
            gutterWidth - metrics.gutterPadding * 2
        )
        let effectiveCurrentLineIndex = caret?.location.lineIndex
            ?? currentLineIndex
        var visible: [LunaStaticTextVisibleLine] = []
        visible.reserveCapacity(viewport.visibleRows.count)

        for (visibleIndex, row) in viewport.visibleRows.enumerated() {
            let rowY = bodyY + visibleIndex * lineHeight
            let rowBounds = LunaRectI(
                x: bounds.x,
                y: rowY,
                w: max(0, bounds.w - laneWidth),
                h: lineHeight
            )
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
                    row.geometry.renderedText,
                    in: textBounds,
                    metrics: metrics.glyphMetrics,
                    overflow: .ellipsizeTail
                ).firstLine ?? LunaBoundedTextLine(
                    text: "",
                    fullText: row.line.text,
                    bounds: textBounds,
                    isClipped: !row.line.text.isEmpty
                )
            case .soft:
                visualText = LunaBoundedTextLine(
                    text: row.geometry.renderedText,
                    fullText: row.line.text,
                    bounds: textBounds,
                    isClipped: false
                )
            }

            visible.append(
                LunaStaticTextVisibleLine(
                    nodeID: lineNodeID(
                        for: row.line.index,
                        wrappedSegmentIndex: row.wrappedSegmentIndex
                    ),
                    line: row.line,
                    lineNumberText: row.wrappedSegmentIndex == 0
                        ? String(row.line.lineNumber)
                        : "",
                    lineNumberBounds: lineNumberBounds,
                    textBounds: textBounds,
                    rowBounds: rowBounds,
                    visualText: visualText,
                    rowGeometry: row.geometry,
                    isCurrentLine: effectiveCurrentLineIndex == row.line.index,
                    wrappedSegmentIndex: row.wrappedSegmentIndex,
                    startUTF8Column: row.startUTF8Column,
                    endUTF8Column: row.endUTF8Column
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
            visibleLineRange = LunaStaticTextVisibleLineRange(
                startLineIndex: 0,
                endLineIndexExclusive: 0
            )
        }

        let visibleTextRange: LunaAccessibilityTextRange
        if let first = visible.first, let last = visible.last {
            let start = first.line.utf8Offset + first.startUTF8Column
            let end = last.line.utf8Offset + last.endUTF8Column
            visibleTextRange = LunaAccessibilityTextRange(
                utf8Offset: start,
                utf8Length: max(0, end - start)
            )
        } else {
            visibleTextRange = LunaAccessibilityTextRange(
                utf8Offset: 0,
                utf8Length: 0
            )
        }

        let computedHighlights = highlightRects(visibleLines: visible)
        let computedSelections = selection.map {
            selectionRects(for: $0, visibleLines: visible)
        } ?? []
        let computedCaret = caret.flatMap {
            caretRect(for: $0, visibleLines: visible)
        }
        let contentHeight = Self.saturatedContentHeight(
            topInset: topInset,
            bottomInset: bottomInset,
            rowCount: totalRows,
            lineHeight: lineHeight
        )

        return LunaStaticTextViewLayout(
            bounds: bounds,
            gutterBounds: gutterBounds,
            textViewportBounds: textViewportBounds,
            visibleLines: visible,
            firstVisibleLineIndex: viewport.firstVisibleAnchor.logicalLineIndex,
            maxVisibleLineCount: maxVisible,
            firstVisibleVisualRowIndex: viewport.firstVisibleVisualRowIndex,
            totalVisualRowCount: totalRows,
            maxScrollTopVisualRow: viewport.maxScrollTopVisualRow,
            visibleLineRange: visibleLineRange,
            contentHeight: contentHeight,
            maxScrollTopLine: viewport.maxScrollTopLine,
            visibleTextRange: visibleTextRange,
            scrollbarLaneBounds: scrollbarLaneBounds,
            scrollbarThumbBounds: scrollbarThumbBounds,
            caretRect: computedCaret,
            highlightRects: computedHighlights,
            selectionRects: computedSelections
        )
    }

    func virtualizedScrolled(
        byVisualRowDelta delta: Int,
        context: LunaStaticTextVirtualizationContext
    ) -> LunaStaticTextView {
        let current = virtualizedLayout(using: context)
        let nextTop = min(
            max(0, current.firstVisibleVisualRowIndex + delta),
            current.maxScrollTopVisualRow
        )
        let advance = max(1, metrics.glyphMetrics.advance)
        let anchor = context.anchor(
            forGlobalVisualRow: nextTop,
            viewportWidth: current.textViewportBounds.w,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: advance
        )
        var copy = self
        copy.scrollTopLine = anchor.logicalLineIndex
        copy.scrollTopVisualRow = nextTop
        return copy
    }

    func virtualizedEnsuringVisible(
        _ requestedLocation: LunaTextLocation,
        context: LunaStaticTextVirtualizationContext
    ) -> LunaStaticTextView {
        let current = virtualizedLayout(using: context)
        let location = document.clampedLocation(requestedLocation)
        let advance = max(1, metrics.glyphMetrics.advance)
        let targetRow = context.globalVisualRow(
            containing: location,
            viewportWidth: current.textViewportBounds.w,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: advance,
            geometryProvider: geometryProvider
        )
        let currentTop = current.firstVisibleVisualRowIndex
        let currentBottom = currentTop + current.maxVisibleLineCount
        let nextTop: Int
        if targetRow < currentTop {
            nextTop = targetRow
        } else if targetRow >= currentBottom {
            nextTop = targetRow - max(0, current.maxVisibleLineCount - 1)
        } else {
            nextTop = currentTop
        }
        let clampedTop = min(
            max(0, nextTop),
            current.maxScrollTopVisualRow
        )
        let anchor = context.anchor(
            forGlobalVisualRow: clampedTop,
            viewportWidth: current.textViewportBounds.w,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: advance
        )
        var copy = self
        copy.scrollTopLine = anchor.logicalLineIndex
        copy.scrollTopVisualRow = clampedTop
        return copy
    }

    private static func virtualizedScrollbarThumbBounds(
        lane: LunaRectI,
        documentRowCount: Int,
        visibleRowCount: Int,
        maximumTopRow: Int,
        topRow: Int,
        metrics: LunaStaticTextViewMetrics
    ) -> LunaRectI? {
        guard !lane.isEmpty,
              documentRowCount > visibleRowCount,
              visibleRowCount > 0
        else { return nil }

        let padding = min(
            max(0, metrics.scrollbarPadding),
            max(0, lane.w / 2)
        )
        let trackHeight = max(0, lane.h - padding * 2)
        guard trackHeight > 0 else { return nil }

        let proportionalHeight = (
            trackHeight * visibleRowCount
        ) / max(1, documentRowCount)
        let thumbHeight = min(
            trackHeight,
            max(metrics.scrollbarThumbMinHeight, proportionalHeight)
        )
        let travel = max(0, trackHeight - thumbHeight)
        let yOffset: Int
        if maximumTopRow <= 0 {
            yOffset = 0
        } else {
            yOffset = Int(
                (
                    Double(travel)
                        * Double(min(max(0, topRow), maximumTopRow))
                        / Double(maximumTopRow)
                ).rounded(.toNearestOrAwayFromZero)
            )
        }

        return LunaRectI(
            x: lane.x + padding,
            y: lane.y + padding + yOffset,
            w: max(1, lane.w - padding * 2),
            h: thumbHeight
        )
    }

    private static func saturatedContentHeight(
        topInset: Int,
        bottomInset: Int,
        rowCount: Int,
        lineHeight: Int
    ) -> Int {
        let rows = max(0, rowCount)
        let height = max(1, lineHeight)
        let (rowHeight, didOverflow) = rows.multipliedReportingOverflow(by: height)
        if didOverflow { return Int.max }
        let (withTop, topOverflow) = rowHeight.addingReportingOverflow(max(0, topInset))
        if topOverflow { return Int.max }
        let (complete, bottomOverflow) = withTop.addingReportingOverflow(max(0, bottomInset))
        return bottomOverflow ? Int.max : complete
    }
}
