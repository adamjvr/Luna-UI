// SPDX-License-Identifier: MPL-2.0
// LunaCore.swift
//
// Foundation-level value types shared by the rest of Luna-UI.
//
// Architectural rule:
// LunaCore must stay pure Swift and must not import renderer, platform, text,
// accessibility, or host modules. Everything else may depend on LunaCore.

import Foundation

/// Stable semantic identity for anything Luna can draw, hit-test, focus, or
/// expose to accessibility.
public struct LunaNodeID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaNodeID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }

    /// Convenience builder for hierarchical IDs such as
    /// `editor.line.42` or `command-palette.item.7`.
    public func child(_ component: some CustomStringConvertible) -> LunaNodeID {
        LunaNodeID(rawValue: "\(rawValue).\(component)")
    }
}

/// Integer point in Luna's logical pixel coordinate system.
public struct LunaPointI: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Integer size in logical pixels.
public struct LunaSizeI: Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Integer edge insets in logical pixels.
public struct LunaInsetsI: Hashable, Sendable {
    public var top: Int
    public var right: Int
    public var bottom: Int
    public var left: Int

    public init(top: Int, right: Int, bottom: Int, left: Int) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public init(_ value: Int) {
        self.init(top: value, right: value, bottom: value, left: value)
    }
}

/// Tiny diagnostics collector used by architecture layers that should not know
/// about logging frameworks yet.
public struct LunaDiagnostics: Sendable {
    public private(set) var warnings: [String] = []
    public private(set) var errors: [String] = []

    public init() {}

    public mutating func warn(_ message: String) {
        warnings.append(message)
    }

    public mutating func error(_ message: String) {
        errors.append(message)
    }

    public var isClean: Bool {
        warnings.isEmpty && errors.isEmpty
    }
}

/// LunaCore root module marker.
public struct LunaCoreModule {
    public init() {}
}
