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
        // Core Luna modules
        // ---------------------------------------------------------------------
        .target(
            name: "LunaRender"
        ),

        // NEW: Theme module (stub for now, becomes Sublime theme parser later)
        .target(
            name: "LunaTheme"
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
                "LunaTheme"
            ]
        ),

        .executableTarget(
            name: "LunaUITestApp",
            dependencies: [
                "LunaUI",
                "LunaRender",
                "LunaHost",
                "LunaTheme",
                "SDL2"
            ]
        ),
    ]
)
