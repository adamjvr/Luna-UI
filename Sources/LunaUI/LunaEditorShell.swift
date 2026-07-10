// LunaEditorShell.swift
//
// Product-neutral editor/workspace chrome primitives.
//
// Phase 4D introduces a reusable shell layer for the surfaces that frame an
// editor-like content view: tab strip, sidebar, and status bar. Luna owns the
// data model shape, state, layout, hit testing, theme-driven display geometry,
// and accessibility semantics. Applications own the actual tabs, project tree,
// status values, and command handlers.

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaRender
import LunaTheme

// MARK: - Shared IDs

public struct LunaShellTabID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaShellTabID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct LunaSidebarItemID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaSidebarItemID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct LunaStatusSegmentID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaStatusSegmentID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

// MARK: - Tabs

public struct LunaShellTab: Hashable, Sendable {
    public var id: LunaShellTabID
    public var title: String
    public var detail: String?
    public var isDirty: Bool
    public var isPinned: Bool
    public var isClosable: Bool
    public var activateCommand: LunaCommandID?
    public var closeCommand: LunaCommandID?
    public var accessibilityLabel: String

    public init(
        id: LunaShellTabID,
        title: String,
        detail: String? = nil,
        isDirty: Bool = false,
        isPinned: Bool = false,
        isClosable: Bool = true,
        activateCommand: LunaCommandID? = nil,
        closeCommand: LunaCommandID? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isDirty = isDirty
        self.isPinned = isPinned
        self.isClosable = isClosable
        self.activateCommand = activateCommand
        self.closeCommand = closeCommand
        self.accessibilityLabel = accessibilityLabel ?? title
    }
}

public struct LunaTabStripState: Hashable, Sendable {
    public var activeTabID: LunaShellTabID?
    public var hoveredTabID: LunaShellTabID?
    public var pressedTabID: LunaShellTabID?
    public var pressedCloseTabID: LunaShellTabID?

    public init(
        activeTabID: LunaShellTabID? = nil,
        hoveredTabID: LunaShellTabID? = nil,
        pressedTabID: LunaShellTabID? = nil,
        pressedCloseTabID: LunaShellTabID? = nil
    ) {
        self.activeTabID = activeTabID
        self.hoveredTabID = hoveredTabID
        self.pressedTabID = pressedTabID
        self.pressedCloseTabID = pressedCloseTabID
    }

    public mutating func normalize(tabs: [LunaShellTab]) {
        let ids = Set(tabs.map(\.id))
        if let activeTabID, !ids.contains(activeTabID) {
            self.activeTabID = tabs.first?.id
        } else if activeTabID == nil {
            self.activeTabID = tabs.first?.id
        }
        if let hoveredTabID, !ids.contains(hoveredTabID) { self.hoveredTabID = nil }
        if let pressedTabID, !ids.contains(pressedTabID) { self.pressedTabID = nil }
        if let pressedCloseTabID, !ids.contains(pressedCloseTabID) { self.pressedCloseTabID = nil }
    }
}

// MARK: - Sidebar

public enum LunaSidebarItemKind: String, Hashable, Sendable {
    case section
    case folder
    case file
    case symbol
    case custom
}

public struct LunaSidebarItem: Hashable, Sendable {
    public var id: LunaSidebarItemID
    public var title: String
    public var subtitle: String?
    public var kind: LunaSidebarItemKind
    public var children: [LunaSidebarItem]
    public var isEnabled: Bool
    public var isSelectable: Bool
    public var activateCommand: LunaCommandID?
    public var accessibilityLabel: String

    public init(
        id: LunaSidebarItemID,
        title: String,
        subtitle: String? = nil,
        kind: LunaSidebarItemKind = .file,
        children: [LunaSidebarItem] = [],
        isEnabled: Bool = true,
        isSelectable: Bool = true,
        activateCommand: LunaCommandID? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.children = children
        self.isEnabled = isEnabled
        self.isSelectable = isSelectable
        self.activateCommand = activateCommand
        self.accessibilityLabel = accessibilityLabel ?? title
    }

    public var hasChildren: Bool { !children.isEmpty }
}

public struct LunaSidebarState: Hashable, Sendable {
    public var selectedItemID: LunaSidebarItemID?
    public var hoveredItemID: LunaSidebarItemID?
    public var expandedItemIDs: Set<LunaSidebarItemID>

    public init(
        selectedItemID: LunaSidebarItemID? = nil,
        hoveredItemID: LunaSidebarItemID? = nil,
        expandedItemIDs: Set<LunaSidebarItemID> = []
    ) {
        self.selectedItemID = selectedItemID
        self.hoveredItemID = hoveredItemID
        self.expandedItemIDs = expandedItemIDs
    }

    public func isExpanded(_ id: LunaSidebarItemID) -> Bool {
        expandedItemIDs.contains(id)
    }

    public mutating func setExpanded(_ expanded: Bool, for id: LunaSidebarItemID) {
        if expanded {
            expandedItemIDs.insert(id)
        } else {
            expandedItemIDs.remove(id)
        }
    }

    public mutating func toggleExpanded(_ id: LunaSidebarItemID) {
        setExpanded(!isExpanded(id), for: id)
    }

    public mutating func normalize(items: [LunaSidebarItem]) {
        let ids = Set(Self.flatten(items).map(\.id))
        if let selectedItemID, !ids.contains(selectedItemID) { self.selectedItemID = nil }
        if let hoveredItemID, !ids.contains(hoveredItemID) { self.hoveredItemID = nil }
        expandedItemIDs = expandedItemIDs.filter { ids.contains($0) }
    }

    private static func flatten(_ items: [LunaSidebarItem]) -> [LunaSidebarItem] {
        var result: [LunaSidebarItem] = []
        for item in items {
            result.append(item)
            result.append(contentsOf: flatten(item.children))
        }
        return result
    }
}

// MARK: - Status bar

public enum LunaStatusSegmentPlacement: String, Hashable, Sendable {
    case leading
    case trailing
}

public enum LunaStatusSegmentEmphasis: String, Hashable, Sendable {
    case normal
    case muted
    case accent
}

public struct LunaStatusSegment: Hashable, Sendable {
    public var id: LunaStatusSegmentID
    public var title: String
    public var value: String?
    public var placement: LunaStatusSegmentPlacement
    public var emphasis: LunaStatusSegmentEmphasis
    public var command: LunaCommandID?
    public var accessibilityLabel: String

    public init(
        id: LunaStatusSegmentID,
        title: String,
        value: String? = nil,
        placement: LunaStatusSegmentPlacement = .leading,
        emphasis: LunaStatusSegmentEmphasis = .normal,
        command: LunaCommandID? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.placement = placement
        self.emphasis = emphasis
        self.command = command
        let visible = value.map { "\(title) \($0)" } ?? title
        self.accessibilityLabel = accessibilityLabel ?? visible
    }

    public var visibleText: String {
        value.map { "\(title) \($0)" } ?? title
    }
}

// MARK: - Shell state and interaction

public struct LunaEditorShellState: Hashable, Sendable {
    public var tabStrip: LunaTabStripState
    public var sidebar: LunaSidebarState
    public var isSidebarVisible: Bool
    public var sidebarWidth: Int

    public init(
        tabStrip: LunaTabStripState = LunaTabStripState(),
        sidebar: LunaSidebarState = LunaSidebarState(),
        isSidebarVisible: Bool = true,
        sidebarWidth: Int = 236
    ) {
        self.tabStrip = tabStrip
        self.sidebar = sidebar
        self.isSidebarVisible = isSidebarVisible
        self.sidebarWidth = max(0, sidebarWidth)
    }

    public mutating func normalize(tabs: [LunaShellTab], sidebarItems: [LunaSidebarItem], metrics: LunaEditorShellMetrics = .demo) {
        tabStrip.normalize(tabs: tabs)
        sidebar.normalize(items: sidebarItems)
        sidebarWidth = min(max(metrics.sidebarMinWidth, sidebarWidth), metrics.sidebarMaxWidth)
    }
}

public struct LunaEditorShellInteractionResult: Hashable, Sendable {
    public var didConsumeEvent: Bool
    public var didChangeState: Bool
    public var requestedCommand: LunaCommandID?
    public var hitNodeID: LunaNodeID?
    public var selectedTabID: LunaShellTabID?
    public var closedTabID: LunaShellTabID?
    public var selectedSidebarItemID: LunaSidebarItemID?
    public var toggledSidebarItemID: LunaSidebarItemID?
    public var activatedStatusSegmentID: LunaStatusSegmentID?

    public init(
        didConsumeEvent: Bool = false,
        didChangeState: Bool = false,
        requestedCommand: LunaCommandID? = nil,
        hitNodeID: LunaNodeID? = nil,
        selectedTabID: LunaShellTabID? = nil,
        closedTabID: LunaShellTabID? = nil,
        selectedSidebarItemID: LunaSidebarItemID? = nil,
        toggledSidebarItemID: LunaSidebarItemID? = nil,
        activatedStatusSegmentID: LunaStatusSegmentID? = nil
    ) {
        self.didConsumeEvent = didConsumeEvent
        self.didChangeState = didChangeState
        self.requestedCommand = requestedCommand
        self.hitNodeID = hitNodeID
        self.selectedTabID = selectedTabID
        self.closedTabID = closedTabID
        self.selectedSidebarItemID = selectedSidebarItemID
        self.toggledSidebarItemID = toggledSidebarItemID
        self.activatedStatusSegmentID = activatedStatusSegmentID
    }
}

// MARK: - Layout

public struct LunaEditorShellMetrics: Hashable, Sendable {
    public var tabStripHeight: Int
    public var statusBarHeight: Int
    public var sidebarMinWidth: Int
    public var sidebarDefaultWidth: Int
    public var sidebarMaxWidth: Int
    public var sidebarHeaderHeight: Int
    public var sidebarRowHeight: Int
    public var sidebarIndentWidth: Int
    public var shellBorderWidth: Int
    public var tabMinWidth: Int
    public var tabMaxWidth: Int
    public var tabHorizontalPadding: Int
    public var tabCloseSize: Int
    public var tabDirtySize: Int
    public var statusHorizontalPadding: Int
    public var statusSegmentGap: Int
    public var textScale: Int
    public var glyphMetrics: LunaDebugTextMetrics

    public init(
        tabStripHeight: Int = 30,
        statusBarHeight: Int = 26,
        sidebarMinWidth: Int = 160,
        sidebarDefaultWidth: Int = 236,
        sidebarMaxWidth: Int = 360,
        sidebarHeaderHeight: Int = 26,
        sidebarRowHeight: Int = 22,
        sidebarIndentWidth: Int = 14,
        shellBorderWidth: Int = 1,
        tabMinWidth: Int = 92,
        tabMaxWidth: Int = 210,
        tabHorizontalPadding: Int = 12,
        tabCloseSize: Int = 12,
        tabDirtySize: Int = 5,
        statusHorizontalPadding: Int = 10,
        statusSegmentGap: Int = 16,
        textScale: Int = 1,
        glyphMetrics: LunaDebugTextMetrics = LunaDebugTextMetrics(scale: 1, advance: 6, lineHeight: 9)
    ) {
        self.tabStripHeight = max(1, tabStripHeight)
        self.statusBarHeight = max(1, statusBarHeight)
        self.sidebarMinWidth = max(0, sidebarMinWidth)
        self.sidebarDefaultWidth = max(sidebarMinWidth, sidebarDefaultWidth)
        self.sidebarMaxWidth = max(sidebarDefaultWidth, sidebarMaxWidth)
        self.sidebarHeaderHeight = max(0, sidebarHeaderHeight)
        self.sidebarRowHeight = max(1, sidebarRowHeight)
        self.sidebarIndentWidth = max(0, sidebarIndentWidth)
        self.shellBorderWidth = max(0, shellBorderWidth)
        self.tabMinWidth = max(1, tabMinWidth)
        self.tabMaxWidth = max(tabMinWidth, tabMaxWidth)
        self.tabHorizontalPadding = max(0, tabHorizontalPadding)
        self.tabCloseSize = max(0, tabCloseSize)
        self.tabDirtySize = max(1, tabDirtySize)
        self.statusHorizontalPadding = max(0, statusHorizontalPadding)
        self.statusSegmentGap = max(0, statusSegmentGap)
        self.textScale = max(1, textScale)
        self.glyphMetrics = glyphMetrics
    }

    public static let demo = LunaEditorShellMetrics()
}

public struct LunaShellTabFrame: Hashable, Sendable {
    public var index: Int
    public var tab: LunaShellTab
    public var bounds: LunaRectI
    public var titleBounds: LunaRectI
    public var dirtyIndicatorBounds: LunaRectI?
    public var closeButtonBounds: LunaRectI?
    public var nodeID: LunaNodeID
    public var closeNodeID: LunaNodeID?
}

public struct LunaSidebarRowFrame: Hashable, Sendable {
    public var item: LunaSidebarItem
    public var depth: Int
    public var bounds: LunaRectI
    public var disclosureBounds: LunaRectI?
    public var titleBounds: LunaRectI
    public var nodeID: LunaNodeID
}

public struct LunaStatusSegmentFrame: Hashable, Sendable {
    public var segment: LunaStatusSegment
    public var bounds: LunaRectI
    public var textBounds: LunaRectI
    public var nodeID: LunaNodeID
}

public struct LunaEditorShellLayout: Hashable, Sendable {
    public var bounds: LunaRectI
    public var tabStripBounds: LunaRectI
    public var sidebarBounds: LunaRectI
    public var sidebarHeaderBounds: LunaRectI
    public var editorContentBounds: LunaRectI
    public var statusBarBounds: LunaRectI
    public var tabFrames: [LunaShellTabFrame]
    public var sidebarRows: [LunaSidebarRowFrame]
    public var statusSegments: [LunaStatusSegmentFrame]

    public func tabFrame(for nodeID: LunaNodeID) -> LunaShellTabFrame? {
        tabFrames.first { $0.nodeID == nodeID || $0.closeNodeID == nodeID }
    }

    public func rowFrame(for nodeID: LunaNodeID) -> LunaSidebarRowFrame? {
        sidebarRows.first { $0.nodeID == nodeID }
    }

    public func statusFrame(for nodeID: LunaNodeID) -> LunaStatusSegmentFrame? {
        statusSegments.first { $0.nodeID == nodeID }
    }
}

// MARK: - Widget

public struct LunaEditorShell: LunaWidget, Hashable, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI
    public var tabs: [LunaShellTab]
    public var sidebarTitle: String
    public var sidebarItems: [LunaSidebarItem]
    public var statusSegments: [LunaStatusSegment]
    public var state: LunaEditorShellState
    public var theme: LunaTheme
    public var metrics: LunaEditorShellMetrics

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        tabs: [LunaShellTab],
        sidebarTitle: String = "Sidebar",
        sidebarItems: [LunaSidebarItem],
        statusSegments: [LunaStatusSegment],
        state: LunaEditorShellState = LunaEditorShellState(),
        theme: LunaTheme,
        metrics: LunaEditorShellMetrics = .demo
    ) {
        self.id = id
        self.bounds = bounds
        self.tabs = tabs
        self.sidebarTitle = sidebarTitle
        self.sidebarItems = sidebarItems
        self.statusSegments = statusSegments
        var normalized = state
        normalized.normalize(tabs: tabs, sidebarItems: sidebarItems, metrics: metrics)
        self.state = normalized
        self.theme = theme
        self.metrics = metrics
    }

    public func layout() -> LunaEditorShellLayout {
        let tabStrip = LunaRectI(x: bounds.x, y: bounds.y, w: bounds.w, h: min(metrics.tabStripHeight, bounds.h))
        let statusH = min(metrics.statusBarHeight, max(0, bounds.h - tabStrip.h))
        let status = LunaRectI(x: bounds.x, y: max(bounds.y, bounds.y + bounds.h - statusH), w: bounds.w, h: statusH)
        let contentY = tabStrip.y + tabStrip.h
        let contentH = max(0, status.y - contentY)
        let content = LunaRectI(x: bounds.x, y: contentY, w: bounds.w, h: contentH)

        let sidebarW = state.isSidebarVisible && content.w > 0
            ? min(max(metrics.sidebarMinWidth, state.sidebarWidth), min(metrics.sidebarMaxWidth, content.w))
            : 0
        let sidebar = LunaRectI(x: content.x, y: content.y, w: sidebarW, h: content.h)
        let sidebarHeader = LunaRectI(x: sidebar.x, y: sidebar.y, w: sidebar.w, h: min(metrics.sidebarHeaderHeight, sidebar.h))
        let editorX = sidebar.x + sidebar.w
        let editor = LunaRectI(x: editorX, y: content.y, w: max(0, content.x + content.w - editorX), h: content.h)

        return LunaEditorShellLayout(
            bounds: bounds,
            tabStripBounds: tabStrip,
            sidebarBounds: sidebar,
            sidebarHeaderBounds: sidebarHeader,
            editorContentBounds: editor,
            statusBarBounds: status,
            tabFrames: layoutTabs(in: tabStrip),
            sidebarRows: layoutSidebarRows(in: sidebar, belowHeader: sidebarHeader),
            statusSegments: layoutStatusSegments(in: status)
        )
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        buildDisplayList(into: &displayList, includesEditorContentBackground: true)
    }

    /// Build shell chrome rectangles.
    ///
    /// The editor content widget often paints its own background. Passing
    /// `false` for `includesEditorContentBackground` lets a host avoid painting
    /// a large editor rect that will immediately be covered by the editor view,
    /// without changing the reusable shell's default behavior.
    public func buildDisplayList(
        into displayList: inout LunaDisplayList,
        includesEditorContentBackground: Bool
    ) {
        let layout = layout()
        let tabsStyle = theme.ui.tabs
        let sidebarStyle = theme.ui.sidebar
        let statusStyle = theme.ui.statusBar
        let chrome = theme.ui.chrome
        let editorStyle = theme.ui.editor

        if metrics.shellBorderWidth > 0 {
            appendRectStroke(bounds, thickness: metrics.shellBorderWidth, color: chrome.windowBorder.asRenderColor, into: &displayList)
        }
        displayList.append(.rect(layout.tabStripBounds, tabsStyle.stripBackground.asRenderColor))
        displayList.append(.rect(layout.statusBarBounds, statusStyle.background.asRenderColor))
        if includesEditorContentBackground {
            displayList.append(.rect(layout.editorContentBounds, editorStyle.background.asRenderColor))
        }

        if !layout.sidebarBounds.isEmpty {
            displayList.append(.rect(layout.sidebarBounds, sidebarStyle.background.asRenderColor))
            if metrics.shellBorderWidth > 0 {
                displayList.append(.rect(LunaRectI(x: layout.sidebarBounds.x + layout.sidebarBounds.w - metrics.shellBorderWidth, y: layout.sidebarBounds.y, w: metrics.shellBorderWidth, h: layout.sidebarBounds.h), sidebarStyle.border.asRenderColor))
            }
            if !layout.sidebarHeaderBounds.isEmpty {
                displayList.append(.rect(LunaRectI(x: layout.sidebarHeaderBounds.x, y: layout.sidebarHeaderBounds.y + layout.sidebarHeaderBounds.h - 1, w: layout.sidebarHeaderBounds.w, h: 1), sidebarStyle.border.asRenderColor))
            }
        }

        for frame in layout.tabFrames {
            let isActive = state.tabStrip.activeTabID == frame.tab.id
            let isHovered = state.tabStrip.hoveredTabID == frame.tab.id
            let fill = isActive ? tabsStyle.activeBackground : (isHovered ? tabsStyle.hoveredBackground : tabsStyle.inactiveBackground)
            displayList.append(.rect(frame.bounds, fill.asRenderColor))
            displayList.append(.rect(LunaRectI(x: frame.bounds.x + frame.bounds.w - 1, y: frame.bounds.y + 4, w: 1, h: max(1, frame.bounds.h - 8)), tabsStyle.divider.asRenderColor))
            if let dirty = frame.dirtyIndicatorBounds {
                displayList.append(.rect(dirty, tabsStyle.dirtyIndicator.asRenderColor))
            }
            if let close = frame.closeButtonBounds {
                displayList.append(.rect(close, tabsStyle.closeButton.asRenderColor))
            }
        }

        if metrics.shellBorderWidth > 0 {
            displayList.append(.rect(LunaRectI(x: bounds.x, y: layout.tabStripBounds.y + layout.tabStripBounds.h - metrics.shellBorderWidth, w: bounds.w, h: metrics.shellBorderWidth), chrome.separator.asRenderColor))
            displayList.append(.rect(LunaRectI(x: bounds.x, y: layout.statusBarBounds.y, w: bounds.w, h: metrics.shellBorderWidth), statusStyle.border.asRenderColor))
        }

        for row in layout.sidebarRows {
            let isSelected = state.sidebar.selectedItemID == row.item.id
            let isHovered = state.sidebar.hoveredItemID == row.item.id
            if isSelected {
                displayList.append(.rect(row.bounds, sidebarStyle.rowSelectedBackground.asRenderColor))
            } else if isHovered {
                displayList.append(.rect(row.bounds, sidebarStyle.rowHoveredBackground.asRenderColor))
            }
        }

        for segment in layout.statusSegments where segment.segment.emphasis == .accent {
            let accentBounds = LunaRectI(x: segment.bounds.x, y: segment.bounds.y, w: max(1, min(3, segment.bounds.w)), h: segment.bounds.h)
            displayList.append(.rect(accentBounds, statusStyle.accent.asRenderColor))
        }
    }

    public func buildAccessibilityNode() -> LunaAccessibilityNode {
        LunaAccessibilityNode(
            id: id,
            role: .group,
            label: "Editor Shell",
            bounds: bounds.asAccessibilityRect,
            children: buildAccessibilityChildren().map(\.id),
            actions: [.focus]
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        let layout = layout()
        var nodes: [LunaAccessibilityNode] = []

        nodes.append(
            LunaAccessibilityNode(
                id: tabStripNodeID,
                role: .group,
                label: "Tabs",
                bounds: layout.tabStripBounds.asAccessibilityRect,
                children: layout.tabFrames.map(\.nodeID),
                actions: [.focus]
            )
        )

        for frame in layout.tabFrames {
            let label = frame.tab.isDirty ? "Modified, \(frame.tab.accessibilityLabel)" : frame.tab.accessibilityLabel
            nodes.append(
                LunaAccessibilityNode(
                    id: frame.nodeID,
                    role: .button,
                    label: label,
                    value: frame.tab.detail,
                    bounds: frame.bounds.asAccessibilityRect,
                    isFocused: state.tabStrip.activeTabID == frame.tab.id,
                    actions: [.press, .focus]
                )
            )
            if let closeID = frame.closeNodeID, let closeBounds = frame.closeButtonBounds {
                nodes.append(
                    LunaAccessibilityNode(
                        id: closeID,
                        role: .button,
                        label: "Close \(frame.tab.accessibilityLabel)",
                        bounds: closeBounds.asAccessibilityRect,
                        isEnabled: frame.tab.isClosable,
                        actions: frame.tab.isClosable ? [.press] : []
                    )
                )
            }
        }

        if !layout.sidebarBounds.isEmpty {
            nodes.append(
                LunaAccessibilityNode(
                    id: sidebarNodeID,
                    role: .list,
                    label: sidebarTitle,
                    bounds: layout.sidebarBounds.asAccessibilityRect,
                    children: layout.sidebarRows.map(\.nodeID),
                    actions: [.focus]
                )
            )
            for row in layout.sidebarRows {
                let expandedText = row.item.hasChildren ? (state.sidebar.isExpanded(row.item.id) ? "expanded" : "collapsed") : nil
                nodes.append(
                    LunaAccessibilityNode(
                        id: row.nodeID,
                        role: row.item.kind == .section ? .group : .listItem,
                        label: row.item.accessibilityLabel,
                        value: expandedText ?? row.item.subtitle,
                        bounds: row.bounds.asAccessibilityRect,
                        isEnabled: row.item.isEnabled,
                        isFocused: state.sidebar.selectedItemID == row.item.id,
                        actions: row.item.isEnabled ? [.press, .focus] : [.focus]
                    )
                )
            }
        }

        nodes.append(
            LunaAccessibilityNode(
                id: statusBarNodeID,
                role: .status,
                label: "Status Bar",
                bounds: layout.statusBarBounds.asAccessibilityRect,
                children: layout.statusSegments.map(\.nodeID)
            )
        )
        for frame in layout.statusSegments {
            nodes.append(
                LunaAccessibilityNode(
                    id: frame.nodeID,
                    role: frame.segment.command == nil ? .status : .button,
                    label: frame.segment.accessibilityLabel,
                    bounds: frame.bounds.asAccessibilityRect,
                    actions: frame.segment.command == nil ? [] : [.press, .focus]
                )
            )
        }

        return nodes
    }

    public func hitTest(_ point: LunaPointI) -> LunaNodeID? {
        let layout = layout()
        for tab in layout.tabFrames.reversed() {
            if let closeID = tab.closeNodeID, let closeBounds = tab.closeButtonBounds, closeBounds.contains(x: point.x, y: point.y) {
                return closeID
            }
            if tab.bounds.contains(x: point.x, y: point.y) { return tab.nodeID }
        }
        for row in layout.sidebarRows where row.bounds.contains(x: point.x, y: point.y) {
            return row.nodeID
        }
        for segment in layout.statusSegments where segment.bounds.contains(x: point.x, y: point.y) {
            return segment.nodeID
        }
        if layout.tabStripBounds.contains(x: point.x, y: point.y) { return tabStripNodeID }
        if layout.sidebarBounds.contains(x: point.x, y: point.y) { return sidebarNodeID }
        if layout.statusBarBounds.contains(x: point.x, y: point.y) { return statusBarNodeID }
        if layout.editorContentBounds.contains(x: point.x, y: point.y) { return editorContentNodeID }
        return bounds.contains(x: point.x, y: point.y) ? id : nil
    }

    public func handlePointerEvent(_ event: LunaPointerEvent, state mutableState: inout LunaEditorShellState) -> LunaEditorShellInteractionResult {
        let layout = layout()
        let hit = hitTest(event.location)
        let hitTab = hit.flatMap { layout.tabFrame(for: $0) }
        let hitRow = hit.flatMap { layout.rowFrame(for: $0) }
        let hitSegment = hit.flatMap { layout.statusFrame(for: $0) }

        switch event.phase {
        case .moved:
            var changed = false
            let newHoveredTab = hitTab?.tab.id
            if mutableState.tabStrip.hoveredTabID != newHoveredTab {
                mutableState.tabStrip.hoveredTabID = newHoveredTab
                changed = true
            }
            let newHoveredItem = hitRow?.item.id
            if mutableState.sidebar.hoveredItemID != newHoveredItem {
                mutableState.sidebar.hoveredItemID = newHoveredItem
                changed = true
            }
            return LunaEditorShellInteractionResult(didConsumeEvent: hit != nil && hit != editorContentNodeID, didChangeState: changed, hitNodeID: hit)

        case .down:
            guard event.button == .primary else {
                return LunaEditorShellInteractionResult(didConsumeEvent: hit != nil && hit != editorContentNodeID, hitNodeID: hit)
            }

            if let tab = hitTab {
                if hit == tab.closeNodeID, tab.tab.isClosable {
                    mutableState.tabStrip.pressedCloseTabID = tab.tab.id
                    return LunaEditorShellInteractionResult(didConsumeEvent: true, didChangeState: true, hitNodeID: hit)
                }
                mutableState.tabStrip.pressedTabID = tab.tab.id
                mutableState.tabStrip.activeTabID = tab.tab.id
                return LunaEditorShellInteractionResult(
                    didConsumeEvent: true,
                    didChangeState: true,
                    requestedCommand: tab.tab.activateCommand,
                    hitNodeID: hit,
                    selectedTabID: tab.tab.id
                )
            }

            if let row = hitRow {
                guard row.item.isEnabled else {
                    return LunaEditorShellInteractionResult(didConsumeEvent: true, hitNodeID: row.nodeID)
                }
                if row.item.hasChildren, let disclosure = row.disclosureBounds, disclosure.contains(x: event.location.x, y: event.location.y) {
                    mutableState.sidebar.toggleExpanded(row.item.id)
                    return LunaEditorShellInteractionResult(
                        didConsumeEvent: true,
                        didChangeState: true,
                        hitNodeID: row.nodeID,
                        toggledSidebarItemID: row.item.id
                    )
                }
                if row.item.hasChildren && !row.item.isSelectable {
                    mutableState.sidebar.toggleExpanded(row.item.id)
                    return LunaEditorShellInteractionResult(
                        didConsumeEvent: true,
                        didChangeState: true,
                        hitNodeID: row.nodeID,
                        toggledSidebarItemID: row.item.id
                    )
                }
                if row.item.isSelectable {
                    mutableState.sidebar.selectedItemID = row.item.id
                    return LunaEditorShellInteractionResult(
                        didConsumeEvent: true,
                        didChangeState: true,
                        requestedCommand: row.item.activateCommand,
                        hitNodeID: row.nodeID,
                        selectedSidebarItemID: row.item.id
                    )
                }
                return LunaEditorShellInteractionResult(didConsumeEvent: true, hitNodeID: row.nodeID)
            }

            if let segment = hitSegment {
                return LunaEditorShellInteractionResult(
                    didConsumeEvent: true,
                    didChangeState: false,
                    requestedCommand: segment.segment.command,
                    hitNodeID: segment.nodeID,
                    activatedStatusSegmentID: segment.segment.id
                )
            }

            return LunaEditorShellInteractionResult(didConsumeEvent: hit != nil && hit != editorContentNodeID, hitNodeID: hit)

        case .up:
            var result = LunaEditorShellInteractionResult(didConsumeEvent: hit != nil && hit != editorContentNodeID, hitNodeID: hit)
            if let pressedClose = mutableState.tabStrip.pressedCloseTabID {
                mutableState.tabStrip.pressedCloseTabID = nil
                if let tab = hitTab?.tab, tab.id == pressedClose, tab.isClosable {
                    result.didConsumeEvent = true
                    result.didChangeState = true
                    result.closedTabID = tab.id
                    result.requestedCommand = tab.closeCommand
                }
            }
            mutableState.tabStrip.pressedTabID = nil
            return result
        }
    }

    public var tabStripNodeID: LunaNodeID { id.child("tabs") }
    public var sidebarNodeID: LunaNodeID { id.child("sidebar") }
    public var editorContentNodeID: LunaNodeID { id.child("editor") }
    public var statusBarNodeID: LunaNodeID { id.child("status") }

    public func tabNodeID(_ tabID: LunaShellTabID) -> LunaNodeID {
        id.child("tab").child(stableComponent(tabID.rawValue))
    }

    public func tabCloseNodeID(_ tabID: LunaShellTabID) -> LunaNodeID {
        tabNodeID(tabID).child("close")
    }

    public func sidebarRowNodeID(_ itemID: LunaSidebarItemID) -> LunaNodeID {
        id.child("sidebar-row").child(stableComponent(itemID.rawValue))
    }

    public func statusSegmentNodeID(_ segmentID: LunaStatusSegmentID) -> LunaNodeID {
        id.child("status-segment").child(stableComponent(segmentID.rawValue))
    }

    private func layoutTabs(in bounds: LunaRectI) -> [LunaShellTabFrame] {
        guard !bounds.isEmpty, !tabs.isEmpty else { return [] }
        let available = max(1, bounds.w)
        let desired = min(metrics.tabMaxWidth, max(metrics.tabMinWidth, available / max(1, tabs.count)))
        var frames: [LunaShellTabFrame] = []
        var x = bounds.x
        for (index, tab) in tabs.enumerated() {
            guard x < bounds.x + bounds.w else { break }
            let remaining = bounds.x + bounds.w - x
            let width = min(desired, remaining)
            guard width > 0 else { break }
            let frameBounds = LunaRectI(x: x, y: bounds.y, w: width, h: bounds.h)
            let closeBounds: LunaRectI?
            if tab.isClosable && width >= metrics.tabMinWidth {
                closeBounds = LunaRectI(
                    x: frameBounds.x + frameBounds.w - metrics.tabHorizontalPadding - metrics.tabCloseSize,
                    y: frameBounds.y + max(1, (frameBounds.h - metrics.tabCloseSize) / 2),
                    w: metrics.tabCloseSize,
                    h: metrics.tabCloseSize
                )
            } else {
                closeBounds = nil
            }
            let dirtyBounds = tab.isDirty
                ? LunaRectI(x: frameBounds.x + 7, y: frameBounds.y + max(1, (frameBounds.h - metrics.tabDirtySize) / 2), w: metrics.tabDirtySize, h: metrics.tabDirtySize)
                : nil
            let leftInset = metrics.tabHorizontalPadding + (tab.isDirty ? metrics.tabDirtySize + 5 : 0)
            let rightInset = metrics.tabHorizontalPadding + (closeBounds == nil ? 0 : metrics.tabCloseSize + 6)
            let titleBounds = LunaRectI(
                x: frameBounds.x + leftInset,
                y: frameBounds.y + max(0, (frameBounds.h - metrics.glyphMetrics.glyphHeight) / 2),
                w: max(1, frameBounds.w - leftInset - rightInset),
                h: metrics.glyphMetrics.lineHeight
            )
            frames.append(
                LunaShellTabFrame(
                    index: index,
                    tab: tab,
                    bounds: frameBounds,
                    titleBounds: titleBounds,
                    dirtyIndicatorBounds: dirtyBounds,
                    closeButtonBounds: closeBounds,
                    nodeID: tabNodeID(tab.id),
                    closeNodeID: closeBounds == nil ? nil : tabCloseNodeID(tab.id)
                )
            )
            x += width
        }
        return frames
    }

    private func layoutSidebarRows(in bounds: LunaRectI, belowHeader header: LunaRectI) -> [LunaSidebarRowFrame] {
        guard !bounds.isEmpty, state.isSidebarVisible else { return [] }
        var rows: [LunaSidebarRowFrame] = []
        var y = bounds.y + header.h

        func appendItems(_ items: [LunaSidebarItem], depth: Int) {
            for item in items {
                guard y < bounds.y + bounds.h else { return }
                let row = LunaRectI(x: bounds.x, y: y, w: bounds.w, h: min(metrics.sidebarRowHeight, bounds.y + bounds.h - y))
                let iconX = row.x + 8 + depth * metrics.sidebarIndentWidth
                let disclosure = item.hasChildren
                    ? LunaRectI(x: iconX, y: row.y + max(1, (row.h - 10) / 2), w: 10, h: 10)
                    : nil
                let titleX = iconX + (item.hasChildren ? 14 : 14)
                let titleBounds = LunaRectI(
                    x: titleX,
                    y: row.y + max(0, (row.h - metrics.glyphMetrics.glyphHeight) / 2),
                    w: max(1, row.x + row.w - titleX - 8),
                    h: metrics.glyphMetrics.lineHeight
                )
                rows.append(
                    LunaSidebarRowFrame(
                        item: item,
                        depth: depth,
                        bounds: row,
                        disclosureBounds: disclosure,
                        titleBounds: titleBounds,
                        nodeID: sidebarRowNodeID(item.id)
                    )
                )
                y += row.h
                if item.hasChildren && state.sidebar.isExpanded(item.id) {
                    appendItems(item.children, depth: depth + 1)
                }
            }
        }

        appendItems(sidebarItems, depth: 0)
        return rows
    }

    private func layoutStatusSegments(in bounds: LunaRectI) -> [LunaStatusSegmentFrame] {
        guard !bounds.isEmpty else { return [] }
        let leading = statusSegments.filter { $0.placement == .leading }
        let trailing = statusSegments.filter { $0.placement == .trailing }
        var frames: [LunaStatusSegmentFrame] = []

        var x = bounds.x + metrics.statusHorizontalPadding
        for segment in leading {
            let width = statusSegmentWidth(segment)
            guard x < bounds.x + bounds.w else { break }
            let w = min(width, max(1, bounds.x + bounds.w - x))
            let segmentBounds = LunaRectI(x: x, y: bounds.y, w: w, h: bounds.h)
            frames.append(makeStatusFrame(segment, bounds: segmentBounds))
            x += w + metrics.statusSegmentGap
        }

        var right = bounds.x + bounds.w - metrics.statusHorizontalPadding
        for segment in trailing.reversed() {
            let width = statusSegmentWidth(segment)
            let x0 = max(bounds.x + metrics.statusHorizontalPadding, right - width)
            guard x0 < right else { continue }
            let segmentBounds = LunaRectI(x: x0, y: bounds.y, w: right - x0, h: bounds.h)
            frames.append(makeStatusFrame(segment, bounds: segmentBounds))
            right = x0 - metrics.statusSegmentGap
        }

        return frames
    }

    private func makeStatusFrame(_ segment: LunaStatusSegment, bounds: LunaRectI) -> LunaStatusSegmentFrame {
        let textBounds = LunaRectI(
            x: bounds.x + 6,
            y: bounds.y + max(0, (bounds.h - metrics.glyphMetrics.glyphHeight) / 2),
            w: max(1, bounds.w - 12),
            h: metrics.glyphMetrics.lineHeight
        )
        return LunaStatusSegmentFrame(segment: segment, bounds: bounds, textBounds: textBounds, nodeID: statusSegmentNodeID(segment.id))
    }

    private func statusSegmentWidth(_ segment: LunaStatusSegment) -> Int {
        max(32, metrics.glyphMetrics.visualWidth(of: segment.visibleText) + 14)
    }


    private func appendRectStroke(
        _ rect: LunaRectI,
        thickness: Int,
        color: LunaRender.LunaRGBA8,
        into displayList: inout LunaDisplayList
    ) {
        let t = max(1, thickness)
        guard !rect.isEmpty else { return }
        displayList.append(.rect(LunaRectI(x: rect.x, y: rect.y, w: rect.w, h: min(t, rect.h)), color))
        displayList.append(.rect(LunaRectI(x: rect.x, y: rect.y + max(0, rect.h - t), w: rect.w, h: min(t, rect.h)), color))
        displayList.append(.rect(LunaRectI(x: rect.x, y: rect.y, w: min(t, rect.w), h: rect.h), color))
        displayList.append(.rect(LunaRectI(x: rect.x + max(0, rect.w - t), y: rect.y, w: min(t, rect.w), h: rect.h), color))
    }

    private func stableComponent(_ value: String) -> String {
        value.map { character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return String(character)
            }
            return "-"
        }.joined()
    }
}
