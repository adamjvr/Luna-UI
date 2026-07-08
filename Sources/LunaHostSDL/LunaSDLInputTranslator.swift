// LunaSDLInputTranslator.swift
//
// Phase 2C: SDL input stays inside LunaHostSDL. Demo apps and future Moth code
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
                    modifiers: .none,
                    isRepeat: event.key.repeat != 0
                )
            )

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
        default:
            return nil
        }
    }
}

#endif
