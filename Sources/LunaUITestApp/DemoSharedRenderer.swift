//
//  DemoSharedRenderer.swift
//  Luna-UI
//
//  CPU-only demo renderer shared between macOS + Linux test apps.
//
//  IMPORTANT DESIGN GOALS (for this repo / your engine work):
//  - Absolutely NO GPU requirements for this demo.
//  - No platform UI dependencies in this file.
//  - The demo draws into `LunaFramebuffer` using only raw pixel writes.
//  - The presenter (AppKit/SDL) is responsible for displaying the pixels.
//
//  Pixel format expectations:
//  - `LunaFramebuffer` stores pixels as BGRA8 (premultiplied alpha is fine; we draw opaque).
//  - Byte layout per pixel: [B, G, R, A]
//
//  This file intentionally includes a tiny built-in 5x7 bitmap font so the
//  demo does not depend on any font stack while the engine is still in flux.
//

import Foundation
import LunaRender

// MARK: - Public demo API

/// A small, deterministic demo scene that can be rendered purely on CPU.
///
/// Feature set (matches your request):
/// - Moving block
/// - Text overlay
public struct LunaCPUDemoScene {
    /// Scene start time reference.
    private let startTime: UInt64

    /// Monotonic frame counter (increments each render).
    public private(set) var frameIndex: UInt64 = 0

    /// Create a new demo scene.
    public init(startTimeNanoseconds: UInt64 = LunaCPUDemoScene.nowMonotonicNanoseconds()) {
        self.startTime = startTimeNanoseconds
    }

    /// Render one frame into the provided framebuffer.
    ///
    /// - Important: This function does *not* allocate on the hot path other than
    ///   small, short-lived strings for the HUD text.
    public mutating func render(into fb: inout LunaFramebuffer) {
        frameIndex &+= 1

        // Compute time (seconds) since scene start.
        let now = Self.nowMonotonicNanoseconds()
        let dtNs = now &- startTime
        let t = Double(dtNs) / 1_000_000_000.0

        // Draw.
        drawBackgroundChecker(into: &fb)
        drawMovingBlock(into: &fb, timeSeconds: t)
        drawHUD(into: &fb, timeSeconds: t, frameIndex: frameIndex)
    }

    // MARK: - Time helper

    /// A monotonic clock suitable for animation timing.
    ///
    /// - Note: `DispatchTime.now()` is monotonic on Apple + Linux.
    public static func nowMonotonicNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

// MARK: - Demo drawing primitives (BGRA8)

/// Fill the entire framebuffer with a subtle checker so “black window” bugs
/// are immediately obvious.
private func drawBackgroundChecker(into fb: inout LunaFramebuffer) {
    // Capture these *outside* the pixel closure to avoid overlapping-access traps.
    let w = fb.width
    let h = fb.height

    // Capture outside the pixel closure to avoid Swift's inout exclusivity
    // complaints (reading `fb` inside the closure can overlap the `inout`).
    let bpr = fb.bytesPerRow

    fb.withUnsafeMutablePixelBytes { base, byteCount in
        // Defensive: expected size = bytesPerRow * height.
        // If this ever differs, avoid writing out of bounds.
        let expected = bpr * h
        let n = min(byteCount, expected)
        if n <= 0 { return }

        // We will write row-by-row.
        for y in 0..<h {
            let row = base.advanced(by: y * bpr)
            for x in 0..<w {
                // 16px checker pattern.
                let cx = (x >> 4) & 1
                let cy = (y >> 4) & 1
                let on = (cx ^ cy) != 0

                // Two close greys so it’s not visually loud.
                let v: UInt8 = on ? 28 : 22

                let p = row.advanced(by: x * 4)
                p[0] = v               // B
                p[1] = v               // G
                p[2] = v               // R
                p[3] = 255             // A
            }
        }
    }
}

/// Draw a moving rectangle whose motion is driven by time.
private func drawMovingBlock(into fb: inout LunaFramebuffer, timeSeconds t: Double) {
    let w = fb.width
    let h = fb.height
    if w <= 0 || h <= 0 { return }

    // Block size scales a bit with window size.
    let blockW = max(32, w / 6)
    let blockH = max(32, h / 6)

    // Simple Lissajous-ish motion.
    let ampX = Double(max(1, w - blockW))
    let ampY = Double(max(1, h - blockH))
    let px = (sin(t * 1.2) * 0.5 + 0.5) * ampX
    let py = (cos(t * 0.9) * 0.5 + 0.5) * ampY
    let x0 = Int(px.rounded(.toNearestOrAwayFromZero))
    let y0 = Int(py.rounded(.toNearestOrAwayFromZero))

    // Bright accent color so it pops.
    fillRectBGRA(into: &fb, x: x0, y: y0, w: blockW, h: blockH, b: 60, g: 190, r: 255, a: 255)

    // A darker outline so motion is crisp.
    strokeRectBGRA(into: &fb, x: x0, y: y0, w: blockW, h: blockH, thickness: 2, b: 10, g: 10, r: 10, a: 255)
}

/// Heads-up display: title + time + frame.
private func drawHUD(into fb: inout LunaFramebuffer, timeSeconds t: Double, frameIndex: UInt64) {
    // Draw a translucent-ish bar (we still write opaque alpha; translucency is
    // achieved by using a dark color over the checker).
    let barH = max(28, min(44, fb.height / 12))
    // NOTE: Our framebuffer coordinate system is **bottom-left** (y increases upward).
    // Users expect HUD at the top, so place it at `height - barH`.
    let barY = max(0, fb.height - barH)
    fillRectBGRA(into: &fb, x: 0, y: barY, w: fb.width, h: barH, b: 8, g: 8, r: 8, a: 255)

    // Text (5x7 font, scaled).
    let title = "Luna-UI CPU Demo"
    let info = String(format: "t=%.2fs  frame=%llu", t, frameIndex)

    // Keep text inside the HUD bar.
    let textX = 10
    let titleY = barY + 8
    let infoY  = barY + 8 + 2 * (7 * 2 + 4)

    drawText5x7BGRA(into: &fb, x: textX, y: titleY, text: title, scale: 2, b: 240, g: 240, r: 240, a: 255)
    drawText5x7BGRA(into: &fb, x: textX, y: infoY,  text: info,  scale: 2, b: 200, g: 200, r: 200, a: 255)
}

/// Fill a rectangle (clipped) with a solid BGRA color.
private func fillRectBGRA(
    into fb: inout LunaFramebuffer,
    x: Int,
    y: Int,
    w: Int,
    h: Int,
    b: UInt8,
    g: UInt8,
    r: UInt8,
    a: UInt8
) {
    let fbW = fb.width
    let fbH = fb.height
    if fbW <= 0 || fbH <= 0 { return }
    if w <= 0 || h <= 0 { return }

    // Clip.
    let x0 = max(0, min(fbW, x))
    let y0 = max(0, min(fbH, y))
    let x1 = max(0, min(fbW, x + w))
    let y1 = max(0, min(fbH, y + h))
    if x1 <= x0 || y1 <= y0 { return }

    let width = x1 - x0
    let height = y1 - y0
    let bpr = fb.bytesPerRow

    fb.withUnsafeMutablePixelBytes { base, byteCount in
        let expected = bpr * fbH
        let n = min(byteCount, expected)
        if n <= 0 { return }

        for yy in 0..<height {
            let row = base.advanced(by: (y0 + yy) * bpr)
            var p = row.advanced(by: x0 * 4)
            for _ in 0..<width {
                p[0] = b
                p[1] = g
                p[2] = r
                p[3] = a
                p = p.advanced(by: 4)
            }
        }
    }
}

/// Stroke the rectangle perimeter (clipped) with a solid BGRA color.
private func strokeRectBGRA(
    into fb: inout LunaFramebuffer,
    x: Int,
    y: Int,
    w: Int,
    h: Int,
    thickness: Int,
    b: UInt8,
    g: UInt8,
    r: UInt8,
    a: UInt8
) {
    let t = max(1, thickness)

    // Top
    fillRectBGRA(into: &fb, x: x, y: y, w: w, h: t, b: b, g: g, r: r, a: a)
    // Bottom
    fillRectBGRA(into: &fb, x: x, y: y + h - t, w: w, h: t, b: b, g: g, r: r, a: a)
    // Left
    fillRectBGRA(into: &fb, x: x, y: y, w: t, h: h, b: b, g: g, r: r, a: a)
    // Right
    fillRectBGRA(into: &fb, x: x + w - t, y: y, w: t, h: h, b: b, g: g, r: r, a: a)
}

// MARK: - Tiny built-in 5x7 bitmap font (ASCII 32..127)

/// Draw ASCII text using a compact 5x7 bitmap font.
///
/// The font table is a classic 5x7 set in a packed format:
/// - 96 glyphs (ASCII 32..127)
/// - Each glyph is 5 columns wide
/// - Each column is 7 bits high (LSB at top)
private func drawText5x7BGRA(
    into fb: inout LunaFramebuffer,
    x: Int,
    y: Int,
    text: String,
    scale: Int,
    b: UInt8,
    g: UInt8,
    r: UInt8,
    a: UInt8
) {
    let s = max(1, scale)
    var penX = x

    for scalar in text.unicodeScalars {
        let code = Int(scalar.value)

        // Newline support (simple).
        if code == 10 { // '\n'
            penX = x
            continue
        }

        if code < 32 || code > 127 {
            penX += (6 * s)
            continue
        }

        let glyphIndex = code - 32
        let glyphBase = glyphIndex * 5

        // Each glyph is 5 columns.
        for col in 0..<5 {
            let columnBits = font5x7[glyphBase + col]
            for row in 0..<7 {
                let bit = (columnBits >> row) & 1
                if bit == 0 { continue }

                // Draw a scaled pixel as a filled rect.
                let px = penX + col * s
                // Framebuffer coordinates are bottom-left origin, but the 5x7
                // font data is authored with "row 0" at the TOP of the glyph.
                // Flip vertically so the text renders right-side-up.
                let py = y + (6 - row) * s
                fillRectBGRA(into: &fb, x: px, y: py, w: s, h: s, b: b, g: g, r: r, a: a)
            }
        }

        // 1 column spacing.
        penX += (6 * s)
    }
}

/// 5x7 font table: ASCII 32..127.
///
/// Source: Common public-domain 5x7 font used widely in embedded demos.
/// Representation: 5 bytes per glyph, each byte is a column, LSB at top.
private let font5x7: [UInt8] = [
    // ASCII 32 ' '
    0x00,0x00,0x00,0x00,0x00,
    // '!'
    0x00,0x00,0x5F,0x00,0x00,
    // '"'
    0x00,0x07,0x00,0x07,0x00,
    // '#'
    0x14,0x7F,0x14,0x7F,0x14,
    // '$'
    0x24,0x2A,0x7F,0x2A,0x12,
    // '%'
    0x23,0x13,0x08,0x64,0x62,
    // '&'
    0x36,0x49,0x55,0x22,0x50,
    // '\''
    0x00,0x05,0x03,0x00,0x00,
    // '('
    0x00,0x1C,0x22,0x41,0x00,
    // ')'
    0x00,0x41,0x22,0x1C,0x00,
    // '*'
    0x14,0x08,0x3E,0x08,0x14,
    // '+'
    0x08,0x08,0x3E,0x08,0x08,
    // ','
    0x00,0x50,0x30,0x00,0x00,
    // '-'
    0x08,0x08,0x08,0x08,0x08,
    // '.'
    0x00,0x60,0x60,0x00,0x00,
    // '/'
    0x20,0x10,0x08,0x04,0x02,
    // '0'
    0x3E,0x51,0x49,0x45,0x3E,
    // '1'
    0x00,0x42,0x7F,0x40,0x00,
    // '2'
    0x42,0x61,0x51,0x49,0x46,
    // '3'
    0x21,0x41,0x45,0x4B,0x31,
    // '4'
    0x18,0x14,0x12,0x7F,0x10,
    // '5'
    0x27,0x45,0x45,0x45,0x39,
    // '6'
    0x3C,0x4A,0x49,0x49,0x30,
    // '7'
    0x01,0x71,0x09,0x05,0x03,
    // '8'
    0x36,0x49,0x49,0x49,0x36,
    // '9'
    0x06,0x49,0x49,0x29,0x1E,
    // ':'
    0x00,0x36,0x36,0x00,0x00,
    // ';'
    0x00,0x56,0x36,0x00,0x00,
    // '<'
    0x08,0x14,0x22,0x41,0x00,
    // '='
    0x14,0x14,0x14,0x14,0x14,
    // '>'
    0x00,0x41,0x22,0x14,0x08,
    // '?'
    0x02,0x01,0x51,0x09,0x06,
    // '@'
    0x32,0x49,0x79,0x41,0x3E,
    // 'A'
    0x7E,0x11,0x11,0x11,0x7E,
    // 'B'
    0x7F,0x49,0x49,0x49,0x36,
    // 'C'
    0x3E,0x41,0x41,0x41,0x22,
    // 'D'
    0x7F,0x41,0x41,0x22,0x1C,
    // 'E'
    0x7F,0x49,0x49,0x49,0x41,
    // 'F'
    0x7F,0x09,0x09,0x09,0x01,
    // 'G'
    0x3E,0x41,0x49,0x49,0x7A,
    // 'H'
    0x7F,0x08,0x08,0x08,0x7F,
    // 'I'
    0x00,0x41,0x7F,0x41,0x00,
    // 'J'
    0x20,0x40,0x41,0x3F,0x01,
    // 'K'
    0x7F,0x08,0x14,0x22,0x41,
    // 'L'
    0x7F,0x40,0x40,0x40,0x40,
    // 'M'
    0x7F,0x02,0x04,0x02,0x7F,
    // 'N'
    0x7F,0x04,0x08,0x10,0x7F,
    // 'O'
    0x3E,0x41,0x41,0x41,0x3E,
    // 'P'
    0x7F,0x09,0x09,0x09,0x06,
    // 'Q'
    0x3E,0x41,0x51,0x21,0x5E,
    // 'R'
    0x7F,0x09,0x19,0x29,0x46,
    // 'S'
    0x46,0x49,0x49,0x49,0x31,
    // 'T'
    0x01,0x01,0x7F,0x01,0x01,
    // 'U'
    0x3F,0x40,0x40,0x40,0x3F,
    // 'V'
    0x1F,0x20,0x40,0x20,0x1F,
    // 'W'
    0x7F,0x20,0x18,0x20,0x7F,
    // 'X'
    0x63,0x14,0x08,0x14,0x63,
    // 'Y'
    0x03,0x04,0x78,0x04,0x03,
    // 'Z'
    0x61,0x51,0x49,0x45,0x43,
    // '['
    0x00,0x7F,0x41,0x41,0x00,
    // '\\'
    0x02,0x04,0x08,0x10,0x20,
    // ']'
    0x00,0x41,0x41,0x7F,0x00,
    // '^'
    0x04,0x02,0x01,0x02,0x04,
    // '_'
    0x40,0x40,0x40,0x40,0x40,
    // '`'
    0x00,0x01,0x02,0x04,0x00,
    // 'a'
    0x20,0x54,0x54,0x54,0x78,
    // 'b'
    0x7F,0x48,0x44,0x44,0x38,
    // 'c'
    0x38,0x44,0x44,0x44,0x20,
    // 'd'
    0x38,0x44,0x44,0x48,0x7F,
    // 'e'
    0x38,0x54,0x54,0x54,0x18,
    // 'f'
    0x08,0x7E,0x09,0x01,0x02,
    // 'g'
    0x0C,0x52,0x52,0x52,0x3E,
    // 'h'
    0x7F,0x08,0x04,0x04,0x78,
    // 'i'
    0x00,0x44,0x7D,0x40,0x00,
    // 'j'
    0x20,0x40,0x44,0x3D,0x00,
    // 'k'
    0x7F,0x10,0x28,0x44,0x00,
    // 'l'
    0x00,0x41,0x7F,0x40,0x00,
    // 'm'
    0x7C,0x04,0x18,0x04,0x78,
    // 'n'
    0x7C,0x08,0x04,0x04,0x78,
    // 'o'
    0x38,0x44,0x44,0x44,0x38,
    // 'p'
    0x7C,0x14,0x14,0x14,0x08,
    // 'q'
    0x08,0x14,0x14,0x18,0x7C,
    // 'r'
    0x7C,0x08,0x04,0x04,0x08,
    // 's'
    0x48,0x54,0x54,0x54,0x20,
    // 't'
    0x04,0x3F,0x44,0x40,0x20,
    // 'u'
    0x3C,0x40,0x40,0x20,0x7C,
    // 'v'
    0x1C,0x20,0x40,0x20,0x1C,
    // 'w'
    0x3C,0x40,0x30,0x40,0x3C,
    // 'x'
    0x44,0x28,0x10,0x28,0x44,
    // 'y'
    0x0C,0x50,0x50,0x50,0x3C,
    // 'z'
    0x44,0x64,0x54,0x4C,0x44,
    // '{'
    0x00,0x08,0x36,0x41,0x00,
    // '|'
    0x00,0x00,0x7F,0x00,0x00,
    // '}'
    0x00,0x41,0x36,0x08,0x00,
    // '~'
    0x08,0x04,0x08,0x10,0x08,
    // ASCII 127 (DEL) – render as blank
    0x00,0x00,0x00,0x00,0x00,
]
