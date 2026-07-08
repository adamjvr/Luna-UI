// LunaCommands.swift
//
// Command metadata shared by menus, keymaps, command palettes, tests, and
// accessibility actions. Luna owns the command vocabulary shape; apps such as
// Applications own the actual handlers/policy.

import Foundation
import LunaCore

public struct LunaCommandID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LunaCommandID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

public enum LunaKeyModifier: String, Hashable, Sendable, CaseIterable {
    /// User's primary menu accelerator: Command on macOS, Control on Linux/Windows.
    case primary

    /// Explicit platform keys for cases where primary is not precise enough.
    case command
    case control
    case option
    case alt
    case shift
    case `super`
}

/// Platform-neutral key equivalent. Host layers translate `primary` to Command
/// on macOS and usually Control on Linux/Windows policy if desired.
public struct LunaKeyEquivalent: Hashable, Sendable {
    public var key: String
    public var modifiers: Set<LunaKeyModifier>

    public init(_ key: String, modifiers: Set<LunaKeyModifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// Command metadata. This is intentionally handler-free so LunaCommands does not
/// depend on LunaUI or any application layer.
public struct LunaCommandDescriptor: Hashable, Sendable {
    public var id: LunaCommandID
    public var title: String
    public var defaultKey: LunaKeyEquivalent?
    public var menuPath: [String]
    public var isPaletteVisible: Bool
    public var accessibilityLabel: String

    public init(
        id: LunaCommandID,
        title: String,
        defaultKey: LunaKeyEquivalent? = nil,
        menuPath: [String] = [],
        isPaletteVisible: Bool = true,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.defaultKey = defaultKey
        self.menuPath = menuPath
        self.isPaletteVisible = isPaletteVisible
        self.accessibilityLabel = accessibilityLabel ?? title
    }
}

/// Small typed registry used by Luna menus/palettes and app command tables.
public struct LunaCommandRegistry: Sendable {
    private var descriptorsByID: [LunaCommandID: LunaCommandDescriptor] = [:]
    private var insertionOrder: [LunaCommandID] = []

    public init() {}

    public var all: [LunaCommandDescriptor] {
        insertionOrder.compactMap { descriptorsByID[$0] }
    }

    public var paletteVisible: [LunaCommandDescriptor] {
        all.filter(\.isPaletteVisible)
    }

    public mutating func register(_ descriptor: LunaCommandDescriptor) {
        if descriptorsByID[descriptor.id] == nil {
            insertionOrder.append(descriptor.id)
        }
        descriptorsByID[descriptor.id] = descriptor
    }

    public mutating func register(contentsOf descriptors: some Sequence<LunaCommandDescriptor>) {
        for descriptor in descriptors {
            register(descriptor)
        }
    }

    public func descriptor(for id: LunaCommandID) -> LunaCommandDescriptor? {
        descriptorsByID[id]
    }

    public func contains(_ id: LunaCommandID) -> Bool {
        descriptorsByID[id] != nil
    }
}

public struct LunaCommandsModule {
    public init() {}
}
