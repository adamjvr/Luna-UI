// LunaMetalView.swift
//
// macOS-only GPU presenter + minimal Metal renderer for LunaDisplayList.
//
// Skeleton stage:
// - Supports: .clear + .rect
// - No text yet, no blending, no clipping.

#if os(macOS)
import Foundation
import Metal
import MetalKit
import QuartzCore

import LunaRender

public final class LunaMetalView: MTKView {

    public var drawsOnPresent: Bool = true

    private var queue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!

    private var vertexBuffer: MTLBuffer?
    private var vertexCapacityBytes: Int = 0

    private var pendingDisplayList: LunaDisplayList?
    private var pendingDrawablePixelSize: (Int, Int) = (0, 0)

    public required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    public override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        commonInit()
    }

    private func commonInit() {

        if self.device == nil {
            self.device = MTLCreateSystemDefaultDevice()
        }
        guard let device = self.device else {
            fatalError("LunaMetalView: Metal device unavailable.")
        }

        self.isPaused = true
        self.enableSetNeedsDisplay = true

        self.colorPixelFormat = .bgra8Unorm
        // self.colorPixelFormat = .bgra8Unorm_srgb

        self.queue = device.makeCommandQueue()
        guard queue != nil else { fatalError("LunaMetalView: failed to create command queue.") }

        self.pipeline = try! LunaMetalView.makePipeline(device: device, pixelFormat: self.colorPixelFormat)

        self.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    }

    public func present(displayList: LunaDisplayList, drawablePixelWidth: Int, drawablePixelHeight: Int) {
        self.pendingDisplayList = displayList
        self.pendingDrawablePixelSize = (drawablePixelWidth, drawablePixelHeight)

        if drawsOnPresent {
            self.needsDisplay = true
        }
    }

    public override func draw(_ dirtyRect: CGRect) {
        guard let device = self.device else { return }
        guard let queue = self.queue else { return }
        guard let pipeline = self.pipeline else { return }
        guard let drawable = self.currentDrawable else { return }
        guard let rpd = self.currentRenderPassDescriptor else { return }
        guard let dl = self.pendingDisplayList else { return }

        let (pixelW, pixelH) = self.pendingDrawablePixelSize
        guard pixelW > 0, pixelH > 0 else { return }

        var clearColor = MTLClearColor(red: 0.07, green: 0.07, blue: 0.086, alpha: 1.0)
        var rects: [(LunaRectI, LunaRGBA8)] = []

        for cmd in dl.commands {
            switch cmd {
            case .clear(let c):
                clearColor = LunaMetalView.toMTLClearColor(c)
            case .rect(let r, let c):
                rects.append((r, c))
            }
        }

        rpd.colorAttachments[0].clearColor = clearColor
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store

        let vertices = LunaMetalView.buildVertices(rects: rects, viewportW: pixelW, viewportH: pixelH)
        let bytesNeeded = vertices.count * MemoryLayout<LunaMetalVertex>.stride

        ensureVertexBuffer(device: device, bytesNeeded: bytesNeeded)

        if let vb = vertexBuffer, bytesNeeded > 0 {
            memcpy(vb.contents(), vertices, bytesNeeded)
        }

        guard let cmdBuf = queue.makeCommandBuffer() else { return }
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }

        encoder.setRenderPipelineState(pipeline)

        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(pixelW),
            height: Double(pixelH),
            znear: 0,
            zfar: 1
        ))

        if let vb = vertexBuffer, bytesNeeded > 0 {
            encoder.setVertexBuffer(vb, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }

        encoder.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    private func ensureVertexBuffer(device: MTLDevice, bytesNeeded: Int) {
        if bytesNeeded <= 0 { return }

        if vertexBuffer == nil || bytesNeeded > vertexCapacityBytes {
            let newCap = max(bytesNeeded, vertexCapacityBytes * 2, 64 * 1024)
            vertexBuffer = device.makeBuffer(length: newCap, options: [.storageModeShared])
            vertexCapacityBytes = newCap
        }
    }

    private static func makePipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) throws -> MTLRenderPipelineState {

        let src = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float2 pos [[attribute(0)]];
            float4 color [[attribute(1)]];
        };

        struct VSOut {
            float4 position [[position]];
            float4 color;
        };

        vertex VSOut vs_main(VertexIn in [[stage_in]]) {
            VSOut o;
            o.position = float4(in.pos, 0.0, 1.0);
            o.color = in.color;
            return o;
        }

        fragment float4 fs_main(VSOut in [[stage_in]]) {
            return in.color;
        }
        """

        let library = try device.makeLibrary(source: src, options: nil)
        let vfn = library.makeFunction(name: "vs_main")!
        let ffn = library.makeFunction(name: "fs_main")!

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = pixelFormat

        let vdesc = MTLVertexDescriptor()

        vdesc.attributes[0].format = .float2
        vdesc.attributes[0].offset = 0
        vdesc.attributes[0].bufferIndex = 0

        vdesc.attributes[1].format = .float4
        vdesc.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vdesc.attributes[1].bufferIndex = 0

        vdesc.layouts[0].stride = MemoryLayout<LunaMetalVertex>.stride
        vdesc.layouts[0].stepRate = 1
        vdesc.layouts[0].stepFunction = .perVertex

        desc.vertexDescriptor = vdesc

        return try device.makeRenderPipelineState(descriptor: desc)
    }

    private struct LunaMetalVertex {
        var pos: SIMD2<Float>
        var color: SIMD4<Float>
    }

    private static func buildVertices(
        rects: [(LunaRectI, LunaRGBA8)],
        viewportW: Int,
        viewportH: Int
    ) -> [LunaMetalVertex] {

        if rects.isEmpty { return [] }

        let w = Float(max(1, viewportW))
        let h = Float(max(1, viewportH))

        var out: [LunaMetalVertex] = []
        out.reserveCapacity(rects.count * 6)

        for (r, c) in rects {

            let x0p = Float(r.x)
            let y0p = Float(r.y)
            let x1p = Float(r.x + r.w)
            let y1p = Float(r.y + r.h)

            let x0n = x0p / w
            let x1n = x1p / w
            let y0n = y0p / h
            let y1n = y1p / h

            let x0 = x0n * 2.0 - 1.0
            let x1 = x1n * 2.0 - 1.0

            let y0 = 1.0 - y0n * 2.0
            let y1 = 1.0 - y1n * 2.0

            let color = toFloat4(c)

            out.append(LunaMetalVertex(pos: SIMD2(x0, y0), color: color))
            out.append(LunaMetalVertex(pos: SIMD2(x1, y0), color: color))
            out.append(LunaMetalVertex(pos: SIMD2(x0, y1), color: color))

            out.append(LunaMetalVertex(pos: SIMD2(x0, y1), color: color))
            out.append(LunaMetalVertex(pos: SIMD2(x1, y0), color: color))
            out.append(LunaMetalVertex(pos: SIMD2(x1, y1), color: color))
        }

        return out
    }

    private static func toFloat4(_ c: LunaRGBA8) -> SIMD4<Float> {
        SIMD4(
            Float(c.r) / 255.0,
            Float(c.g) / 255.0,
            Float(c.b) / 255.0,
            Float(c.a) / 255.0
        )
    }

    private static func toMTLClearColor(_ c: LunaRGBA8) -> MTLClearColor {
        MTLClearColor(
            red: Double(c.r) / 255.0,
            green: Double(c.g) / 255.0,
            blue: Double(c.b) / 255.0,
            alpha: Double(c.a) / 255.0
        )
    }
}
#endif
