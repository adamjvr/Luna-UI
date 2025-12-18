// swift-tools-version: 6.2.3
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
    targets: [
        .systemLibrary(
            name: "SDL2",
            pkgConfig: "sdl2",
            providers: [
                .apt(["libsdl2-dev"])
            ]
        ),

        .target(name: "LunaCore"),
        .target(name: "LunaShaping"),
        .target(name: "LunaLayout"),
        .target(name: "LunaRender"),
        .target(name: "LunaTheme"),
        .target(name: "LunaChrome"),
        .target(name: "LunaInput"),
        .target(name: "LunaHost"),

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

        .executableTarget(
            name: "LunaUITestApp",
            dependencies: ["LunaUI", "SDL2"]
        )
    ]
)
