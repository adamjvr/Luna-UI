// SPDX-License-Identifier: MPL-2.0
// FramebufferPresenters.swift
#if os(Linux)

import Foundation
import LunaHostCore
import LunaRender
import SDL2

public final class LunaSDLPresenter {
    private let window: OpaquePointer
    private let renderer: OpaquePointer
    public let capabilities: LunaSDLRendererCapabilities
    public var usesVSync: Bool { capabilities.hasPresentVSync }
    private var texture: OpaquePointer?
    private var texW: Int32 = 0
    private var texH: Int32 = 0

    public init(window: OpaquePointer, useVSync: Bool = true) {
        self.window = window
        var requestedFlags = UInt32(SDL_RENDERER_ACCELERATED.rawValue)
        if useVSync {
            requestedFlags |= UInt32(SDL_RENDERER_PRESENTVSYNC.rawValue)
        }

        guard let renderer = SDL_CreateRenderer(window, -1, requestedFlags) else {
            fatalError("SDL_CreateRenderer failed: \(String(cString: SDL_GetError()))")
        }
        self.renderer = renderer

        var info = SDL_RendererInfo()
        let querySucceeded = SDL_GetRendererInfo(renderer, &info) == 0
        let actualFlags = querySucceeded ? info.flags : 0
        let softwareFlag = UInt32(SDL_RENDERER_SOFTWARE.rawValue)
        let acceleratedFlag = UInt32(SDL_RENDERER_ACCELERATED.rawValue)
        let targetTextureFlag = UInt32(SDL_RENDERER_TARGETTEXTURE.rawValue)
        let presentVSyncFlag = UInt32(SDL_RENDERER_PRESENTVSYNC.rawValue)
        let rendererName: String
        if querySucceeded, let name = info.name {
            rendererName = String(cString: name)
        } else {
            rendererName = "unknown"
        }
        self.capabilities = LunaSDLRendererCapabilities(
            rendererName: rendererName,
            querySucceeded: querySucceeded,
            requestedFlags: requestedFlags,
            actualFlags: actualFlags,
            isSoftware: (actualFlags & softwareFlag) != 0,
            isAccelerated: (actualFlags & acceleratedFlag) != 0,
            supportsTargetTextures: (actualFlags & targetTextureFlag) != 0,
            vsyncWasRequested: useVSync,
            hasPresentVSync: (actualFlags & presentVSyncFlag) != 0,
            maximumTextureWidth: Int(info.max_texture_width),
            maximumTextureHeight: Int(info.max_texture_height)
        )
    }

    deinit {
        if let texture { SDL_DestroyTexture(texture) }
        SDL_DestroyRenderer(renderer)
    }

    public func getOutputPixelSize(fallbackWidth: Int, fallbackHeight: Int) -> (Int, Int) {
        var width: Int32 = 0
        var height: Int32 = 0
        SDL_GetRendererOutputSize(renderer, &width, &height)
        guard width > 0, height > 0 else {
            return (fallbackWidth, fallbackHeight)
        }
        return (Int(width), Int(height))
    }

    public func ensureTexture(width: Int32, height: Int32) {
        if texture != nil, width == texW, height == texH { return }
        if let texture { SDL_DestroyTexture(texture) }
        texture = nil

        let format = UInt32(SDL_PIXELFORMAT_ARGB8888.rawValue)
        guard let texture = SDL_CreateTexture(
            renderer,
            format,
            Int32(SDL_TEXTUREACCESS_STREAMING.rawValue),
            width,
            height
        ) else {
            fatalError("SDL_CreateTexture failed: \(String(cString: SDL_GetError()))")
        }
        self.texture = texture
        texW = width
        texH = height
    }

    public func present(framebuffer: LunaFramebuffer) {
        let width = Int32(framebuffer.width)
        let height = Int32(framebuffer.height)
        ensureTexture(width: width, height: height)
        guard let texture else { return }
        let pitch = Int32(framebuffer.bytesPerRow)
        _ = framebuffer.withUnsafePixelBytes { pointer, _ in
            SDL_UpdateTexture(texture, nil, pointer, pitch)
        }
        SDL_RenderClear(renderer)
        SDL_RenderCopy(renderer, texture, nil, nil)
        SDL_RenderPresent(renderer)
    }
}
#endif
