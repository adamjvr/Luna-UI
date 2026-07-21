// SPDX-License-Identifier: MPL-2.0
//
// LunaUnicodeTextRenderer.swift
//
// Reusable CPU shaped-text painter for Luna framebuffers. HarfBuzz owns UTF-8
// cluster shaping, FreeType owns glyph rasterization, and LunaRender owns the
// destination framebuffer. The renderer is intentionally independent of Moth.

import Foundation
import LunaRender
import LunaText
import LunaTextCore

/// One shaped glyph positioned relative to a text-run origin and baseline.
public struct LunaUnicodeGlyphPlacement: Sendable {
    public let glyphID: UInt32
    public let clusterUTF8Offset: Int
    public let penX26Dot6: Int32
    public let xOffset26Dot6: Int32
    public let yOffset26Dot6: Int32
    public let xAdvance26Dot6: Int32
    public let isMissingGlyph: Bool

    public init(
        glyphID: UInt32,
        clusterUTF8Offset: Int,
        penX26Dot6: Int32,
        xOffset26Dot6: Int32,
        yOffset26Dot6: Int32,
        xAdvance26Dot6: Int32,
        isMissingGlyph: Bool
    ) {
        self.glyphID = glyphID
        self.clusterUTF8Offset = max(0, clusterUTF8Offset)
        self.penX26Dot6 = penX26Dot6
        self.xOffset26Dot6 = xOffset26Dot6
        self.yOffset26Dot6 = yOffset26Dot6
        self.xAdvance26Dot6 = xAdvance26Dot6
        self.isMissingGlyph = isMissingGlyph
    }
}

/// Immutable result of shaping one single-direction UTF-8 run.
public struct LunaUnicodeTextLayout: Sendable {
    public let text: String
    public let direction: LunaTextCore.LunaTextDirection
    public let glyphs: [LunaUnicodeGlyphPlacement]
    public let advance26Dot6: Int32

    public init(
        text: String,
        direction: LunaTextCore.LunaTextDirection,
        glyphs: [LunaUnicodeGlyphPlacement],
        advance26Dot6: Int32
    ) {
        self.text = text
        self.direction = direction
        self.glyphs = glyphs
        self.advance26Dot6 = advance26Dot6
    }

    public var advancePixels: Int {
        Self.ceil26Dot6(advance26Dot6)
    }

    /// Return the closest UTF-8 cluster boundary for a horizontal run position.
    /// This is the bridge later text-view geometry can use for shaped hit testing.
    public func closestClusterUTF8Offset(toX x: Int) -> Int {
        guard !glyphs.isEmpty else { return 0 }
        let target = Int32(max(0, x) * 64)
        var bestOffset = glyphs[0].clusterUTF8Offset
        var bestDistance = Int64.max
        for glyph in glyphs {
            let center = glyph.penX26Dot6 + glyph.xAdvance26Dot6 / 2
            let distance = abs(Int64(center) - Int64(target))
            if distance < bestDistance {
                bestDistance = distance
                bestOffset = glyph.clusterUTF8Offset
            }
        }
        if target >= advance26Dot6 { return text.utf8.count }
        return bestOffset
    }

    private static func ceil26Dot6(_ value: Int32) -> Int {
        if value <= 0 { return 0 }
        return Int((value + 63) / 64)
    }
}

/// Thread-safe shaped-text renderer with a per-font glyph-mask cache.
///
/// The current editor integration intentionally uses a single monospaced face so
/// Luna's existing cell-oriented wrapping/caret geometry remains aligned while
/// document painting gains real Unicode, combining-mark, and glyph-cluster support.
public final class LunaUnicodeTextRenderer: @unchecked Sendable {
    public let font: LunaText.LunaFontDescriptor

    private let lock = NSLock()
    private let shaper: LunaTextShaper
    private var glyphCache: [UInt32: LunaTextCore.LunaGlyphMask8] = [:]

    public init(font: LunaText.LunaFontDescriptor) throws {
        let shaper = try LunaTextShaper()
        try shaper.loadFont(font)
        self.font = font
        self.shaper = shaper
    }

    public convenience init(monospacedPointSize pointSize: Double = 12) throws {
        try self.init(
            font: LunaText.LunaFontDescriptor(
                filePath: LunaFontLocator.bestMonospacedFontPath(),
                pointSize: pointSize
            )
        )
    }

    /// Shape a UTF-8 run. Clusters are byte offsets, matching Luna and Moth's
    /// existing stable text-coordinate convention.
    public func layout(
        _ text: String,
        direction: LunaTextCore.LunaTextDirection = .ltr
    ) throws -> LunaUnicodeTextLayout {
        lock.lock()
        defer { lock.unlock() }
        let run = try shaper.shape(text: text, direction: Self.shaperDirection(direction))
        var penX: Int32 = 0
        let placements = run.glyphs.map { glyph -> LunaUnicodeGlyphPlacement in
            defer { penX &+= glyph.xAdvance }
            return LunaUnicodeGlyphPlacement(
                glyphID: glyph.glyphID,
                clusterUTF8Offset: Int(glyph.cluster),
                penX26Dot6: penX,
                xOffset26Dot6: glyph.xOffset,
                yOffset26Dot6: glyph.yOffset,
                xAdvance26Dot6: glyph.xAdvance,
                isMissingGlyph: glyph.glyphID == 0
            )
        }
        return LunaUnicodeTextLayout(
            text: text,
            direction: direction,
            glyphs: placements,
            advance26Dot6: penX
        )
    }

    /// Paint a previously shaped run at a baseline. Unsupported glyphs are shown
    /// as explicit boxes instead of silently consuming blank horizontal space.
    public func draw(
        _ layout: LunaUnicodeTextLayout,
        atX originX: Int,
        baselineY: Int,
        color: LunaRender.LunaRGBA8,
        maximumWidth: Int? = nil,
        into framebuffer: inout LunaFramebuffer
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let packed = Self.packBGRA(color)
        let widthLimit = maximumWidth.map { max(0, $0) }

        for glyph in layout.glyphs {
            let penX = Self.round26Dot6(glyph.penX26Dot6 + glyph.xOffset26Dot6)
            let nextPenX = Self.round26Dot6(
                glyph.penX26Dot6 + glyph.xAdvance26Dot6
            )
            if let widthLimit {
                if penX >= widthLimit { break }
                if glyph.xAdvance26Dot6 > 0, nextPenX > widthLimit { break }
            }

            if glyph.isMissingGlyph {
                drawMissingGlyph(
                    x: originX + penX,
                    baselineY: baselineY,
                    widthLimit: widthLimit,
                    originX: originX,
                    color: color,
                    framebuffer: &framebuffer
                )
                continue
            }

            let mask: LunaTextCore.LunaGlyphMask8
            if let cached = glyphCache[glyph.glyphID] {
                mask = cached
            } else {
                let rasterized = try shaper.rasterizeGlyphMask8(glyphID: glyph.glyphID)
                let coreMask = LunaTextCore.LunaGlyphMask8(
                    width: rasterized.width,
                    height: rasterized.height,
                    pitch: rasterized.pitch,
                    bearingX: rasterized.bearingX,
                    bearingY: rasterized.bearingY,
                    advanceX: rasterized.advanceX,
                    advanceY: rasterized.advanceY,
                    pixels: rasterized.pixels
                )
                glyphCache[glyph.glyphID] = coreMask
                mask = coreMask
            }

            let drawX = originX + penX + mask.bearingX
            let verticalOffset = Self.round26Dot6(glyph.yOffset26Dot6)
            let drawY = baselineY - verticalOffset - mask.bearingY

            if let widthLimit, drawX >= originX + widthLimit { break }
            LunaCPUGlyphBlitter.blitMask8_BGRA8888(
                fb: &framebuffer,
                mask: mask,
                dstX: drawX,
                dstY: drawY,
                colorBGRA: packed
            )
        }
    }

    /// Shape and draw in one call for application chrome and editor rows.
    @discardableResult
    public func draw(
        _ text: String,
        atX x: Int,
        baselineY: Int,
        direction: LunaTextCore.LunaTextDirection = .ltr,
        color: LunaRender.LunaRGBA8,
        maximumWidth: Int? = nil,
        into framebuffer: inout LunaFramebuffer
    ) throws -> LunaUnicodeTextLayout {
        let shaped = try layout(text, direction: direction)
        try draw(
            shaped,
            atX: x,
            baselineY: baselineY,
            color: color,
            maximumWidth: maximumWidth,
            into: &framebuffer
        )
        return shaped
    }

    public func removeAllCachedGlyphs() {
        lock.lock()
        glyphCache.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private func drawMissingGlyph(
        x: Int,
        baselineY: Int,
        widthLimit: Int?,
        originX: Int,
        color: LunaRender.LunaRGBA8,
        framebuffer: inout LunaFramebuffer
    ) {
        let height = max(7, Int(font.pointSize.rounded()))
        let width = max(5, height * 2 / 3)
        if let widthLimit, x >= originX + widthLimit { return }
        let top = baselineY - height
        framebuffer.fillRect(LunaRender.LunaRectI(x: x, y: top, w: width, h: 1), color: color)
        framebuffer.fillRect(LunaRender.LunaRectI(x: x, y: baselineY - 1, w: width, h: 1), color: color)
        framebuffer.fillRect(LunaRender.LunaRectI(x: x, y: top, w: 1, h: height), color: color)
        framebuffer.fillRect(LunaRender.LunaRectI(x: x + width - 1, y: top, w: 1, h: height), color: color)
    }

    private static func shaperDirection(
        _ direction: LunaTextCore.LunaTextDirection
    ) -> LunaText.LunaTextDirection {
        switch direction {
        case .ltr: return .ltr
        case .rtl: return .rtl
        }
    }

    private static func round26Dot6(_ value: Int32) -> Int {
        if value >= 0 { return Int((value + 32) / 64) }
        return Int((value - 32) / 64)
    }

    private static func packBGRA(_ color: LunaRender.LunaRGBA8) -> UInt32 {
        UInt32(color.a) << 24
            | UInt32(color.r) << 16
            | UInt32(color.g) << 8
            | UInt32(color.b)
    }
}
