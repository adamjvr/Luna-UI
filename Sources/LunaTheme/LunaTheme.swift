// LunaTheme.swift
// Public theme model used by Luna-UI and consumers (moth-text)

public struct LunaTheme {

    /// Named color values (keys come from Sublime scopes or UI roles)
    public let colors: [String: LunaColor]

    public init(colors: [String: LunaColor] = [:]) {
        self.colors = colors
    }
}

/// Simple RGBA color representation.
/// This stays platform-neutral.
public struct LunaColor {
    public let r: Float
    public let g: Float
    public let b: Float
    public let a: Float

    public init(r: Float, g: Float, b: Float, a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}
