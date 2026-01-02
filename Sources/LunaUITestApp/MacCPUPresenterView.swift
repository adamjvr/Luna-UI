//
//  MacCPUPresenterView.swift
//  LunaUITestApp
//
//  A tiny NSView that can present a `LunaFramebuffer` by copying its pixels into
//  a `Data` buffer and creating a CGImage on demand in `draw(_:)`.
//
//  Why copy?
//  - `LunaFramebuffer` owns its memory.
//  - The demo reuses (and may resize) the framebuffer every frame.
//  - AppKit will call `draw(_:)` asynchronously relative to when we request a
//    redraw.
//  Therefore we keep an owning copy of the latest pixel bytes so the memory is
//  valid for the duration of the draw call.

#if os(macOS)

import AppKit
import CoreGraphics

import LunaRender

/// Presents BGRA8888 CPU pixels.
@MainActor
final class MacCPUPresenterView: NSView {

    /// Latest pixel data (BGRA8888), owned by this view.
    private var pixelData: Data = Data()

    /// Dimensions that match `pixelData`.
    private var pixelWidth: Int = 0
    private var pixelHeight: Int = 0

    /// Bytes per row for the pixel buffer.
    private var bytesPerRow: Int = 0

    /// Present a new framebuffer.
    ///
    /// - Important: This copies pixels.
    func present(framebuffer fb: LunaFramebuffer) {
        // Capture everything we need OUTSIDE of the closure.
        let w = fb.width
        let h = fb.height
        let bpr = fb.bytesPerRow

        // Allocate destination buffer.
        let byteCount = max(0, bpr * h)
        var copy = Data(count: byteCount)

        // Copy pixels (source is BGRA8888).
        copy.withUnsafeMutableBytes { dstRaw in
            guard let dstBase = dstRaw.baseAddress else { return }
            fb.withUnsafePixelBytes { srcBase, srcCount in
                // Defensive: never read beyond what framebuffer reports.
                let n = min(srcCount, dstRaw.count)
                if n > 0 {
                    memcpy(dstBase, srcBase, n)
                }
            }
        }

        // Store.
        self.pixelData = copy
        self.pixelWidth = w
        self.pixelHeight = h
        self.bytesPerRow = bpr

        // Ask AppKit to redraw.
        self.needsDisplay = true
    }

    // IMPORTANT:
    // Our demo renderer writes pixels assuming a *top-left* origin (x→right, y→down)
    // which is the most natural for software rasterizers.
    //
    // AppKit/CoreGraphics gives us a CGContext whose default user-space is
    // *bottom-left* origin (x→right, y→up). Rather than flipping the entire view
    // coordinate system (which interacts in surprising ways with CGImage drawing),
    // we keep the view non-flipped and explicitly flip the CGContext when drawing
    // the backing CGImage.
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard pixelWidth > 0, pixelHeight > 0, !pixelData.isEmpty else {
            // Fill with a neutral background so "blank" is intentional.
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
            return
        }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Create a CGImage from our BGRA8888 bytes.
        // We use an sRGB color space. For a demo, this is fine.
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))

        // NOTE: `CGDataProvider` will retain `CFData` until the image is released.
        let cfData: CFData = pixelData as CFData
        guard let provider = CGDataProvider(data: cfData) else { return }

        guard let image = CGImage(
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return
        }

        // Draw image scaled to view bounds.
        // Our framebuffer is top-left origin; CoreGraphics draws with bottom-left
        // origin. We flip Y so row 0 in the buffer appears at the top of the view.
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.translateBy(x: 0, y: self.bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: self.bounds)
        ctx.restoreGState()
    }
}

#endif
