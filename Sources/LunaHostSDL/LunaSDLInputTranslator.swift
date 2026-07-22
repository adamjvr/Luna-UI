// SPDX-License-Identifier: MPL-2.0
// LunaSDLInputTranslator.swift
//
// Phase 2C: SDL input stays inside LunaHostSDL. Demo apps and future editor code
// consume LunaHostInputEvent / LunaPointerEvent / LunaKeyboardEvent instead of
// decoding SDL keycodes, mouse buttons, or window event constants directly.

#if os(Linux)

import SDL2
import LunaCore
import LunaHostCore
import LunaInput

public struct LunaSDLInputTranslator {
    public init() {}

    /// Poll queued SDL events within a frame-fair budget.
    ///
    /// Sustained text input and key repeat must not keep the host inside SDL's
    /// queue until presentation is starved. Reaching either limit is reported as
    /// a conservative backlog signal; the application runner renders the current
    /// state, skips any additional sleep, and resumes polling on the next loop.
    public mutating func pollEvents(
        budget: LunaInputPollingBudget = .interactive,
        nowNanoseconds: () -> UInt64 = LunaMonotonicClock.nowNanoseconds
    ) -> LunaPolledInputBatch {
        let startedAt = nowNanoseconds()
        var translated: [LunaHostInputEvent] = []
        translated.reserveCapacity(min(32, budget.maximumRawEventCount))
        var rawEventCount = 0
        var didReachEventLimit = false
        var didReachTimeLimit = false
        var event = SDL_Event()

        while true {
            let now = nowNanoseconds()
            let elapsed = now >= startedAt ? now - startedAt : 0
            guard budget.permitsAnotherEvent(
                afterProcessing: rawEventCount,
                elapsedNanoseconds: elapsed
            ) else {
                didReachEventLimit = rawEventCount >= budget.maximumRawEventCount
                didReachTimeLimit = elapsed >= budget.maximumPollingNanoseconds
                break
            }

            guard SDL_PollEvent(&event) != 0 else { break }
            rawEventCount += 1
            if let value = translate(event) {
                translated.append(value)
            }
        }

        let finishedAt = nowNanoseconds()
        return LunaPolledInputBatch(
            events: translated,
            stats: LunaInputPollingStats(
                rawEventCount: rawEventCount,
                translatedEventCount: translated.count,
                pollingNanoseconds: finishedAt >= startedAt ? finishedAt - startedAt : 0,
                didReachEventLimit: didReachEventLimit,
                didReachTimeLimit: didReachTimeLimit
            )
        )
    }

    /// Compatibility convenience for callers that intentionally want one
    /// interactive-budget batch rather than an unbounded queue drain.
    public mutating func pollEvents() -> [LunaHostInputEvent] {
        pollEvents(budget: .interactive).events
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
            if event.window.event == UInt8(SDL_WINDOWEVENT_FOCUS_LOST.rawValue) {
                return .pointerCaptureLost
            }
            return nil

        case SDL_MOUSEMOTION:
            return .pointer(
                LunaPointerEvent(
                    phase: .moved,
                    location: LunaPointI(x: Int(event.motion.x), y: Int(event.motion.y)),
                    button: .primary,
                    clickCount: 0,
                    modifiers: translateCurrentModifiers()
                )
            )

        case SDL_MOUSEBUTTONDOWN:
            return .pointer(
                LunaPointerEvent(
                    phase: .down,
                    location: LunaPointI(x: Int(event.button.x), y: Int(event.button.y)),
                    button: translateMouseButton(event.button.button),
                    clickCount: Int(event.button.clicks),
                    modifiers: translateCurrentModifiers()
                )
            )

        case SDL_MOUSEBUTTONUP:
            return .pointer(
                LunaPointerEvent(
                    phase: .up,
                    location: LunaPointI(x: Int(event.button.x), y: Int(event.button.y)),
                    button: translateMouseButton(event.button.button),
                    clickCount: Int(event.button.clicks),
                    modifiers: translateCurrentModifiers()
                )
            )

        case SDL_MOUSEWHEEL:
            var mouseX: Int32 = 0
            var mouseY: Int32 = 0
            _ = SDL_GetMouseState(&mouseX, &mouseY)

            return .scroll(
                translateScrollWheel(
                    integerX: Int(event.wheel.x),
                    integerY: Int(event.wheel.y),
                    preciseX: Double(event.wheel.preciseX),
                    preciseY: Double(event.wheel.preciseY),
                    isFlipped: event.wheel.direction == UInt32(SDL_MOUSEWHEEL_FLIPPED.rawValue),
                    location: LunaPointI(x: Int(mouseX), y: Int(mouseY)),
                    modifiers: translateCurrentModifiers()
                )
            )

        case SDL_KEYDOWN:
            guard let key = translateKey(event.key.keysym.sym) else { return nil }
            let modifiers = translateModifiers(event.key.keysym.mod)

            // Committed text comes from SDL_TEXTINPUT, not printable keycodes.
            // Dropping plain printable key-down events avoids an otherwise
            // meaningless barrier between adjacent text events, allowing the host
            // coalescer to apply rapid typing as one ordered document transaction.
            // Command-modified key events remain visible for shortcuts.
            guard shouldForwardKeyboardEvent(key: key, modifiers: modifiers) else {
                return nil
            }
            return .keyboard(
                LunaKeyboardEvent(
                    key: key,
                    modifiers: modifiers,
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


    /// Normalize SDL's wheel convention into Luna's document-scroll convention.
    ///
    /// SDL reports positive Y for a physical wheel movement away from the user,
    /// while Luna defines positive Y as movement toward later document rows. The
    /// host owns that sign conversion and preserves fractional trackpad deltas.
    func translateScrollWheel(
        integerX: Int,
        integerY: Int,
        preciseX: Double,
        preciseY: Double,
        isFlipped: Bool,
        location: LunaPointI,
        modifiers: LunaKeyboardModifiers = .none
    ) -> LunaScrollEvent {
        let direction: Double = isFlipped ? -1 : 1
        let rawX = preciseX == 0 ? Double(integerX) : preciseX
        let rawY = preciseY == 0 ? Double(integerY) : preciseY
        let isPrecise = rawX != Double(integerX)
            || rawY != Double(integerY)
            || rawX.rounded(.towardZero) != rawX
            || rawY.rounded(.towardZero) != rawY

        return LunaScrollEvent(
            location: location,
            deltaX: -rawX * direction,
            deltaY: -rawY * direction,
            phase: .changed,
            isPrecise: isPrecise,
            modifiers: modifiers
        )
    }


    func shouldForwardKeyboardEvent(
        key: LunaKeyboardKey,
        modifiers: LunaKeyboardModifiers
    ) -> Bool {
        let hasCommandModifier = modifiers.control || modifiers.command || modifiers.option
        guard !hasCommandModifier else { return true }

        switch key {
        case .other(let value):
            return value.count != 1
        case .space:
            return false
        default:
            return true
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

    public func translateCurrentModifiers() -> LunaKeyboardModifiers {
        translateModifiers(SDL_GetModState())
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
        case 97...122:
            // SDL lowercase letter keycodes match ASCII on Linux. Keep this raw
            // normalization inside LunaHostSDL so shortcuts such as Ctrl+P can
            // reach Luna as platform-neutral .other("p") without leaking SDL
            // key constants into the demo/editor layer.
            if let scalar = UnicodeScalar(Int(symRaw)) {
                return .other(String(scalar))
            }
            return nil
        case 65...90:
            if let scalar = UnicodeScalar(Int(symRaw + 32)) {
                return .other(String(scalar))
            }
            return nil
        default:
            return nil
        }
    }
}

#endif
