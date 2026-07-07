// LunaAccessibility.swift
//
// Accessibility model shared by Luna widgets and platform bridges.
//
// This target intentionally does NOT import AppKit, UIKit, GTK, AccessKit, or
// any renderer module. Platform bridges translate this pure Swift tree into the
// host accessibility API later.

import Foundation
import LunaCore

// MARK: - Geometry

/// Accessibility bounds in logical pixel coordinates.
///
/// This duplicates only the small rectangle shape accessibility needs so this
/// module can stay independent from LunaRender. LunaUI is responsible for
/// converting renderer/widget rectangles into this type.
public struct LunaAccessibilityRect: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public static let zero = LunaAccessibilityRect(x: 0, y: 0, width: 0, height: 0)

    public func contains(_ point: LunaPointI) -> Bool {
        point.x >= x && point.y >= y && point.x < x + width && point.y < y + height
    }
}

// MARK: - Roles and actions

/// Semantic role for an accessibility node.
public enum LunaAccessibilityRole: Hashable, Sendable {
    case application
    case window
    case group
    case menuBar
    case menu
    case menuItem
    case button
    case toggleButton
    case textArea
    case textRun
    case list
    case listItem
    case dialog
    case status
    case liveRegion
    case scrollbar
    case separator
    case image
    case custom(String)
}

/// User-facing accessibility action.
public struct LunaAccessibilityAction: Hashable, Sendable {
    public var name: String
    public var label: String

    public init(name: String, label: String) {
        precondition(!name.isEmpty, "Accessibility action name cannot be empty")
        self.name = name
        self.label = label
    }

    public static let press = LunaAccessibilityAction(name: "press", label: "Press")
    public static let focus = LunaAccessibilityAction(name: "focus", label: "Focus")
    public static let increment = LunaAccessibilityAction(name: "increment", label: "Increment")
    public static let decrement = LunaAccessibilityAction(name: "decrement", label: "Decrement")
}

/// Text range expressed in UTF-8 byte offsets for future editor-buffer stability.
/// Moth can map this to rope/piece-table coordinates rather than Swift `String`
/// character indices.
public struct LunaAccessibilityTextRange: Hashable, Sendable {
    public var utf8Offset: Int
    public var utf8Length: Int

    public init(utf8Offset: Int, utf8Length: Int) {
        self.utf8Offset = max(0, utf8Offset)
        self.utf8Length = max(0, utf8Length)
    }
}

// MARK: - Node and tree

/// Pure semantic description of a visible or interactive UI element.
public struct LunaAccessibilityNode: Hashable, Sendable {
    public var id: LunaNodeID
    public var role: LunaAccessibilityRole
    public var label: String?
    public var value: String?
    public var bounds: LunaAccessibilityRect
    public var isEnabled: Bool
    public var isFocused: Bool
    public var children: [LunaNodeID]
    public var actions: [LunaAccessibilityAction]
    public var textRange: LunaAccessibilityTextRange?

    public init(
        id: LunaNodeID,
        role: LunaAccessibilityRole,
        label: String? = nil,
        value: String? = nil,
        bounds: LunaAccessibilityRect = .zero,
        isEnabled: Bool = true,
        isFocused: Bool = false,
        children: [LunaNodeID] = [],
        actions: [LunaAccessibilityAction] = [],
        textRange: LunaAccessibilityTextRange? = nil
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.value = value
        self.bounds = bounds
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.children = children
        self.actions = actions
        self.textRange = textRange
    }
}

/// Snapshot of the accessibility tree for the current UI frame/state.
public struct LunaAccessibilityTree: Sendable {
    public var rootID: LunaNodeID
    public var nodes: [LunaNodeID: LunaAccessibilityNode]

    public init(rootID: LunaNodeID, nodes: [LunaNodeID: LunaAccessibilityNode]) {
        self.rootID = rootID
        self.nodes = nodes
    }

    public subscript(id: LunaNodeID) -> LunaAccessibilityNode? {
        nodes[id]
    }

    /// Basic structural validation. Platform bridges can refuse to publish a
    /// broken tree and surface these messages in debug overlays.
    public func validate() -> LunaDiagnostics {
        var diagnostics = LunaDiagnostics()

        if nodes[rootID] == nil {
            diagnostics.error("Accessibility root node is missing: \(rootID.rawValue)")
        }

        for node in nodes.values {
            for childID in node.children where nodes[childID] == nil {
                diagnostics.error("Accessibility node \(node.id.rawValue) references missing child \(childID.rawValue)")
            }

            if node.label == nil && node.value == nil {
                switch node.role {
                case .button, .toggleButton, .menuItem, .listItem, .textRun, .status, .liveRegion:
                    diagnostics.warn("Accessibility node \(node.id.rawValue) has no label or value")
                default:
                    break
                }
            }
        }

        return diagnostics
    }
}

// MARK: - Live announcements

public enum LunaAccessibilityPoliteness: Hashable, Sendable {
    case polite
    case assertive
}

/// A transient announcement such as "Saved main.swift" or "No matches".
public struct LunaLiveAnnouncement: Hashable, Sendable {
    public var text: String
    public var politeness: LunaAccessibilityPoliteness

    public init(_ text: String, politeness: LunaAccessibilityPoliteness = .polite) {
        self.text = text
        self.politeness = politeness
    }
}

public struct LunaAccessibilityModule {
    public init() {}
}
