//
//  Entry.swift
//  LunaUITestApp
//
//  Single executable that runs on both macOS + Linux.
//
//  - macOS: AppKit window + custom NSView that presents CPU-rendered pixels.
//  - Linux: SDL2 window via `LunaSDLPresenter`.
//
//  This target is intentionally *small* and shares its CPU demo renderer code
//  across macOS + Linux.

@main
enum Entry {
    @MainActor
    static func main() {
        #if os(macOS)
        runMacDemo()
        #elseif os(Linux)
        runLinuxDemo()
        #else
        fatalError("LunaUITestApp only supports macOS + Linux in this repo.")
        #endif
    }
}
