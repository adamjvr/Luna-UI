// SPDX-License-Identifier: MPL-2.0
//
// DemoLinux.swift
// LunaUITestApp
//
// Linux entry point using the reusable LunaHostSDL application runner.

#if os(Linux)

import Foundation

import LunaCore
import LunaHostCore
import LunaHostSDL
import LunaInput
import LunaRender
import LunaUI

private struct LunaDemoSDLScene: LunaSDLApplicationScene {
    var demo: LunaCPUDemoScene
    let logsCommandRequests: Bool

    var wantsContinuousRendering: Bool { demo.wantsContinuousRendering }
    var cursorIntent: LunaCursorIntent { demo.cursorIntent }
    var wantsPointerCapture: Bool { demo.wantsPointerCapture }

    mutating func handleHostEvent(
        _ event: LunaHostInputEvent,
        framebufferSize: LunaSizeI
    ) -> LunaFrameInvalidationSet {
        switch event {
        case .quit:
            return LunaFrameInvalidationSet()

        case .windowResized(let size):
            demo.handleWindowResize(size)
            return LunaFrameInvalidationSet(.windowResized)

        case .pointerCaptureLost:
            demo.cancelPointerInteraction()
            return LunaFrameInvalidationSet(.input)

        case .pointer(let pointerEvent):
            let result = demo.handlePointerEvent(
                pointerEvent,
                framebufferSize: framebufferSize
            )
            var invalidations = LunaFrameInvalidationSet()
            if pointerEvent.phase != .moved || result.didChangeVisualState || result.didRequestCommand {
                invalidations.insert(.input)
            }
            if let command = result.requestedCommand {
                invalidations.insert(.commandExecuted)
                if logsCommandRequests {
                    print("Luna demo requested command: \(command.rawValue)")
                }
            }
            return invalidations

        case .keyboard(let keyboardEvent):
            _ = demo.handleKeyboardEvent(
                keyboardEvent,
                framebufferSize: framebufferSize
            )
            return LunaFrameInvalidationSet(.input)

        case .textInput(let textInputEvent):
            _ = demo.handleTextInput(
                textInputEvent,
                framebufferSize: framebufferSize
            )
            return LunaFrameInvalidationSet(Set([.textInput, .documentChanged]))
        }
    }

    mutating func updateFrameRuntimeDiagnostics(
        timingStats: LunaFrameTimingStats,
        invalidations: LunaFrameInvalidationSet,
        inputCoalescingStats: LunaInputCoalescingStats
    ) {
        demo.updateFrameRuntimeDiagnostics(
            timingStats: timingStats,
            invalidations: invalidations,
            inputCoalescingStats: inputCoalescingStats
        )
    }

    mutating func render(into framebuffer: inout LunaFramebuffer) {
        demo.render(into: &framebuffer)
    }
}

func runLinuxDemo() {
    let environment = ProcessInfo.processInfo.environment
    let arguments = Array(CommandLine.arguments.dropFirst())
    let launchOptions = LunaDemoLaunchOptions.parse(
        arguments: arguments,
        environment: environment
    )

    var scene = LunaDemoSDLScene(
        demo: LunaCPUDemoScene(
            theme: MothDemoTheme.theme,
            mode: launchOptions.mode,
            openLocalFilePaths: launchOptions.openFilePaths,
            createLocalFilePaths: launchOptions.createFilePaths,
            newUntitledDocumentCount: launchOptions.newUntitledDocumentCount,
            dialogService: launchOptions.dialogService,
            overwritesDemoSaveAsTarget: launchOptions.overwritesSaveAsTarget,
            overwritesCreatedLocalFiles: launchOptions.overwritesCreatedFiles
        ),
        logsCommandRequests: launchOptions.logsCommandRequests
    )

    let result = runLunaSDLApplication(
        configuration: LunaSDLApplicationConfiguration(
            title: "Luna-UI CPU Demo",
            initialWidth: 960,
            initialHeight: 640
        ),
        scene: &scene
    )

    if result != 0 {
        FileHandle.standardError.write(
            Data("LunaUITestApp host exited with code \(result)\n".utf8)
        )
    }
}

#endif
