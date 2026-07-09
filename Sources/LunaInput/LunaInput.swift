// LunaInput.swift
//
// Platform-neutral input events for Luna. Host layers translate SDL/AppKit/etc.
// into these values; widgets, overlays, demos, and future applications never need
// to decode platform keycodes or mouse button constants directly.

import Foundation
import LunaCore

public struct LunaInputModule {
    public init() {}
}

// MARK: - Pointer input

public enum LunaPointerButton: Hashable, Sendable {
    case primary
    case secondary
    case middle
    case other(Int)
}

public enum LunaPointerPhase: Hashable, Sendable {
    case down
    case up
    case moved
}

public struct LunaPointerEvent: Hashable, Sendable {
    public var phase: LunaPointerPhase
    public var location: LunaPointI
    public var button: LunaPointerButton
    public var clickCount: Int

    public init(
        phase: LunaPointerPhase,
        location: LunaPointI,
        button: LunaPointerButton = .primary,
        clickCount: Int = 1
    ) {
        self.phase = phase
        self.location = location
        self.button = button
        self.clickCount = max(0, clickCount)
    }
}

// MARK: - Keyboard input

public enum LunaKeyboardKey: Hashable, Sendable {
    case enter
    case escape
    case tab
    case space
    case arrowUp
    case arrowDown
    case pageUp
    case pageDown
    case home
    case end
    case number(Int)
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

// MARK: - Host-level events

public enum LunaHostInputEvent: Hashable, Sendable {
    case quit
    case windowResized(LunaSizeI)
    case pointer(LunaPointerEvent)
    case keyboard(LunaKeyboardEvent)
}
