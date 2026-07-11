// SPDX-License-Identifier: MPL-2.0
// LunaCompletionPopup.swift
//
// Product-neutral anchored completion popup primitives.
//
// Phase 4F introduces the reusable popup surface that future editor completion,
// snippets, symbol suggestions, language-server results, and app-defined
// insertion choices can feed. Luna owns state, anchored layout, viewport
// clamping, input routing, display-list geometry, and accessibility semantics.
// Applications own completion sources, filtering/ranking policy, insertion
// behavior, and any document/language semantics.

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme

// MARK: - Completion model

public struct LunaCompletionItemID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaCompletionItemID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

/// One app-supplied completion candidate.
///
/// `insertText` is only a suggested payload. Luna never mutates a document from
/// inside this type; a host application may instead route through `command` or
/// ignore insertion entirely and use the selected item as metadata.
public struct LunaCompletionItem: Hashable, Sendable {
    public var id: LunaCompletionItemID
    public var title: String
    public var annotation: String?
    public var detail: String?
    public var insertText: String?
    public var command: LunaCommandID?
    public var isEnabled: Bool
    public var accessibilityLabel: String

    public init(
        id: LunaCompletionItemID,
        title: String,
        annotation: String? = nil,
        detail: String? = nil,
        insertText: String? = nil,
        command: LunaCommandID? = nil,
        isEnabled: Bool = true,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.annotation = annotation
        self.detail = detail
        self.insertText = insertText
        self.command = command
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel ?? title
    }
}

/// Mutable popup interaction state.
public struct LunaCompletionPopupState: Hashable, Sendable {
    public var items: [LunaCompletionItem]
    public var anchorRect: LunaRectI
    public var selectedIndex: Int
    public var scrollTopIndex: Int
    public var isOpen: Bool

    public init(
        items: [LunaCompletionItem] = [],
        anchorRect: LunaRectI = LunaRectI(x: 0, y: 0, w: 1, h: 1),
        selectedIndex: Int = 0,
        scrollTopIndex: Int = 0,
        isOpen: Bool = false
    ) {
        self.items = items
        self.anchorRect = anchorRect
        self.selectedIndex = max(0, selectedIndex)
        self.scrollTopIndex = max(0, scrollTopIndex)
        self.isOpen = isOpen && !items.isEmpty
        normalizeSelection()
    }

    public var selectedItem: LunaCompletionItem? {
        guard isOpen, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    public mutating func open(items: [LunaCompletionItem], anchorRect: LunaRectI, preferredSelectedIndex: Int = 0) {
        self.items = items
        self.anchorRect = anchorRect
        self.selectedIndex = max(0, preferredSelectedIndex)
        self.scrollTopIndex = 0
        self.isOpen = !items.isEmpty
        normalizeSelection()
    }

    public mutating func close() {
        isOpen = false
        items = []
        selectedIndex = 0
        scrollTopIndex = 0
    }

    public mutating func highlight(index: Int, visibleRowCount: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        ensureSelectedVisible(visibleRowCount: visibleRowCount)
    }

    public mutating func moveSelection(by delta: Int, visibleRowCount: Int) {
        guard isOpen, !items.isEmpty else { return }
        let enabled = items.indices.filter { items[$0].isEnabled }
        guard !enabled.isEmpty else {
            selectedIndex = 0
            scrollTopIndex = 0
            return
        }
        let currentPosition = enabled.firstIndex(of: selectedIndex) ?? (delta >= 0 ? -1 : enabled.count)
        let nextPosition = min(max(0, currentPosition + delta), enabled.count - 1)
        selectedIndex = enabled[nextPosition]
        ensureSelectedVisible(visibleRowCount: visibleRowCount)
    }

    public mutating func moveToStart(visibleRowCount: Int) {
        guard let first = items.indices.first(where: { items[$0].isEnabled }) else { return }
        selectedIndex = first
        ensureSelectedVisible(visibleRowCount: visibleRowCount)
    }

    public mutating func moveToEnd(visibleRowCount: Int) {
        guard let last = items.indices.reversed().first(where: { items[$0].isEnabled }) else { return }
        selectedIndex = last
        ensureSelectedVisible(visibleRowCount: visibleRowCount)
    }

    public mutating func ensureSelectedVisible(visibleRowCount: Int) {
        let count = max(1, visibleRowCount)
        let maxTop = max(0, items.count - count)
        if selectedIndex < scrollTopIndex {
            scrollTopIndex = selectedIndex
        } else if selectedIndex >= scrollTopIndex + count {
            scrollTopIndex = selectedIndex - count + 1
        }
        scrollTopIndex = min(max(0, scrollTopIndex), maxTop)
    }

    private mutating func normalizeSelection() {
        guard isOpen, !items.isEmpty else {
            selectedIndex = 0
            scrollTopIndex = 0
            isOpen = false
            return
        }
        selectedIndex = min(max(0, selectedIndex), items.count - 1)
        if !items[selectedIndex].isEnabled, let firstEnabled = items.indices.first(where: { items[$0].isEnabled }) {
            selectedIndex = firstEnabled
        }
        scrollTopIndex = min(max(0, scrollTopIndex), max(0, items.count - 1))
    }
}

public struct LunaCompletionInteractionResult: Hashable, Sendable {
    public var didConsumeEvent: Bool
    public var didDismiss: Bool
    public var didChangeState: Bool
    public var selectedItem: LunaCompletionItem?
    public var requestedCommand: LunaCommandID?
    public var insertionText: String?
    public var hitNodeID: LunaNodeID?

    public init(
        didConsumeEvent: Bool = false,
        didDismiss: Bool = false,
        didChangeState: Bool = false,
        selectedItem: LunaCompletionItem? = nil,
        requestedCommand: LunaCommandID? = nil,
        insertionText: String? = nil,
        hitNodeID: LunaNodeID? = nil
    ) {
        self.didConsumeEvent = didConsumeEvent
        self.didDismiss = didDismiss
        self.didChangeState = didChangeState
        self.selectedItem = selectedItem
        self.requestedCommand = requestedCommand
        self.insertionText = insertionText
        self.hitNodeID = hitNodeID
    }
}

// MARK: - Completion layout

public struct LunaCompletionPopupMetrics: Hashable, Sendable {
    public var minWidth: Int
    public var maxWidth: Int
    public var panelPadding: Int
    public var rowHeight: Int
    public var detailHeight: Int
    public var maxVisibleRows: Int
    public var anchorGap: Int
    public var titleHorizontalPadding: Int
    public var annotationColumnWidth: Int
    public var textScale: Int
    public var glyphMetrics: LunaDebugTextMetrics

    public init(
        minWidth: Int = 250,
        maxWidth: Int = 520,
        panelPadding: Int = 5,
        rowHeight: Int = 24,
        detailHeight: Int = 42,
        maxVisibleRows: Int = 8,
        anchorGap: Int = 3,
        titleHorizontalPadding: Int = 9,
        annotationColumnWidth: Int = 118,
        textScale: Int = 1,
        glyphMetrics: LunaDebugTextMetrics = LunaDebugTextMetrics(scale: 1, advance: 6, lineHeight: 9)
    ) {
        self.minWidth = max(1, minWidth)
        self.maxWidth = max(minWidth, maxWidth)
        self.panelPadding = max(0, panelPadding)
        self.rowHeight = max(1, rowHeight)
        self.detailHeight = max(0, detailHeight)
        self.maxVisibleRows = max(1, maxVisibleRows)
        self.anchorGap = max(0, anchorGap)
        self.titleHorizontalPadding = max(0, titleHorizontalPadding)
        self.annotationColumnWidth = max(0, annotationColumnWidth)
        self.textScale = max(1, textScale)
        self.glyphMetrics = glyphMetrics
    }

    public static let demo = LunaCompletionPopupMetrics()
}

public struct LunaCompletionRowFrame: Hashable, Sendable {
    public var nodeID: LunaNodeID
    public var item: LunaCompletionItem
    public var index: Int
    public var bounds: LunaRectI
    public var titleBounds: LunaRectI
    public var annotationBounds: LunaRectI
    public var isSelected: Bool

    public init(
        nodeID: LunaNodeID,
        item: LunaCompletionItem,
        index: Int,
        bounds: LunaRectI,
        titleBounds: LunaRectI,
        annotationBounds: LunaRectI,
        isSelected: Bool
    ) {
        self.nodeID = nodeID
        self.item = item
        self.index = max(0, index)
        self.bounds = bounds
        self.titleBounds = titleBounds
        self.annotationBounds = annotationBounds
        self.isSelected = isSelected
    }
}

public struct LunaCompletionPopupLayout: Hashable, Sendable {
    public var bounds: LunaRectI
    public var popupBounds: LunaRectI
    public var listBounds: LunaRectI
    public var detailBounds: LunaRectI?
    public var rows: [LunaCompletionRowFrame]
    public var visibleRange: Range<Int>
    public var itemCount: Int
    public var anchorRect: LunaRectI

    public init(
        bounds: LunaRectI,
        popupBounds: LunaRectI,
        listBounds: LunaRectI,
        detailBounds: LunaRectI?,
        rows: [LunaCompletionRowFrame],
        visibleRange: Range<Int>,
        itemCount: Int,
        anchorRect: LunaRectI
    ) {
        self.bounds = bounds
        self.popupBounds = popupBounds
        self.listBounds = listBounds
        self.detailBounds = detailBounds
        self.rows = rows
        self.visibleRange = visibleRange
        self.itemCount = max(0, itemCount)
        self.anchorRect = anchorRect
    }
}

public struct LunaCompletionRowTextLayout: Hashable, Sendable {
    public var nodeID: LunaNodeID
    public var title: LunaBoundedTextLine
    public var annotation: LunaBoundedTextLine?
    public var isSelected: Bool

    public init(nodeID: LunaNodeID, title: LunaBoundedTextLine, annotation: LunaBoundedTextLine?, isSelected: Bool) {
        self.nodeID = nodeID
        self.title = title
        self.annotation = annotation
        self.isSelected = isSelected
    }
}

public struct LunaCompletionPopupTextLayout: Hashable, Sendable {
    public var rows: [LunaCompletionRowTextLayout]
    public var detail: LunaBoundedTextLine?
    public var status: LunaBoundedTextLine?

    public init(rows: [LunaCompletionRowTextLayout], detail: LunaBoundedTextLine?, status: LunaBoundedTextLine?) {
        self.rows = rows
        self.detail = detail
        self.status = status
    }
}

// MARK: - Completion widget

public struct LunaCompletionPopup: LunaWidget, Hashable, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI
    public var state: LunaCompletionPopupState
    public var theme: LunaTheme
    public var metrics: LunaCompletionPopupMetrics

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        state: LunaCompletionPopupState = LunaCompletionPopupState(),
        theme: LunaTheme,
        metrics: LunaCompletionPopupMetrics = .demo
    ) {
        self.id = id
        self.bounds = bounds
        self.state = state
        self.theme = theme
        self.metrics = metrics
    }

    public var listNodeID: LunaNodeID { id.child("list") }
    public var detailNodeID: LunaNodeID { id.child("detail") }
    public var statusNodeID: LunaNodeID { id.child("status") }

    public func itemNodeID(index: Int, item: LunaCompletionItem) -> LunaNodeID {
        id.child("item").child(index).child(item.id.rawValue)
    }

    public func layout() -> LunaCompletionPopupLayout {
        guard state.isOpen, !state.items.isEmpty, !bounds.isEmpty else {
            return LunaCompletionPopupLayout(
                bounds: bounds,
                popupBounds: LunaRectI(x: state.anchorRect.x, y: state.anchorRect.y, w: 0, h: 0),
                listBounds: LunaRectI(x: state.anchorRect.x, y: state.anchorRect.y, w: 0, h: 0),
                detailBounds: nil,
                rows: [],
                visibleRange: 0..<0,
                itemCount: 0,
                anchorRect: state.anchorRect
            )
        }

        let visibleCount = min(metrics.maxVisibleRows, state.items.count)
        let maxTop = max(0, state.items.count - visibleCount)
        let scrollTop = min(max(0, state.scrollTopIndex), maxTop)
        let visibleRange = scrollTop..<(scrollTop + visibleCount)
        let selectedDetail = state.selectedItem?.detail
        let hasDetail = selectedDetail?.isEmpty == false
        let width = popupWidth(for: state.items)
        let listHeight = visibleCount * metrics.rowHeight
        let detailHeight = hasDetail ? metrics.detailHeight : 0
        let totalHeight = metrics.panelPadding * 2 + listHeight + detailHeight
        let origin = popupOrigin(width: width, height: totalHeight)
        let popup = LunaRectI(x: origin.x, y: origin.y, w: width, h: totalHeight)
        let list = LunaRectI(
            x: popup.x + metrics.panelPadding,
            y: popup.y + metrics.panelPadding,
            w: max(1, popup.w - metrics.panelPadding * 2),
            h: listHeight
        )

        var rows: [LunaCompletionRowFrame] = []
        rows.reserveCapacity(visibleCount)
        for (visualOffset, index) in visibleRange.enumerated() {
            let item = state.items[index]
            let row = LunaRectI(x: list.x, y: list.y + visualOffset * metrics.rowHeight, w: list.w, h: metrics.rowHeight)
            let titleX = row.x + metrics.titleHorizontalPadding
            let annotationWidth = min(metrics.annotationColumnWidth, max(0, row.w / 2))
            let titleWidth = max(1, row.w - metrics.titleHorizontalPadding * 2 - annotationWidth - 8)
            let title = LunaRectI(
                x: titleX,
                y: row.y + max(0, (row.h - metrics.glyphMetrics.glyphHeight) / 2),
                w: titleWidth,
                h: metrics.glyphMetrics.lineHeight
            )
            let annotation = LunaRectI(
                x: row.x + max(1, row.w - metrics.titleHorizontalPadding - annotationWidth),
                y: title.y,
                w: annotationWidth,
                h: metrics.glyphMetrics.lineHeight
            )
            rows.append(
                LunaCompletionRowFrame(
                    nodeID: itemNodeID(index: index, item: item),
                    item: item,
                    index: index,
                    bounds: row,
                    titleBounds: title,
                    annotationBounds: annotation,
                    isSelected: index == state.selectedIndex
                )
            )
        }

        let detail: LunaRectI?
        if hasDetail {
            detail = LunaRectI(
                x: list.x,
                y: list.y + list.h,
                w: list.w,
                h: detailHeight
            )
        } else {
            detail = nil
        }

        return LunaCompletionPopupLayout(
            bounds: bounds,
            popupBounds: popup,
            listBounds: list,
            detailBounds: detail,
            rows: rows,
            visibleRange: visibleRange,
            itemCount: state.items.count,
            anchorRect: state.anchorRect
        )
    }

    public func textLayout() -> LunaCompletionPopupTextLayout {
        let layout = layout()
        var rowTexts: [LunaCompletionRowTextLayout] = []
        for row in layout.rows {
            let title = LunaBoundedTextLayout.layout(
                row.item.title,
                in: row.titleBounds,
                metrics: metrics.glyphMetrics,
                overflow: .ellipsizeTail
            ).firstLine ?? LunaBoundedTextLine(text: "", fullText: row.item.title, bounds: row.titleBounds, isClipped: !row.item.title.isEmpty)

            let annotation = row.item.annotation.flatMap { text in
                LunaBoundedTextLayout.layout(
                    text,
                    in: row.annotationBounds,
                    metrics: metrics.glyphMetrics,
                    overflow: .ellipsizeTail,
                    alignment: .trailing
                ).firstLine
            }
            rowTexts.append(LunaCompletionRowTextLayout(nodeID: row.nodeID, title: title, annotation: annotation, isSelected: row.isSelected))
        }

        let detail = layout.detailBounds.flatMap { bounds -> LunaBoundedTextLine? in
            guard let detail = state.selectedItem?.detail else { return nil }
            return LunaBoundedTextLayout.layout(
                detail,
                in: bounds.insetForCompletionText(x: 8, y: 7),
                metrics: metrics.glyphMetrics,
                overflow: .ellipsizeTail
            ).firstLine
        }

        let statusText = layout.itemCount > layout.rows.count
            ? "\(layout.visibleRange.lowerBound + 1)-\(layout.visibleRange.upperBound) of \(layout.itemCount)"
            : nil
        let status = statusText.flatMap { text in
            LunaBoundedTextLayout.layout(
                text,
                in: LunaRectI(x: layout.popupBounds.x + max(1, layout.popupBounds.w - 96), y: layout.popupBounds.y + layout.popupBounds.h - metrics.panelPadding - metrics.glyphMetrics.lineHeight, w: 88, h: metrics.glyphMetrics.lineHeight),
                metrics: metrics.glyphMetrics,
                overflow: .ellipsizeTail,
                alignment: .trailing
            ).firstLine
        }

        return LunaCompletionPopupTextLayout(rows: rowTexts, detail: detail, status: status)
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        let layout = layout()
        guard state.isOpen, !layout.popupBounds.isEmpty else { return }
        let panel = theme.ui.panel
        let menu = theme.ui.menu
        let controls = theme.ui.controlColors

        // A subtle anchor marker makes the app-supplied attachment point visible
        // without making the popup depend on editor/caret-specific types.
        displayList.append(.rect(layout.anchorRect, controls.accent.asRenderColor))
        displayList.append(.rect(layout.popupBounds, panel.background.asRenderColor))
        displayList.appendStroke(layout.popupBounds, color: panel.border.asRenderColor, thickness: 1)

        for row in layout.rows {
            if row.isSelected {
                displayList.append(.rect(row.bounds, menu.rowHoveredBackground.asRenderColor))
            } else if !row.item.isEnabled {
                displayList.append(.rect(row.bounds, controls.disabledBackground.asRenderColor))
            }
        }

        if let detail = layout.detailBounds {
            displayList.append(.rect(LunaRectI(x: detail.x, y: detail.y, w: detail.w, h: 1), panel.border.asRenderColor))
            displayList.append(.rect(detail, LunaRender.LunaRGBA8(r: panel.titleBackground.r, g: panel.titleBackground.g, b: panel.titleBackground.b, a: min(panel.titleBackground.a, 230))))
        }
    }

    public func buildAccessibilityNode() -> LunaAccessibilityNode {
        let layout = layout()
        return LunaAccessibilityNode(
            id: id,
            role: .list,
            label: "Completion Suggestions",
            value: "\(layout.itemCount) suggestions",
            bounds: layout.popupBounds.asAccessibilityRect,
            isEnabled: state.isOpen,
            isFocused: state.isOpen,
            children: buildAccessibilityChildren().map(\.id),
            actions: [.focus]
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        let layout = layout()
        var nodes: [LunaAccessibilityNode] = []
        for row in layout.rows {
            nodes.append(
                LunaAccessibilityNode(
                    id: row.nodeID,
                    role: .listItem,
                    label: row.item.accessibilityLabel,
                    value: row.item.annotation ?? row.item.detail ?? row.item.insertText ?? row.item.command?.rawValue,
                    bounds: row.bounds.asAccessibilityRect,
                    isEnabled: row.item.isEnabled,
                    isFocused: row.isSelected,
                    actions: row.item.isEnabled ? [.press, .focus] : [.focus]
                )
            )
        }
        if let detail = layout.detailBounds, let selected = state.selectedItem, let detailText = selected.detail, !detailText.isEmpty {
            nodes.append(
                LunaAccessibilityNode(
                    id: detailNodeID,
                    role: .status,
                    label: detailText,
                    bounds: detail.asAccessibilityRect
                )
            )
        }
        return nodes
    }

    public func hitTest(_ point: LunaPointI) -> LunaNodeID? {
        let layout = layout()
        for row in layout.rows where row.bounds.contains(x: point.x, y: point.y) {
            return row.nodeID
        }
        if let detail = layout.detailBounds, detail.contains(x: point.x, y: point.y) { return detailNodeID }
        if layout.popupBounds.contains(x: point.x, y: point.y) { return id }
        return nil
    }

    public func rowIndex(for nodeID: LunaNodeID) -> Int? {
        layout().rows.first(where: { $0.nodeID == nodeID })?.index
    }

    public func handlePointerEvent(_ event: LunaPointerEvent, state mutableState: inout LunaCompletionPopupState) -> LunaCompletionInteractionResult {
        guard mutableState.isOpen else { return LunaCompletionInteractionResult() }
        let layout = layout()
        let hit = hitTest(event.location)
        let hitRow = hit.flatMap { nodeID in layout.rows.first(where: { $0.nodeID == nodeID }) }

        switch event.phase {
        case .moved:
            if let row = hitRow {
                mutableState.highlight(index: row.index, visibleRowCount: metrics.maxVisibleRows)
                return LunaCompletionInteractionResult(didConsumeEvent: true, didChangeState: true, hitNodeID: row.nodeID)
            }
            return LunaCompletionInteractionResult(didConsumeEvent: true, hitNodeID: hit)

        case .down:
            guard event.button == .primary else {
                return LunaCompletionInteractionResult(didConsumeEvent: true, hitNodeID: hit)
            }
            if let row = hitRow {
                mutableState.highlight(index: row.index, visibleRowCount: metrics.maxVisibleRows)
                guard row.item.isEnabled else {
                    return LunaCompletionInteractionResult(didConsumeEvent: true, didChangeState: true, hitNodeID: row.nodeID)
                }
                mutableState.close()
                return LunaCompletionInteractionResult(
                    didConsumeEvent: true,
                    didDismiss: true,
                    didChangeState: true,
                    selectedItem: row.item,
                    requestedCommand: row.item.command,
                    insertionText: row.item.insertText ?? row.item.title,
                    hitNodeID: row.nodeID
                )
            }
            mutableState.close()
            return LunaCompletionInteractionResult(didConsumeEvent: true, didDismiss: true, didChangeState: true, hitNodeID: hit)

        case .up:
            return LunaCompletionInteractionResult(didConsumeEvent: true, hitNodeID: hit)
        }
    }

    public func handleKeyboardEvent(_ event: LunaKeyboardEvent, state mutableState: inout LunaCompletionPopupState) -> LunaCompletionInteractionResult {
        guard mutableState.isOpen else { return LunaCompletionInteractionResult() }
        let visibleCount = metrics.maxVisibleRows

        switch event.key {
        case .escape:
            mutableState.close()
            return LunaCompletionInteractionResult(didConsumeEvent: true, didDismiss: true, didChangeState: true)
        case .arrowUp:
            mutableState.moveSelection(by: -1, visibleRowCount: visibleCount)
            return LunaCompletionInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .arrowDown:
            mutableState.moveSelection(by: 1, visibleRowCount: visibleCount)
            return LunaCompletionInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .pageUp:
            mutableState.moveSelection(by: -visibleCount, visibleRowCount: visibleCount)
            return LunaCompletionInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .pageDown:
            mutableState.moveSelection(by: visibleCount, visibleRowCount: visibleCount)
            return LunaCompletionInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .home:
            mutableState.moveToStart(visibleRowCount: visibleCount)
            return LunaCompletionInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .end:
            mutableState.moveToEnd(visibleRowCount: visibleCount)
            return LunaCompletionInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .enter, .tab:
            guard let item = mutableState.selectedItem, item.isEnabled else {
                return LunaCompletionInteractionResult(didConsumeEvent: true)
            }
            mutableState.close()
            return LunaCompletionInteractionResult(
                didConsumeEvent: true,
                didDismiss: true,
                didChangeState: true,
                selectedItem: item,
                requestedCommand: item.command,
                insertionText: item.insertText ?? item.title
            )
        default:
            return LunaCompletionInteractionResult(didConsumeEvent: false)
        }
    }

    private func popupWidth(for items: [LunaCompletionItem]) -> Int {
        var widestTitle = 0
        var widestAnnotation = 0
        for item in items {
            widestTitle = max(widestTitle, metrics.glyphMetrics.visualWidth(of: item.title))
            if let annotation = item.annotation {
                widestAnnotation = max(widestAnnotation, metrics.glyphMetrics.visualWidth(of: annotation))
            }
        }
        let desired = metrics.titleHorizontalPadding * 2 + widestTitle + 18 + min(metrics.annotationColumnWidth, widestAnnotation)
        return min(max(metrics.minWidth, desired), metrics.maxWidth)
    }

    private func popupOrigin(width: Int, height: Int) -> LunaPointI {
        let requestedBelowY = state.anchorRect.y + state.anchorRect.h + metrics.anchorGap
        let requestedAboveY = state.anchorRect.y - metrics.anchorGap - height
        let spaceBelow = bounds.y + bounds.h - requestedBelowY
        let requestedY = spaceBelow >= height || requestedAboveY < bounds.y ? requestedBelowY : requestedAboveY
        let requestedX = state.anchorRect.x

        let minX = bounds.x
        let minY = bounds.y
        let maxX = max(minX, bounds.x + bounds.w - max(1, width))
        let maxY = max(minY, bounds.y + bounds.h - max(1, height))
        return LunaPointI(
            x: min(max(requestedX, minX), maxX),
            y: min(max(requestedY, minY), maxY)
        )
    }
}

// MARK: - Local helpers

private extension LunaRectI {
    func insetForCompletionText(x dx: Int, y dy: Int) -> LunaRectI {
        LunaRectI(
            x: x + max(0, dx),
            y: y + max(0, dy),
            w: max(1, w - max(0, dx) * 2),
            h: max(1, h - max(0, dy) * 2)
        )
    }
}

private extension LunaDisplayList {
    mutating func appendStroke(_ rect: LunaRectI, color: LunaRender.LunaRGBA8, thickness: Int) {
        guard !rect.isEmpty else { return }
        let t = max(1, thickness)
        append(.rect(LunaRectI(x: rect.x, y: rect.y, w: rect.w, h: t), color))
        append(.rect(LunaRectI(x: rect.x, y: rect.y + rect.h - t, w: rect.w, h: t), color))
        append(.rect(LunaRectI(x: rect.x, y: rect.y, w: t, h: rect.h), color))
        append(.rect(LunaRectI(x: rect.x + rect.w - t, y: rect.y, w: t, h: rect.h), color))
    }
}
