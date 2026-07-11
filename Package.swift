// swift-tools-version: 6.0
// SPDX-License-Identifier: MPL-2.0
import PackageDescription

let package = Package(
    name: "Luna-UI",
    platforms: [
        .macOS(.v13)
        // Linux supported implicitly
    ],
    products: [
        .library(name: "LunaUI", targets: ["LunaUI"]),
        .library(name: "LunaCore", targets: ["LunaCore"]),
        .library(name: "LunaAccessibility", targets: ["LunaAccessibility"]),
        .library(name: "LunaCommands", targets: ["LunaCommands"]),
        .library(name: "LunaTextCore", targets: ["LunaTextCore"]),
        .library(name: "LunaInput", targets: ["LunaInput"]),
        .library(name: "LunaLayout", targets: ["LunaLayout"]),
        .library(name: "LunaRender", targets: ["LunaRender"]),
        .library(name: "LunaHostCore", targets: ["LunaHostCore"]),
        .library(name: "LunaHostSDL", targets: ["LunaHostSDL"]),
        .executable(name: "LunaUITestApp", targets: ["LunaUITestApp"]),
    ],
    targets: [
        // -------------------------
        // System libraries (C deps)
        // -------------------------

        // SDL2 (Linux presenter / windowing)
        .systemLibrary(
            name: "SDL2",
            pkgConfig: "sdl2",
            providers: [
                .apt(["libsdl2-dev", "pkg-config"]),
                .brew(["sdl2", "pkg-config"])
            ]
        ),





        // FreeType
        .systemLibrary(
            name: "FreeType",
            pkgConfig: "freetype2",
            providers: [
                .apt(["libfreetype6-dev", "pkg-config"]),
                .brew(["freetype", "pkg-config"])
            ]
        ),

        // HarfBuzz
        .systemLibrary(
            name: "HarfBuzz",
            pkgConfig: "harfbuzz",
            providers: [
                .apt(["libharfbuzz-dev", "pkg-config"]),
                .brew(["harfbuzz", "pkg-config"])
            ]
        ),

        // -------------------------
        // Swift targets
        // -------------------------

        .target(
            name: "LunaCore",
            dependencies: []
        ),

        .target(
            name: "LunaAccessibility",
            dependencies: [
                "LunaCore",
            ]
        ),

        .target(
            name: "LunaCommands",
            dependencies: [
                "LunaCore",
            ]
        ),

        .target(
            name: "LunaTheme",
            dependencies: []
        ),

        .target(
            name: "LunaInput",
            dependencies: [
                "LunaCore",
            ]
        ),

        .target(
            name: "LunaLayout",
            dependencies: [
                "LunaCore",
                "LunaRender",
            ]
        ),

        .target(
            name: "LunaTextCore",
            dependencies: []
        ),

        .target(
            name: "LunaText",
            dependencies: [
                "FreeType",
                "HarfBuzz",
                "LunaTextCore",
                "LunaTheme",
            ]
        ),

        .target(
            name: "LunaRender",
            dependencies: [
                "LunaTextCore"
            ]
        ),

        .target(
            name: "LunaHostCore",
            dependencies: [
                "LunaInput",
                "LunaRender",
            ]
        ),

        .target(
            name: "LunaHostSDL",
            dependencies: [
                "LunaCore",
                "LunaHostCore",
                "LunaInput",
                "LunaRender",
                "SDL2",
            ]
        ),

        .target(
            name: "LunaHostMetal",
            dependencies: [
                "LunaHostCore",
                "LunaRender",
            ]
        ),



        .target(
            name: "LunaUI",
            dependencies: [
                "LunaCore",
                "LunaAccessibility",
                "LunaCommands",
                "LunaInput",
                "LunaLayout",
                "LunaTheme",
                "LunaRender",

                // Always available host API surface (platform-agnostic).
                // Concrete platform hosts stay outside LunaUI so pure UI tests do
                // not require SDL/Metal/system headers. Apps opt into hosts.
                "LunaHostCore",
            ]
        ),


        .executableTarget(
            name: "LunaUITestApp",
            dependencies: [
                "LunaUI",
                "LunaCommands",
                "LunaInput",
                "LunaLayout",
                "LunaRender",
                "LunaHostCore",
                .target(name: "LunaHostSDL", condition: .when(platforms: [.linux])),
                .target(name: "SDL2", condition: .when(platforms: [.linux])),
            ]
        ),

        .testTarget(
            name: "LunaHostSDLApplicationTests",
            dependencies: [
                "LunaCore",
                "LunaHostCore",
                "LunaInput",
                "LunaRender",
                .target(name: "LunaHostSDL", condition: .when(platforms: [.linux])),
            ]
        ),

        .testTarget(
            name: "LunaArchitectureTests",
            dependencies: [
                "LunaCore",
                "LunaAccessibility",
                "LunaCommands",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase1Tests",
            dependencies: [
                "LunaUI",
                "LunaInput",
                "LunaLayout",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase2Tests",
            dependencies: [
                "LunaUI",
                "LunaInput",
                "LunaLayout",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase2DTests",
            dependencies: [
                "LunaUI",
                "LunaInput",
                "LunaLayout",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase2ETests",
            dependencies: [
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase3ATests",
            dependencies: [
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase3BTests",
            dependencies: [
                "LunaAccessibility",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase3CTests",
            dependencies: [
                "LunaAccessibility",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase3DTests",
            dependencies: [
                "LunaAccessibility",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase4ATests",
            dependencies: [
                "LunaAccessibility",
                "LunaCommands",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),


        .testTarget(
            name: "LunaUIPhase4BTests",
            dependencies: [
                "LunaAccessibility",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase4B1Tests",
            dependencies: [
                "LunaAccessibility",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase4B2Tests",
            dependencies: [
                "LunaAccessibility",
                "LunaCommands",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase4CTests",
            dependencies: [
                "LunaAccessibility",
                "LunaCommands",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase4DTests",
            dependencies: [
                "LunaAccessibility",
                "LunaCommands",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase4ETests",
            dependencies: [
                "LunaAccessibility",
                "LunaCommands",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase4FTests",
            dependencies: [
                "LunaAccessibility",
                "LunaCommands",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),


        .testTarget(
            name: "LunaUIPhase5ATests",
            dependencies: [
                "LunaCommands",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase5BTests",
            dependencies: [
                "LunaCommands",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase5CTests",
            dependencies: [
                "LunaCommands",
                "LunaInput",
                "LunaUI",
                "LunaTheme",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaUIPhase5ETests",
            dependencies: [
                "LunaInput",
                "LunaUI",
                "LunaRender",
            ]
        ),

        .testTarget(
            name: "LunaHostPhase5C1Tests",
            dependencies: [
                "LunaHostCore",
                "LunaInput",
                "LunaRender",
            ]
        ),
    ]
)
