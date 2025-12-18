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
        // We build up the targets list in Swift so we can add SDL2 only on Linux.
        // This prevents SwiftPM from trying to resolve pkg-config / sdl2.pc on macOS.
        var targets: [Target] = [
            // Core modules
            .target(name: "LunaCore"),
            .target(name: "LunaShaping"),
            .target(name: "LunaLayout"),
            .target(name: "LunaRender"),
            .target(name: "LunaTheme"),
            .target(name: "LunaChrome"),
            .target(name: "LunaInput"),
            .target(name: "LunaHost"),

            // Public umbrella module
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
        // SDL2 is only needed for the Linux test harness window.
        // Keeping it Linux-only avoids pkg-config warnings on macOS.
        targets.append(
            .systemLibrary(
                name: "SDL2",
                pkgConfig: "sdl2",
                providers: [
                    .apt(["libsdl2-dev"])
                ]
            )
        )

        targets.append(
            .executableTarget(
                name: "LunaUITestApp",
                dependencies: ["LunaUI", "SDL2"]
            )
        )
        #else
        // macOS test harness uses AppKit; no SDL2 dependency.
        targets.append(
            .executableTarget(
                name: "LunaUITestApp",
                dependencies: ["LunaUI"]
            )
        )
        #endif

        return targets
    }()
)
