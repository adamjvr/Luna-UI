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
public struct LunaUnicodeGlyphPlacement: Hashable, Sendable {
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

/// One stable insertion boundary in a shaped UTF-8 run.
///
/// Offsets remain UTF-8 byte offsets so downstream editor surfaces can use the
/// same coordinate space as their source buffers. Horizontal positions retain
/// HarfBuzz 26.6 precision until the final framebuffer rectangle is produced.
public struct LunaUnicodeTextInsertionPosition: Hashable, Sendable {
    public let utf8Offset: Int
    public let x26Dot6: Int32

    public init(utf8Offset: Int, x26Dot6: Int32) {
        self.utf8Offset = max(0, utf8Offset)
        self.x26Dot6 = x26Dot6
    }
}

/// Immutable result of shaping one single-direction UTF-8 run.
public struct LunaUnicodeTextLayout: Hashable, Sendable {
    public let text: String
    public let direction: LunaTextCore.LunaTextDirection
    public let glyphs: [LunaUnicodeGlyphPlacement]
    public let insertionPositions: [LunaUnicodeTextInsertionPosition]
    public let advance26Dot6: Int32

    public init(
        text: String,
        direction: LunaTextCore.LunaTextDirection,
        glyphs: [LunaUnicodeGlyphPlacement],
        insertionPositions: [LunaUnicodeTextInsertionPosition]? = nil,
        advance26Dot6: Int32
    ) {
        self.text = text
        self.direction = direction
        self.glyphs = glyphs
        self.advance26Dot6 = advance26Dot6
        self.insertionPositions = insertionPositions
            ?? Self.makeInsertionPositions(
                text: text,
                direction: direction,
                glyphs: glyphs,
                advance26Dot6: advance26Dot6
            )
    }

    public var advancePixels: Int {
        Self.ceil26Dot6(advance26Dot6)
    }

    /// Return the shaped horizontal insertion position for a UTF-8 boundary.
    /// Arbitrary offsets inside a grapheme cluster resolve to the preceding
    /// stable insertion boundary.
    public func insertionX26Dot6(forUTF8Offset requestedOffset: Int) -> Int32 {
        guard !insertionPositions.isEmpty else { return 0 }
        let target = min(max(0, requestedOffset), text.utf8.count)
        var low = 0
        var high = insertionPositions.count
        while low < high {
            let mid = (low + high) / 2
            if insertionPositions[mid].utf8Offset <= target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return insertionPositions[max(0, low - 1)].x26Dot6
    }

    public func insertionX(forUTF8Offset offset: Int) -> Int {
        Self.round26Dot6(insertionX26Dot6(forUTF8Offset: offset))
    }

    /// Return the closest stable UTF-8 insertion boundary for a horizontal run
    /// position. Midpoints between adjacent insertion positions determine which
    /// side owns a pointer coordinate.
    public func closestInsertionUTF8Offset(toX26Dot6 requestedX: Int32) -> Int {
        guard let first = insertionPositions.first else { return 0 }
        guard insertionPositions.count > 1 else { return first.utf8Offset }

        let x = min(max(0, requestedX), max(0, advance26Dot6))
        for index in 0..<(insertionPositions.count - 1) {
            let current = insertionPositions[index]
            let next = insertionPositions[index + 1]
            let midpoint = current.x26Dot6 + (next.x26Dot6 - current.x26Dot6) / 2
            if x < midpoint { return current.utf8Offset }
        }
        return insertionPositions.last?.utf8Offset ?? text.utf8.count
    }

    public func closestInsertionUTF8Offset(toX x: Int) -> Int {
        closestInsertionUTF8Offset(toX26Dot6: Int32(max(0, x) * 64))
    }

    /// Backward-compatible cluster hit testing now delegates to the stable
    /// insertion geometry rather than glyph centers.
    public func closestClusterUTF8Offset(toX x: Int) -> Int {
        closestInsertionUTF8Offset(toX: x)
    }

    private struct ClusterExtent {
        var sourceStart: Int
        var sourceEnd: Int
        var xStart: Int32
        var xEnd: Int32
    }

    private static func makeInsertionPositions(
        text: String,
        direction: LunaTextCore.LunaTextDirection,
        glyphs: [LunaUnicodeGlyphPlacement],
        advance26Dot6: Int32
    ) -> [LunaUnicodeTextInsertionPosition] {
        let textLength = text.utf8.count
        var graphemeBoundaries = [0]
        graphemeBoundaries.reserveCapacity(text.count + 1)
        var sourceOffset = 0
        for character in text {
            sourceOffset += String(character).utf8.count
            graphemeBoundaries.append(sourceOffset)
        }
        if graphemeBoundaries.last != textLength {
            graphemeBoundaries.append(textLength)
        }

        guard !glyphs.isEmpty else {
            return graphemeBoundaries.map { boundary in
                LunaUnicodeTextInsertionPosition(
                    utf8Offset: boundary,
                    x26Dot6: boundary == textLength ? advance26Dot6 : 0
                )
            }
        }

        var grouped: [Int: (minX: Int32, maxX: Int32)] = [:]
        grouped.reserveCapacity(glyphs.count)
        for glyph in glyphs {
            let start = glyph.penX26Dot6
            let end = glyph.penX26Dot6 + glyph.xAdvance26Dot6
            let low = min(start, end)
            let high = max(start, end)
            if let existing = grouped[glyph.clusterUTF8Offset] {
                grouped[glyph.clusterUTF8Offset] = (
                    min(existing.minX, low),
                    max(existing.maxX, high)
                )
            } else {
                grouped[glyph.clusterUTF8Offset] = (low, high)
            }
        }

        let clusterStarts = grouped.keys.sorted()
        var extents: [ClusterExtent] = []
        extents.reserveCapacity(clusterStarts.count)
        for (index, start) in clusterStarts.enumerated() {
            let sourceEnd = index + 1 < clusterStarts.count
                ? clusterStarts[index + 1]
                : textLength
            let x = grouped[start] ?? (0, 0)
            extents.append(
                ClusterExtent(
                    sourceStart: min(max(0, start), textLength),
                    sourceEnd: min(max(start, sourceEnd), textLength),
                    xStart: x.minX,
                    xEnd: x.maxX
                )
            )
        }

        // Fill the grapheme insertion table in one forward pass. A HarfBuzz
        // cluster can cover more than one grapheme boundary (for example a
        // ligature). Internal boundaries are distributed across that cluster's
        // exact 26.6 span; the cluster end itself is owned by the following
        // cluster or by the final run advance.
        var xByBoundary = Array<Int32?>(repeating: nil, count: graphemeBoundaries.count)
        var boundaryIndex = 0
        for extent in extents {
            while boundaryIndex < graphemeBoundaries.count,
                  graphemeBoundaries[boundaryIndex] < extent.sourceStart {
                boundaryIndex += 1
            }

            let firstIndex = boundaryIndex
            while boundaryIndex < graphemeBoundaries.count,
                  graphemeBoundaries[boundaryIndex] < extent.sourceEnd {
                boundaryIndex += 1
            }
            let boundaryCount = boundaryIndex - firstIndex
            guard boundaryCount > 0 else { continue }

            let span = Int64(extent.xEnd) - Int64(extent.xStart)
            let denominator = Int64(max(1, boundaryCount))
            for relativeIndex in 0..<boundaryCount {
                let interpolated = Int64(extent.xStart)
                    + span * Int64(relativeIndex) / denominator
                xByBoundary[firstIndex + relativeIndex] = Int32(clamping: interpolated)
            }
        }

        if let finalIndex = graphemeBoundaries.indices.last {
            xByBoundary[finalIndex] = direction == .ltr ? advance26Dot6 : 0
        }

        var result: [LunaUnicodeTextInsertionPosition] = []
        result.reserveCapacity(graphemeBoundaries.count)
        var previousRawX: Int32 = 0
        for index in graphemeBoundaries.indices {
            let boundary = graphemeBoundaries[index]
            let rawX = xByBoundary[index] ?? previousRawX
            previousRawX = rawX
            result.append(
                LunaUnicodeTextInsertionPosition(
                    utf8Offset: boundary,
                    x26Dot6: direction == .ltr
                        ? rawX
                        : max(0, advance26Dot6 - rawX)
                )
            )
        }

        // LTR editor geometry must be monotonic even when a font emits unusual
        // zero-width cluster ordering. This does not claim full bidi support; it
        // guarantees stable single-run insertion geometry for the current editor.
        if direction == .ltr {
            var previous: Int32 = 0
            for index in result.indices {
                let clamped = min(
                    max(previous, result[index].x26Dot6),
                    max(0, advance26Dot6)
                )
                result[index] = LunaUnicodeTextInsertionPosition(
                    utf8Offset: result[index].utf8Offset,
                    x26Dot6: clamped
                )
                previous = clamped
            }
        }

        if result.first?.utf8Offset != 0 {
            result.insert(
                LunaUnicodeTextInsertionPosition(utf8Offset: 0, x26Dot6: 0),
                at: 0
            )
        }
        if result.last?.utf8Offset != textLength {
            result.append(
                LunaUnicodeTextInsertionPosition(
                    utf8Offset: textLength,
                    x26Dot6: direction == .ltr ? advance26Dot6 : 0
                )
            )
        }
        return result
    }

    private static func ceil26Dot6(_ value: Int32) -> Int {
        if value <= 0 { return 0 }
        return Int((value + 63) / 64)
    }

    private static func round26Dot6(_ value: Int32) -> Int {
        if value >= 0 { return Int((value + 32) / 64) }
        return Int((value - 32) / 64)
    }
}

/// Thread-safe shaped-text renderer with a per-font glyph-mask cache.
///
/// The current editor integration intentionally uses one monospaced face, while
/// exposing exact shaped insertion positions so wrapping, caret, selection, hit
/// testing, and painting do not depend on a rounded fixed-cell approximation.
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
