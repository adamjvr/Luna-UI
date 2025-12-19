import Foundation
import HarfBuzz
import FreeType

// ------------------------------------------------------------
// MARK: - Core Public Types
// ------------------------------------------------------------

public enum LunaTextDirection {
    case ltr
    case rtl
}

public struct LunaFontDescriptor {
    public let filePath: String
    public let pointSize: Int

    public init(filePath: String, pointSize: Int) {
        self.filePath = filePath
        self.pointSize = pointSize
    }
}

public struct LunaGlyphPosition {
    public let glyphID: UInt32
    public let cluster: UInt32
    public let xAdvance: Int32
    public let yAdvance: Int32
    public let xOffset: Int32
    public let yOffset: Int32
}

public struct LunaShapedRun {
    public let glyphs: [LunaGlyphPosition]
}

public struct LunaGlyphRasterInfo {
    public let width: Int
    public let height: Int
    public let bearingX: Int
    public let bearingY: Int
    public let advanceX: Int
}

// ------------------------------------------------------------
// MARK: - Errors
// ------------------------------------------------------------

public enum LunaTextError: Error, CustomStringConvertible {
    case freeTypeInitFailed
    case fontLoadFailed(String)
    case harfBuzzInitFailed

    public var description: String {
        switch self {
        case .freeTypeInitFailed:
            return "FreeType initialization failed"
        case .fontLoadFailed(let path):
            return "Failed to load font: \(path)"
        case .harfBuzzInitFailed:
            return "HarfBuzz initialization failed"
        }
    }
}

// ------------------------------------------------------------
// MARK: - Text Shaper
// ------------------------------------------------------------

public final class LunaTextShaper {

    private let font: LunaFontDescriptor

    private var ftLibrary: FT_Library?
    private var ftFace: FT_Face?
    private var hbFont: OpaquePointer?

    // --------------------------------------------------------

    public init(font: LunaFontDescriptor) throws {
        self.font = font

        if FT_Init_FreeType(&ftLibrary) != 0 {
            throw LunaTextError.freeTypeInitFailed
        }

        if FT_New_Face(ftLibrary, font.filePath, 0, &ftFace) != 0 {
            throw LunaTextError.fontLoadFailed(font.filePath)
        }

        // FT_Set_Char_Size expects FT_F26Dot6 (often typedef'd to Int in Swift bindings)
        // Font size is in points; FreeType wants 26.6 fixed point => points * 64.
        let charSize26_6: FT_F26Dot6 = FT_F26Dot6(font.pointSize * 64)

        FT_Set_Char_Size(
            ftFace,
            0,
            charSize26_6,
            0,
            0
        )

        guard let face = ftFace else {
            throw LunaTextError.fontLoadFailed(font.filePath)
        }

        hbFont = hb_ft_font_create_referenced(face)

        guard hbFont != nil else {
            throw LunaTextError.harfBuzzInitFailed
        }

        hb_font_set_scale(
            hbFont,
            Int32(font.pointSize * 64),
            Int32(font.pointSize * 64)
        )
    }

    deinit {
        if let hbFont {
            hb_font_destroy(hbFont)
        }
        if let face = ftFace {
            FT_Done_Face(face)
        }
        if let lib = ftLibrary {
            FT_Done_FreeType(lib)
        }
    }

    // --------------------------------------------------------
    // MARK: Shaping
    // --------------------------------------------------------

    public func shape(
        _ text: String,
        direction: LunaTextDirection = .ltr,
        language: String? = nil,
        script: String? = nil
    ) -> LunaShapedRun {

        guard let hbFont else {
            return LunaShapedRun(glyphs: [])
        }

        let buffer = hb_buffer_create()
        hb_buffer_add_utf8(buffer, text, Int32(text.utf8.count), 0, Int32(text.utf8.count))

        switch direction {
        case .ltr:
            hb_buffer_set_direction(buffer, HB_DIRECTION_LTR)
        case .rtl:
            hb_buffer_set_direction(buffer, HB_DIRECTION_RTL)
        }

        if let language {
            hb_buffer_set_language(buffer, hb_language_from_string(language, -1))
        }

        if let script {
            hb_buffer_set_script(buffer, hb_script_from_string(script, -1))
        }

        hb_shape(hbFont, buffer, nil, 0)

        var count: UInt32 = 0
        let infos = hb_buffer_get_glyph_infos(buffer, &count)
        let positions = hb_buffer_get_glyph_positions(buffer, &count)

        var out: [LunaGlyphPosition] = []
        out.reserveCapacity(Int(count))

        for i in 0..<Int(count) {
            let info = infos![i]
            let pos = positions![i]

            out.append(
                LunaGlyphPosition(
                    glyphID: info.codepoint,
                    cluster: info.cluster,
                    xAdvance: pos.x_advance,
                    yAdvance: pos.y_advance,
                    xOffset: pos.x_offset,
                    yOffset: pos.y_offset
                )
            )
        }

        hb_buffer_destroy(buffer)

        return LunaShapedRun(glyphs: out)
    }

    // --------------------------------------------------------
    // MARK: FreeType Raster Metrics
    // --------------------------------------------------------

    public func rasterInfo(forGlyphID gid: UInt32) throws -> LunaGlyphRasterInfo {
        guard let face = ftFace else {
            throw LunaTextError.fontLoadFailed(font.filePath)
        }

        if FT_Load_Glyph(face, FT_UInt(gid), FT_LOAD_DEFAULT) != 0 {
            throw LunaTextError.fontLoadFailed(font.filePath)
        }

        let m = face.pointee.glyph.pointee.metrics

        return LunaGlyphRasterInfo(
            width: Int(m.width >> 6),
            height: Int(m.height >> 6),
            bearingX: Int(m.horiBearingX >> 6),
            bearingY: Int(m.horiBearingY >> 6),
            advanceX: Int(m.horiAdvance >> 6)
        )
    }
}
