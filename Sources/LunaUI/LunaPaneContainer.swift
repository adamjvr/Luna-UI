// SPDX-License-Identifier: MPL-2.0
// LunaPaneContainer.swift
//
// Product-neutral split/pane mechanics introduced in Luna UI Phase 5F.1.
//
// Luna owns pane identity, split geometry, focus traversal, divider resizing,
// hit testing, accessibility, and command-context projection. Applications own
// what each pane means, which document/view it presents, and whether splitting a
// pane clones an editor view or creates some other product-specific surface.

import Foundation
import LunaAccessibility
import LunaCommands
import LunaCore
import LunaInput
import LunaHostCore
import LunaRender
import LunaTheme

// MARK: - Identity and structure

public struct LunaPaneID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaPaneID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

public struct LunaSplitID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaSplitID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

/// Axis along which child panes are arranged.
///
/// - `horizontal`: children are placed left-to-right, separated by a vertical divider.
/// - `vertical`: children are placed top-to-bottom, separated by a horizontal divider.
public enum LunaSplitAxis: String, Hashable, Sendable, CaseIterable {
    case horizontal
    case vertical
}

public enum LunaPaneInsertionPlacement: String, Hashable, Sendable {
    case before
    case after
}

public enum LunaPaneTraversalDirection: String, Hashable, Sendable, CaseIterable {
    case next
    case previous
    case left
    case right
    case up
    case down
}

/// Recursive product-neutral pane tree.
///
/// The tree intentionally stores no document, editor, or project object. A host
/// application maps a `LunaPaneID` to its own presentation state.
public indirect enum LunaPaneNode: Hashable, Sendable {
    case pane(LunaPaneID)
    case split(
        id: LunaSplitID,
        axis: LunaSplitAxis,
        fraction: Double,
        first: LunaPaneNode,
        second: LunaPaneNode
    )

    public var paneIDs: [LunaPaneID] {
        switch self {
        case .pane(let id):
            return [id]
        case .split(_, _, _, let first, let second):
            return first.paneIDs + second.paneIDs
        }
    }

    public var splitIDs: [LunaSplitID] {
        switch self {
        case .pane:
            return []
        case .split(let id, _, _, let first, let second):
            return [id] + first.splitIDs + second.splitIDs
        }
    }

    public func contains(paneID: LunaPaneID) -> Bool {
        paneIDs.contains(paneID)
    }

    public func contains(splitID: LunaSplitID) -> Bool {
        splitIDs.contains(splitID)
    }


}

// MARK: - Workspace state and product-neutral operations

public struct LunaPaneWorkspaceState: Hashable, Sendable {
    public var root: LunaPaneNode
    public var activePaneID: LunaPaneID
    public var minimumSplitFraction: Double
    public var maximumSplitFraction: Double

    public init(
        root: LunaPaneNode,
        activePaneID: LunaPaneID? = nil,
        minimumSplitFraction: Double = 0.1,
        maximumSplitFraction: Double = 0.9
    ) {
        precondition(minimumSplitFraction > 0)
        precondition(maximumSplitFraction < 1)
        precondition(minimumSplitFraction < maximumSplitFraction)
        let panes = root.paneIDs
        precondition(!panes.isEmpty, "A Luna pane workspace requires at least one pane")
        precondition(Set(panes).count == panes.count, "A Luna pane workspace requires unique pane IDs")
        let splits = root.splitIDs
        precondition(Set(splits).count == splits.count, "A Luna pane workspace requires unique split IDs")

        self.root = Self.clampFractions(
            in: root,
            minimum: minimumSplitFraction,
            maximum: maximumSplitFraction
        )
        self.activePaneID = activePaneID.flatMap { panes.contains($0) ? $0 : nil } ?? panes[0]
        self.minimumSplitFraction = minimumSplitFraction
        self.maximumSplitFraction = maximumSplitFraction
    }

    public var paneIDs: [LunaPaneID] { root.paneIDs }
    public var splitIDs: [LunaSplitID] { root.splitIDs }

    @discardableResult
    public mutating func activate(_ paneID: LunaPaneID) -> Bool {
        guard root.contains(paneID: paneID), paneID != activePaneID else { return false }
        activePaneID = paneID
        return true
    }

    @discardableResult
    public mutating func traverse(
        _ direction: LunaPaneTraversalDirection,
        layout: LunaPaneContainerLayout? = nil
    ) -> LunaPaneID {
        let ids = paneIDs
        guard ids.count > 1, let currentIndex = ids.firstIndex(of: activePaneID) else {
            return activePaneID
        }

        let target: LunaPaneID?
        switch direction {
        case .next:
            target = ids[(currentIndex + 1) % ids.count]
        case .previous:
            target = ids[(currentIndex - 1 + ids.count) % ids.count]
        case .left, .right, .up, .down:
            target = layout?.nearestPane(from: activePaneID, direction: direction)
        }

        if let target { activePaneID = target }
        return activePaneID
    }

    /// Split an existing pane while leaving application-specific cloned-view
    /// policy to the caller. The existing pane remains one leaf; Luna inserts a
    /// second caller-supplied pane ID beside it.
    @discardableResult
    public mutating func split(
        paneID: LunaPaneID,
        newPaneID: LunaPaneID,
        splitID: LunaSplitID,
        axis: LunaSplitAxis,
        placement: LunaPaneInsertionPlacement = .after,
        fraction: Double = 0.5,
        activatesNewPane: Bool = true
    ) -> Bool {
        guard root.contains(paneID: paneID) else { return false }
        guard !root.contains(paneID: newPaneID), !root.contains(splitID: splitID) else { return false }

        let clamped = min(max(minimumSplitFraction, fraction), maximumSplitFraction)
        var changed = false
        root = Self.replacingPane(in: root, paneID: paneID) { existing in
            changed = true
            let inserted = LunaPaneNode.pane(newPaneID)
            switch placement {
            case .before:
                return .split(id: splitID, axis: axis, fraction: clamped, first: inserted, second: existing)
            case .after:
                return .split(id: splitID, axis: axis, fraction: clamped, first: existing, second: inserted)
            }
        }
        if changed && activatesNewPane { activePaneID = newPaneID }
        return changed
    }

    /// Remove a pane and collapse its now-redundant parent split.
    /// The final remaining pane cannot be removed.
    @discardableResult
    public mutating func remove(paneID: LunaPaneID) -> Bool {
        guard paneIDs.count > 1, root.contains(paneID: paneID) else { return false }
        guard let replacement = Self.removingPane(from: root, paneID: paneID) else { return false }
        root = replacement
        if activePaneID == paneID || !root.contains(paneID: activePaneID) {
            activePaneID = root.paneIDs[0]
        }
        return true
    }

    @discardableResult
    public mutating func setSplitFraction(_ fraction: Double, for splitID: LunaSplitID) -> Bool {
        guard root.contains(splitID: splitID) else { return false }
        let clamped = min(max(minimumSplitFraction, fraction), maximumSplitFraction)
        var didChange = false
        root = Self.mappingSplits(in: root) { id, axis, current, first, second in
            guard id == splitID else {
                return .split(id: id, axis: axis, fraction: current, first: first, second: second)
            }
            didChange = current != clamped
            return .split(id: id, axis: axis, fraction: clamped, first: first, second: second)
        }
        return didChange
    }

    public func commandContext(
        activeDocumentID: String? = nil,
        source: String? = nil,
        targetPaneID: LunaPaneID? = nil,
        attributes: [String: String] = [:]
    ) -> LunaCommandContext {
        var merged = attributes
        merged[LunaCommandContextAttributeKey.activePaneID] = activePaneID.rawValue
        if let targetPaneID {
            merged[LunaCommandContextAttributeKey.targetPaneID] = targetPaneID.rawValue
        }
        return LunaCommandContext(
            focusedSurface: "luna.pane.\(activePaneID.rawValue)",
            activeDocumentID: activeDocumentID,
            source: source,
            attributes: merged
        )
    }

    private static func clampFractions(
        in node: LunaPaneNode,
        minimum: Double,
        maximum: Double
    ) -> LunaPaneNode {
        switch node {
        case .pane:
            return node
        case .split(let id, let axis, let fraction, let first, let second):
            return .split(
                id: id,
                axis: axis,
                fraction: min(max(minimum, fraction), maximum),
                first: clampFractions(in: first, minimum: minimum, maximum: maximum),
                second: clampFractions(in: second, minimum: minimum, maximum: maximum)
            )
        }
    }

    private static func replacingPane(
        in node: LunaPaneNode,
        paneID: LunaPaneID,
        replacement: (LunaPaneNode) -> LunaPaneNode
    ) -> LunaPaneNode {
        switch node {
        case .pane(let id):
            return id == paneID ? replacement(node) : node
        case .split(let id, let axis, let fraction, let first, let second):
            return .split(
                id: id,
                axis: axis,
                fraction: fraction,
                first: replacingPane(in: first, paneID: paneID, replacement: replacement),
                second: replacingPane(in: second, paneID: paneID, replacement: replacement)
            )
        }
    }

    private static func removingPane(from node: LunaPaneNode, paneID: LunaPaneID) -> LunaPaneNode? {
        switch node {
        case .pane(let id):
            return id == paneID ? nil : node
        case .split(let id, let axis, let fraction, let first, let second):
            let nextFirst = removingPane(from: first, paneID: paneID)
            let nextSecond = removingPane(from: second, paneID: paneID)
            switch (nextFirst, nextSecond) {
            case (nil, nil): return nil
            case (let only?, nil), (nil, let only?): return only
            case (let first?, let second?):
                return .split(id: id, axis: axis, fraction: fraction, first: first, second: second)
            }
        }
    }

    private static func mappingSplits(
        in node: LunaPaneNode,
        transform: (LunaSplitID, LunaSplitAxis, Double, LunaPaneNode, LunaPaneNode) -> LunaPaneNode
    ) -> LunaPaneNode {
        switch node {
        case .pane:
            return node
        case .split(let id, let axis, let fraction, let first, let second):
            return transform(
                id,
                axis,
                fraction,
                mappingSplits(in: first, transform: transform),
                mappingSplits(in: second, transform: transform)
            )
        }
    }
}

// MARK: - Layout

public struct LunaPaneFrame: Hashable, Sendable {
    public var paneID: LunaPaneID
    public var bounds: LunaRectI
    public var nodeID: LunaNodeID

    public init(paneID: LunaPaneID, bounds: LunaRectI, nodeID: LunaNodeID) {
        self.paneID = paneID
        self.bounds = bounds
        self.nodeID = nodeID
    }
}

/// Product-neutral content regions derived from one pane leaf.
///
/// Luna owns the geometry and clipping contract. Applications remain free to
/// place an editor, terminal, preview, or any other surface in `contentBounds`.
public struct LunaPaneContentFrame: Hashable, Sendable {
    public var paneID: LunaPaneID
    public var paneBounds: LunaRectI
    public var headerBounds: LunaRectI
    public var contentBounds: LunaRectI
    public var nodeID: LunaNodeID

    public init(
        paneID: LunaPaneID,
        paneBounds: LunaRectI,
        headerBounds: LunaRectI,
        contentBounds: LunaRectI,
        nodeID: LunaNodeID
    ) {
        self.paneID = paneID
        self.paneBounds = paneBounds
        self.headerBounds = headerBounds
        self.contentBounds = contentBounds
        self.nodeID = nodeID
    }
}

public struct LunaPaneContentMetrics: Hashable, Sendable {
    public var headerHeight: Int
    public var contentInsets: LunaInsetsI

    public init(
        headerHeight: Int = 22,
        contentInsets: LunaInsetsI = LunaInsetsI(top: 0, right: 0, bottom: 0, left: 0)
    ) {
        self.headerHeight = max(0, headerHeight)
        self.contentInsets = contentInsets
    }

    public static let editor = LunaPaneContentMetrics()
}

public struct LunaSplitDividerFrame: Hashable, Sendable {
    public var splitID: LunaSplitID
    public var axis: LunaSplitAxis
    public var bounds: LunaRectI
    public var availableBounds: LunaRectI
    public var nodeID: LunaNodeID

    public init(
        splitID: LunaSplitID,
        axis: LunaSplitAxis,
        bounds: LunaRectI,
        availableBounds: LunaRectI,
        nodeID: LunaNodeID
    ) {
        self.splitID = splitID
        self.axis = axis
        self.bounds = bounds
        self.availableBounds = availableBounds
        self.nodeID = nodeID
    }

    public func fraction(for point: LunaPointI) -> Double {
        switch axis {
        case .horizontal:
            guard availableBounds.w > 0 else { return 0.5 }
            return Double(point.x - availableBounds.x) / Double(availableBounds.w)
        case .vertical:
            guard availableBounds.h > 0 else { return 0.5 }
            return Double(point.y - availableBounds.y) / Double(availableBounds.h)
        }
    }

    /// The visible center rule is intentionally narrower than the full semantic
    /// divider control. The complete `bounds` remain the draw, hit-test, cursor,
    /// drag, accessibility, and pointer-capture region.
    public func centerRuleBounds(thickness: Int) -> LunaRectI {
        let rule = max(1, thickness)
        switch axis {
        case .horizontal:
            let width = min(rule, max(0, bounds.w))
            return LunaRectI(
                x: bounds.x + max(0, (bounds.w - width) / 2),
                y: bounds.y,
                w: width,
                h: bounds.h
            )
        case .vertical:
            let height = min(rule, max(0, bounds.h))
            return LunaRectI(
                x: bounds.x,
                y: bounds.y + max(0, (bounds.h - height) / 2),
                w: bounds.w,
                h: height
            )
        }
    }
}

public struct LunaPaneContainerLayout: Hashable, Sendable {
    public var bounds: LunaRectI
    public var paneFrames: [LunaPaneFrame]
    public var dividerFrames: [LunaSplitDividerFrame]

    public init(
        bounds: LunaRectI,
        paneFrames: [LunaPaneFrame],
        dividerFrames: [LunaSplitDividerFrame]
    ) {
        self.bounds = bounds
        self.paneFrames = paneFrames
        self.dividerFrames = dividerFrames
    }

    public func paneFrame(for paneID: LunaPaneID) -> LunaPaneFrame? {
        paneFrames.first { $0.paneID == paneID }
    }

    public func dividerFrame(for splitID: LunaSplitID) -> LunaSplitDividerFrame? {
        dividerFrames.first { $0.splitID == splitID }
    }

    public func dividerFrame(at point: LunaPointI) -> LunaSplitDividerFrame? {
        dividerFrames.reversed().first { $0.bounds.contains(x: point.x, y: point.y) }
    }

    public func contentFrames(
        metrics: LunaPaneContentMetrics = .editor
    ) -> [LunaPaneContentFrame] {
        paneFrames.map { pane in
            let headerH = min(max(0, metrics.headerHeight), pane.bounds.h)
            let header = LunaRectI(
                x: pane.bounds.x,
                y: pane.bounds.y,
                w: pane.bounds.w,
                h: headerH
            )
            let rawContent = LunaRectI(
                x: pane.bounds.x,
                y: pane.bounds.y + headerH,
                w: pane.bounds.w,
                h: max(0, pane.bounds.h - headerH)
            )
            let insets = metrics.contentInsets
            let content = LunaRectI(
                x: rawContent.x + max(0, insets.left),
                y: rawContent.y + max(0, insets.top),
                w: max(0, rawContent.w - max(0, insets.left) - max(0, insets.right)),
                h: max(0, rawContent.h - max(0, insets.top) - max(0, insets.bottom))
            )
            return LunaPaneContentFrame(
                paneID: pane.paneID,
                paneBounds: pane.bounds,
                headerBounds: header,
                contentBounds: content,
                nodeID: pane.nodeID.child("content")
            )
        }
    }

    public func contentFrame(
        for paneID: LunaPaneID,
        metrics: LunaPaneContentMetrics = .editor
    ) -> LunaPaneContentFrame? {
        contentFrames(metrics: metrics).first { $0.paneID == paneID }
    }

    public func nearestPane(
        from paneID: LunaPaneID,
        direction: LunaPaneTraversalDirection
    ) -> LunaPaneID? {
        guard let source = paneFrame(for: paneID) else { return nil }
        let sourceCenter = source.bounds.center

        let candidates = paneFrames.compactMap { candidate -> (LunaPaneID, Int, Int)? in
            guard candidate.paneID != paneID else { return nil }
            let center = candidate.bounds.center
            let primary: Int
            let secondary: Int
            switch direction {
            case .left:
                guard center.x < sourceCenter.x else { return nil }
                primary = sourceCenter.x - center.x
                secondary = abs(sourceCenter.y - center.y)
            case .right:
                guard center.x > sourceCenter.x else { return nil }
                primary = center.x - sourceCenter.x
                secondary = abs(sourceCenter.y - center.y)
            case .up:
                guard center.y < sourceCenter.y else { return nil }
                primary = sourceCenter.y - center.y
                secondary = abs(sourceCenter.x - center.x)
            case .down:
                guard center.y > sourceCenter.y else { return nil }
                primary = center.y - sourceCenter.y
                secondary = abs(sourceCenter.x - center.x)
            case .next, .previous:
                return nil
            }
            return (candidate.paneID, primary, secondary)
        }

        return candidates.min { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            return lhs.0.rawValue < rhs.0.rawValue
        }?.0
    }
}

public struct LunaPaneContainerMetrics: Hashable, Sendable {
    /// Full semantic divider-control thickness. This is deliberately wider than
    /// the center rule so users do not have to hunt for a single pixel.
    public var dividerThickness: Int
    public var dividerRuleThickness: Int
    public var minimumPaneExtent: Int
    public var activePaneBorderThickness: Int

    public init(
        dividerThickness: Int = 11,
        dividerRuleThickness: Int = 1,
        minimumPaneExtent: Int = 40,
        activePaneBorderThickness: Int = 2
    ) {
        self.dividerThickness = max(3, dividerThickness)
        self.dividerRuleThickness = min(max(1, dividerRuleThickness), self.dividerThickness)
        self.minimumPaneExtent = max(1, minimumPaneExtent)
        self.activePaneBorderThickness = max(0, activePaneBorderThickness)
    }

    public static let demo = LunaPaneContainerMetrics()
}

/// Transient pointer state for one pane container. Applications own the value so
/// it survives reconstruction of Luna's value-semantic widget each frame.
public struct LunaPaneContainerInteractionState: Hashable, Sendable {
    public var hoveredSplitID: LunaSplitID?
    public var draggedSplitID: LunaSplitID?

    public init(
        hoveredSplitID: LunaSplitID? = nil,
        draggedSplitID: LunaSplitID? = nil
    ) {
        self.hoveredSplitID = hoveredSplitID
        self.draggedSplitID = draggedSplitID
    }

    public var isDraggingDivider: Bool { draggedSplitID != nil }
    public var wantsPointerCapture: Bool { isDraggingDivider }

    public mutating func cancelDrag() {
        draggedSplitID = nil
    }
}

public struct LunaPaneContainerInteractionResult: Hashable, Sendable {
    public var didConsumeEvent: Bool
    public var didChangeState: Bool
    public var activatedPaneID: LunaPaneID?
    public var resizedSplitID: LunaSplitID?
    public var hitNodeID: LunaNodeID?

    public init(
        didConsumeEvent: Bool = false,
        didChangeState: Bool = false,
        activatedPaneID: LunaPaneID? = nil,
        resizedSplitID: LunaSplitID? = nil,
        hitNodeID: LunaNodeID? = nil
    ) {
        self.didConsumeEvent = didConsumeEvent
        self.didChangeState = didChangeState
        self.activatedPaneID = activatedPaneID
        self.resizedSplitID = resizedSplitID
        self.hitNodeID = hitNodeID
    }
}

// MARK: - Reusable pane container widget

public struct LunaPaneContainer: LunaWidget, Hashable, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI
    public var state: LunaPaneWorkspaceState
    public var interactionState: LunaPaneContainerInteractionState
    public var theme: LunaTheme
    public var metrics: LunaPaneContainerMetrics

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        state: LunaPaneWorkspaceState,
        interactionState: LunaPaneContainerInteractionState = LunaPaneContainerInteractionState(),
        theme: LunaTheme,
        metrics: LunaPaneContainerMetrics = .demo
    ) {
        self.id = id
        self.bounds = bounds
        self.state = state
        self.interactionState = interactionState
        self.theme = theme
        self.metrics = metrics
    }

    public func layout() -> LunaPaneContainerLayout {
        var panes: [LunaPaneFrame] = []
        var dividers: [LunaSplitDividerFrame] = []

        func append(node: LunaPaneNode, in frame: LunaRectI) {
            switch node {
            case .pane(let paneID):
                panes.append(LunaPaneFrame(paneID: paneID, bounds: frame, nodeID: paneNodeID(paneID)))

            case .split(let splitID, let axis, let fraction, let first, let second):
                let thickness: Int
                let availableExtent: Int
                switch axis {
                case .horizontal:
                    thickness = min(metrics.dividerThickness, max(0, frame.w))
                    availableExtent = max(0, frame.w - thickness)
                    let rawFirst = Int((Double(availableExtent) * fraction).rounded())
                    let firstWidth = clampExtent(rawFirst, total: availableExtent)
                    let secondWidth = max(0, availableExtent - firstWidth)
                    let firstFrame = LunaRectI(x: frame.x, y: frame.y, w: firstWidth, h: frame.h)
                    let divider = LunaRectI(x: frame.x + firstWidth, y: frame.y, w: thickness, h: frame.h)
                    let secondFrame = LunaRectI(x: divider.x + divider.w, y: frame.y, w: secondWidth, h: frame.h)
                    append(node: first, in: firstFrame)
                    dividers.append(LunaSplitDividerFrame(
                        splitID: splitID,
                        axis: axis,
                        bounds: divider,
                        availableBounds: frame,
                        nodeID: dividerNodeID(splitID)
                    ))
                    append(node: second, in: secondFrame)

                case .vertical:
                    thickness = min(metrics.dividerThickness, max(0, frame.h))
                    availableExtent = max(0, frame.h - thickness)
                    let rawFirst = Int((Double(availableExtent) * fraction).rounded())
                    let firstHeight = clampExtent(rawFirst, total: availableExtent)
                    let secondHeight = max(0, availableExtent - firstHeight)
                    let firstFrame = LunaRectI(x: frame.x, y: frame.y, w: frame.w, h: firstHeight)
                    let divider = LunaRectI(x: frame.x, y: frame.y + firstHeight, w: frame.w, h: thickness)
                    let secondFrame = LunaRectI(x: frame.x, y: divider.y + divider.h, w: frame.w, h: secondHeight)
                    append(node: first, in: firstFrame)
                    dividers.append(LunaSplitDividerFrame(
                        splitID: splitID,
                        axis: axis,
                        bounds: divider,
                        availableBounds: frame,
                        nodeID: dividerNodeID(splitID)
                    ))
                    append(node: second, in: secondFrame)
                }
            }
        }

        append(node: state.root, in: bounds)
        return LunaPaneContainerLayout(bounds: bounds, paneFrames: panes, dividerFrames: dividers)
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        let layout = layout()
        let separator = theme.ui.chrome.separator.asRenderColor
        let dividerSurface = theme.ui.editor.background.asRenderColor
        let dividerHover = theme.ui.chrome.menuBarHoveredBackground.asRenderColor
        let active = theme.ui.statusBar.accent.asRenderColor

        for divider in layout.dividerFrames where !divider.bounds.isEmpty {
            let isDragged = interactionState.draggedSplitID == divider.splitID
            let isHovered = interactionState.hoveredSplitID == divider.splitID
            displayList.append(.rect(
                divider.bounds,
                isDragged ? active : (isHovered ? dividerHover : dividerSurface)
            ))
            displayList.append(.rect(
                divider.centerRuleBounds(thickness: metrics.dividerRuleThickness),
                isDragged || isHovered ? active : separator
            ))
        }

        if metrics.activePaneBorderThickness > 0,
           let frame = layout.paneFrame(for: state.activePaneID),
           !frame.bounds.isEmpty {
            appendRectStroke(
                frame.bounds,
                thickness: metrics.activePaneBorderThickness,
                color: active,
                into: &displayList
            )
        }
    }

    public func buildAccessibilityNode() -> LunaAccessibilityNode {
        LunaAccessibilityNode(
            id: id,
            role: .group,
            label: "Pane Container",
            bounds: bounds.asAccessibilityRect,
            children: buildAccessibilityChildren().map(\.id),
            actions: [.focus]
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        let layout = layout()
        let panes = layout.paneFrames.map { frame in
            LunaAccessibilityNode(
                id: frame.nodeID,
                role: .group,
                label: "Pane \(frame.paneID.rawValue)",
                bounds: frame.bounds.asAccessibilityRect,
                isFocused: frame.paneID == state.activePaneID,
                actions: [.focus, .press]
            )
        }
        let dividers = layout.dividerFrames.map { frame in
            LunaAccessibilityNode(
                id: frame.nodeID,
                role: .separator,
                label: frame.axis == .horizontal ? "Vertical split divider" : "Horizontal split divider",
                value: frame.splitID.rawValue,
                bounds: frame.bounds.asAccessibilityRect,
                actions: [.focus]
            )
        }
        return panes + dividers
    }

    public func hitTest(_ point: LunaPointI) -> LunaNodeID? {
        let layout = layout()
        if let divider = layout.dividerFrame(at: point) {
            return divider.nodeID
        }
        if let pane = layout.paneFrames.reversed().first(where: { $0.bounds.contains(x: point.x, y: point.y) }) {
            return pane.nodeID
        }
        return bounds.contains(x: point.x, y: point.y) ? id : nil
    }

    public func cursorIntent(at point: LunaPointI) -> LunaCursorIntent? {
        let layout = layout()
        let divider = interactionState.draggedSplitID.flatMap { layout.dividerFrame(for: $0) }
            ?? layout.dividerFrame(at: point)
        guard let divider else { return nil }
        return divider.axis == .horizontal ? .resizeHorizontal : .resizeVertical
    }

    public var wantsPointerCapture: Bool { interactionState.wantsPointerCapture }

    /// Backward-compatible stateless entry point retained for callers that only
    /// need press activation. New interactive consumers should preserve the
    /// explicit interaction state using the overload below.
    public func handlePointerEvent(
        _ event: LunaPointerEvent,
        state mutableState: inout LunaPaneWorkspaceState
    ) -> LunaPaneContainerInteractionResult {
        var transient = LunaPaneContainerInteractionState()
        return handlePointerEvent(event, state: &mutableState, interactionState: &transient)
    }

    public func handlePointerEvent(
        _ event: LunaPointerEvent,
        state mutableState: inout LunaPaneWorkspaceState,
        interactionState mutableInteraction: inout LunaPaneContainerInteractionState
    ) -> LunaPaneContainerInteractionResult {
        let layout = layout()
        let hoveredDivider = layout.dividerFrame(at: event.location)
        let previousHover = mutableInteraction.hoveredSplitID
        mutableInteraction.hoveredSplitID = hoveredDivider?.splitID

        if event.phase == .moved,
           let splitID = mutableInteraction.draggedSplitID,
           let divider = layout.dividerFrame(for: splitID) {
            mutableInteraction.hoveredSplitID = splitID
            let changed = mutableState.setSplitFraction(
                divider.fraction(for: event.location),
                for: splitID
            )
            return LunaPaneContainerInteractionResult(
                didConsumeEvent: true,
                didChangeState: changed || previousHover != mutableInteraction.hoveredSplitID,
                resizedSplitID: splitID,
                hitNodeID: divider.nodeID
            )
        }

        if event.phase == .up, let splitID = mutableInteraction.draggedSplitID {
            let divider = layout.dividerFrame(for: splitID)
            mutableInteraction.draggedSplitID = nil
            return LunaPaneContainerInteractionResult(
                didConsumeEvent: true,
                didChangeState: true,
                resizedSplitID: splitID,
                hitNodeID: divider?.nodeID
            )
        }

        guard event.button == .primary || event.phase == .moved else {
            return LunaPaneContainerInteractionResult(
                didConsumeEvent: hoveredDivider != nil,
                didChangeState: previousHover != mutableInteraction.hoveredSplitID,
                hitNodeID: hoveredDivider?.nodeID
            )
        }

        if event.phase == .down, let divider = hoveredDivider {
            mutableInteraction.draggedSplitID = divider.splitID
            mutableInteraction.hoveredSplitID = divider.splitID
            _ = mutableState.setSplitFraction(
                divider.fraction(for: event.location),
                for: divider.splitID
            )
            return LunaPaneContainerInteractionResult(
                didConsumeEvent: true,
                didChangeState: true,
                resizedSplitID: divider.splitID,
                hitNodeID: divider.nodeID
            )
        }

        if event.phase == .down,
           let pane = layout.paneFrames.first(where: { $0.bounds.contains(x: event.location.x, y: event.location.y) }) {
            let changed = mutableState.activate(pane.paneID)
            return LunaPaneContainerInteractionResult(
                didConsumeEvent: true,
                didChangeState: changed,
                activatedPaneID: pane.paneID,
                hitNodeID: pane.nodeID
            )
        }

        return LunaPaneContainerInteractionResult(
            didConsumeEvent: hoveredDivider != nil,
            didChangeState: previousHover != mutableInteraction.hoveredSplitID,
            hitNodeID: hoveredDivider?.nodeID
        )
    }

    public func paneNodeID(_ paneID: LunaPaneID) -> LunaNodeID {
        id.child("pane").child(stableComponent(paneID.rawValue))
    }

    public func dividerNodeID(_ splitID: LunaSplitID) -> LunaNodeID {
        id.child("split-divider").child(stableComponent(splitID.rawValue))
    }

    private func clampExtent(_ proposed: Int, total: Int) -> Int {
        guard total >= metrics.minimumPaneExtent * 2 else {
            return min(max(0, proposed), total)
        }
        return min(max(metrics.minimumPaneExtent, proposed), total - metrics.minimumPaneExtent)
    }

    private func appendRectStroke(
        _ rect: LunaRectI,
        thickness: Int,
        color: LunaRender.LunaRGBA8,
        into displayList: inout LunaDisplayList
    ) {
        guard thickness > 0, rect.w > 0, rect.h > 0 else { return }
        let t = min(thickness, max(1, min(rect.w, rect.h)))
        displayList.append(.rect(LunaRectI(x: rect.x, y: rect.y, w: rect.w, h: t), color))
        displayList.append(.rect(LunaRectI(x: rect.x, y: rect.y + rect.h - t, w: rect.w, h: t), color))
        displayList.append(.rect(LunaRectI(x: rect.x, y: rect.y, w: t, h: rect.h), color))
        displayList.append(.rect(LunaRectI(x: rect.x + rect.w - t, y: rect.y, w: t, h: rect.h), color))
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

private extension LunaRectI {
    var center: LunaPointI {
        LunaPointI(x: x + w / 2, y: y + h / 2)
    }
}
