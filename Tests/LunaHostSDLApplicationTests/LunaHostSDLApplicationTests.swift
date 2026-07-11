// SPDX-License-Identifier: MPL-2.0

#if os(Linux)
import XCTest
import LunaCore
import LunaHostCore
import LunaHostSDL
import LunaInput
import LunaRender

private struct DefaultScene: LunaSDLApplicationScene {
    mutating func handleHostEvent(
        _ event: LunaHostInputEvent,
        framebufferSize: LunaSizeI
    ) -> LunaFrameInvalidationSet {
        LunaFrameInvalidationSet(.input)
    }

    mutating func render(into framebuffer: inout LunaFramebuffer) {
        framebuffer.clear(LunaRGBA8(r: 1, g: 2, b: 3))
    }
}

final class LunaHostSDLApplicationTests: XCTestCase {
    func testConfigurationClampsInvalidDimensionsAndFrameRate() {
        let configuration = LunaSDLApplicationConfiguration(
            title: "Test",
            initialWidth: 0,
            initialHeight: -1,
            targetFramesPerSecond: 0,
            usesVSync: false
        )

        XCTAssertEqual(configuration.initialWidth, 1)
        XCTAssertEqual(configuration.initialHeight, 1)
        XCTAssertEqual(configuration.targetFramesPerSecond, 1)
        XCTAssertFalse(configuration.usesVSync)
    }

    func testSceneDefaultsToInvalidationDrivenRendering() {
        var scene = DefaultScene()
        XCTAssertFalse(scene.wantsContinuousRendering)

        var framebuffer = LunaFramebuffer(width: 2, height: 2)
        scene.render(into: &framebuffer)

        var bytes: [UInt8] = []
        framebuffer.withUnsafePixelBytes { pointer, count in
            bytes = Array(UnsafeBufferPointer(start: pointer, count: count))
        }
        XCTAssertEqual(Array(bytes.prefix(4)), [3, 2, 1, 255])
    }
}
#endif
