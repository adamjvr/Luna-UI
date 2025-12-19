// LunaTextShaper.swift
//
// HarfBuzz + FreeType shaper.
// This is the Day-1 correctness foundation:
// - ligatures
// - complex scripts
// - correct cluster mapping
//
// This does NOT rasterize yet.
// Next stage: FreeType raster -> glyph atlas -> textured quads in DisplayList.

import Foundation
import HarfBuzz
import FreeType

public enum LunaTextError: Error, CustomStringConvertible {
    case freetypeInitFailed
    case freetypeNewFaceFailed(path: String)
    case harfbuzzCreateFailed

    public var description: String {
        switch self {
        case .freetypeInitFailed:
            return "FreeType init failed (FT_Init_FreeType)."
        case .freetypeNewFaceFailed(let path):
            return "FreeType could not load face at path: \(path)"
        case .harfbuzzCreateFailed:
            return "HarfBuzz could not create hb_face/hb_font."
        }
    }
}

/// Main shaper object.
/// Keep one per font instance for caching and performance later.
public final class LunaTextShaper {

    // FreeType handles
    private var ftLibrary: FT_Library?
    private var ftFace: FT_Face?

    // HarfBuzz handles (hb-ft helpers create these from the FT_Face)
    private var hbFace: OpaquePointer?    // hb_face_t*
    private var hbFont: OpaquePointer?    // hb_font_t*

    public let font: LunaFontDescriptor

    /// Create a shaper for a specific font file.
    public init(font: LunaFontDescriptor) throws {
        self.font = font

        // 1) Init FreeType
        var lib: FT_Library?
        if FT_Init_FreeType(&lib) != 0 || lib == nil {
            throw LunaTextError.freetypeInitFailed
        }
        self.ftLibrary = lib

        // 2) Load font face
        var face: FT_Face?
        let pathCString = (font.filePath as NSString).fileSystemRepresentation
        if FT_New_Face(lib, pathCString, 0, &face) != 0 || face == nil {
            throw LunaTextError.freetypeNewFaceFailed(path: font.filePath)
        }
        self.ftFace = face

        // 3) Set nominal size
        //
        // We’ll refine this to honor DPI + fractional metrics.
        // For now: 64ths of points in FreeType API:
        //   FT_Set_Char_Size(face, char_width, char_height, hres, vres)
        // - Use 0 width (auto) and a point size height.
        // - Assume 72 DPI baseline for now; the host will scale later.
        let pt64 = FT_F26Dot6(font.pointSize * 64.0)
        _ = FT_Set_Char_Size(face, 0, pt64, 72, 72)

        // 4) Create HarfBuzz face+font from FreeType face
        //
        // hb-ft API gives us correct font funcs for outlines/metrics.
        // These functions come from hb-ft.h.
        guard let hbFace = hb_ft_face_create_referenced(face),
              let hbFont = hb_ft_font_create_referenced(face)
        else {
            throw LunaTextError.harfbuzzCreateFailed
        }

        self.hbFace = hbFace
        self.hbFont = hbFont

        // Ensure hb_font is scaled (optional; hb-ft usually sets this appropriately).
        // We can tune this later for pixel-perfect subpixel positioning.
        hb_font_set_scale(hbFont, Int32(font.pointSize * 64.0), Int32(font.pointSize * 64.0))
    }

    deinit {
        if let hbFont { hb_font_destroy(hbFont) }
        if let hbFace { hb_face_destroy(hbFace) }

        if let ftFace { FT_Done_Face(ftFace) }
        if let ftLibrary { FT_Done_FreeType(ftLibrary) }
    }

    /// Shape a UTF-8 string into positioned glyphs.
    ///
    /// - Parameters:
    ///   - text: input string
    ///   - direction: LTR/RTL
    ///   - language: BCP-47-ish string (e.g. "en", "ar", "hi"). Optional.
    ///   - script: ISO 15924 4-letter script tag (e.g. "Latn", "Arab"). Optional.
    ///
    /// If language/script aren’t provided, HarfBuzz will guess from the text
    /// but giving them later will improve determinism.
    public func shape(
        _ text: String,
        direction: LunaTextDirection = .ltr,
        language: String? = nil,
        script: String? = nil
    ) -> LunaShapedRun {

        // 1) Create buffer
        guard let buf = hb_buffer_create() else {
            // hb_buffer_create returns non-null normally; if it fails, return empty.
            return LunaShapedRun(glyphs: [])
        }
        defer { hb_buffer_destroy(buf) }

        // 2) Add UTF-8 text
        text.withCString { cstr in
            hb_buffer_add_utf8(buf, cstr, Int32(strlen(cstr)), 0, Int32(strlen(cstr)))
        }

        // 3) Configure direction/script/lang
        switch direction {
        case .ltr:
            hb_buffer_set_direction(buf, HB_DIRECTION_LTR)
        case .rtl:
            hb_buffer_set_direction(buf, HB_DIRECTION_RTL)
        }

        if let language {
            language.withCString { langC in
                let hbLang = hb_language_from_string(langC, Int32(strlen(langC)))
                hb_buffer_set_language(buf, hbLang)
            }
        }

        if let script, script.count == 4 {
            // HarfBuzz script is hb_script_t; we can parse from 4-char tag.
            let tag = LunaTextShaper.hbTag(from4CC: script)
            let hbScript = hb_script_from_iso15924_tag(tag)
            hb_buffer_set_script(buf, hbScript)
        }

        // 4) Guess segment properties if we didn’t supply enough info
        hb_buffer_guess_segment_properties(buf)

        // 5) Shape
        if let hbFont {
            hb_shape(hbFont, buf, nil, 0)
        }

        // 6) Extract glyph info/positions
        var glyphCount: UInt32 = 0
        guard let infos = hb_buffer_get_glyph_infos(buf, &glyphCount),
              let poss = hb_buffer_get_glyph_positions(buf, &glyphCount)
        else {
            return LunaShapedRun(glyphs: [])
        }

        var out: [LunaGlyphPosition] = []
        out.reserveCapacity(Int(glyphCount))

        for i in 0..<Int(glyphCount) {
            let info = infos[i]
            let pos = poss[i]

            out.append(LunaGlyphPosition(
                glyphID: info.codepoint,
                cluster: info.cluster,
                xAdvance: pos.x_advance,
                yAdvance: pos.y_advance,
                xOffset: pos.x_offset,
                yOffset: pos.y_offset
            ))
        }

        return LunaShapedRun(glyphs: out)
    }

    // MARK: - Helpers

    /// Convert a 4-character script tag (e.g. "Latn") to hb_tag_t.
    /// HarfBuzz tags are 4-byte packed values.
    private static func hbTag(from4CC s: String) -> hb_tag_t {
        let bytes = Array(s.utf8.prefix(4))
        let a = bytes.count > 0 ? bytes[0] : UInt8(ascii: " ")
        let b = bytes.count > 1 ? bytes[1] : UInt8(ascii: " ")
        let c = bytes.count > 2 ? bytes[2] : UInt8(ascii: " ")
        let d = bytes.count > 3 ? bytes[3] : UInt8(ascii: " ")
        return hb_tag_t(UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d))
    }
}
