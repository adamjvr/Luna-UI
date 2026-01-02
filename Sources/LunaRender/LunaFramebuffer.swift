import Foundation

// NOTE:
// - This file is a perfect example of "Step 5" (Swift exclusivity rules).
// - Rule of thumb:
//     If you call `withUnsafeMutablePixelBytes { ... }`
//     DO NOT read `self.width/self.height/self.bytesPerRow` inside that closure.
//     Copy them into local constants *before* entering the closure.

public struct LunaFramebuffer {

    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var bytesPerRow: Int

    // Backing pixel storage: BGRA8, row-major, tightly packed (bytesPerRow = width*4)
    private var storage: [UInt8]

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.bytesPerRow = self.width * 4
        self.storage = [UInt8](repeating: 0, count: self.bytesPerRow * self.height)
    }

    public mutating func resize(width: Int, height: Int) {
        let w = max(1, width)
        let h = max(1, height)
        if w == self.width && h == self.height { return }

        self.width = w
        self.height = h
        self.bytesPerRow = w * 4
        self.storage = [UInt8](repeating: 0, count: self.bytesPerRow * h)
    }

    // MARK: - Pixel access

    /// Provides *mutable* access to the framebuffer's pixel bytes.
    ///
    /// - Parameters:
    ///   - body: Closure receiving:
    ///     - base pointer to the first byte of the framebuffer
    ///     - row stride in bytes (bytesPerRow)
    ///
    /// IMPORTANT:
    /// - Because this closure provides mutable access, avoid referencing `self.*`
    ///   inside the closure (Swift exclusivity / overlapping access rules).
    @inline(__always)
    public mutating func withUnsafeMutablePixelBytes<R>(
        _ body: (UnsafeMutablePointer<UInt8>, Int) -> R
    ) -> R {
        storage.withUnsafeMutableBytes {
            // bindMemory ensures we interpret as UInt8 bytes.
            let base = $0.bindMemory(to: UInt8.self).baseAddress!
            return body(base, bytesPerRow)
        }
    }

    /// Provides *read-only* access to the framebuffer's pixel bytes.
    @inline(__always)
    public func withUnsafePixelBytes<R>(
        _ body: (UnsafePointer<UInt8>, Int) -> R
    ) -> R {
        storage.withUnsafeBytes {
            let base = $0.bindMemory(to: UInt8.self).baseAddress!
            return body(base, bytesPerRow)
        }
    }
}

// MARK: - CPU drawing ops

extension LunaFramebuffer {

    /// Pack RGBA into a 32-bit BGRA pixel.
    ///
    /// Memory layout we store in `storage` is BGRA8 bytes.
    /// When writing as a UInt32, we use:
    ///   (A << 24) | (R << 16) | (G << 8) | (B)
    ///
    /// This matches what we want for a "BGRA in memory on little-endian" representation.
    @inline(__always)
    private func packBGRA(_ c: LunaRGBA8) -> UInt32 {
        (UInt32(c.a) << 24) |
        (UInt32(c.r) << 16) |
        (UInt32(c.g) << 8)  |
        UInt32(c.b)
    }

    /// Clear the entire framebuffer to a single color.
    public mutating func clear(_ color: LunaRGBA8) {
        // STEP 5: Copy any self-dependent values BEFORE the closure.
        let localBytesPerRow = self.bytesPerRow
        let localHeight = self.height

        let px = packBGRA(color)
        let countU32 = (localBytesPerRow * localHeight) / 4

        withUnsafeMutablePixelBytes { raw, _ in
            // Convert raw bytes to a typed UInt32 view.
            raw.withMemoryRebound(to: UInt32.self, capacity: countU32) { u32 in
                for i in 0..<countU32 {
                    u32[i] = px
                }
            }
        }
    }

    /// Draw a filled rectangle (solid, no blending).
    public mutating func fillRect(_ rect: LunaRectI, color: LunaRGBA8) {
        // STEP 5: Copy any self-dependent values BEFORE the closure.
        let localWidth = self.width
        let localHeight = self.height

        let px = packBGRA(color)

        // Clip rect to framebuffer bounds (all computed BEFORE closure).
        let x0 = max(0, rect.x)
        let y0 = max(0, rect.y)
        let x1 = min(localWidth, rect.x + rect.w)
        let y1 = min(localHeight, rect.y + rect.h)
        if x1 <= x0 || y1 <= y0 { return }

        withUnsafeMutablePixelBytes { raw, strideBytes in
            // We only use localWidth/localHeight inside the closure (no self.*).
            for y in y0..<y1 {
                let rowBytes = raw.advanced(by: y * strideBytes)

                // Treat this scanline as UInt32 pixels.
                rowBytes.withMemoryRebound(to: UInt32.self, capacity: localWidth) { rowU32 in
                    for x in x0..<x1 {
                        rowU32[x] = px
                    }
                }
            }
        }
    }
}
