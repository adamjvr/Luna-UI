import Foundation
import LunaText

public enum LunaCPUGlyphBlitter {

    @inline(__always)
    private static func blendPixelBGRA(
        dst: UnsafeMutablePointer<UInt8>,
        srcBGRA: UInt32,
        coverage: UInt8
    ) {
        let alpha = Int(coverage)
        if alpha == 0 { return }

        let invA = 255 - alpha

        // Source BGRA channels (packed)
        let sb = Int(srcBGRA & 0xFF)
        let sg = Int((srcBGRA >> 8) & 0xFF)
        let sr = Int((srcBGRA >> 16) & 0xFF)
        let sa = Int((srcBGRA >> 24) & 0xFF)

        // Destination BGRA channels (in framebuffer)
        let db = Int(dst[0])
        let dg = Int(dst[1])
        let dr = Int(dst[2])
        let da = Int(dst[3])

        // Simple “coverage-as-alpha” blend.
        // NOTE: This is not gamma-correct yet (fine for now).
        dst[0] = UInt8((sb * alpha + db * invA) >> 8)
        dst[1] = UInt8((sg * alpha + dg * invA) >> 8)
        dst[2] = UInt8((sr * alpha + dr * invA) >> 8)

        // Keep alpha from exploding: this is a placeholder policy.
        // Later we can do proper alpha compositing.
        dst[3] = UInt8(min(255, sa + da))
    }

    /// Blit an 8-bit coverage mask into a BGRA8888 framebuffer.
    ///
    /// - fb: destination framebuffer (BGRA8888)
    /// - mask: 8-bit coverage mask (row-major), `pitch` bytes per row
    /// - dstX/dstY: destination top-left in framebuffer pixel coordinates
    /// - colorBGRA: packed color in BGRA (A<<24|R<<16|G<<8|B)
    public static func blitMask8_BGRA8888(
        fb: inout LunaFramebuffer,
        mask: LunaGlyphMask8,
        dstX: Int,
        dstY: Int,
        colorBGRA: UInt32
    ) {
        // STEP 5 pattern:
        // Copy all properties we’ll need into locals before entering any mutation closures.
        let fbWidth = fb.width
        let fbHeight = fb.height

        let maskW = mask.width
        let maskH = mask.height
        let maskPitch = mask.pitch
        let maskPixels = mask.pixels   // [UInt8] storage

        // Trivial rejection
        if dstX >= fbWidth || dstY >= fbHeight { return }
        if dstX + maskW <= 0 || dstY + maskH <= 0 { return }

        // Clip the draw region to framebuffer bounds.
        let startX = max(0, dstX)
        let startY = max(0, dstY)
        let endX = min(fbWidth, dstX + maskW)
        let endY = min(fbHeight, dstY + maskH)
        if endX <= startX || endY <= startY { return }

        // Where to start reading within the mask.
        let maskStartX = startX - dstX
        let maskStartY = startY - dstY

        // IMPORTANT:
        // Take ONE stable pointer to the mask pixel array and keep it alive for the duration.
        // Avoid calling maskPixels.withUnsafeBytes repeatedly inside the framebuffer mutation closure.
        maskPixels.withUnsafeBytes { maskRaw in
            let maskBase = maskRaw.bindMemory(to: UInt8.self).baseAddress!

            // Now mutate framebuffer pixels.
            fb.withUnsafeMutablePixelBytes { dstBase, strideBytes in
                // Only use locals inside this closure.
                for y in startY..<endY {

                    // Row pointers:
                    // mask row = (maskStartY + (y - startY)) * maskPitch
                    let maskRowIndex = maskStartY + (y - startY)
                    let srcRow = maskBase.advanced(by: maskRowIndex * maskPitch)

                    let dstRow = dstBase.advanced(by: y * strideBytes)

                    for x in startX..<endX {
                        // Column within mask row
                        let maskCol = maskStartX + (x - startX)
                        let coverage = srcRow[maskCol]
                        if coverage == 0 { continue }

                        // Destination pixel in BGRA8888
                        let dstPx = dstRow.advanced(by: x * 4)
                        blendPixelBGRA(dst: dstPx, srcBGRA: colorBGRA, coverage: coverage)
                    }
                }
            }
        }
    }
}
