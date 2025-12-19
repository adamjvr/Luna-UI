// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Luna-UI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LunaUI", targets: ["LunaUI"]),
        .executable(name: "LunaUITestApp", targets: ["LunaUITestApp"]),
    ],
    targets: [

        // ---------------------------------------------------------------------
        // SDL2 system library (Linux windowing / presentation)
        // ---------------------------------------------------------------------
        .systemLibrary(
            name: "SDL2",
            pkgConfig: "sdl2",
            providers: [
                .apt(["libsdl2-dev", "pkg-config"]),
                .brew(["sdl2", "pkg-config"])
            ]
        ),

        // ---------------------------------------------------------------------
        // HarfBuzz + FreeType system libraries (cross-platform text shaping)
        //
        // Ubuntu / Pop!_OS:
        //   sudo apt install libharfbuzz-dev libfreetype6-dev pkg-config
        //
        // macOS:
        //   brew install harfbuzz freetype pkg-config
        // ---------------------------------------------------------------------
        .systemLibrary(
            name: "HarfBuzz",
            pkgConfig: "harfbuzz",
            providers: [
                .apt(["libharfbuzz-dev", "pkg-config"]),
                .brew(["harfbuzz", "pkg-config"])
            ]
        ),

        .systemLibrary(
            name: "FreeType",
            pkgConfig: "freetype2",
            providers: [
                .apt(["libfreetype6-dev", "pkg-config"]),
                .brew(["freetype", "pkg-config"])
            ]
        ),

        // ---------------------------------------------------------------------
        // Core Luna modules
        // ---------------------------------------------------------------------
        .target(name: "LunaRender"),

        .target(name: "LunaTheme"),

        // NEW: LunaText (shaping + font loading)
        .target(
            name: "LunaText",
            dependencies: [
                "HarfBuzz",
                "FreeType"
            ]
        ),

        .target(
            name: "LunaHost",
            dependencies: [
                "LunaRender",
                "SDL2"
            ]
        ),

        .target(
            name: "LunaUI",
            dependencies: [
                "LunaRender",
                "LunaHost",
                "LunaTheme",
                "LunaText"
            ]
        ),

        .executableTarget(
            name: "LunaUITestApp",
            dependencies: [
                "LunaUI",
                "LunaRender",
                "LunaHost",
                "LunaTheme",
                "LunaText",
                "SDL2"
            ]
        ),
    ]
)
