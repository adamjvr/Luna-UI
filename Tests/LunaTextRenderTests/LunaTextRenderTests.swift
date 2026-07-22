// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest
import LunaRender
@testable import LunaTextRender

final class LunaTextRenderTests: XCTestCase {
    func testPrecomposedAndDecomposedAccentsShapeWithoutMissingGlyphs() throws {
        let renderer = try makeRenderer()
        let precomposed = try renderer.layout("café naïve façade résumé")
        let decomposed = try renderer.layout("cafe\u{301}")

        XCTAssertFalse(precomposed.glyphs.isEmpty)
        XCTAssertFalse(decomposed.glyphs.isEmpty)
        XCTAssertFalse(precomposed.glyphs.contains(where: \.isMissingGlyph))
        XCTAssertFalse(decomposed.glyphs.contains(where: \.isMissingGlyph))
    }

    func testCombiningMarkUsesOneMonospacedCell() throws {
        let renderer = try makeRenderer()
        let precomposed = try renderer.layout("é")
        let decomposed = try renderer.layout("e\u{301}")

        XCTAssertLessThanOrEqual(abs(precomposed.advancePixels - decomposed.advancePixels), 1)
        XCTAssertLessThanOrEqual(decomposed.glyphs.count, 2)
    }

    func testCommonSymbolsGreekAndCyrillicProduceVisiblePixels() throws {
        let renderer = try makeRenderer()
        var framebuffer = LunaFramebuffer(width: 480, height: 48)
        let text = "• ● — café Ελληνικά Кириллица"
        let layout = try renderer.draw(
            text,
            atX: 4,
            baselineY: 30,
            color: LunaRGBA8(r: 255, g: 255, b: 255),
            into: &framebuffer
        )

        XCTAssertFalse(layout.glyphs.contains(where: \.isMissingGlyph))
        XCTAssertGreaterThan(nonZeroColorByteCount(in: framebuffer), 100)
    }

    func testMissingGlyphPaintsExplicitFallbackBox() throws {
        let renderer = try makeRenderer()
        let layout = LunaUnicodeTextLayout(
            text: "?",
            direction: .ltr,
            glyphs: [
                LunaUnicodeGlyphPlacement(
                    glyphID: 0,
                    clusterUTF8Offset: 0,
                    penX26Dot6: 0,
                    xOffset26Dot6: 0,
                    yOffset26Dot6: 0,
                    xAdvance26Dot6: 8 * 64,
                    isMissingGlyph: true
                )
            ],
            advance26Dot6: 8 * 64
        )

        var framebuffer = LunaFramebuffer(width: 64, height: 40)
        try renderer.draw(
            layout,
            atX: 4,
            baselineY: 28,
            color: LunaRGBA8(r: 255, g: 255, b: 255),
            into: &framebuffer
        )
        XCTAssertGreaterThan(nonZeroColorByteCount(in: framebuffer), 8)
    }

    func testClusterLookupUsesUTF8Offsets() throws {
        let renderer = try makeRenderer()
        let layout = try renderer.layout("aéz")

        XCTAssertEqual(layout.closestClusterUTF8Offset(toX: 0), 0)
        XCTAssertEqual(layout.closestClusterUTF8Offset(toX: layout.advancePixels + 20), "aéz".utf8.count)
        XCTAssertTrue([0, 1, 3, 4].contains(layout.closestClusterUTF8Offset(toX: layout.advancePixels / 2)))
    }

    func testSyntheticFractionalLayoutKeepsAbsoluteInsertionGeometry() {
        let text = String(repeating: "a", count: 32)
        let advance: Int32 = 6 * 64 + 16
        let glyphs = text.utf8.indices.enumerated().map { index, _ in
            LunaUnicodeGlyphPlacement(
                glyphID: 1,
                clusterUTF8Offset: index,
                penX26Dot6: Int32(index) * advance,
                xOffset26Dot6: 0,
                yOffset26Dot6: 0,
                xAdvance26Dot6: advance,
                isMissingGlyph: false
            )
        }
        let layout = LunaUnicodeTextLayout(
            text: text,
            direction: .ltr,
            glyphs: glyphs,
            advance26Dot6: Int32(text.utf8.count) * advance
        )

        XCTAssertEqual(layout.insertionPositions.count, text.count + 1)
        XCTAssertEqual(layout.insertionX26Dot6(forUTF8Offset: 20), 20 * advance)
        XCTAssertEqual(layout.insertionX(forUTF8Offset: 20), Int((20 * advance + 32) / 64))
        XCTAssertNotEqual(layout.insertionX(forUTF8Offset: 20), 20 * layout.insertionX(forUTF8Offset: 1))
    }

    func testCombiningSequenceExposesOnlyGraphemeInsertionBoundaries() {
        let text = "e\u{301}x"
        let layout = LunaUnicodeTextLayout(
            text: text,
            direction: .ltr,
            glyphs: [
                LunaUnicodeGlyphPlacement(
                    glyphID: 1,
                    clusterUTF8Offset: 0,
                    penX26Dot6: 0,
                    xOffset26Dot6: 0,
                    yOffset26Dot6: 0,
                    xAdvance26Dot6: 7 * 64,
                    isMissingGlyph: false
                ),
                LunaUnicodeGlyphPlacement(
                    glyphID: 2,
                    clusterUTF8Offset: 0,
                    penX26Dot6: 7 * 64,
                    xOffset26Dot6: 0,
                    yOffset26Dot6: 0,
                    xAdvance26Dot6: 0,
                    isMissingGlyph: false
                ),
                LunaUnicodeGlyphPlacement(
                    glyphID: 3,
                    clusterUTF8Offset: 3,
                    penX26Dot6: 7 * 64,
                    xOffset26Dot6: 0,
                    yOffset26Dot6: 0,
                    xAdvance26Dot6: 7 * 64,
                    isMissingGlyph: false
                ),
            ],
            advance26Dot6: 14 * 64
        )

        XCTAssertEqual(layout.insertionPositions.map(\.utf8Offset), [0, 3, 4])
        XCTAssertEqual(layout.insertionX(forUTF8Offset: 1), 0)
        XCTAssertEqual(layout.insertionX(forUTF8Offset: 3), 7)
        XCTAssertEqual(layout.closestInsertionUTF8Offset(toX: 6), 3)
    }

    func testRendererInsertionGeometryIsMonotonicAcrossLongInput() throws {
        let renderer = try makeRenderer()
        let text = String(repeating: "rapid typing ", count: 20) + "cafe\u{301}"
        let layout = try renderer.layout(text)

        XCTAssertEqual(layout.insertionPositions.first?.utf8Offset, 0)
        XCTAssertEqual(layout.insertionPositions.last?.utf8Offset, text.utf8.count)
        XCTAssertEqual(layout.insertionPositions.last?.x26Dot6, layout.advance26Dot6)
        for pair in zip(layout.insertionPositions, layout.insertionPositions.dropFirst()) {
            XCTAssertLessThan(pair.0.utf8Offset, pair.1.utf8Offset)
            XCTAssertLessThanOrEqual(pair.0.x26Dot6, pair.1.x26Dot6)
        }
    }

    private func makeRenderer() throws -> LunaUnicodeTextRenderer {
        do {
            return try LunaUnicodeTextRenderer(monospacedPointSize: 13)
        } catch {
            throw XCTSkip("No usable development font/shaper is installed: \(error)")
        }
    }

    private func nonZeroColorByteCount(in framebuffer: LunaFramebuffer) -> Int {
        var count = 0
        framebuffer.withUnsafePixelBytes { pointer, stride in
            for y in 0..<framebuffer.height {
                let row = pointer.advanced(by: y * stride)
                for x in 0..<(framebuffer.width * 4) where row[x] != 0 {
                    count += 1
                }
            }
        }
        return count
    }
}
