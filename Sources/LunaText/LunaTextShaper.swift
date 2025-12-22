import Foundation
import HarfBuzz
import FreeType

/// Text shaping + glyph rasterization.
/// IMPORTANT ARCH RULE:
/// - LunaText is the ONLY module that imports FreeType/HarfBuzz.
/// - Everyone else consumes the *pure Swift* types declared in LunaTextTypes.swift.
public final class LunaTextShaper {

    // MARK: - State

    private var ftLibrary: FT_Library?
    private var ftFace: FT_Face?

    private var hbFont: OpaquePointer?
    private var hbBuffer: OpaquePointer?

    public private(set) var currentFont: LunaFontDescriptor?

    // MARK: - Init / Deinit

    public init() throws {
        // Init FreeType
        var lib: FT_Library?
        if FT_Init_FreeType(&lib) != 0 || lib == nil {
            throw LunaTextError.freetypeInitFailed
        }
        self.ftLibrary = lib

        // Init HarfBuzz buffer
        self.hbBuffer = hb_buffer_create()
    }

    deinit {
        if let hbFont { hb_font_destroy(hbFont) }
        if let hbBuffer { hb_buffer_destroy(hbBuffer) }

        if let ftFace { FT_Done_Face(ftFace) }
        if let ftLibrary { FT_Done_FreeType(ftLibrary) }
    }

    // MARK: - Font loading

    /// Load a font and set it as the current face for shaping + rasterization.
    public func loadFont(_ font: LunaFontDescriptor) throws {
        guard let ftLibrary else {
            throw LunaTextError.freetypeInitFailed
        }

        // Dispose previous resources first
        if let hbFont { hb_font_destroy(hbFont); self.hbFont = nil }
        if let ftFace { FT_Done_Face(ftFace); self.ftFace = nil }

        // Load face
        var face: FT_Face?
        if FT_New_Face(ftLibrary, font.filePath, 0, &face) != 0 || face == nil {
            throw LunaTextError.fontLoadFailed(font.filePath)
        }
        self.ftFace = face
        self.currentFont = font

        // Set character size (26.6 fixed point)
        let charSize: FT_F26Dot6 = Int(font.pointSize * 64)
        if FT_Set_Char_Size(face, 0, charSize, 0, 0) != 0 {
            throw LunaTextError.fontSizeSetFailed(pointSize: Int(font.pointSize))
        }

        // Create HarfBuzz font from the FT face
        guard let hb = hb_ft_font_create_referenced(face) else {
            throw LunaTextError.harfbuzzInitFailed
        }
        self.hbFont = hb

        // Set HB scale to match our FT size (common pattern)
        hb_font_set_scale(hb, Int32(font.pointSize * 64), Int32(font.pointSize * 64))
    }

    // MARK: - Shaping

    public func shape(text: String, direction: LunaTextDirection) throws -> LunaShapedRun {
        guard let hbFont, let hbBuffer else {
            throw LunaTextError.noFontLoaded
        }

        hb_buffer_clear_contents(hbBuffer)

        // Feed UTF-8
        text.withCString { cstr in
            hb_buffer_add_utf8(hbBuffer, cstr, Int32(strlen(cstr)), 0, -1)
        }

        // Direction
        switch direction {
        case .ltr: hb_buffer_set_direction(hbBuffer, HB_DIRECTION_LTR)
        case .rtl: hb_buffer_set_direction(hbBuffer, HB_DIRECTION_RTL)
        }

        hb_buffer_guess_segment_properties(hbBuffer)

        hb_shape(hbFont, hbBuffer, nil, 0)

        var glyphCount: Int32 = 0
        let infos = hb_buffer_get_glyph_infos(hbBuffer, &glyphCount)
        let poses = hb_buffer_get_glyph_positions(hbBuffer, &glyphCount)

        let count = Int(glyphCount)
        var out: [LunaGlyphPosition] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            let info = infos![i]
            let pos = poses![i]

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

        return LunaShapedRun(text: text, direction: direction, glyphs: out)
    }

    // MARK: - Rasterization

    /// Rasterize a glyph into an 8-bit alpha mask using FreeType.
    ///
    /// Returns a `LunaGlyphMask8` which includes:
    /// - bitmap dimensions
    /// - pitch (bytes per row; can be negative in some cases)
    /// - bearings + advances (pixel-ish units, derived from FT metrics)
    public func rasterizeGlyphMask8(glyphID: UInt32) throws -> LunaGlyphMask8 {
        guard let face = ftFace else {
            throw LunaTextError.noFontLoaded
        }

        // Load glyph into slot
        if FT_Load_Glyph(face, FT_UInt(glyphID), FT_Int32(FT_LOAD_DEFAULT)) != 0 {
            throw LunaTextError.glyphLoadFailed(glyphID)
        }

        // Render to grayscale bitmap
        if FT_Render_Glyph(face.pointee.glyph, FT_RENDER_MODE_NORMAL) != 0 {
            throw LunaTextError.glyphRenderFailed(glyphID)
        }

        let slot = face.pointee.glyph!
        let bmp = slot.pointee.bitmap

        let width = Int(bmp.width)
        let height = Int(bmp.rows)

        // NOTE: pitch can be negative; we normalize copy row-by-row.
        let pitch = Int(bmp.pitch)
        let absPitch = abs(pitch)

        let byteCount = max(0, absPitch * height)
        var pixels = [UInt8](repeating: 0, count: byteCount)

        if let buf = bmp.buffer, byteCount > 0 {
            // FreeType gives UInt8* but imported as mutable pointer on Swift side.
            let src: UnsafePointer<UInt8> = UnsafePointer(buf)

            pixels.withUnsafeMutableBytes { dstRaw in
                guard let dstBase = dstRaw.baseAddress else { return }

                // Copy respecting pitch sign.
                // If pitch is negative, the bitmap is stored upside-down.
                for row in 0..<height {
                    let srcRowPtr: UnsafePointer<UInt8>
                    if pitch >= 0 {
                        srcRowPtr = src.advanced(by: row * absPitch)
                    } else {
                        srcRowPtr = src.advanced(by: (height - 1 - row) * absPitch)
                    }

                    let dstRowPtr = dstBase.advanced(by: row * absPitch)
                    memcpy(dstRowPtr, srcRowPtr, absPitch)
                }
            }
        }

        // Bearings (bitmap left/top) are in pixels.
        let bearingX = Int(slot.pointee.bitmap_left)
        let bearingY = Int(slot.pointee.bitmap_top)

        // Advance is 26.6 fixed point -> convert to pixels (rounded).
        let advX = Int((slot.pointee.advance.x + 32) / 64)
        let advY = Int((slot.pointee.advance.y + 32) / 64)

        return LunaGlyphMask8(
            width: width,
            height: height,
            pitch: absPitch,
            bearingX: bearingX,
            bearingY: bearingY,
            advanceX: advX,
            advanceY: advY,
            pixels: pixels
        )
    }
}
