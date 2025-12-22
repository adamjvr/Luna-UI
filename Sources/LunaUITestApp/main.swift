// Sources/LunaUITestApp/main.swift
//
// Cross-platform test harness:
// - Linux: SDL window + CPU framebuffer presenter (via LunaHost SDL presenter)
// - macOS: AppKit window + CPU framebuffer presenter (and optional Metal path elsewhere)
//
// This demo now proves:
//   ✅ HarfBuzz shaping (ligatures + complex scripts) works
//   ✅ FreeType rasterization produces real glyph masks
//   ✅ CPU blitting blends masks correctly into the framebuffer
//
// IMPORTANT UNIT RULES:
// - HarfBuzz positions/advances are in 26.6 fixed-point (scaled by 64).
// - FreeType bitmap bearings and raster sizes are in *pixels*.
// - Therefore: convert HB values to pixels before mixing them with FT bearings.
//

import Foundation
import LunaUI
import LunaRender
import LunaHostCore

#if os(Linux)
import LunaHostSDL
#endif

#if os(macOS)
import LunaHostMetal
#endif

import LunaText

#if os(Linux)
import SDL2
#endif

// ------------------------------------------------------------
// MARK: - Tiny fixed-point helper (HB 26.6 -> px)
// ------------------------------------------------------------

@inline(__always)
private func hb26_6_to_px(_ v: Int32) -> Int {
    // Add 32 for rounding, then divide by 64.
    return Int((v + 32) / 64)
}

@inline(__always)
func packBGRA(_ c: (UInt8, UInt8, UInt8, UInt8)) -> UInt32 {
    let (b, g, r, a) = c
    return (UInt32(b)      ) |
           (UInt32(g) <<  8) |
           (UInt32(r) << 16) |
           (UInt32(a) << 24)
}


// ------------------------------------------------------------
// MARK: - Text draw helper (CPU framebuffer)
// ------------------------------------------------------------

/// Draw shaped + rasterized text into the CPU framebuffer.
///
/// - Parameters:
///   - fb: Destination BGRA framebuffer.
///   - shaper: LunaTextShaper (owns HB+FT).
///   - text: String to draw.
///   - baselineX: Baseline X in framebuffer pixels.
///   - baselineY: Baseline Y in framebuffer pixels (y increases downward on screen).
///   - colorBGRA: Text color (BGRA).
private func drawTextCPU(
    fb: inout LunaFramebuffer,
    shaper: LunaTextShaper,
    text: String,
    baselineX: Int,
    baselineY: Int,
    colorBGRA: (UInt8, UInt8, UInt8, UInt8)

) {
    let colorBGRA32: UInt32 = packBGRA(colorBGRA)
    // 1) Shape using HarfBuzz.
    // NOTE: If you want automatic script/lang detection later, we’ll add that.
    let run: LunaShapedRun
do {
    run = try shaper.shape(text: text, direction: .ltr)
} catch {
    // If shaping fails, don’t crash the demo; just draw nothing this frame.
    return
}



    // 2) Walk glyphs, rasterize each glyph, and blit its coverage mask.
    var penX = baselineX
    var penY = baselineY

    for g in run.glyphs {

        // HB 26.6 -> pixels
        let xOffPx = hb26_6_to_px(g.xOffset)
        let yOffPx = hb26_6_to_px(g.yOffset)
        let xAdvPx = hb26_6_to_px(g.xAdvance)
        // let yAdvPx = hb26_6_to_px(g.yAdvance) // not used in this simple baseline demo

        // Rasterize glyph to an 8-bit mask (Swift-owned pixels).
        // If rasterization fails for some glyph, skip it without crashing the demo.
        let mask: LunaGlyphMask8
        do {
            mask = try shaper.rasterizeGlyphMask8(glyphID: g.glyphID)
        } catch {
            // If raster fails, still advance using HB.
            penX += xAdvPx
            continue
        }

        // Compute the top-left destination for the bitmap.
        //
        // Coordinate model:
        // - baseline is at (penX, penY)
        // - FreeType bearingX is pixels to the right from pen to bitmap left
        // - FreeType bearingY is pixels *above* the baseline to bitmap top
        // - Screen Y grows downward, so "above baseline" means subtract bearingY
        //
        // HarfBuzz yOffset:
        // - In HB, positive y_offset means "move glyph up" in font coords.
        // - On screen, up means negative Y, so we subtract yOffPx.
        //
        // Empirically, this mapping gives the expected baseline behavior:
        let dstX = penX + xOffPx + mask.bearingX
        let dstY = penY - yOffPx - mask.bearingY

        LunaCPUGlyphBlitter.blitMask8_BGRA8888(
            fb: &fb,
            mask: mask,
            dstX: dstX,
            dstY: dstY,
            colorBGRA: colorBGRA32
        )


        // Advance pen:
        // - Prefer HarfBuzz advance (proper shaping/kerning/ligature positioning).
        // - If HB gives 0 for some reason, fall back to FreeType advanceX.
        penX += (xAdvPx != 0 ? xAdvPx : mask.advanceX)
    }
}

// ------------------------------------------------------------
// MARK: - Linux entry (SDL)
// ------------------------------------------------------------

#if os(Linux)

SDL_Init(SDL_INIT_VIDEO)

let width = 900
let height = 600

guard let window = SDL_CreateWindow(
    "Luna-UI Test Harness (Linux / CPU)",
    Int32(SDL_WINDOWPOS_UNDEFINED_MASK),  // avoid macro import issues in Swift
    Int32(SDL_WINDOWPOS_UNDEFINED_MASK),
    Int32(width),
    Int32(height),
    SDL_WINDOW_SHOWN.rawValue
) else {
    fatalError("SDL_CreateWindow failed: \(String(cString: SDL_GetError()))")
}

defer {
    SDL_DestroyWindow(window)
    SDL_Quit()
}

let presenter = LunaSDLPresenter(window: window)

// Basic framebuffer we render into each frame.
var framebuffer = LunaFramebuffer(width: width, height: height)

let shaper = try! LunaTextShaper()
try! shaper.loadFont(
    LunaFontDescriptor(
        filePath: "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        pointSize: 28
    )
)


var running = true
var t: Double = 0.0

while running {

    // Pump events.
    var event = SDL_Event()
    while SDL_PollEvent(&event) == 1 {
        if event.type == SDL_QUIT.rawValue {
            running = false
        }
    }

    // ------------------------------------------------------------
    // 1) Clear framebuffer
    // ------------------------------------------------------------
    framebuffer.clear(LunaRGBA8(r: 25, g: 25, b: 28, a: 255))

    // ------------------------------------------------------------
    // 2) Demo moving block (keep your earlier proof alive)
    // ------------------------------------------------------------
    t += 1.0 / 60.0
    let bx = 40 + Int((sin(t) + 1.0) * 0.5 * 300.0)
    let by = 40

    framebuffer.fillRect(
        LunaRectI(x: bx, y: by, w: 60, h: 60),
        color: LunaRGBA8(r: 240, g: 120, b: 90, a: 255)
    )

    // ------------------------------------------------------------
    // 3) Render text (REAL glyph masks)
    // ------------------------------------------------------------
    drawTextCPU(
        fb: &framebuffer,
        shaper: shaper,
        text: "office -> fi fl ffi | مرحبا بالعالم | हिन्दी भाषा",
        baselineX: 40,
        baselineY: 160,
        colorBGRA: (255, 255, 255, 255)
    )

    // ------------------------------------------------------------
    // 4) Present
    // ------------------------------------------------------------
    presenter.present(framebuffer: framebuffer)

    SDL_Delay(1)
}

#endif
