// LunaContextMenu.swift
//
// Product-neutral context menu primitives.
//
// Phase 4E reuses the same Luna menu item model introduced for menu bars, but
// presents it as a positioned floating menu. Luna owns state, layout, hit
// testing, pointer/keyboard routing, display-list geometry, and accessibility
// semantics. Applications own where the menu is opened, which items appear for
// that context, and how requested command IDs are handled.

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme

// MARK: - Context menu model

public struct LunaContextMenuDefinition: Hashable, Sendable {
    public var id: String
    public var title: String
    public var items: [LunaMenuItem]
    public var sourceNodeID: LunaNodeID?
    public var accessibilityLabel: String

    public init(
        id: String,
        title: String = "Context Menu",
        items: [LunaMenuItem],
        sourceNodeID: LunaNodeID? = nil,
        accessibilityLabel: String? = nil
    ) {
        precondition(!id.isEmpty, "LunaContextMenuDefinition id cannot be empty")
        self.id = id
        self.title = title
        self.items = items
        self.sourceNodeID = sourceNodeID
        self.accessibilityLabel = accessibilityLabel ?? title
    }
}

public struct LunaContextMenuState: Hashable, Sendable {
    public var definition: LunaContextMenuDefinition?
    public var origin: LunaPointI
    public var highlightedPath: LunaMenuItemPath?

    public init(
        definition: LunaContextMenuDefinition? = nil,
        origin: LunaPointI = LunaPointI(x: 0, y: 0),
        highlightedPath: LunaMenuItemPath? = nil
    ) {
        self.definition = definition
        self.origin = origin
        self.highlightedPath = highlightedPath
    }

    public var isOpen: Bool { definition != nil }

    public mutating func open(_ definition: LunaContextMenuDefinition, at origin: LunaPointI) {
        self.definition = definition
        self.origin = origin
        self.highlightedPath = Self.firstEnabledPath(in: definition.items)
    }

    public mutating func close() {
        definition = nil
        highlightedPath = nil
    }

    public mutating func highlight(_ path: LunaMenuItemPath?) {
        guard let path else {
            highlightedPath = nil
            return
        }
        guard path.menuIndex == 0, item(at: path) != nil else { return }
        highlightedPath = path
    }

    public mutating func moveHighlightedItem(by delta: Int) {
        guard let definition else { return }
        let prefix = highlightedPath?.parent?.itemIndices ?? []
        let siblings = Self.items(in: definition.items, prefix: prefix)
        let enabledIndices = siblings.indices.filter { !siblings[$0].isSeparator && siblings[$0].isEnabled }
        guard !enabledIndices.isEmpty else {
            highlightedPath = nil
            return
        }
        let currentLocal = highlightedPath?.itemIndices.last
        let currentPosition = currentLocal.flatMap { enabledIndices.firstIndex(of: $0) } ?? (delta >= 0 ? -1 : enabledIndices.count)
        let nextPosition = Self.positiveModulo(currentPosition + delta, enabledIndices.count)
        let nextIndex = enabledIndices[nextPosition]
        highlightedPath = LunaMenuItemPath(menuIndex: 0, itemIndices: prefix + [nextIndex])
    }

    public mutating func openSubmenu() {
        guard let path = highlightedPath, let item = item(at: path), item.hasSubmenu else { return }
        highlightedPath = Self.firstEnabledChildPath(in: item.children, parent: path) ?? highlightedPath
    }

    public mutating func closeSubmenuOrDismiss() {
        guard let highlightedPath else {
            close()
            return
        }
        if highlightedPath.itemIndices.count > 1, let parent = highlightedPath.parent {
            self.highlightedPath = parent
        } else {
            close()
        }
    }

    public func item(at path: LunaMenuItemPath) -> LunaMenuItem? {
        guard path.menuIndex == 0, let definition else { return nil }
        var items = definition.items
        var current: LunaMenuItem?
        for index in path.itemIndices {
            guard items.indices.contains(index) else { return nil }
            current = items[index]
            items = current?.children ?? []
        }
        return current
    }

    fileprivate static func items(in rootItems: [LunaMenuItem], prefix: [Int]) -> [LunaMenuItem] {
        guard !prefix.isEmpty else { return rootItems }
        var items = rootItems
        var current: LunaMenuItem?
        for index in prefix {
            guard items.indices.contains(index) else { return [] }
            current = items[index]
            items = current?.children ?? []
        }
        return items
    }

    private static func firstEnabledPath(in items: [LunaMenuItem]) -> LunaMenuItemPath? {
        for index in items.indices {
            let item = items[index]
            if !item.isSeparator && item.isEnabled {
                return LunaMenuItemPath(menuIndex: 0, itemIndices: [index])
            }
        }
        return nil
    }

    private static func firstEnabledChildPath(in items: [LunaMenuItem], parent: LunaMenuItemPath) -> LunaMenuItemPath? {
        for index in items.indices {
            let item = items[index]
            if !item.isSeparator && item.isEnabled {
                return LunaMenuItemPath(menuIndex: 0, itemIndices: parent.itemIndices + [index])
            }
        }
        return nil
    }

    private static func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        guard modulus > 0 else { return 0 }
        let m = value % modulus
        return m >= 0 ? m : m + modulus
    }
}

// MARK: - Layout

public struct LunaContextMenuLayout: Hashable, Sendable {
    public var bounds: LunaRectI
    public var definition: LunaContextMenuDefinition?
    public var origin: LunaPointI
    public var dropdowns: [LunaMenuDropdownFrame]

    public var isOpen: Bool { definition != nil }

    public func row(for nodeID: LunaNodeID) -> LunaMenuRowFrame? {
        dropdowns.reversed().flatMap(\.rows).first(where: { $0.nodeID == nodeID })
    }
}

// MARK: - Widget

public struct LunaContextMenu: LunaWidget, Hashable, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI
    public var state: LunaContextMenuState
    public var theme: LunaTheme
    public var metrics: LunaMenuBarMetrics

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        state: LunaContextMenuState = LunaContextMenuState(),
        theme: LunaTheme,
        metrics: LunaMenuBarMetrics = .demo
    ) {
        self.id = id
        self.bounds = bounds
        self.state = state
        self.theme = theme
        self.metrics = metrics
    }

    public func layout() -> LunaContextMenuLayout {
        guard let definition = state.definition, !definition.items.isEmpty else {
            return LunaContextMenuLayout(bounds: bounds, definition: nil, origin: state.origin, dropdowns: [])
        }

        var dropdowns: [LunaMenuDropdownFrame] = []
        let rootWidth = dropdownWidth(for: definition.items)
        let rootHeight = dropdownHeight(for: definition.items)
        let origin = clampedOrigin(width: rootWidth, height: rootHeight, requestedX: state.origin.x, requestedY: state.origin.y)
        appendDropdowns(items: definition.items, prefix: [], x: origin.x, y: origin.y, into: &dropdowns)
        return LunaContextMenuLayout(bounds: bounds, definition: definition, origin: origin, dropdowns: dropdowns)
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        let layout = layout()
        let menu = theme.ui.menu

        for dropdown in layout.dropdowns {
            displayList.append(.rect(dropdown.bounds, menu.background.asRenderColor))
            displayList.append(.rect(LunaRectI(x: dropdown.bounds.x, y: dropdown.bounds.y, w: dropdown.bounds.w, h: 1), menu.border.asRenderColor))
            displayList.append(.rect(LunaRectI(x: dropdown.bounds.x, y: dropdown.bounds.y + dropdown.bounds.h - 1, w: dropdown.bounds.w, h: 1), menu.border.asRenderColor))
            displayList.append(.rect(LunaRectI(x: dropdown.bounds.x, y: dropdown.bounds.y, w: 1, h: dropdown.bounds.h), menu.border.asRenderColor))
            displayList.append(.rect(LunaRectI(x: dropdown.bounds.x + dropdown.bounds.w - 1, y: dropdown.bounds.y, w: 1, h: dropdown.bounds.h), menu.border.asRenderColor))

            for row in dropdown.rows {
                if row.item.isSeparator {
                    let y = row.bounds.y + max(1, row.bounds.h / 2)
                    displayList.append(.rect(LunaRectI(x: row.bounds.x + 9, y: y, w: max(1, row.bounds.w - 18), h: 1), menu.separator.asRenderColor))
                    continue
                }

                if state.highlightedPath == row.path {
                    displayList.append(.rect(row.bounds, menu.rowHoveredBackground.asRenderColor))
                }
            }
        }
    }

    public func buildAccessibilityNode() -> LunaAccessibilityNode {
        let layout = layout()
        let rootBounds = layout.dropdowns.first?.bounds ?? LunaRectI(x: state.origin.x, y: state.origin.y, w: 0, h: 0)
        return LunaAccessibilityNode(
            id: id,
            role: .menu,
            label: state.definition?.accessibilityLabel ?? "Context Menu",
            bounds: rootBounds.asAccessibilityRect,
            children: buildAccessibilityChildren().map(\.id),
            actions: [.focus]
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        let layout = layout()
        var nodes: [LunaAccessibilityNode] = []
        for dropdown in layout.dropdowns {
            for row in dropdown.rows where !row.item.isSeparator {
                let labelPrefix = row.item.isChecked ? "Checked, " : ""
                let roleLabel = row.item.hasSubmenu ? "submenu" : "menu item"
                nodes.append(
                    LunaAccessibilityNode(
                        id: row.nodeID,
                        role: .menuItem,
                        label: labelPrefix + row.item.accessibilityLabel,
                        value: row.item.hasSubmenu ? roleLabel : row.item.keyEquivalent?.lunaMenuDisplayString,
                        bounds: row.bounds.asAccessibilityRect,
                        isEnabled: row.item.isEnabled,
                        isFocused: state.highlightedPath == row.path,
                        actions: row.item.isEnabled ? [.press, .focus] : [.focus]
                    )
                )
            }
        }
        return nodes
    }

    public func hitTest(_ point: LunaPointI) -> LunaNodeID? {
        let layout = layout()
        for row in layout.dropdowns.reversed().flatMap(\.rows).reversed() {
            if row.bounds.contains(x: point.x, y: point.y) {
                return row.nodeID
            }
        }
        for dropdown in layout.dropdowns.reversed() where dropdown.bounds.contains(x: point.x, y: point.y) {
            return dropdownNodeID(prefix: dropdown.prefix)
        }
        return nil
    }

    public func handlePointerEvent(_ event: LunaPointerEvent, state mutableState: inout LunaContextMenuState) -> LunaMenuInteractionResult {
        guard mutableState.isOpen else { return LunaMenuInteractionResult() }

        let layout = layout()
        let hit = hitTest(event.location)
        let hitRow = hit.flatMap { layout.row(for: $0) }

        switch event.phase {
        case .moved:
            if let row = hitRow {
                mutableState.highlight(row.path)
                return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true, hitNodeID: row.nodeID)
            }
            return LunaMenuInteractionResult(didConsumeEvent: true, hitNodeID: hit)

        case .down:
            guard event.button == .primary || event.button == .secondary else {
                return LunaMenuInteractionResult(didConsumeEvent: true, hitNodeID: hit)
            }

            if let row = hitRow {
                mutableState.highlight(row.path)
                guard row.item.isEnabled, !row.item.isSeparator else {
                    return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true, hitNodeID: row.nodeID)
                }
                if row.item.hasSubmenu {
                    mutableState.openSubmenu()
                    return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true, hitNodeID: row.nodeID)
                }
                if let command = row.item.command {
                    mutableState.close()
                    return LunaMenuInteractionResult(
                        didConsumeEvent: true,
                        didDismiss: true,
                        didChangeState: true,
                        requestedCommand: command,
                        hitNodeID: row.nodeID,
                        activatedTitle: row.item.title
                    )
                }
                return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true, hitNodeID: row.nodeID)
            }

            mutableState.close()
            return LunaMenuInteractionResult(didConsumeEvent: true, didDismiss: true, didChangeState: true, hitNodeID: hit)

        case .up:
            return LunaMenuInteractionResult(didConsumeEvent: true, hitNodeID: hit)
        }
    }

    public func handleKeyboardEvent(_ event: LunaKeyboardEvent, state mutableState: inout LunaContextMenuState) -> LunaMenuInteractionResult {
        guard mutableState.isOpen else { return LunaMenuInteractionResult() }

        switch event.key {
        case .escape:
            mutableState.close()
            return LunaMenuInteractionResult(didConsumeEvent: true, didDismiss: true, didChangeState: true)
        case .arrowDown:
            mutableState.moveHighlightedItem(by: 1)
            return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .arrowUp:
            mutableState.moveHighlightedItem(by: -1)
            return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .arrowRight:
            mutableState.openSubmenu()
            return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .arrowLeft:
            mutableState.closeSubmenuOrDismiss()
            return LunaMenuInteractionResult(didConsumeEvent: true, didDismiss: !mutableState.isOpen, didChangeState: true)
        case .enter, .space:
            guard let path = mutableState.highlightedPath, let item = mutableState.item(at: path) else {
                return LunaMenuInteractionResult(didConsumeEvent: true)
            }
            guard item.isEnabled, !item.isSeparator else {
                return LunaMenuInteractionResult(didConsumeEvent: true)
            }
            if item.hasSubmenu {
                mutableState.openSubmenu()
                return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true)
            }
            if let command = item.command {
                mutableState.close()
                return LunaMenuInteractionResult(
                    didConsumeEvent: true,
                    didDismiss: true,
                    didChangeState: true,
                    requestedCommand: command,
                    activatedTitle: item.title
                )
            }
            return LunaMenuInteractionResult(didConsumeEvent: true)
        default:
            return LunaMenuInteractionResult(didConsumeEvent: true)
        }
    }

    public func itemNodeID(_ path: LunaMenuItemPath) -> LunaNodeID {
        let suffix = path.itemIndices.map(String.init).joined(separator: "-")
        return id.child("item").child(suffix.isEmpty ? "root" : suffix)
    }

    public func dropdownNodeID(prefix: [Int]) -> LunaNodeID {
        let suffix = prefix.map(String.init).joined(separator: "-")
        return id.child("dropdown").child(suffix.isEmpty ? "root" : suffix)
    }

    private func appendDropdowns(items: [LunaMenuItem], prefix: [Int], x: Int, y: Int, into dropdowns: inout [LunaMenuDropdownFrame]) {
        guard !items.isEmpty else { return }

        let width = dropdownWidth(for: items)
        let height = dropdownHeight(for: items)
        let origin = clampedOrigin(width: width, height: height, requestedX: x, requestedY: y)
        var rows: [LunaMenuRowFrame] = []
        var cursorY = origin.y + metrics.dropdownPadding

        for index in items.indices {
            let item = items[index]
            let rowHeight = item.isSeparator ? metrics.separatorHeight : metrics.rowHeight
            let rowBounds = LunaRectI(x: origin.x + metrics.dropdownPadding, y: cursorY, w: width - metrics.dropdownPadding * 2, h: rowHeight)
            let path = LunaMenuItemPath(menuIndex: 0, itemIndices: prefix + [index])
            let titleBounds = LunaRectI(
                x: rowBounds.x + metrics.rowHorizontalPadding + 16,
                y: rowBounds.y + max(0, (rowBounds.h - metrics.glyphMetrics.glyphHeight) / 2),
                w: max(1, rowBounds.w - metrics.rowHorizontalPadding * 2 - metrics.shortcutColumnWidth - 30),
                h: metrics.glyphMetrics.lineHeight
            )
            let shortcutBounds = LunaRectI(
                x: rowBounds.x + max(1, rowBounds.w - metrics.rowHorizontalPadding - metrics.shortcutColumnWidth),
                y: titleBounds.y,
                w: metrics.shortcutColumnWidth,
                h: metrics.glyphMetrics.lineHeight
            )
            rows.append(LunaMenuRowFrame(path: path, item: item, bounds: rowBounds, titleBounds: titleBounds, shortcutBounds: shortcutBounds, nodeID: itemNodeID(path)))
            cursorY += rowHeight
        }

        let dropdownBounds = LunaRectI(x: origin.x, y: origin.y, w: width, h: height)
        dropdowns.append(LunaMenuDropdownFrame(menuIndex: 0, prefix: prefix, bounds: dropdownBounds, rows: rows))

        if let highlighted = state.highlightedPath,
           highlighted.itemIndices.count > prefix.count,
           Array(highlighted.itemIndices.prefix(prefix.count)) == prefix,
           let nextIndex = highlighted.itemIndices.dropFirst(prefix.count).first,
           rows.indices.contains(nextIndex) {
            let row = rows[nextIndex]
            if row.item.hasSubmenu {
                let childItems = row.item.children
                let childWidth = dropdownWidth(for: childItems)
                let rightX = row.bounds.x + row.bounds.w + metrics.submenuGap
                let leftX = row.bounds.x - metrics.submenuGap - childWidth
                let preferredX = rightX + childWidth <= bounds.x + bounds.w ? rightX : leftX
                let preferredY = row.bounds.y - metrics.dropdownPadding
                appendDropdowns(items: childItems, prefix: row.path.itemIndices, x: preferredX, y: preferredY, into: &dropdowns)
            }
        }
    }

    private func dropdownWidth(for items: [LunaMenuItem]) -> Int {
        var widestTitle = 0
        var widestShortcut = 0
        for item in items where !item.isSeparator {
            widestTitle = max(widestTitle, metrics.glyphMetrics.visualWidth(of: item.title))
            if let key = item.keyEquivalent?.lunaMenuDisplayString {
                widestShortcut = max(widestShortcut, metrics.glyphMetrics.visualWidth(of: key))
            }
        }
        let desired = metrics.rowHorizontalPadding * 2 + 16 + widestTitle + 24 + max(metrics.shortcutColumnWidth, widestShortcut) + 18
        return min(max(metrics.dropdownMinWidth, desired), metrics.dropdownMaxWidth)
    }

    private func dropdownHeight(for items: [LunaMenuItem]) -> Int {
        metrics.dropdownPadding * 2 + items.reduce(0) { partial, item in
            partial + (item.isSeparator ? metrics.separatorHeight : metrics.rowHeight)
        }
    }

    private func clampedOrigin(width: Int, height: Int, requestedX: Int, requestedY: Int) -> LunaPointI {
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
