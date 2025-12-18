// FramebufferPresenters.swift
//
// Platform presentation helpers for the shared BGRA framebuffer.
//
// Important:
// - The CPU renderer produces a BGRA8888 buffer.
// - Presenters "show it" on screen using platform APIs.
// - This separation is what keeps Luna-UI cross-platform and pixel-identical.

import LunaRender

#if os(macOS)
import AppKit
import CoreGraphics
import os // OSAllocatedUnfairLock

/// An NSView that displays a LunaFramebuffer.
///
/// IMPORTANT (Swift Concurrency / AppKit reality):
/// - AppKit may call `draw(_:)` off the main thread in some configurations.
/// - Therefore, `draw(_:)` must be thread-safe.
/// - We avoid storing a mutable framebuffer directly and instead keep an immutable
///   snapshot of the pixel bytes (Data) guarded by a lock.
public final class LunaFramebufferView: NSView {

    /// Immutable snapshot used by draw(). This can be safely read from any thread.
    private struct Snapshot {
        var width: Int
        var height: Int
        var bytesPerRow: Int
        var bytesBGRA: Data
    }

    /// Lock protecting the snapshot (fast, no allocations).
    private let snapshotLock = OSAllocatedUnfairLock<Snapshot?>(initialState: nil)

    /// Public API used by the harness.
    ///
    /// NOTE:
    /// - Setting this creates a snapshot copy (Data) so drawing never races with rendering.
    /// - `LunaFramebuffer` uses `[UInt8]`; we intentionally copy into `Data` to make it immutable.
    public var framebuffer: LunaFramebuffer? {
        didSet {
            guard let fb = framebuffer else {
                snapshotLock.withLock { $0 = nil }
                return
            }

            // Snapshot copy: makes the pixels immutable for draw().
            let snap = Snapshot(
                width: fb.width,
                height: fb.height,
                bytesPerRow: fb.bytesPerRow,
                bytesBGRA: Data(fb.bytes)
            )

            snapshotLock.withLock { $0 = snap }
        }
    }

    public override var isFlipped: Bool {
        // Top-left origin, like typical UI coordinates.
        true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }

        // Copy snapshot pointer under lock, then draw without holding the lock.
        let snap: Snapshot? = snapshotLock.withLock { $0 }
        guard let snap else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Wrap immutable pixel data in a provider.
        let cfData = snap.bytesBGRA as CFData
        guard let provider = CGDataProvider(data: cfData) else { return }

        // BGRA in memory, little-endian, premultiplied alpha first (fast CoreGraphics path).
        let bitmapInfo =
            CGBitmapInfo.byteOrder32Little.union(
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            )

        guard let image = CGImage(
            width: snap.width,
            height: snap.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: snap.bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return }

        cgContext.interpolationQuality = .none
        cgContext.draw(image, in: bounds)
    }
}
#endif


#if os(Linux)
import SDL2

/// Linux presenter: uploads the framebuffer bytes into an SDL_Texture and copies it.
public final class LunaSDLPresenter {

    private var renderer: OpaquePointer?
    private var texture: OpaquePointer?
    private var window: OpaquePointer?

    public init(window: OpaquePointer) {
        self.window = window

        // Create an SDL renderer (accelerated if possible).
        self.renderer = SDL_CreateRenderer(window, -1, UInt32(SDL_RENDERER_ACCELERATED.rawValue))

        // If accelerated renderer isn't available, fall back to software.
        if self.renderer == nil {
            self.renderer = SDL_CreateRenderer(window, -1, UInt32(SDL_RENDERER_SOFTWARE.rawValue))
        }
    }

    /// Ensure a texture exists at the given dimensions.
    /// We recreate it when the window is resized.
    public func ensureTexture(width: Int32, height: Int32) {
        if texture != nil {
            SDL_DestroyTexture(texture)
            texture = nil
        }

        texture = SDL_CreateTexture(
            renderer,
            UInt32(SDL_PIXELFORMAT_BGRA8888),
            Int32(SDL_TEXTUREACCESS_STREAMING.rawValue),
            width,
            height
        )
    }

    public func present(framebuffer: LunaFramebuffer) {
        guard let renderer = renderer else { return }

        if texture == nil {
            ensureTexture(width: Int32(framebuffer.width), height: Int32(framebuffer.height))
        }

        guard let texture = texture else { return }

        framebuffer.bytes.withUnsafeBytes { rawBuf in
            guard let ptr = rawBuf.baseAddress else { return }
            SDL_UpdateTexture(texture, nil, ptr, Int32(framebuffer.bytesPerRow))
        }

        SDL_RenderClear(renderer)
        SDL_RenderCopy(renderer, texture, nil, nil)
        SDL_RenderPresent(renderer)
    }

    deinit {
        if texture != nil { SDL_DestroyTexture(texture) }
        if renderer != nil { SDL_DestroyRenderer(renderer) }
    }
}
#endif
