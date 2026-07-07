// DisplayList.swift
//
// A backend-agnostic list of draw commands.
//
// Key idea:
// - Layout + Chrome produce a "what to draw" list.
// - Backends (CPU/GPU) consume the same list.
// - This keeps visuals consistent and makes GPU/CPU switching sane.

public struct LunaDisplayList: Equatable, Sendable {

    /// Ordered draw commands. Later commands draw "on top of" earlier ones.
    public var commands: [LunaDrawCommand]

    public init(commands: [LunaDrawCommand] = []) {
        self.commands = commands
    }

    public mutating func append(_ command: LunaDrawCommand) {
        commands.append(command)
    }
}

/// A simple set of draw commands for v0.1 "first pixels".
/// We'll expand this later with glyph runs, paths, images, etc.
public enum LunaDrawCommand: Equatable, Sendable {
    case clear(LunaRGBA8)
    case rect(LunaRectI, LunaRGBA8)
}

/// Integer rectangle in pixel coordinates (top-left origin).
public struct LunaRectI: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int

    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var isEmpty: Bool {
        w <= 0 || h <= 0
    }

    public func contains(x px: Int, y py: Int) -> Bool {
        guard !isEmpty else { return false }
        return px >= x && py >= y && px < x + w && py < y + h
    }
}

/// 8-bit per channel RGBA color.
/// NOTE: Our CPU framebuffer will store pixels as BGRA (little-endian friendly),
/// but we keep this color struct in logical RGBA terms for clarity.
public struct LunaRGBA8: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}
