// LunaMenu.swift
//
// Product-neutral menu bar and dropdown primitives.
//
// Luna owns generic menu state, layout, hit testing, theme-driven display
// geometry, and accessibility semantics. Applications own the menu contents and
// command handlers. The LunaUITestApp uses these primitives only as an
// integration shell; reusable Luna APIs stay product-neutral.

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme

// MARK: - Menu model

public enum LunaMenuItemKind: Hashable, Sendable {
    case command
    case submenu
    case separator
}

public struct LunaMenuItem: Hashable, Sendable {
    public var id: String
    public var title: String
    public var kind: LunaMenuItemKind
    public var command: LunaCommandID?
    public var keyEquivalent: LunaKeyEquivalent?
    public var isEnabled: Bool
    public var isChecked: Bool
    public var children: [LunaMenuItem]
    public var accessibilityLabel: String

    public init(
        id: String,
        title: String,
        kind: LunaMenuItemKind = .command,
        command: LunaCommandID? = nil,
        keyEquivalent: LunaKeyEquivalent? = nil,
        isEnabled: Bool = true,
        isChecked: Bool = false,
        children: [LunaMenuItem] = [],
        accessibilityLabel: String? = nil
    ) {
        precondition(!id.isEmpty, "LunaMenuItem id cannot be empty")
        self.id = id
        self.title = title
        self.kind = children.isEmpty ? kind : .submenu
        self.command = command
        self.keyEquivalent = keyEquivalent
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.children = children
        self.accessibilityLabel = accessibilityLabel ?? title
    }

    public static func command(
        id: String,
        title: String,
        command: LunaCommandID,
        keyEquivalent: LunaKeyEquivalent? = nil,
        isEnabled: Bool = true,
        isChecked: Bool = false,
        accessibilityLabel: String? = nil
    ) -> LunaMenuItem {
        LunaMenuItem(
            id: id,
            title: title,
            kind: .command,
            command: command,
            keyEquivalent: keyEquivalent,
            isEnabled: isEnabled,
            isChecked: isChecked,
            accessibilityLabel: accessibilityLabel
        )
    }

    public static func submenu(
        id: String,
        title: String,
        children: [LunaMenuItem],
        isEnabled: Bool = true,
        accessibilityLabel: String? = nil
    ) -> LunaMenuItem {
        LunaMenuItem(
            id: id,
            title: title,
            kind: .submenu,
            isEnabled: isEnabled,
            children: children,
            accessibilityLabel: accessibilityLabel
        )
    }

    public static func separator(id: String) -> LunaMenuItem {
        LunaMenuItem(id: id, title: "", kind: .separator, isEnabled: false, accessibilityLabel: "Separator")
    }

    public var isSeparator: Bool { kind == .separator }
    public var hasSubmenu: Bool { kind == .submenu && !children.isEmpty }
    public var canActivate: Bool { isEnabled && kind == .command && command != nil }
}

public struct LunaMenuDefinition: Hashable, Sendable {
    public var id: String
    public var title: String
    public var items: [LunaMenuItem]

    public init(id: String, title: String, items: [LunaMenuItem]) {
        precondition(!id.isEmpty, "LunaMenuDefinition id cannot be empty")
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct LunaMenuItemPath: Hashable, Sendable {
    public var menuIndex: Int
    public var itemIndices: [Int]

    public init(menuIndex: Int, itemIndices: [Int]) {
        self.menuIndex = max(0, menuIndex)
        self.itemIndices = itemIndices.map { max(0, $0) }
    }

    public var isTopLevelOnly: Bool { itemIndices.isEmpty }
    public var parent: LunaMenuItemPath? {
        guard !itemIndices.isEmpty else { return nil }
        return LunaMenuItemPath(menuIndex: menuIndex, itemIndices: Array(itemIndices.dropLast()))
    }
}

public extension LunaKeyEquivalent {
    var lunaMenuDisplayString: String {
        var parts: [String] = []

        func appendModifier(_ displayName: String) {
            if !parts.contains(displayName) {
                parts.append(displayName)
            }
        }

        if modifiers.contains(.primary) { appendModifier("Ctrl") }
        if modifiers.contains(.control) { appendModifier("Ctrl") }
        if modifiers.contains(.command) { appendModifier("Cmd") }
        if modifiers.contains(.option) || modifiers.contains(.alt) { appendModifier("Alt") }
        if modifiers.contains(.shift) { appendModifier("Shift") }
        if modifiers.contains(.super) { appendModifier("Super") }
        let keyPart = key.count == 1 ? key.uppercased() : key
        parts.append(keyPart)
        return parts.joined(separator: "+")
    }
}

// MARK: - Menu state and interaction

public struct LunaMenuBarState: Hashable, Sendable {
    public var activeMenuIndex: Int?
    public var hoveredMenuIndex: Int?
    public var highlightedPath: LunaMenuItemPath?

    public init(activeMenuIndex: Int? = nil, hoveredMenuIndex: Int? = nil, highlightedPath: LunaMenuItemPath? = nil) {
        self.activeMenuIndex = activeMenuIndex
        self.hoveredMenuIndex = hoveredMenuIndex
        self.highlightedPath = highlightedPath
    }

    public var isOpen: Bool { activeMenuIndex != nil }

    public mutating func close() {
        activeMenuIndex = nil
        hoveredMenuIndex = nil
        highlightedPath = nil
    }

    public mutating func open(menuIndex: Int, menus: [LunaMenuDefinition]) {
        guard menus.indices.contains(menuIndex) else {
            close()
            return
        }
        activeMenuIndex = menuIndex
        hoveredMenuIndex = menuIndex
        highlightedPath = firstEnabledPath(in: menus, menuIndex: menuIndex)
    }

    public mutating func toggle(menuIndex: Int, menus: [LunaMenuDefinition]) {
        if activeMenuIndex == menuIndex {
            close()
        } else {
            open(menuIndex: menuIndex, menus: menus)
        }
    }

    public mutating func highlight(_ path: LunaMenuItemPath?, menus: [LunaMenuDefinition]) {
        guard let path else {
            highlightedPath = nil
            return
        }
        guard menus.indices.contains(path.menuIndex) else { return }
        activeMenuIndex = path.menuIndex
        hoveredMenuIndex = path.menuIndex
        highlightedPath = path
    }

    public mutating func moveTopLevel(by delta: Int, menus: [LunaMenuDefinition]) {
        guard !menus.isEmpty else {
            close()
            return
        }
        let current = activeMenuIndex ?? hoveredMenuIndex ?? 0
        let next = positiveModulo(current + delta, menus.count)
        open(menuIndex: next, menus: menus)
    }

    public mutating func moveHighlightedItem(by delta: Int, menus: [LunaMenuDefinition]) {
        guard let menuIndex = activeMenuIndex, menus.indices.contains(menuIndex) else { return }
        let prefix = highlightedPath?.parent?.itemIndices ?? []
        let siblings = items(in: menus, menuIndex: menuIndex, prefix: prefix)
        let enabledIndices = siblings.indices.filter { !siblings[$0].isSeparator && siblings[$0].isEnabled }
        guard !enabledIndices.isEmpty else {
            highlightedPath = nil
            return
        }
        let currentLocal = highlightedPath?.itemIndices.last
        let currentPosition = currentLocal.flatMap { enabledIndices.firstIndex(of: $0) } ?? (delta >= 0 ? -1 : enabledIndices.count)
        let nextPosition = positiveModulo(currentPosition + delta, enabledIndices.count)
        let nextIndex = enabledIndices[nextPosition]
        highlightedPath = LunaMenuItemPath(menuIndex: menuIndex, itemIndices: prefix + [nextIndex])
    }

    public mutating func openSubmenuOrMoveRight(menus: [LunaMenuDefinition]) {
        guard let highlightedPath, let item = item(in: menus, at: highlightedPath), item.hasSubmenu else {
            moveTopLevel(by: 1, menus: menus)
            return
        }
        if let firstChild = firstEnabledChildPath(in: menus, parent: highlightedPath) {
            self.highlightedPath = firstChild
        }
    }

    public mutating func closeSubmenuOrMoveLeft(menus: [LunaMenuDefinition]) {
        if let highlightedPath, highlightedPath.itemIndices.count > 1, let parent = highlightedPath.parent {
            self.highlightedPath = parent
        } else {
            moveTopLevel(by: -1, menus: menus)
        }
    }

    public func item(in menus: [LunaMenuDefinition], at path: LunaMenuItemPath) -> LunaMenuItem? {
        guard menus.indices.contains(path.menuIndex) else { return nil }
        var items = menus[path.menuIndex].items
        var current: LunaMenuItem?
        for index in path.itemIndices {
            guard items.indices.contains(index) else { return nil }
            current = items[index]
            items = current?.children ?? []
        }
        return current
    }

    private func firstEnabledPath(in menus: [LunaMenuDefinition], menuIndex: Int) -> LunaMenuItemPath? {
        guard menus.indices.contains(menuIndex) else { return nil }
        for index in menus[menuIndex].items.indices {
            let item = menus[menuIndex].items[index]
            if !item.isSeparator && item.isEnabled {
                return LunaMenuItemPath(menuIndex: menuIndex, itemIndices: [index])
            }
        }
        return nil
    }

    private func firstEnabledChildPath(in menus: [LunaMenuDefinition], parent: LunaMenuItemPath) -> LunaMenuItemPath? {
        guard let parentItem = item(in: menus, at: parent) else { return nil }
        for index in parentItem.children.indices {
            let item = parentItem.children[index]
            if !item.isSeparator && item.isEnabled {
                return LunaMenuItemPath(menuIndex: parent.menuIndex, itemIndices: parent.itemIndices + [index])
            }
        }
        return nil
    }

    private func items(in menus: [LunaMenuDefinition], menuIndex: Int, prefix: [Int]) -> [LunaMenuItem] {
        guard menus.indices.contains(menuIndex) else { return [] }
        guard !prefix.isEmpty else { return menus[menuIndex].items }
        var items = menus[menuIndex].items
        var current: LunaMenuItem?
        for index in prefix {
            guard items.indices.contains(index) else { return [] }
            current = items[index]
            items = current?.children ?? []
        }
        return items
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        guard modulus > 0 else { return 0 }
        let m = value % modulus
        return m >= 0 ? m : m + modulus
    }
}

public struct LunaMenuInteractionResult: Hashable, Sendable {
    public var didConsumeEvent: Bool
    public var didDismiss: Bool
    public var didChangeState: Bool
    public var requestedCommand: LunaCommandID?
    public var hitNodeID: LunaNodeID?
    public var activatedTitle: String?

    public init(
        didConsumeEvent: Bool = false,
        didDismiss: Bool = false,
        didChangeState: Bool = false,
        requestedCommand: LunaCommandID? = nil,
        hitNodeID: LunaNodeID? = nil,
        activatedTitle: String? = nil
    ) {
        self.didConsumeEvent = didConsumeEvent
        self.didDismiss = didDismiss
        self.didChangeState = didChangeState
        self.requestedCommand = requestedCommand
        self.hitNodeID = hitNodeID
        self.activatedTitle = activatedTitle
    }
}

// MARK: - Layout

public struct LunaMenuBarMetrics: Hashable, Sendable {
    public var barHeight: Int
    public var topLevelHorizontalPadding: Int
    public var dropdownMinWidth: Int
    public var dropdownMaxWidth: Int
    public var dropdownPadding: Int
    public var rowHeight: Int
    public var separatorHeight: Int
    public var rowHorizontalPadding: Int
    public var shortcutColumnWidth: Int
    public var submenuGap: Int
    public var textScale: Int
    public var glyphMetrics: LunaDebugTextMetrics

    public init(
        barHeight: Int = 24,
        topLevelHorizontalPadding: Int = 10,
        dropdownMinWidth: Int = 210,
        dropdownMaxWidth: Int = 320,
        dropdownPadding: Int = 5,
        rowHeight: Int = 24,
        separatorHeight: Int = 7,
        rowHorizontalPadding: Int = 10,
        shortcutColumnWidth: Int = 82,
        submenuGap: Int = 2,
        textScale: Int = 1,
        glyphMetrics: LunaDebugTextMetrics = LunaDebugTextMetrics(scale: 1, advance: 6, lineHeight: 9)
    ) {
        self.barHeight = max(1, barHeight)
        self.topLevelHorizontalPadding = max(0, topLevelHorizontalPadding)
        self.dropdownMinWidth = max(1, dropdownMinWidth)
        self.dropdownMaxWidth = max(dropdownMinWidth, dropdownMaxWidth)
        self.dropdownPadding = max(0, dropdownPadding)
        self.rowHeight = max(1, rowHeight)
        self.separatorHeight = max(1, separatorHeight)
        self.rowHorizontalPadding = max(0, rowHorizontalPadding)
        self.shortcutColumnWidth = max(0, shortcutColumnWidth)
        self.submenuGap = max(0, submenuGap)
        self.textScale = max(1, textScale)
        self.glyphMetrics = glyphMetrics
    }

    public static let demo = LunaMenuBarMetrics()
}

public struct LunaMenuTopLevelFrame: Hashable, Sendable {
    public var index: Int
    public var title: String
    public var bounds: LunaRectI
    public var nodeID: LunaNodeID
}

public struct LunaMenuRowFrame: Hashable, Sendable {
    public var path: LunaMenuItemPath
    public var item: LunaMenuItem
    public var bounds: LunaRectI
    public var titleBounds: LunaRectI
    public var shortcutBounds: LunaRectI
    public var nodeID: LunaNodeID
}

public struct LunaMenuDropdownFrame: Hashable, Sendable {
    public var menuIndex: Int
    public var prefix: [Int]
    public var bounds: LunaRectI
    public var rows: [LunaMenuRowFrame]
}

public struct LunaMenuBarLayout: Hashable, Sendable {
    public var bounds: LunaRectI
    public var topLevelFrames: [LunaMenuTopLevelFrame]
    public var dropdowns: [LunaMenuDropdownFrame]

    public func topLevelIndex(for nodeID: LunaNodeID) -> Int? {
        topLevelFrames.first(where: { $0.nodeID == nodeID })?.index
    }

    public func row(for nodeID: LunaNodeID) -> LunaMenuRowFrame? {
        dropdowns.reversed().flatMap(\.rows).first(where: { $0.nodeID == nodeID })
    }
}

// MARK: - Widget

public struct LunaMenuBar: LunaWidget, Hashable, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI
    public var menus: [LunaMenuDefinition]
    public var state: LunaMenuBarState
    public var theme: LunaTheme
    public var metrics: LunaMenuBarMetrics

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        menus: [LunaMenuDefinition],
        state: LunaMenuBarState = LunaMenuBarState(),
        theme: LunaTheme,
        metrics: LunaMenuBarMetrics = .demo
    ) {
        self.id = id
        self.bounds = bounds
        self.menus = menus
        self.state = state
        self.theme = theme
        self.metrics = metrics
    }

    public func layout() -> LunaMenuBarLayout {
        var topFrames: [LunaMenuTopLevelFrame] = []
        var cursorX = bounds.x + 4
        for index in menus.indices {
            let title = menus[index].title
            let width = max(28, metrics.glyphMetrics.visualWidth(of: title) + metrics.topLevelHorizontalPadding * 2)
            let frame = LunaRectI(x: cursorX, y: bounds.y, w: width, h: min(metrics.barHeight, bounds.h))
            topFrames.append(LunaMenuTopLevelFrame(index: index, title: title, bounds: frame, nodeID: topLevelNodeID(index)))
            cursorX += width
        }

        var dropdowns: [LunaMenuDropdownFrame] = []
        if let menuIndex = state.activeMenuIndex, menus.indices.contains(menuIndex) {
            let rootAnchor = topFrames.first(where: { $0.index == menuIndex })?.bounds ?? LunaRectI(x: bounds.x, y: bounds.y + metrics.barHeight, w: 0, h: 0)
            let rootX = min(max(bounds.x, rootAnchor.x), max(bounds.x, bounds.x + bounds.w - metrics.dropdownMinWidth))
            let rootY = bounds.y + metrics.barHeight
            appendDropdowns(menuIndex: menuIndex, prefix: [], x: rootX, y: rootY, into: &dropdowns)
        }

        return LunaMenuBarLayout(bounds: bounds, topLevelFrames: topFrames, dropdowns: dropdowns)
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        let layout = layout()
        let chrome = theme.ui.chrome
        let menu = theme.ui.menu
        displayList.append(.rect(bounds, chrome.menuBarBackground.asRenderColor))
        if bounds.h > 0 {
            displayList.append(.rect(LunaRectI(x: bounds.x, y: bounds.y + bounds.h - 1, w: bounds.w, h: 1), chrome.separator.asRenderColor))
        }

        for top in layout.topLevelFrames {
            let isActive = state.activeMenuIndex == top.index
            let isHovered = state.hoveredMenuIndex == top.index
            if isActive || isHovered {
                displayList.append(.rect(top.bounds, chrome.menuBarHoveredBackground.asRenderColor))
            }
            if isActive {
                let underline = LunaRectI(x: top.bounds.x + 5, y: top.bounds.y + top.bounds.h - 2, w: max(1, top.bounds.w - 10), h: 2)
                displayList.append(.rect(underline, chrome.menuBarActiveUnderline.asRenderColor))
            }
        }

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
        LunaAccessibilityNode(
            id: id,
            role: .menuBar,
            label: "Menu Bar",
            bounds: bounds.asAccessibilityRect,
            children: buildAccessibilityChildren().map(\.id),
            actions: [.focus]
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        let layout = layout()
        var nodes: [LunaAccessibilityNode] = []
        for top in layout.topLevelFrames {
            nodes.append(
                LunaAccessibilityNode(
                    id: top.nodeID,
                    role: .menu,
                    label: top.title,
                    bounds: top.bounds.asAccessibilityRect,
                    isFocused: state.activeMenuIndex == top.index,
                    actions: [.press, .focus]
                )
            )
        }

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
        for dropdown in layout.dropdowns.reversed() {
            for row in dropdown.rows.reversed() where row.bounds.contains(x: point.x, y: point.y) {
                return row.nodeID
            }
        }
        for dropdown in layout.dropdowns.reversed() where dropdown.bounds.contains(x: point.x, y: point.y) {
            return id.child("dropdown-").child(dropdown.menuIndex).child(dropdown.prefix.map(String.init).joined(separator: "-"))
        }
        for top in layout.topLevelFrames where top.bounds.contains(x: point.x, y: point.y) {
            return top.nodeID
        }
        return bounds.contains(x: point.x, y: point.y) ? id : nil
    }

    public func handlePointerEvent(_ event: LunaPointerEvent, state mutableState: inout LunaMenuBarState) -> LunaMenuInteractionResult {
        let layout = layout()
        let hit = hitTest(event.location)
        let hitTop = hit.flatMap { layout.topLevelIndex(for: $0) }
        let hitRow = hit.flatMap { layout.row(for: $0) }

        switch event.phase {
        case .moved:
            if let top = hitTop {
                mutableState.hoveredMenuIndex = top
                if mutableState.isOpen, mutableState.activeMenuIndex != top {
                    mutableState.open(menuIndex: top, menus: menus)
                }
                return LunaMenuInteractionResult(didConsumeEvent: mutableState.isOpen, didChangeState: true, hitNodeID: hit)
            }
            if let row = hitRow {
                mutableState.highlight(row.path, menus: menus)
                return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true, hitNodeID: row.nodeID)
            }
            if mutableState.isOpen { return LunaMenuInteractionResult(didConsumeEvent: true, hitNodeID: hit) }
            return LunaMenuInteractionResult(didConsumeEvent: false, hitNodeID: hit)

        case .down:
            guard event.button == .primary else {
                return LunaMenuInteractionResult(didConsumeEvent: mutableState.isOpen, hitNodeID: hit)
            }

            if let top = hitTop {
                mutableState.toggle(menuIndex: top, menus: menus)
                return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true, hitNodeID: hit)
            }

            if let row = hitRow {
                mutableState.highlight(row.path, menus: menus)
                guard row.item.isEnabled, !row.item.isSeparator else {
                    return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true, hitNodeID: row.nodeID)
                }
                if row.item.hasSubmenu {
                    mutableState.openSubmenuOrMoveRight(menus: menus)
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

            if mutableState.isOpen {
                mutableState.close()
                return LunaMenuInteractionResult(didConsumeEvent: true, didDismiss: true, didChangeState: true, hitNodeID: hit)
            }
            return LunaMenuInteractionResult(didConsumeEvent: false, hitNodeID: hit)

        case .up:
            return LunaMenuInteractionResult(didConsumeEvent: mutableState.isOpen, hitNodeID: hit)
        }
    }

    public func handleKeyboardEvent(_ event: LunaKeyboardEvent, state mutableState: inout LunaMenuBarState) -> LunaMenuInteractionResult {
        guard mutableState.isOpen else { return LunaMenuInteractionResult() }

        switch event.key {
        case .escape:
            mutableState.close()
            return LunaMenuInteractionResult(didConsumeEvent: true, didDismiss: true, didChangeState: true)
        case .arrowLeft:
            mutableState.closeSubmenuOrMoveLeft(menus: menus)
            return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .arrowRight:
            mutableState.openSubmenuOrMoveRight(menus: menus)
            return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .arrowDown:
            mutableState.moveHighlightedItem(by: 1, menus: menus)
            return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .arrowUp:
            mutableState.moveHighlightedItem(by: -1, menus: menus)
            return LunaMenuInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .enter, .space:
            guard let path = mutableState.highlightedPath, let item = mutableState.item(in: menus, at: path) else {
                return LunaMenuInteractionResult(didConsumeEvent: true)
            }
            guard item.isEnabled, !item.isSeparator else {
                return LunaMenuInteractionResult(didConsumeEvent: true)
            }
            if item.hasSubmenu {
                mutableState.openSubmenuOrMoveRight(menus: menus)
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

    public func topLevelNodeID(_ index: Int) -> LunaNodeID {
        id.child("top").child(index)
    }

    public func itemNodeID(_ path: LunaMenuItemPath) -> LunaNodeID {
        let suffix = ([path.menuIndex] + path.itemIndices).map(String.init).joined(separator: "-")
        return id.child("item").child(suffix)
    }

    private func appendDropdowns(menuIndex: Int, prefix: [Int], x: Int, y: Int, into dropdowns: inout [LunaMenuDropdownFrame]) {
        let items = itemsForPrefix(menuIndex: menuIndex, prefix: prefix)
        guard !items.isEmpty else { return }

        let width = dropdownWidth(for: items)
        let clampedX = min(max(bounds.x, x), max(bounds.x, bounds.x + bounds.w - width))
        var rows: [LunaMenuRowFrame] = []
        var cursorY = y + metrics.dropdownPadding
        for index in items.indices {
            let item = items[index]
            let rowHeight = item.isSeparator ? metrics.separatorHeight : metrics.rowHeight
            let rowBounds = LunaRectI(x: clampedX + metrics.dropdownPadding, y: cursorY, w: max(1, width - metrics.dropdownPadding * 2), h: rowHeight)
            let path = LunaMenuItemPath(menuIndex: menuIndex, itemIndices: prefix + [index])
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

        let dropdownBounds = LunaRectI(x: clampedX, y: y, w: width, h: cursorY - y + metrics.dropdownPadding)
        let currentDropdown = LunaMenuDropdownFrame(menuIndex: menuIndex, prefix: prefix, bounds: dropdownBounds, rows: rows)
        dropdowns.append(currentDropdown)

        if let highlighted = state.highlightedPath,
           highlighted.menuIndex == menuIndex,
           highlighted.itemIndices.count > prefix.count,
           Array(highlighted.itemIndices.prefix(prefix.count)) == prefix,
           let nextIndex = highlighted.itemIndices.dropFirst(prefix.count).first,
           rows.indices.contains(nextIndex) {
            let row = rows[nextIndex]
            if row.item.hasSubmenu {
                let submenuX = min(max(bounds.x, row.bounds.x + row.bounds.w + metrics.submenuGap), max(bounds.x, bounds.x + bounds.w - metrics.dropdownMinWidth))
                let submenuY = max(bounds.y + metrics.barHeight, row.bounds.y - metrics.dropdownPadding)
                appendDropdowns(menuIndex: menuIndex, prefix: row.path.itemIndices, x: submenuX, y: submenuY, into: &dropdowns)
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

    private func itemsForPrefix(menuIndex: Int, prefix: [Int]) -> [LunaMenuItem] {
        guard menus.indices.contains(menuIndex) else { return [] }
        var items = menus[menuIndex].items
        for index in prefix {
            guard items.indices.contains(index) else { return [] }
            items = items[index].children
        }
        return items
    }
}
