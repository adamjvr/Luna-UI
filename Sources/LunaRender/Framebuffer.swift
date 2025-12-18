// Framebuffer.swift
//
// CPU framebuffer (BGRA8888) used by the CPU renderer.
//
// PERFORMANCE (HiDPI):
// - HiDPI can be ~4× pixels on 2.0 scale.
// - Use 32-bit packed pixel writes for large speedups vs per-byte loops.

public struct LunaFramebuffer {

    public private(set) var width: Int
    public private(set) var height: Int

    // BGRA8888 bytes: [B, G, R, A] per pixel
    public var bytes: [UInt8]

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.bytes = Array(repeating: 0, count: self.width * self.height * 4)
    }

    public mutating func resize(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.bytes = Array(repeating: 0, count: self.width * self.height * 4)
    }

    public var bytesPerRow: Int { width * 4 }

    // MARK: - Packed pixel helpers (BGRA little-endian)

    @inline(__always)
    private func packBGRA(_ c: LunaRGBA8) -> UInt32 {
        // Break into locals to avoid slow type-checking in some toolchains.
        let a = UInt32(c.a) << 24
        let r = UInt32(c.r) << 16
        let g = UInt32(c.g) << 8
        let b = UInt32(c.b)
        return a | r | g | b
    }

    // MARK: - Fast clears / fills

    /// Fast full-buffer clear.
    public mutating func clear(_ color: LunaRGBA8) {
        let px = packBGRA(color)
        let pixelCount = width * height

        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let p = base.bindMemory(to: UInt32.self, capacity: pixelCount)

            var i = 0
            while i < pixelCount {
                p[i] = px
                i += 1
            }
        }
    }

    /// Fast filled rectangle (no blending yet).
    public mutating func fillRect(_ rect: LunaRectI, color: LunaRGBA8) {

        let x0 = max(0, rect.x)
        let y0 = max(0, rect.y)
        let x1 = min(width, rect.x + rect.w)
        let y1 = min(height, rect.y + rect.h)

        if x1 <= x0 || y1 <= y0 { return }

        let px = packBGRA(color)

        let rowPixels = width
        let rectPixelsPerRow = x1 - x0

        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let p = base.bindMemory(to: UInt32.self, capacity: width * height)

            for y in y0..<y1 {
                var idx = y * rowPixels + x0
                var c = 0
                while c < rectPixelsPerRow {
                    p[idx] = px
                    idx += 1
                    c += 1
                }
            }
        }
    }
}
