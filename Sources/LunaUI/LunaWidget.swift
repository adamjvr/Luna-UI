// SPDX-License-Identifier: MPL-2.0
// LunaWidget.swift
//
// HybX-inspired widget contract: anything Luna can draw should also be able to
// describe itself semantically for hit testing and accessibility.

import Foundation
import LunaAccessibility
import LunaCore
import LunaRender

public protocol LunaWidget {
    /// Stable semantic ID. The same visible control should keep the same ID
    /// across frames so focus/accessibility state can remain stable.
    var id: LunaNodeID { get }

    /// Current widget bounds in logical pixel coordinates.
    var bounds: LunaRectI { get }

    /// Append backend-neutral draw commands.
    func buildDisplayList(into displayList: inout LunaDisplayList)

    /// Build the accessibility node for this widget.
    func buildAccessibilityNode() -> LunaAccessibilityNode

    /// Build child accessibility nodes if this widget owns semantic children.
    func buildAccessibilityChildren() -> [LunaAccessibilityNode]

    /// Return the deepest semantic node hit by a point, if any.
    func hitTest(_ point: LunaPointI) -> LunaNodeID?
}

public extension LunaWidget {
    func buildAccessibilityChildren() -> [LunaAccessibilityNode] { [] }

    func hitTest(_ point: LunaPointI) -> LunaNodeID? {
        bounds.asAccessibilityRect.contains(point) ? id : nil
    }
}

public extension LunaRectI {
    var asAccessibilityRect: LunaAccessibilityRect {
        LunaAccessibilityRect(x: x, y: y, width: w, height: h)
    }
}
