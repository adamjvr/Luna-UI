// CPURenderer.swift
//
// CPU renderer that consumes a LunaDisplayList and writes into a LunaFramebuffer.
// This is intentionally tiny for v0.1 "first pixels".

public final class LunaCPURenderer {

    /// Render the display list into the framebuffer.
    /// In v0.1 we do not do blending, text, antialiasing, etc.
    public func render(displayList: LunaDisplayList, into framebuffer: inout LunaFramebuffer) {

        for cmd in displayList.commands {
            switch cmd {
            case .clear(let color):
                framebuffer.clear(color)

            case .rect(let rect, let color):
                framebuffer.fillRect(rect, color: color)
            }
        }
    }

    public init() {}
}
