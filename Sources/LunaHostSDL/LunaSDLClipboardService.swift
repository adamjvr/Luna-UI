// SPDX-License-Identifier: MPL-2.0

#if os(Linux)

import Foundation
import SDL2
import LunaHostCore

/// SDL-backed system clipboard implementation for Linux Luna applications.
public struct LunaSDLClipboardService: LunaClipboardService {
    public init() {}
    public var isAvailable: Bool { true }

    public func readText() throws -> String? {
        guard SDL_HasClipboardText() == SDL_TRUE else { return nil }
        guard let pointer = SDL_GetClipboardText() else {
            throw LunaClipboardError.readFailed(Self.lastSDLError())
        }
        defer { SDL_free(UnsafeMutableRawPointer(pointer)) }
        return String(cString: pointer)
    }

    public func writeText(_ text: String) throws {
        let result = text.withCString { SDL_SetClipboardText($0) }
        guard result == 0 else {
            throw LunaClipboardError.writeFailed(Self.lastSDLError())
        }
    }

    private static func lastSDLError() -> String {
        let value = String(cString: SDL_GetError())
        return value.isEmpty ? "unknown SDL error" : value
    }
}

#endif
