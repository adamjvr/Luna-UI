// SPDX-License-Identifier: MPL-2.0
//
// LunaA1PerformanceInvestigationTests.swift
//
// A1.1R headless probes for the two performance families observed during native
// acceptance: whole-document text layout and full-frame demo composition. These
// tests measure the current implementation; they do not impose unstable timing
// thresholds and they do not claim to replace SDL/native profiling.

import Foundation
import XCTest
import LunaCore
import LunaRender
import LunaTheme
import LunaUI

final class LunaA1PerformanceInvestigationTests: XCTestCase {
    private let metrics = LunaStaticTextViewMetrics(
        contentInsets: LunaInsetsI(top: 8, right: 10, bottom: 8, left: 0),
        gutterWidth: 52,
        gutterPadding: 6,
        lineHeight: 16,
        glyphMetrics: LunaDebugTextMetrics(scale: 1, advance: 7, lineHeight: 16),
        scrollbarLaneWidth: 8,
        scrollbarPadding: 1,
        scrollbarThumbMinHeight: 14
    )

    func testBoundedProbeRecordsWholeDocumentWorkAndVisibleRowsSeparately() throws {
        let result = measureTextLayout(lineCount: 500, width: 640, wrapMode: .soft)

        XCTAssertEqual(result.lineCount, 500)
        XCTAssertGreaterThan(result.totalVisualRows, 0)
        XCTAssertGreaterThan(result.visibleRows, 0)
        XCTAssertLessThan(result.visibleRows, result.totalVisualRows)
        XCTAssertEqual(result.audit.logicalLinesPresentedToLayout, 500)
        XCTAssertGreaterThan(result.audit.staticTextLayoutPasses, 0)
        XCTAssertGreaterThan(result.elapsedNanoseconds, 0)
        XCTAssertNoThrow(try JSONEncoder().encode(result))
    }

    func testCompositionProxyCountsFullFrameTraffic() throws {
        let result = measureCompositionProxy(width: 1100, height: 720, frameCount: 60)

        XCTAssertEqual(result.frameCount, 60)
        XCTAssertEqual(result.fullFrameCopyCount, 60)
        XCTAssertEqual(result.fullFrameBytesPerCopy, 1100 * 720 * 4)
        XCTAssertEqual(
            result.totalCopiedBytes,
            UInt64(result.fullFrameBytesPerCopy * result.frameCount)
        )
        XCTAssertGreaterThan(result.fullFrameCopyNanoseconds, 0)
        XCTAssertGreaterThan(result.smallDynamicDrawNanoseconds, 0)
        XCTAssertNoThrow(try JSONEncoder().encode(result))
    }

    func testFullInvestigationMatrixWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["LUNA_RUN_A1_PERFORMANCE_PROBE"] == "1" else {
            throw XCTSkip("Set LUNA_RUN_A1_PERFORMANCE_PROBE=1 to execute the expensive A1.1R matrix")
        }

        let outputDirectory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["LUNA_A1_OUTPUT_DIR"]
                ?? ".build/a1.1r-luna-investigation",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        var textResults: [LunaA1TextLayoutProbeResult] = []
        for lineCount in [50, 500, 5_000, 50_000] {
            for width in [320, 720] {
                for wrapMode in [LunaStaticTextWrapMode.none, .soft] {
                    textResults.append(
                        measureTextLayout(
                            lineCount: lineCount,
                            width: width,
                            wrapMode: wrapMode
                        )
                    )
                }
            }
        }

        let compositionResults = [
            measureCompositionProxy(width: 900, height: 600, frameCount: 60),
            measureCompositionProxy(width: 1100, height: 720, frameCount: 60),
            measureCompositionProxy(width: 1920, height: 1080, frameCount: 60),
        ]

        let report = LunaA1PerformanceInvestigationReport(
            generatedAtUTC: ISO8601DateFormatter().string(from: Date()),
            textLayout: textResults,
            composition: compositionResults,
            limitations: [
                "Headless CPU probe only; SDL texture upload and SDL_RenderPresent require native profiling.",
                "Timing values are observations, not pass/fail thresholds.",
                "The composition proxy isolates full-frame memory traffic and a small dynamic draw; it does not recreate every kitchen-sink widget.",
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(
            to: outputDirectory.appendingPathComponent("LUNA_A1.1R_PERFORMANCE_REPORT.json"),
            options: .atomic
        )

        let rows = [LunaA1TextLayoutProbeResult.csvHeader]
            + textResults.map(\.csvRow)
        try (rows.joined(separator: "\n") + "\n").write(
            to: outputDirectory.appendingPathComponent("LUNA_A1.1R_TEXT_LAYOUT.csv"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func measureTextLayout(
        lineCount: Int,
        width: Int,
        wrapMode: LunaStaticTextWrapMode
    ) -> LunaA1TextLayoutProbeResult {
        let text = (0..<lineCount).map { index in
            String(format: "%06d | café Ελληνικά 日本語 🙂 ", index + 1)
                + String(repeating: "wrapped layout probe ", count: 5)
        }.joined(separator: "\n")

        let recorder = LunaA1AuditRecorder()
        let view = LunaStaticTextView(
            id: "luna.a1r.text-probe",
            bounds: LunaRectI(x: 0, y: 0, w: width, h: 720),
            document: LunaStaticTextDocument(text: text),
            theme: .lunaDefaultDark,
            metrics: metrics,
            wrapMode: wrapMode
        )

        let clock = ContinuousClock()
        let start = clock.now
        let layout = LunaA1StaticTextAudit.layout(
            view,
            recorder: recorder,
            label: "luna.a1r.text-layout"
        )
        let elapsed = start.duration(to: clock.now).a1rNanoseconds
        let snapshot = recorder.snapshot()

        return LunaA1TextLayoutProbeResult(
            lineCount: lineCount,
            viewportWidth: width,
            wrapMode: wrapMode.rawValue,
            elapsedNanoseconds: elapsed,
            totalVisualRows: layout.totalVisualRowCount,
            visibleRows: layout.visibleLines.count,
            audit: LunaA1PublicAuditValues(snapshot: snapshot)
        )
    }

    private func measureCompositionProxy(
        width: Int,
        height: Int,
        frameCount: Int
    ) -> LunaA1CompositionProbeResult {
        var cached = LunaFramebuffer(width: width, height: height)
        cached.clear(LunaRGBA8(r: 18, g: 18, b: 20))
        var destination = LunaFramebuffer(width: width, height: height)
        let recorder = LunaA1AuditRecorder()
        let clock = ContinuousClock()

        let copyStart = clock.now
        for _ in 0..<frameCount {
            LunaA1FramebufferAudit.copyPixels(
                from: cached,
                into: &destination,
                recorder: recorder
            )
        }
        let copyNanoseconds = copyStart.duration(to: clock.now).a1rNanoseconds

        let drawStart = clock.now
        for frame in 0..<frameCount {
            let x = 16 + (frame % max(1, width - 48))
            LunaA1FramebufferAudit.fillRect(
                LunaRectI(x: x, y: 24, w: 32, h: 32),
                color: LunaRGBA8(r: 220, g: 220, b: 230),
                in: &destination,
                recorder: recorder
            )
        }
        let drawNanoseconds = drawStart.duration(to: clock.now).a1rNanoseconds
        let snapshot = recorder.snapshot()

        return LunaA1CompositionProbeResult(
            width: width,
            height: height,
            frameCount: frameCount,
            fullFrameCopyCount: Int(snapshot[.framebufferCopies]),
            fullFrameBytesPerCopy: width * height * 4,
            totalCopiedBytes: snapshot[.framebufferCopyBytes],
            fullFrameCopyNanoseconds: copyNanoseconds,
            smallDynamicDrawNanoseconds: drawNanoseconds,
            smallDynamicPixels: snapshot[.framebufferRectanglePixels]
        )
    }
}

private struct LunaA1PublicAuditValues: Codable, Equatable, Sendable {
    var staticTextLayoutPasses: UInt64
    var logicalLinesPresentedToLayout: UInt64
    var visualRowsProduced: UInt64
    var visibleRowsProduced: UInt64
    var geometryRequests: UInt64
    var suffixGeometryRequests: UInt64

    init(snapshot: LunaA1AuditSnapshot) {
        staticTextLayoutPasses = snapshot[.staticTextLayoutPasses]
        logicalLinesPresentedToLayout = snapshot[.logicalLinesPresentedToLayout]
        visualRowsProduced = snapshot[.visualRowsProduced]
        visibleRowsProduced = snapshot[.visibleRowsProduced]
        geometryRequests = snapshot[.geometryRequests]
        suffixGeometryRequests = snapshot[.suffixGeometryRequests]
    }
}

private struct LunaA1TextLayoutProbeResult: Codable, Equatable, Sendable {
    var lineCount: Int
    var viewportWidth: Int
    var wrapMode: String
    var elapsedNanoseconds: UInt64
    var totalVisualRows: Int
    var visibleRows: Int
    var audit: LunaA1PublicAuditValues

    static let csvHeader = [
        "line_count",
        "viewport_width",
        "wrap_mode",
        "elapsed_ns",
        "total_visual_rows",
        "visible_rows",
        "layout_passes",
        "logical_lines_presented",
        "geometry_requests",
        "suffix_geometry_requests",
    ].joined(separator: ",")

    var csvRow: String {
        let columns: [String] = [
            lineCount.description,
            viewportWidth.description,
            wrapMode,
            elapsedNanoseconds.description,
            totalVisualRows.description,
            visibleRows.description,
            audit.staticTextLayoutPasses.description,
            audit.logicalLinesPresentedToLayout.description,
            audit.geometryRequests.description,
            audit.suffixGeometryRequests.description,
        ]
        return columns.joined(separator: ",")
    }
}

private struct LunaA1CompositionProbeResult: Codable, Equatable, Sendable {
    var width: Int
    var height: Int
    var frameCount: Int
    var fullFrameCopyCount: Int
    var fullFrameBytesPerCopy: Int
    var totalCopiedBytes: UInt64
    var fullFrameCopyNanoseconds: UInt64
    var smallDynamicDrawNanoseconds: UInt64
    var smallDynamicPixels: UInt64
}

private struct LunaA1PerformanceInvestigationReport: Codable, Equatable, Sendable {
    var generatedAtUTC: String
    var textLayout: [LunaA1TextLayoutProbeResult]
    var composition: [LunaA1CompositionProbeResult]
    var limitations: [String]
}

private extension Duration {
    var a1rNanoseconds: UInt64 {
        let value = components
        guard value.seconds >= 0 else { return 0 }

        let seconds = UInt64(value.seconds)
        let whole = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        if whole.overflow { return UInt64.max }

        let fraction: UInt64
        if value.attoseconds > 0 {
            fraction = UInt64(value.attoseconds / 1_000_000_000)
        } else {
            fraction = 0
        }

        let sum = whole.partialValue.addingReportingOverflow(fraction)
        return sum.overflow ? UInt64.max : sum.partialValue
    }
}
