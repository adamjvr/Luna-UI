// LunaSDLInputTranslator.swift
//
// Phase 2C: SDL input stays inside LunaHostSDL. Demo apps and future editor code
// consume LunaHostInputEvent / LunaPointerEvent / LunaKeyboardEvent instead of
// decoding SDL keycodes, mouse buttons, or window event constants directly.

#if os(Linux)

import SDL2
import LunaCore
import LunaInput

public struct LunaSDLInputTranslator {
    public init() {}

    /// Poll all queued SDL events and return platform-neutral Luna events.
    public mutating func pollEvents() -> [LunaHostInputEvent] {
        var translated: [LunaHostInputEvent] = []
        var event = SDL_Event()
        while SDL_PollEvent(&event) != 0 {
            if let value = translate(event) {
                translated.append(value)
            }
        }
        return translated
    }

    /// Translate a single SDL event into a platform-neutral Luna event.
    public func translate(_ event: SDL_Event) -> LunaHostInputEvent? {
        switch SDL_EventType(rawValue: event.type) {
        case SDL_QUIT:
            return .quit

        case SDL_WINDOWEVENT:
            if event.window.event == UInt8(SDL_WINDOWEVENT_SIZE_CHANGED.rawValue) {
                return .windowResized(
                    LunaSizeI(
                        width: max(1, Int(event.window.data1)),
                        height: max(1, Int(event.window.data2))
                    )
                )
            }
            return nil

        case SDL_MOUSEMOTION:
            return .pointer(
                LunaPointerEvent(
                    phase: .moved,
                    location: LunaPointI(x: Int(event.motion.x), y: Int(event.motion.y)),
                    button: .primary,
                    clickCount: 0
                )
            )

        case SDL_MOUSEBUTTONDOWN:
            return .pointer(
                LunaPointerEvent(
                    phase: .down,
                    location: LunaPointI(x: Int(event.button.x), y: Int(event.button.y)),
                    button: translateMouseButton(event.button.button),
                    clickCount: Int(event.button.clicks)
                )
            )

        case SDL_MOUSEBUTTONUP:
            return .pointer(
                LunaPointerEvent(
                    phase: .up,
                    location: LunaPointI(x: Int(event.button.x), y: Int(event.button.y)),
                    button: translateMouseButton(event.button.button),
                    clickCount: Int(event.button.clicks)
                )
            )

        case SDL_KEYDOWN:
            guard let key = translateKey(event.key.keysym.sym) else { return nil }
            return .keyboard(
                LunaKeyboardEvent(
                    key: key,
                    modifiers: translateModifiers(event.key.keysym.mod),
                    isRepeat: event.key.repeat != 0
                )
            )

        case SDL_TEXTINPUT:
            let text = translateTextInput(event.text)
            guard !text.isEmpty else { return nil }
            return .textInput(LunaTextInputEvent(text: text))

        default:
            return nil
        }
    }

    public func translateMouseButton(_ button: UInt8) -> LunaPointerButton {
        switch button {
        case 1: return .primary
        case 2: return .middle
        case 3: return .secondary
        default: return .other(Int(button))
        }
    }

    /// Translate SDL modifier bits into Luna's platform-neutral modifier set.
    ///
    /// Swift/SDL bindings are inconsistent across versions here: `SDL_GetModState()`
    /// and the `KMOD_*` constants may appear as the typed `SDL_Keymod`, while
    /// `SDL_Keysym.mod` is imported on Linux as the raw `Uint16` field used by
    /// SDL's C struct. Keep that mismatch inside LunaHostSDL by accepting the raw
    /// bits from events and normalizing them before app/demo code ever sees them.
    public func translateModifiers(_ rawModifiers: UInt16) -> LunaKeyboardModifiers {
        translateModifierBits(UInt32(rawModifiers))
    }

    public func translateModifiers(_ rawModifiers: SDL_Keymod) -> LunaKeyboardModifiers {
        translateModifierBits(UInt32(rawModifiers.rawValue))
    }

    private func translateModifierBits(_ mods: UInt32) -> LunaKeyboardModifiers {
        let shiftMask = UInt32(KMOD_LSHIFT.rawValue) | UInt32(KMOD_RSHIFT.rawValue)
        let controlMask = UInt32(KMOD_LCTRL.rawValue) | UInt32(KMOD_RCTRL.rawValue)
        let optionMask = UInt32(KMOD_LALT.rawValue) | UInt32(KMOD_RALT.rawValue)
        let commandMask = UInt32(KMOD_LGUI.rawValue) | UInt32(KMOD_RGUI.rawValue)
        return LunaKeyboardModifiers(
            shift: (mods & shiftMask) != 0,
            control: (mods & controlMask) != 0,
            option: (mods & optionMask) != 0,
            command: (mods & commandMask) != 0
        )
    }

    public func translateTextInput(_ textEvent: SDL_TextInputEvent) -> String {
        withUnsafeBytes(of: textEvent.text) { rawBuffer in
            let bytes = rawBuffer.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    public func translateKey(_ rawSDLKeycode: SDL_Keycode) -> LunaKeyboardKey? {
        // Swift 6.2 imports SDL key constants as typed SDL_KeyCode values whose
        // rawValue is UInt32, while SDL_Keysym.sym is the raw Int32 alias.
        // Normalize at the host boundary so no app/demo/widget code touches this.
        let symRaw = UInt32(bitPattern: rawSDLKeycode)
        switch symRaw {
        case SDLK_RETURN.rawValue, SDLK_KP_ENTER.rawValue:
            return .enter
        case SDLK_ESCAPE.rawValue:
            return .escape
        case SDLK_TAB.rawValue:
            return .tab
        case SDLK_SPACE.rawValue:
            return .space
        case SDLK_UP.rawValue:
            return .arrowUp
        case SDLK_DOWN.rawValue:
            return .arrowDown
        case SDLK_LEFT.rawValue:
            return .arrowLeft
        case SDLK_RIGHT.rawValue:
            return .arrowRight
        case SDLK_PAGEUP.rawValue:
            return .pageUp
        case SDLK_PAGEDOWN.rawValue:
            return .pageDown
        case SDLK_HOME.rawValue:
            return .home
        case SDLK_END.rawValue:
            return .end
        case SDLK_BACKSPACE.rawValue:
            return .backspace
        case SDLK_DELETE.rawValue:
            return .delete
        case SDLK_1.rawValue:
            return .number(1)
        case SDLK_2.rawValue:
            return .number(2)
        case SDLK_3.rawValue:
            return .number(3)
        default:
            return nil
        }
    }
}

#endif
