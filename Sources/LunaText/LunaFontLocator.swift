// LunaFontLocator.swift
//
// Goal:
// - Pick a font file path that actually supports a script on the current OS,
//   so HarfBuzz shaping doesn't produce .notdef glyphs (gid=0).
//
// Why:
// - DejaVuSans on many Linux installs does NOT include Devanagari glyph coverage,
//   so shaping returns gid=0 even though HarfBuzz is working correctly.
//
// Strategy:
// - Provide per-platform candidate lists.
// - Prefer script-specific Noto fonts when available.
// - Fall back to broadly-coverage fonts when present.
//
// Later:
// - Replace this with a real font discovery system (fontconfig on Linux,
//   CoreText/CTFont on macOS), and/or ship fonts with the app.

import Foundation

public enum LunaScriptHint: Sendable {
    case latin
    case arabic
    case devanagari
    case unknown
}

public enum LunaFontLocator {

    /// Return the best available font path for a given script hint.
    public static func bestFontPath(for script: LunaScriptHint) -> String {

        #if os(Linux)
        // Common locations on Ubuntu/Pop!_OS
        let baseCandidates: [String] = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
        ]

        let devanagariCandidates: [String] = [
            // These are the most common Noto Devanagari installs.
            "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf",
            "/usr/share/fonts/truetype/noto/NotoSerifDevanagari-Regular.ttf",
            // Some distros place them in google-noto style folders; keep a couple guesses:
            "/usr/share/fonts/truetype/noto/NotoSansDevanagariUI-Regular.ttf",
        ]

        let arabicCandidates: [String] = [
            "/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf",
            "/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        ]
        #else
        // macOS candidates (we’ll later switch to CoreText font discovery)
        let baseCandidates: [String] = [
            "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
        ]

        let devanagariCandidates: [String] = [
            "/System/Library/Fonts/Supplemental/Devanagari Sangam MN.ttf",
            "/System/Library/Fonts/Supplemental/NotoSansDevanagari-Regular.ttf",
        ]

        let arabicCandidates: [String] = [
            "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            "/System/Library/Fonts/Supplemental/GeezaPro.ttf",
            "/System/Library/Fonts/Supplemental/Al Bayan.ttf",
        ]
        #endif

        let fm = FileManager.default

        func pickFirstExisting(_ candidates: [String]) -> String? {
            for p in candidates {
                if fm.fileExists(atPath: p) { return p }
            }
            return nil
        }

        let chosen: String? = {
            switch script {
            case .devanagari:
                return pickFirstExisting(devanagariCandidates) ?? pickFirstExisting(baseCandidates)
            case .arabic:
                return pickFirstExisting(arabicCandidates) ?? pickFirstExisting(baseCandidates)
            case .latin:
                return pickFirstExisting(baseCandidates)
            case .unknown:
                return pickFirstExisting(baseCandidates)
            }
        }()

        // If we couldn't find any of our guesses, just return the first base candidate
        // so the caller can still try (and produce a clear error if it truly doesn't exist).
        return chosen ?? baseCandidates.first ?? ""
    }
}
