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
    // Our CPU renderer writes pixels assuming a *top-left* origin (x→right, y→down).
    // AppKit's default NSView coordinate system is bottom-left (y→up), so if we draw
    // the CGImage directly the framebuffer will appear vertically flipped.
    //
    // We keep AppKit's default coordinate system and apply an explicit vertical flip
    // in `draw(_:)`. This avoids surprising side-effects from `isFlipped` (many
    // AppKit layout and event APIs implicitly assume the default coordinate system).

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
        // Flip the CoreGraphics context so that framebuffer row 0 (top) shows at the
        // top of the window.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: self.bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: self.bounds.width, height: self.bounds.height))
        ctx.restoreGState()
    }
}

#endif
