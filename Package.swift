// swift-tools-version: 6.0
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
                "LunaRender",
            ]
        ),

        .target(
            name: "LunaHostSDL",
            dependencies: [
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
                "LunaInput",
                "LunaLayout",
                "LunaRender",
                .target(name: "LunaHostSDL", condition: .when(platforms: [.linux])),
                .target(name: "SDL2", condition: .when(platforms: [.linux])),
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
    ]
)
