// FramebufferPresenters.swift
//
// Platform presentation helpers for the shared BGRA framebuffer.
//
// - CPU renderer produces BGRA8888 (LunaFramebuffer)
// - macOS: present via CALayer.contents (avoid draw(_:) threading issues)
// - Linux: present via SDL texture upload

import LunaRender

#if os(macOS)
import AppKit
import CoreGraphics

public final class LunaFramebufferView: NSView {

    // Reusable snapshot storage (BGRA bytes).
    // Updated on main thread (from the test app tick()).
    private var snapshotWidth: Int = 0
    private var snapshotHeight: Int = 0
    private var snapshotBytesPerRow: Int = 0
    private var snapshotData: Data = Data()

    private var hasNewFrame: Bool = false

    public override var isFlipped: Bool { true }

    // Tell AppKit we want layer updates, not draw(_:)
    public override var wantsUpdateLayer: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.wantsLayer = true
    }

    /// Set by the harness (from @MainActor tick()).
    /// We snapshot into a reusable Data buffer (avoid per-frame allocs).
    public var framebuffer: LunaFramebuffer? {
        didSet {
            guard let fb = framebuffer else {
                snapshotWidth = 0
                snapshotHeight = 0
                snapshotBytesPerRow = 0
                snapshotData.removeAll(keepingCapacity: true)
                hasNewFrame = true
                self.needsDisplay = true
                return
            }

            snapshotWidth = fb.width
            snapshotHeight = fb.height
            snapshotBytesPerRow = fb.bytesPerRow

            let byteCount = fb.bytes.count
            if snapshotData.count != byteCount {
                snapshotData = Data(count: byteCount)
            }

            snapshotData.withUnsafeMutableBytes { dstRaw in
                guard let dst = dstRaw.baseAddress else { return }
                fb.bytes.withUnsafeBytes { srcRaw in
                    guard let src = srcRaw.baseAddress else { return }
                    memcpy(dst, src, byteCount)
                }
            }

            hasNewFrame = true
            self.needsDisplay = true
        }
    }

    /// AppKit updates the layer. This avoids threaded draw() paths.
    public override func updateLayer() {
        guard let layer = self.layer else { return }
        guard hasNewFrame else { return }
        hasNewFrame = false

        guard snapshotWidth > 0, snapshotHeight > 0, snapshotBytesPerRow > 0 else {
            layer.contents = nil
            return
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let cfData = snapshotData as CFData
        guard let provider = CGDataProvider(data: cfData) else { return }

        let bitmapInfo =
            CGBitmapInfo.byteOrder32Little.union(
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            )

        guard let image = CGImage(
            width: snapshotWidth,
            height: snapshotHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: snapshotBytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return }

        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.contentsGravity = .resizeAspectFill
        layer.contents = image
    }
}
#endif


#if os(Linux)
import SDL2

public final class LunaSDLPresenter {

    private var renderer: OpaquePointer?
    private var texture: OpaquePointer?
    private var window: OpaquePointer?

    public init(window: OpaquePointer) {
        self.window = window

        self.renderer = SDL_CreateRenderer(window, -1, UInt32(SDL_RENDERER_ACCELERATED.rawValue))
        if self.renderer == nil {
            self.renderer = SDL_CreateRenderer(window, -1, UInt32(SDL_RENDERER_SOFTWARE.rawValue))
        }
    }

    public func getOutputPixelSize(fallbackWidth: Int, fallbackHeight: Int) -> (Int, Int) {
        guard let renderer else { return (fallbackWidth, fallbackHeight) }

        var w: Int32 = 0
        var h: Int32 = 0
        let rc = SDL_GetRendererOutputSize(renderer, &w, &h)
        if rc != 0 || w <= 0 || h <= 0 {
            return (fallbackWidth, fallbackHeight)
        }
        return (Int(w), Int(h))
    }

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
        guard let texture else { return }

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
