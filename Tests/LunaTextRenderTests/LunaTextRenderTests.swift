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
