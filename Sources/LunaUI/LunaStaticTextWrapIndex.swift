// SPDX-License-Identifier: MPL-2.0
//
// LunaStaticTextWrapIndex.swift
//
// C2.5B: single-shape soft-wrap records.
//
// A logical line is shaped once. Wrap decisions are then made from insertion
// positions in that complete geometry rather than repeatedly shaping suffixes.

import Foundation

/// One visual continuation row within a logical line.
public struct LunaStaticTextWrapRecord: Hashable, Sendable {
    public let visualRowIndex: Int
    public let utf8Range: Range<Int>

    public init(visualRowIndex: Int, utf8Range: Range<Int>) {
        self.visualRowIndex = max(0, visualRowIndex)
        let lower = max(0, utf8Range.lowerBound)
        self.utf8Range = lower..<max(lower, utf8Range.upperBound)
    }

    public var startUTF8Column: Int { utf8Range.lowerBound }
    public var endUTF8Column: Int { utf8Range.upperBound }
}

/// Diagnostics used by operation-count regressions.
///
/// These counters describe deterministic work rather than wall-clock timing, so
/// normal CI can enforce scalability without depending on machine speed.
public struct LunaStaticTextWrapBuildDiagnostics: Hashable, Sendable {
    public let graphemeBoundaryCount: Int
    public let widthProbeCount: Int
    public let emittedRecordCount: Int

    public init(
        graphemeBoundaryCount: Int,
        widthProbeCount: Int,
        emittedRecordCount: Int
    ) {
        self.graphemeBoundaryCount = max(0, graphemeBoundaryCount)
        self.widthProbeCount = max(0, widthProbeCount)
        self.emittedRecordCount = max(0, emittedRecordCount)
    }
}

/// Immutable wrap index for one logical line and one viewport width.
public struct LunaStaticTextWrapIndex: Hashable, Sendable {
    public let sourceUTF8Length: Int
    public let viewportWidth: Int
    public let records: [LunaStaticTextWrapRecord]
    public let diagnostics: LunaStaticTextWrapBuildDiagnostics

    public init(
        sourceUTF8Length: Int,
        viewportWidth: Int,
        records: [LunaStaticTextWrapRecord],
        diagnostics: LunaStaticTextWrapBuildDiagnostics
    ) {
        self.sourceUTF8Length = max(0, sourceUTF8Length)
        self.viewportWidth = max(0, viewportWidth)
        self.records = records
        self.diagnostics = diagnostics
    }

    public var visualRowCount: Int { records.count }

    /// Return the visual row containing a logical UTF-8 column.
    public func visualRowIndex(containingUTF8Column column: Int) -> Int {
        guard !records.isEmpty else { return 0 }
        let clamped = min(max(0, column), sourceUTF8Length)
        if clamped == sourceUTF8Length {
            return records.count - 1
        }
        return records.firstIndex { $0.utf8Range.contains(clamped) }
            ?? records.count - 1
    }

    /// Build wrap records from one complete shaped-line geometry.
    ///
    /// `LunaStaticTextRowGeometry` already contains insertion positions for the
    /// complete source line. The algorithm probes those positions with binary
    /// search and never asks the shaping provider to shape a suffix or segment.
    public static func build(
        sourceText: String,
        geometry: LunaStaticTextRowGeometry,
        viewportWidth: Int
    ) -> LunaStaticTextWrapIndex {
        let length = sourceText.utf8.count
        let width = max(1, viewportWidth)
        let boundaries = graphemeBoundaries(in: sourceText)
        var probes = 0

        guard length > 0 else {
            let record = LunaStaticTextWrapRecord(visualRowIndex: 0, utf8Range: 0..<0)
            return LunaStaticTextWrapIndex(
                sourceUTF8Length: 0,
                viewportWidth: viewportWidth,
                records: [record],
                diagnostics: LunaStaticTextWrapBuildDiagnostics(
                    graphemeBoundaryCount: boundaries.count,
                    widthProbeCount: 0,
                    emittedRecordCount: 1
                )
            )
        }

        var records: [LunaStaticTextWrapRecord] = []
        var startBoundaryIndex = 0

        while startBoundaryIndex < boundaries.count - 1 {
            let start = boundaries[startBoundaryIndex]
            let startX = geometry.x(forUTF8Offset: start)

            var low = startBoundaryIndex + 1
            var high = boundaries.count - 1
            var best = low

            while low <= high {
                let middle = low + (high - low) / 2
                let end = boundaries[middle]
                probes += 1
                let measuredWidth = geometry.x(forUTF8Offset: end) - startX
                if measuredWidth <= width {
                    best = middle
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }

            // Progress by at least one grapheme even when one glyph is wider than
            // the viewport.
            best = max(startBoundaryIndex + 1, best)

            if best < boundaries.count - 1,
               let preferred = preferredWhitespaceBoundary(
                    in: sourceText,
                    boundaries: boundaries,
                    startBoundaryIndex: startBoundaryIndex,
                    fittingBoundaryIndex: best
               ) {
                best = preferred
            }

            let end = boundaries[best]
            records.append(
                LunaStaticTextWrapRecord(
                    visualRowIndex: records.count,
                    utf8Range: start..<end
                )
            )
            startBoundaryIndex = best
        }

        return LunaStaticTextWrapIndex(
            sourceUTF8Length: length,
            viewportWidth: viewportWidth,
            records: records,
            diagnostics: LunaStaticTextWrapBuildDiagnostics(
                graphemeBoundaryCount: boundaries.count,
                widthProbeCount: probes,
                emittedRecordCount: records.count
            )
        )
    }

    private static func graphemeBoundaries(in text: String) -> [Int] {
        var result = [0]
        result.reserveCapacity(text.count + 1)
        var offset = 0
        for character in text {
            offset += String(character).utf8.count
            result.append(offset)
        }
        return result
    }

    private static func preferredWhitespaceBoundary(
        in text: String,
        boundaries: [Int],
        startBoundaryIndex: Int,
        fittingBoundaryIndex: Int
    ) -> Int? {
        guard fittingBoundaryIndex > startBoundaryIndex else { return nil }

        var characterIndex = 0
        var candidate: Int?
        for character in text {
            let boundaryIndex = characterIndex + 1
            if boundaryIndex > fittingBoundaryIndex { break }
            if boundaryIndex > startBoundaryIndex,
               character == " " || character == "\t" {
                candidate = boundaryIndex
            }
            characterIndex += 1
        }

        guard let candidate, candidate > startBoundaryIndex else { return nil }
        return candidate
    }
}
