// LunaTextTypes.swift
//
// Public LunaText types:
// - Cross-platform shaping results
// - Direction/script/language knobs
//
// This is intentionally minimal for v0:
// - We prove HarfBuzz shaping works (ligatures + complex scripts).
// - Rasterization/glyph atlas comes next.

import Foundation

public enum LunaTextDirection: Sendable {
    case ltr
    case rtl
}

public struct LunaFontDescriptor: Sendable, Hashable {
    /// Path to a font file (TTF/OTF). For now we load by file path.
    public var filePath: String

    /// Requested size in points (we’ll treat it as “nominal size” for now).
    public var pointSize: Double

    public init(filePath: String, pointSize: Double) {
        self.filePath = filePath
        self.pointSize = pointSize
    }
}

public struct LunaGlyphPosition: Sendable, Hashable {
    /// HarfBuzz glyph ID (font-specific).
    public var glyphID: UInt32

    /// Cluster index into the original UTF-8 text.
    public var cluster: UInt32

    /// Advances and offsets in *font units scaled to pixels-ish*.
    /// We will formalize units when we integrate DPI + subpixel later.
    public var xAdvance: Int32
    public var yAdvance: Int32
    public var xOffset: Int32
    public var yOffset: Int32

    public init(
        glyphID: UInt32,
        cluster: UInt32,
        xAdvance: Int32,
        yAdvance: Int32,
        xOffset: Int32,
        yOffset: Int32
    ) {
        self.glyphID = glyphID
        self.cluster = cluster
        self.xAdvance = xAdvance
        self.yAdvance = yAdvance
        self.xOffset = xOffset
        self.yOffset = yOffset
    }
}

public struct LunaShapedRun: Sendable, Hashable {
    public var glyphs: [LunaGlyphPosition]

    public init(glyphs: [LunaGlyphPosition]) {
        self.glyphs = glyphs
    }
}
