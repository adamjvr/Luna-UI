// SPDX-License-Identifier: MPL-2.0
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

    /// Keyboard modifiers active at the time of the pointer event.
    ///
    /// Luna keeps this on the platform-neutral pointer event so widgets and apps
    /// can implement standard editor gestures such as Shift-click selection
    /// extension without decoding host-specific modifier masks above LunaHostSDL
    /// / LunaHostMetal.
    public var modifiers: LunaKeyboardModifiers

    public init(
        phase: LunaPointerPhase,
        location: LunaPointI,
        button: LunaPointerButton = .primary,
        clickCount: Int = 1,
        modifiers: LunaKeyboardModifiers = .none
    ) {
        self.phase = phase
        self.location = location
        self.button = button
        self.clickCount = max(0, clickCount)
        self.modifiers = modifiers
    }
}

// MARK: - Scroll input

public enum LunaScrollPhase: Hashable, Sendable {
    case began
    case changed
    case ended
    case momentum
}

/// Platform-neutral two-axis scroll input.
///
/// Positive `deltaY` requests movement toward later document rows; negative
/// values request movement toward earlier rows. Precise devices may emit
/// fractional deltas, which product view state can accumulate without loss.
public struct LunaScrollEvent: Hashable, Sendable {
    public var location: LunaPointI
    public var deltaX: Double
    public var deltaY: Double
    public var phase: LunaScrollPhase
    public var isPrecise: Bool
    public var modifiers: LunaKeyboardModifiers

    public init(
        location: LunaPointI,
        deltaX: Double = 0,
        deltaY: Double,
        phase: LunaScrollPhase = .changed,
        isPrecise: Bool = false,
        modifiers: LunaKeyboardModifiers = .none
    ) {
        self.location = location
        self.deltaX = deltaX.isFinite ? deltaX : 0
        self.deltaY = deltaY.isFinite ? deltaY : 0
        self.phase = phase
        self.isPrecise = isPrecise
        self.modifiers = modifiers
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
    case arrowLeft
    case arrowRight
    case pageUp
    case pageDown
    case home
    case end
    case backspace
    case delete
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

// MARK: - Text input

/// Platform-neutral committed text input.
///
/// Key events represent physical/special keys. Text input represents the text
/// the host text system actually committed after keyboard layout, dead keys,
/// and future IME/composition handling. Phase 3D consumes this for editable text
/// insertion instead of trying to infer printable characters from keycodes.
public struct LunaTextInputEvent: Hashable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

// MARK: - Host-level events

public enum LunaHostInputEvent: Hashable, Sendable {
    case quit
    case windowResized(LunaSizeI)
    /// The native host lost pointer-drag ownership, usually because the window
    /// lost focus. Scenes must cancel any active capture gesture immediately.
    case pointerCaptureLost
    case pointer(LunaPointerEvent)
    case scroll(LunaScrollEvent)
    case keyboard(LunaKeyboardEvent)
    case textInput(LunaTextInputEvent)
}
