// SPDX-License-Identifier: MPL-2.0
// LunaQuickPanel.swift
//
// Phase 4A: command palette / quick panel foundation.
//
// This is intentionally still renderer-neutral and product-neutral. Apps supply
// command descriptors or arbitrary items; Luna supplies the geometry, filtering,
// keyboard/pointer state, accessibility shape, and theme-driven display-list
// output. Demo-only labels such as "Moth" stay in LunaUITestApp.

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme

// MARK: - Quick-panel data model

/// One searchable/actionable item in a Luna quick panel.
public struct LunaQuickPanelItem: Hashable, Sendable {
    public var id: LunaNodeID
    public var title: String
    public var subtitle: String?
    public var command: LunaCommandID?
    public var isEnabled: Bool

    public init(
        id: LunaNodeID,
        title: String,
        subtitle: String? = nil,
        command: LunaCommandID? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.command = command
        self.isEnabled = isEnabled
    }

    public init(command descriptor: LunaCommandDescriptor) {
        let menu = descriptor.menuPath.isEmpty ? nil : descriptor.menuPath.joined(separator: " › ")
        self.init(
            id: LunaNodeID(rawValue: "command.\(descriptor.id.rawValue)"),
            title: descriptor.title,
            subtitle: menu,
            command: descriptor.id,
            isEnabled: true
        )
    }
}

/// A filtered quick-panel item plus stable index information.
public struct LunaQuickPanelMatch: Hashable, Sendable {
    public var item: LunaQuickPanelItem
    public var originalIndex: Int
    public var score: Int

    public init(item: LunaQuickPanelItem, originalIndex: Int, score: Int) {
        self.item = item
        self.originalIndex = max(0, originalIndex)
        self.score = score
    }
}

/// Product-neutral fuzzy-ish filtering for command palettes and quick panels.
///
/// Phase 4A deliberately keeps the algorithm simple and deterministic: all query
/// tokens must appear in the title/subtitle/command haystack, with better scores
/// for title prefix/exact matches. That is enough to prove the palette contract
/// before advanced Sublime-style fuzzy scoring lands.
public enum LunaQuickPanelFilter {
    public static func matches(items: [LunaQuickPanelItem], query: String) -> [LunaQuickPanelMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        return items.enumerated().compactMap { index, item in
            guard item.isEnabled else {
                if tokens.isEmpty { return LunaQuickPanelMatch(item: item, originalIndex: index, score: -10_000 - index) }
                return nil
            }

            let title = item.title.lowercased()
            let subtitle = (item.subtitle ?? "").lowercased()
            let command = (item.command?.rawValue ?? "").lowercased()
            let haystack = "\(title) \(subtitle) \(command)"

            guard tokens.allSatisfy({ haystack.contains($0) }) else { return nil }
            guard !tokens.isEmpty else {
                return LunaQuickPanelMatch(item: item, originalIndex: index, score: 10_000 - index)
            }

            var score = 0
            for token in tokens {
                if title == token { score += 2_000 }
                else if title.hasPrefix(token) { score += 1_200 }
                else if title.contains(token) { score += 700 }
                else if subtitle.contains(token) { score += 350 }
                else if command.contains(token) { score += 250 }
                else { score += 100 }
            }
            score -= index
            return LunaQuickPanelMatch(item: item, originalIndex: index, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.originalIndex < rhs.originalIndex
        }
    }
}

/// Mutable quick-panel interaction state.
public struct LunaQuickPanelState: Hashable, Sendable {
    public var allItems: [LunaQuickPanelItem]
    public var query: String
    public var selectedIndex: Int

    public init(
        items: [LunaQuickPanelItem],
        query: String = "",
        selectedIndex: Int = 0
    ) {
        self.allItems = items
        self.query = query
        self.selectedIndex = max(0, selectedIndex)
        clampSelection()
    }

    public var matches: [LunaQuickPanelMatch] {
        LunaQuickPanelFilter.matches(items: allItems, query: query)
    }

    public var selectedMatch: LunaQuickPanelMatch? {
        let visible = matches
        guard !visible.isEmpty else { return nil }
        return visible[min(max(0, selectedIndex), visible.count - 1)]
    }

    public mutating func appendCommittedText(_ text: String) {
        guard !text.isEmpty else { return }
        query.append(text)
        selectedIndex = 0
        clampSelection()
    }

    public mutating func deleteBackwardInQuery() {
        guard !query.isEmpty else { return }
        query.removeLast()
        selectedIndex = min(selectedIndex, max(0, matches.count - 1))
        clampSelection()
    }

    public mutating func moveSelection(by delta: Int) {
        let count = matches.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex + delta), count - 1)
    }

    public mutating func resetQuery() {
        query = ""
        selectedIndex = 0
    }

    private mutating func clampSelection() {
        let count = matches.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex), count - 1)
    }
}

/// Result from a quick-panel keyboard or pointer interaction.
public struct LunaQuickPanelInteractionResult: Hashable, Sendable {
    public var didConsumeEvent: Bool
    public var didDismiss: Bool
    public var didChangeState: Bool
    public var requestedCommand: LunaCommandID?
    public var selectedItem: LunaQuickPanelItem?

    public init(
        didConsumeEvent: Bool = false,
        didDismiss: Bool = false,
        didChangeState: Bool = false,
        requestedCommand: LunaCommandID? = nil,
        selectedItem: LunaQuickPanelItem? = nil
    ) {
        self.didConsumeEvent = didConsumeEvent
        self.didDismiss = didDismiss
        self.didChangeState = didChangeState
        self.requestedCommand = requestedCommand
        self.selectedItem = selectedItem
    }
}

// MARK: - Quick-panel layout

public struct LunaQuickPanelMetrics: Hashable, Sendable {
    public var maxPanelWidth: Int
    public var minPanelWidth: Int
    public var topMargin: Int
    public var sideMargin: Int
    public var panelPadding: Int
    public var titleHeight: Int
    public var inputHeight: Int
    public var rowHeight: Int
    public var rowGap: Int
    public var maxVisibleRows: Int
    public var textScale: Int
    public var titleScale: Int
    public var glyphMetrics: LunaDebugTextMetrics

    public init(
        maxPanelWidth: Int = 640,
        minPanelWidth: Int = 260,
        topMargin: Int = 72,
        sideMargin: Int = 18,
        panelPadding: Int = 10,
        titleHeight: Int = 26,
        inputHeight: Int = 30,
        rowHeight: Int = 34,
        rowGap: Int = 2,
        maxVisibleRows: Int = 8,
        textScale: Int = 1,
        titleScale: Int = 2,
        glyphMetrics: LunaDebugTextMetrics = LunaDebugTextMetrics(scale: 1, advance: 6, lineHeight: 9)
    ) {
        self.maxPanelWidth = max(1, maxPanelWidth)
        self.minPanelWidth = max(1, minPanelWidth)
        self.topMargin = max(0, topMargin)
        self.sideMargin = max(0, sideMargin)
        self.panelPadding = max(0, panelPadding)
        self.titleHeight = max(0, titleHeight)
        self.inputHeight = max(1, inputHeight)
        self.rowHeight = max(1, rowHeight)
        self.rowGap = max(0, rowGap)
        self.maxVisibleRows = max(1, maxVisibleRows)
        self.textScale = max(1, textScale)
        self.titleScale = max(1, titleScale)
        self.glyphMetrics = glyphMetrics
    }

    public static let demo = LunaQuickPanelMetrics()
}

public struct LunaQuickPanelVisibleRow: Hashable, Sendable {
    public var nodeID: LunaNodeID
    public var match: LunaQuickPanelMatch
    public var index: Int
    public var bounds: LunaRectI
    public var titleBounds: LunaRectI
    public var subtitleBounds: LunaRectI
    public var isSelected: Bool

    public init(
        nodeID: LunaNodeID,
        match: LunaQuickPanelMatch,
        index: Int,
        bounds: LunaRectI,
        titleBounds: LunaRectI,
        subtitleBounds: LunaRectI,
        isSelected: Bool
    ) {
        self.nodeID = nodeID
        self.match = match
        self.index = max(0, index)
        self.bounds = bounds
        self.titleBounds = titleBounds
        self.subtitleBounds = subtitleBounds
        self.isSelected = isSelected
    }
}

public struct LunaQuickPanelLayout: Hashable, Sendable {
    public var bounds: LunaRectI
    public var panelBounds: LunaRectI
    public var titleBounds: LunaRectI
    public var inputBounds: LunaRectI
    public var listBounds: LunaRectI
    public var rows: [LunaQuickPanelVisibleRow]
    public var emptyStateBounds: LunaRectI
    public var matchCount: Int

    public init(
        bounds: LunaRectI,
        panelBounds: LunaRectI,
        titleBounds: LunaRectI,
        inputBounds: LunaRectI,
        listBounds: LunaRectI,
        rows: [LunaQuickPanelVisibleRow],
        emptyStateBounds: LunaRectI,
        matchCount: Int
    ) {
        self.bounds = bounds
        self.panelBounds = panelBounds
        self.titleBounds = titleBounds
        self.inputBounds = inputBounds
        self.listBounds = listBounds
        self.rows = rows
        self.emptyStateBounds = emptyStateBounds
        self.matchCount = max(0, matchCount)
    }
}

public struct LunaQuickPanelRowTextLayout: Hashable, Sendable {
    public var nodeID: LunaNodeID
    public var title: LunaBoundedTextLine
    public var subtitle: LunaBoundedTextLine?
    public var isSelected: Bool

    public init(nodeID: LunaNodeID, title: LunaBoundedTextLine, subtitle: LunaBoundedTextLine?, isSelected: Bool) {
        self.nodeID = nodeID
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
    }
}

public struct LunaQuickPanelTextLayout: Hashable, Sendable {
    public var title: LunaBoundedTextLine
    public var query: LunaBoundedTextLine
    public var rows: [LunaQuickPanelRowTextLayout]
    public var emptyState: LunaBoundedTextLine?

    public init(
        title: LunaBoundedTextLine,
        query: LunaBoundedTextLine,
        rows: [LunaQuickPanelRowTextLayout],
        emptyState: LunaBoundedTextLine?
    ) {
        self.title = title
        self.query = query
        self.rows = rows
        self.emptyState = emptyState
    }
}

// MARK: - Quick-panel widget

/// Accessible command-palette / quick-panel widget.
public struct LunaQuickPanel: LunaWidget, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI
    public var title: String
    public var placeholder: String
    public var state: LunaQuickPanelState
    public var theme: LunaTheme
    public var metrics: LunaQuickPanelMetrics

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        title: String = "Command Palette",
        placeholder: String = "Type a command…",
        state: LunaQuickPanelState,
        theme: LunaTheme = .lunaDefaultDark,
        metrics: LunaQuickPanelMetrics = .demo
    ) {
        self.id = id
        self.bounds = bounds
        self.title = title
        self.placeholder = placeholder
        self.state = state
        self.theme = theme
        self.metrics = metrics
    }

    public var inputNodeID: LunaNodeID { id.child("input") }
    public var listNodeID: LunaNodeID { id.child("list") }
    public var emptyNodeID: LunaNodeID { id.child("empty") }

    public func rowNodeID(for item: LunaQuickPanelItem) -> LunaNodeID {
        id.child("item").child(item.id.rawValue)
    }

    public func layout() -> LunaQuickPanelLayout {
        guard !bounds.isEmpty else {
            return LunaQuickPanelLayout(
                bounds: bounds,
                panelBounds: bounds,
                titleBounds: bounds,
                inputBounds: bounds,
                listBounds: bounds,
                rows: [],
                emptyStateBounds: bounds,
                matchCount: 0
            )
        }

        let horizontalRoom = max(1, bounds.w - metrics.sideMargin * 2)
        let panelW = min(metrics.maxPanelWidth, max(metrics.minPanelWidth, horizontalRoom))
        let matches = state.matches
        let visibleRowCount = min(metrics.maxVisibleRows, matches.count)
        let rowsHeight = visibleRowCount > 0
            ? visibleRowCount * metrics.rowHeight + max(0, visibleRowCount - 1) * metrics.rowGap
            : metrics.rowHeight
        let panelH = metrics.panelPadding * 2 + metrics.titleHeight + metrics.inputHeight + 8 + rowsHeight
        let panelX = bounds.x + max(0, (bounds.w - panelW) / 2)
        let panelY = bounds.y + min(max(0, metrics.topMargin), max(0, bounds.h - panelH))
        let panel = LunaRectI(x: panelX, y: panelY, w: panelW, h: min(panelH, bounds.h))
        let contentX = panel.x + metrics.panelPadding
        let contentW = max(1, panel.w - metrics.panelPadding * 2)
        let titleBounds = LunaRectI(x: contentX, y: panel.y + metrics.panelPadding, w: contentW, h: metrics.titleHeight)
        let inputBounds = LunaRectI(x: contentX, y: titleBounds.y + titleBounds.h, w: contentW, h: metrics.inputHeight)
        let listY = inputBounds.y + inputBounds.h + 8
        let listBounds = LunaRectI(x: contentX, y: listY, w: contentW, h: max(1, panel.y + panel.h - listY - metrics.panelPadding))

        var rows: [LunaQuickPanelVisibleRow] = []
        rows.reserveCapacity(visibleRowCount)
        for index in 0..<visibleRowCount {
            let match = matches[index]
            let rowY = listBounds.y + index * (metrics.rowHeight + metrics.rowGap)
            let row = LunaRectI(x: listBounds.x, y: rowY, w: listBounds.w, h: metrics.rowHeight)
            let textX = row.x + 8
            let title = LunaRectI(x: textX, y: row.y + 5, w: max(1, row.w - 16), h: 10)
            let subtitle = LunaRectI(x: textX, y: row.y + 19, w: max(1, row.w - 16), h: 10)
            rows.append(
                LunaQuickPanelVisibleRow(
                    nodeID: rowNodeID(for: match.item),
                    match: match,
                    index: index,
                    bounds: row,
                    titleBounds: title,
                    subtitleBounds: subtitle,
                    isSelected: index == min(max(0, state.selectedIndex), max(0, matches.count - 1))
                )
            )
        }

        let empty = LunaRectI(x: listBounds.x + 8, y: listBounds.y + 8, w: max(1, listBounds.w - 16), h: 16)
        return LunaQuickPanelLayout(
            bounds: bounds,
            panelBounds: panel,
            titleBounds: titleBounds,
            inputBounds: inputBounds,
            listBounds: listBounds,
            rows: rows,
            emptyStateBounds: empty,
            matchCount: matches.count
        )
    }

    public func textLayout() -> LunaQuickPanelTextLayout {
        let layout = layout()
        let titleLine = LunaBoundedTextLayout.layout(
            title,
            in: layout.titleBounds,
            metrics: LunaDebugTextMetrics(scale: metrics.titleScale, advance: metrics.glyphMetrics.advance, lineHeight: metrics.glyphMetrics.lineHeight),
            overflow: .ellipsizeTail
        ).firstLine ?? LunaBoundedTextLine(text: "", fullText: title, bounds: layout.titleBounds, isClipped: !title.isEmpty)

        let queryText = state.query.isEmpty ? placeholder : state.query
        let queryLine = LunaBoundedTextLayout.layout(
            queryText,
            in: layout.inputBounds.insetForText(x: 8, y: 6),
            metrics: metrics.glyphMetrics,
            overflow: .ellipsizeTail
        ).firstLine ?? LunaBoundedTextLine(text: "", fullText: queryText, bounds: layout.inputBounds, isClipped: !queryText.isEmpty)

        let rows = layout.rows.map { row in
            let title = LunaBoundedTextLayout.layout(
                row.match.item.title,
                in: row.titleBounds,
                metrics: metrics.glyphMetrics,
                overflow: .ellipsizeTail
            ).firstLine ?? LunaBoundedTextLine(text: "", fullText: row.match.item.title, bounds: row.titleBounds, isClipped: !row.match.item.title.isEmpty)

            let subtitleText = row.match.item.subtitle ?? row.match.item.command?.rawValue
            let subtitle = subtitleText.flatMap { text in
                LunaBoundedTextLayout.layout(
                    text,
                    in: row.subtitleBounds,
                    metrics: metrics.glyphMetrics,
                    overflow: .ellipsizeTail
                ).firstLine
            }
            return LunaQuickPanelRowTextLayout(nodeID: row.nodeID, title: title, subtitle: subtitle, isSelected: row.isSelected)
        }

        let empty: LunaBoundedTextLine?
        if layout.matchCount == 0 {
            let text = state.query.isEmpty ? "No commands" : "No matches for \"\(state.query)\""
            empty = LunaBoundedTextLayout.layout(text, in: layout.emptyStateBounds, metrics: metrics.glyphMetrics, overflow: .ellipsizeTail).firstLine
        } else {
            empty = nil
        }

        return LunaQuickPanelTextLayout(title: titleLine, query: queryLine, rows: rows, emptyState: empty)
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        guard !bounds.isEmpty else { return }
        let layout = layout()
        let panel = LunaPanelVisualStyle(theme: theme)
        let field = LunaTextFieldVisualStyle(theme: theme)
        let menu = LunaMenuVisualStyle(theme: theme)

        displayList.append(.rect(bounds, panel.overlayBackdrop))
        displayList.append(.rect(layout.panelBounds, panel.border))
        displayList.append(.rect(layout.panelBounds.inset(by: 1), panel.background))
        displayList.append(.rect(LunaRectI(x: layout.panelBounds.x, y: layout.panelBounds.y, w: layout.panelBounds.w, h: 1), field.focusedBorder))

        displayList.append(.rect(layout.inputBounds, field.border))
        displayList.append(.rect(layout.inputBounds.inset(by: 1), field.background))

        if !layout.listBounds.isEmpty {
            displayList.append(.rect(layout.listBounds, menu.background))
        }

        for row in layout.rows {
            let color = row.isSelected ? menu.rowHoveredBackground : menu.background
            displayList.append(.rect(row.bounds, color))
            if row.isSelected {
                displayList.appendStroke(row.bounds, color: field.focusedBorder, thickness: 1)
            }
        }
    }

    public func buildAccessibilityNode() -> LunaAccessibilityNode {
        let layout = layout()
        return LunaAccessibilityNode(
            id: id,
            role: .dialog,
            label: title,
            value: state.query,
            bounds: layout.panelBounds.asAccessibilityRect,
            isEnabled: true,
            isFocused: true,
            children: [inputNodeID, listNodeID],
            actions: [.focus]
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        let layout = layout()
        var nodes: [LunaAccessibilityNode] = []
        nodes.append(
            LunaAccessibilityNode(
                id: inputNodeID,
                role: .textArea,
                label: placeholder,
                value: state.query,
                bounds: layout.inputBounds.asAccessibilityRect,
                isEnabled: true,
                isFocused: true,
                isEditable: true,
                actions: [.focus]
            )
        )

        let rowIDs = layout.rows.map(\.nodeID)
        nodes.append(
            LunaAccessibilityNode(
                id: listNodeID,
                role: .list,
                label: "Command results",
                value: "\(layout.matchCount) matches",
                bounds: layout.listBounds.asAccessibilityRect,
                isEnabled: true,
                isFocused: false,
                children: rowIDs,
                actions: [.focus]
            )
        )

        if layout.matchCount == 0 {
            nodes.append(
                LunaAccessibilityNode(
                    id: emptyNodeID,
                    role: .status,
                    label: "No matches",
                    bounds: layout.emptyStateBounds.asAccessibilityRect
                )
            )
        }

        for row in layout.rows {
            nodes.append(
                LunaAccessibilityNode(
                    id: row.nodeID,
                    role: .listItem,
                    label: row.match.item.title,
                    value: row.match.item.subtitle ?? row.match.item.command?.rawValue,
                    bounds: row.bounds.asAccessibilityRect,
                    isEnabled: row.match.item.isEnabled,
                    isFocused: row.isSelected,
                    actions: row.match.item.isEnabled ? [.press, .focus] : [.focus]
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
        if layout.inputBounds.contains(x: point.x, y: point.y) { return inputNodeID }
        if layout.panelBounds.contains(x: point.x, y: point.y) { return id }
        if bounds.contains(x: point.x, y: point.y) { return id }
        return nil
    }

    public func rowIndex(for nodeID: LunaNodeID) -> Int? {
        layout().rows.first(where: { $0.nodeID == nodeID })?.index
    }
}

// MARK: - Interaction helpers

public extension LunaQuickPanelState {
    mutating func handleTextInput(_ event: LunaTextInputEvent) -> LunaQuickPanelInteractionResult {
        guard !event.text.isEmpty else { return LunaQuickPanelInteractionResult() }
        appendCommittedText(event.text)
        return LunaQuickPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
    }

    mutating func handleKeyboardEvent(_ event: LunaKeyboardEvent) -> LunaQuickPanelInteractionResult {
        switch event.key {
        case .escape:
            return LunaQuickPanelInteractionResult(didConsumeEvent: true, didDismiss: true)
        case .arrowUp:
            moveSelection(by: -1)
            return LunaQuickPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .arrowDown:
            moveSelection(by: 1)
            return LunaQuickPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .pageUp:
            moveSelection(by: -6)
            return LunaQuickPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .pageDown:
            moveSelection(by: 6)
            return LunaQuickPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .home:
            selectedIndex = 0
            return LunaQuickPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .end:
            selectedIndex = max(0, matches.count - 1)
            return LunaQuickPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .backspace:
            deleteBackwardInQuery()
            return LunaQuickPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .enter:
            guard let selected = selectedMatch else {
                return LunaQuickPanelInteractionResult(didConsumeEvent: true)
            }
            return LunaQuickPanelInteractionResult(
                didConsumeEvent: true,
                didDismiss: true,
                requestedCommand: selected.item.command,
                selectedItem: selected.item
            )
        default:
            return LunaQuickPanelInteractionResult()
        }
    }

    mutating func selectOriginalIndex(_ originalIndex: Int) -> LunaQuickPanelInteractionResult {
        let visible = matches
        guard let visibleIndex = visible.firstIndex(where: { $0.originalIndex == originalIndex }) else {
            return LunaQuickPanelInteractionResult()
        }
        selectedIndex = visibleIndex
        let selected = visible[visibleIndex]
        return LunaQuickPanelInteractionResult(
            didConsumeEvent: true,
            didDismiss: true,
            requestedCommand: selected.item.command,
            selectedItem: selected.item
        )
    }
}

// MARK: - Local draw helpers

private extension LunaRectI {
    func inset(by amount: Int) -> LunaRectI {
        let a = max(0, amount)
        return LunaRectI(x: x + a, y: y + a, w: max(0, w - a * 2), h: max(0, h - a * 2))
    }

    func insetForText(x dx: Int, y dy: Int) -> LunaRectI {
        LunaRectI(x: x + max(0, dx), y: y + max(0, dy), w: max(1, w - max(0, dx) * 2), h: max(1, h - max(0, dy) * 2))
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
