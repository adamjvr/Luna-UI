// SPDX-License-Identifier: MPL-2.0

#if os(Linux)
import XCTest
import LunaCore
import LunaHostCore
@testable import LunaHostSDL
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


    func testScrollWheelTranslationPreservesPrecisionAndDirection() {
        let translator = LunaSDLInputTranslator()
        let location = LunaPointI(x: 40, y: 60)

        let conventional = translator.translateScrollWheel(
            integerX: 0,
            integerY: -1,
            preciseX: 0,
            preciseY: 0,
            isFlipped: false,
            location: location
        )
        XCTAssertEqual(conventional.location, location)
        XCTAssertEqual(conventional.deltaY, 1)
        XCTAssertFalse(conventional.isPrecise)

        let precise = translator.translateScrollWheel(
            integerX: 0,
            integerY: 0,
            preciseX: 0.25,
            preciseY: -0.375,
            isFlipped: false,
            location: location
        )
        XCTAssertEqual(precise.deltaX, -0.25, accuracy: 0.0001)
        XCTAssertEqual(precise.deltaY, 0.375, accuracy: 0.0001)
        XCTAssertTrue(precise.isPrecise)

        let flipped = translator.translateScrollWheel(
            integerX: 0,
            integerY: -1,
            preciseX: 0,
            preciseY: 0,
            isFlipped: true,
            location: location
        )
        XCTAssertEqual(flipped.deltaY, -1)
    }

    func testSceneDefaultsToInvalidationDrivenRenderingAndAllowsTermination() {
        var scene = DefaultScene()
        XCTAssertFalse(scene.wantsContinuousRendering)
        XCTAssertTrue(scene.shouldTerminate())

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
