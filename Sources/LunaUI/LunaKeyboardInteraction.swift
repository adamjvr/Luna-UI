// LunaKeyboardInteraction.swift
//
// Phase 2B: platform-neutral keyboard events for modal/overlay routing.

import Foundation

public enum LunaKeyboardKey: Hashable, Sendable {
    case enter
    case escape
    case tab
    case space
    case other(String)
}

public struct LunaKeyboardModifiers: Hashable, Sendable {
    public var shift: Bool
    public var control: Bool
    public var option: Bool
    public var command: Bool

    public init(
        shift: Bool = false,
        control: Bool = false,
        option: Bool = false,
        command: Bool = false
    ) {
        self.shift = shift
        self.control = control
        self.option = option
        self.command = command
    }

    public static let none = LunaKeyboardModifiers()
}

public struct LunaKeyboardEvent: Hashable, Sendable {
    public var key: LunaKeyboardKey
    public var modifiers: LunaKeyboardModifiers
    public var isRepeat: Bool

    public init(
        key: LunaKeyboardKey,
        modifiers: LunaKeyboardModifiers = .none,
        isRepeat: Bool = false
    ) {
        self.key = key
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}
