// swift-tools-version: 6.0.3

import PackageDescription

let package = Package(
    name: "LunaUI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LunaUI", targets: ["LunaUI"]),
        .executable(name: "LunaUITestApp", targets: ["LunaUITestApp"])
    ],
    targets: {
        // Build targets list dynamically so SDL2 is only resolved on Linux.
        // This prevents pkg-config / sdl2.pc warnings on macOS.
        var targets: [Target] = [

            // Core modules (pure Swift, platform-neutral)
            .target(name: "LunaCore"),
            .target(name: "LunaShaping"),
            .target(name: "LunaLayout"),
            .target(name: "LunaRender"),
            .target(name: "LunaTheme"),
            .target(name: "LunaChrome"),
            .target(name: "LunaInput"),

            // Host layer:
            // - macOS: AppKit presentation helpers
            // - Linux: SDL presentation helpers
            //
            // IMPORTANT:
            // LunaHost must depend on LunaRender because it presents the shared
            // CPU framebuffer type (LunaFramebuffer) defined in LunaRender.
            .target(
                name: "LunaHost",
                dependencies: ["LunaRender"]
            ),

            // Public umbrella module for consumers (moth-text).
            .target(
                name: "LunaUI",
                dependencies: [
                    "LunaCore",
                    "LunaShaping",
                    "LunaLayout",
                    "LunaRender",
                    "LunaTheme",
                    "LunaChrome",
                    "LunaInput",
                    "LunaHost"
                ]
            ),
        ]

        #if os(Linux)
        // SDL2 is only required on Linux for the test harness and Linux presentation.
        targets.append(
            .systemLibrary(
                name: "SDL2",
                pkgConfig: "sdl2",
                providers: [
                    .apt(["libsdl2-dev"])
                ]
            )
        )

        // Linux test harness depends on SDL2.
        targets.append(
            .executableTarget(
                name: "LunaUITestApp",
                dependencies: ["LunaUI", "LunaRender", "LunaHost", "SDL2"]
            )
        )
        #else
        // macOS test harness uses AppKit; no SDL2 dependency.
        targets.append(
            .executableTarget(
                name: "LunaUITestApp",
                dependencies: ["LunaUI", "LunaRender", "LunaHost"]
            )
        )
        #endif

        return targets
    }()
)
