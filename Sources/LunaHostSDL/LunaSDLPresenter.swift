// FramebufferPresenters.swift
//
// Linux:
// - SDL2 presenter that uploads the CPU framebuffer into an SDL streaming texture.
//
// NOTE:
// - We do NOT assume a particular LunaFramebuffer storage property name.
// - We use `LunaFramebuffer.withUnsafePixelBytes` (reflection shim in LunaRender) to access bytes.
#if os(Linux)

import Foundation
import LunaRender
import LunaHostCore

import SDL2

public final class LunaSDLPresenter {

    private let window: OpaquePointer
    private let renderer: OpaquePointer
    private var texture: OpaquePointer?

    private var texW: Int32 = 0
    private var texH: Int32 = 0

    public init(window: OpaquePointer) {
        self.window = window

        guard let r = SDL_CreateRenderer(
            window,
            -1,
            UInt32(SDL_RENDERER_ACCELERATED.rawValue | SDL_RENDERER_PRESENTVSYNC.rawValue)
        ) else {
            fatalError("SDL_CreateRenderer failed: \(String(cString: SDL_GetError()))")
        }

        self.renderer = r
    }

    deinit {
        if let tex = texture {
            SDL_DestroyTexture(tex)
        }
        SDL_DestroyRenderer(renderer)
        // Window is owned by the caller.
    }

    public func getOutputPixelSize(fallbackWidth: Int, fallbackHeight: Int) -> (Int, Int) {
        var w: Int32 = 0
        var h: Int32 = 0
        SDL_GetRendererOutputSize(renderer, &w, &h)

        if w <= 0 || h <= 0 {
            return (fallbackWidth, fallbackHeight)
        }
        return (Int(w), Int(h))
    }

    public func ensureTexture(width: Int32, height: Int32) {
        if texture != nil && width == texW && height == texH {
            return
        }

        if let tex = texture {
            SDL_DestroyTexture(tex)
            texture = nil
        }

        // SDL pixel format constant is a typed enum in Swift bindings -> use .rawValue
        let fmt: UInt32 = UInt32(SDL_PIXELFORMAT_BGRA8888.rawValue)

        guard let tex = SDL_CreateTexture(
            renderer,
            fmt,
            Int32(SDL_TEXTUREACCESS_STREAMING.rawValue),
            width,
            height
        ) else {
            fatalError("SDL_CreateTexture failed: \(String(cString: SDL_GetError()))")
        }

        texture = tex
        texW = width
        texH = height
    }

    public func present(framebuffer fb: LunaFramebuffer) {

        let w = Int32(fb.width)
        let h = Int32(fb.height)

        ensureTexture(width: w, height: h)

        guard let tex = texture else { return }

        let pitch = Int32(fb.bytesPerRow)

        // Upload pixels using the stable helper (no dependency on fb.pixels name)
        fb.withUnsafePixelBytes { ptr, _ in
            SDL_UpdateTexture(tex, nil, ptr, pitch)
        }

        SDL_RenderClear(renderer)
        SDL_RenderCopy(renderer, tex, nil, nil)
        SDL_RenderPresent(renderer)
    }
}
#endif
