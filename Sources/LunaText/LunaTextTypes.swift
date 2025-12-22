import Foundation

// MARK: - Text direction

public enum LunaTextDirection: Sendable {
    case ltr
    case rtl
}

// MARK: - Errors

public enum LunaTextError: Error, CustomStringConvertible {
    /// FreeType library initialization failed.
    case freetypeInitFailed

    /// HarfBuzz font creation failed.
    case harfbuzzInitFailed

    /// FreeType couldn't load a font face from the given file path.
    case fontLoadFailed(String)

    /// FreeType couldn't apply the requested point size.
    case fontSizeSetFailed(pointSize: Int)

    /// Convenience escape hatch for C-API failures we haven't named yet.
    case freetypeError(String)

    /// Caller attempted to shape/rasterize before a font was loaded.
    case noFontLoaded

    /// FreeType couldn't load a glyph into the face's glyph slot.
    case glyphLoadFailed(UInt32)

    /// FreeType couldn't render the glyph slot into a bitmap.
    case glyphRenderFailed(UInt32)

    public var description: String {
        switch self {
        case .freetypeInitFailed:
            return "Failed to initialize FreeType"
        case .harfbuzzInitFailed:
            return "Failed to initialize HarfBuzz"
        case .fontLoadFailed(let path):
            return "Failed to load font: \(path)"
        case .fontSizeSetFailed(let pointSize):
            return "Failed to set font size: \(pointSize)pt"
        case .freetypeError(let msg):
            return "FreeType error: \(msg)"
        case .noFontLoaded:
            return "No font loaded"
        case .glyphLoadFailed(let gid):
            return "Failed to load glyph \(gid)"
        case .glyphRenderFailed(let gid):
            return "Failed to render glyph \(gid)"
        }
    }
}

// MARK: - Public types used by host/render layers

/// Packed RGBA8 color.
public struct LunaRGBA8: Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8
    public let a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let white = LunaRGBA8(r: 255, g: 255, b: 255, a: 255)
    public static let black = LunaRGBA8(r: 0, g: 0, b: 0, a: 255)
}

/// Integer rect (pixels).
public struct LunaRectI: Sendable {
    public let x: Int
    public let y: Int
    public let w: Int
    public let h: Int

    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// What the shaper produces per glyph.
/// NOTE: These are in HarfBuzz 26.6 fixed-point units in the smoke test prints,
/// unless your caller converts them. Keep this stable and explicit.
public struct LunaGlyphPosition: Sendable {
    public let glyphID: UInt32
    public let cluster: UInt32
    public let xAdvance: Int32
    public let yAdvance: Int32
    public let xOffset: Int32
    public let yOffset: Int32

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

/// A shaped run (single-direction). For now we keep this minimal.
public struct LunaShapedRun: Sendable {
    public let text: String
    public let direction: LunaTextDirection
    public let glyphs: [LunaGlyphPosition]

    public init(text: String, direction: LunaTextDirection, glyphs: [LunaGlyphPosition]) {
        self.text = text
        self.direction = direction
        self.glyphs = glyphs
    }
}

/// 8-bit coverage mask for a glyph (grayscale alpha).
/// - `pitch` can be > width (FreeType often pads rows).
/// - Pixels are row-major, `height` rows, each row `pitch` bytes.
/// - bearings/advances are in *pixels* (already converted from FreeType 26.6 where applicable).
public struct LunaGlyphMask8: Sendable {
    public let width: Int
    public let height: Int
    public let pitch: Int

    public let bearingX: Int
    public let bearingY: Int
    public let advanceX: Int
    public let advanceY: Int

    public let pixels: [UInt8]

    public init(
        width: Int,
        height: Int,
        pitch: Int,
        bearingX: Int,
        bearingY: Int,
        advanceX: Int,
        advanceY: Int,
        pixels: [UInt8]
    ) {
        self.width = width
        self.height = height
        self.pitch = pitch

        self.bearingX = bearingX
        self.bearingY = bearingY
        self.advanceX = advanceX
        self.advanceY = advanceY

        self.pixels = pixels
    }
}

/// Minimal font descriptor for now.
/// (You can extend later with weight/style, postscript name, collections, etc.)
public struct LunaFontDescriptor: Sendable {
    public let filePath: String
    public let pointSize: Double

    public init(filePath: String, pointSize: Double) {
        self.filePath = filePath
        self.pointSize = pointSize
    }
}
