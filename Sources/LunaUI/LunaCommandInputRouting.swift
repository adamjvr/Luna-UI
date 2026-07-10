// LunaCommandInputRouting.swift
//
// LunaUI adapter between platform-neutral LunaInput keyboard events and the
// product-neutral command keymap model in LunaCommands.

import Foundation
import LunaCommands
import LunaInput

public extension LunaKeyboardEvent {
    var lunaCommandKeyStroke: LunaKeyStroke {
        LunaKeyStroke(lunaCommandKeyName, modifiers: modifiers.lunaCommandModifiers)
    }

    /// One-shot text-input suppression hint for shortcut chords that may also
    /// generate a committed text event on some host/input stacks.
    var lunaShortcutTextInputSuppressionCandidate: String? {
        switch key {
        case .other(let value):
            return value.count == 1 ? value.lowercased() : nil
        case .number(let value):
            return String(value)
        default:
            return nil
        }
    }

    private var lunaCommandKeyName: String {
        switch key {
        case .enter: return "Enter"
        case .escape: return "Escape"
        case .tab: return "Tab"
        case .space: return "Space"
        case .arrowUp: return "ArrowUp"
        case .arrowDown: return "ArrowDown"
        case .arrowLeft: return "ArrowLeft"
        case .arrowRight: return "ArrowRight"
        case .pageUp: return "PageUp"
        case .pageDown: return "PageDown"
        case .home: return "Home"
        case .end: return "End"
        case .backspace: return "Backspace"
        case .delete: return "Delete"
        case .number(let value): return String(value)
        case .other(let value): return value
        }
    }
}

public extension LunaKeyboardModifiers {
    var lunaCommandModifiers: Set<LunaKeyModifier> {
        var result: Set<LunaKeyModifier> = []
        if shift { result.insert(.shift) }
        if control { result.insert(.control) }
        if command { result.insert(.command) }
        if option {
            result.insert(.option)
            result.insert(.alt)
        }
        return result
    }
}
