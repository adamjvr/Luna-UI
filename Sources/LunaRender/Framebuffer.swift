// Framebuffer.swift
//
// A simple CPU framebuffer (BGRA8888) used by the CPU renderer.
// This is the "Option 2" core: one pixel buffer everywhere,
// with platform-specific presentation (CoreGraphics on macOS, SDL texture on Linux).

public struct LunaFramebuffer {

    /// Width in pixels.
    public private(set) var width: Int

    /// Height in pixels.
    public private(set) var height: Int

    /// Pixel storage: BGRA8888 (4 bytes per pixel).
    ///
    /// Layout per pixel in memory:
    ///   bytes[i+0] = B
    ///   bytes[i+1] = G
    ///   bytes[i+2] = R
    ///   bytes[i+3] = A
    ///
    /// Why BGRA?
    /// - On macOS, CoreGraphics loves BGRA little-endian (fast path).
    /// - On Linux SDL2, we can use SDL_PIXELFORMAT_BGRA8888 directly.
    public var bytes: [UInt8]

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.bytes = Array(repeating: 0, count: self.width * self.height * 4)
    }

    /// Resize the framebuffer. This destroys old contents (fine for now).
    public mutating func resize(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.bytes = Array(repeating: 0, count: self.width * self.height * 4)
    }

    /// Bytes per row in the BGRA buffer.
    public var bytesPerRow: Int { width * 4 }

    /// Fill entire buffer with a solid color.
    public mutating func clear(_ color: LunaRGBA8) {
        // Convert logical RGBA -> stored BGRA
        let b = color.b
        let g = color.g
        let r = color.r
        let a = color.a

        // Fill pixel-by-pixel. (Later we can optimize with memset-like tricks.)
        var i = 0
        while i < bytes.count {
            bytes[i + 0] = b
            bytes[i + 1] = g
            bytes[i + 2] = r
            bytes[i + 3] = a
            i += 4
        }
    }

    /// Draw a filled rectangle (no blending yet).
    public mutating func fillRect(_ rect: LunaRectI, color: LunaRGBA8) {

        // Clip to framebuffer bounds to avoid out-of-range writes.
        let x0 = max(0, rect.x)
        let y0 = max(0, rect.y)
        let x1 = min(width, rect.x + rect.w)
        let y1 = min(height, rect.y + rect.h)

        if x1 <= x0 || y1 <= y0 {
            return
        }

        let b = color.b
        let g = color.g
        let r = color.r
        let a = color.a

        // Write row-by-row.
        for y in y0..<y1 {
            var idx = (y * width + x0) * 4
            for _ in x0..<x1 {
                bytes[idx + 0] = b
                bytes[idx + 1] = g
                bytes[idx + 2] = r
                bytes[idx + 3] = a
                idx += 4
            }
        }
    }
}
