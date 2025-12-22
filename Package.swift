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
            name: "LunaTheme",
            dependencies: []
        ),

        .target(
            name: "LunaText",
            dependencies: [
                "FreeType",
                "HarfBuzz",
                "LunaTheme",
            ]
        ),

        .target(
            name: "LunaRender",
            dependencies: [
                "LunaText"
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
                "LunaTheme",
                "LunaText",
                "LunaRender",

                // Always available host API surface (platform-agnostic)
                "LunaHostCore",

                // Platform host implementations (only linked where they exist)
                .target(name: "LunaHostSDL", condition: .when(platforms: [.linux])),
                .target(name: "LunaHostMetal", condition: .when(platforms: [.macOS])),
            ]
        ),


        .executableTarget(
            name: "LunaUITestApp",
            dependencies: [
                "LunaUI"
            ]
        ),
    ]
)
