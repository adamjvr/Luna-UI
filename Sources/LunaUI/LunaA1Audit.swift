// SPDX-License-Identifier: MPL-2.0
//
// LunaA1Audit.swift
//
// A1.1 observational scalability-audit support. This file intentionally does
// not alter Luna's production layout or rendering behavior. It wraps public
// framework seams so tests and products can measure the current implementation
// before any corrective virtualization work is approved.

import Foundation
import LunaCore
import LunaRender

/// Stable names for operation counts recorded during the A1.1 audit.
public enum LunaA1AuditCounter: String, CaseIterable, Codable, Hashable, Sendable {
    case measuredOperations
    case staticTextLayoutPasses
    case logicalLinesPresentedToLayout
    case visualRowsProduced
    case visibleRowsProduced
    case geometryRequests
    case completeLineGeometryRequests
    case suffixGeometryRequests
    case framebufferClears
    case framebufferClearBytes
    case framebufferCopies
    case framebufferCopyBytes
    case framebufferRectangleFills
    case framebufferRectanglePixels
}

/// Immutable result suitable for tests, CSV export, and JSON export.
public struct LunaA1AuditSnapshot: Codable, Equatable, Sendable {
    public var counters: [LunaA1AuditCounter: UInt64]
    public var durationsNanoseconds: [String: UInt64]

    public init(
        counters: [LunaA1AuditCounter: UInt64] = [:],
        durationsNanoseconds: [String: UInt64] = [:]
    ) {
        self.counters = counters
        self.durationsNanoseconds = durationsNanoseconds
    }

    public subscript(_ counter: LunaA1AuditCounter) -> UInt64 {
        counters[counter, default: 0]
    }

    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// Thread-safe, process-local recorder used only when an audit harness opts in.
///
/// The recorder is deliberately explicit rather than globally interposed into
/// production paths. This keeps A1.1 observational and prevents measurement code
/// from becoming a permanent dependency of normal rendering behavior.
public final class LunaA1AuditRecorder: @unchecked Sendable {
    public static let shared = LunaA1AuditRecorder()

    private let lock = NSLock()
    private var counters: [LunaA1AuditCounter: UInt64] = [:]
    private var durationsNanoseconds: [String: UInt64] = [:]

    public init() {}

    public func reset() {
        lock.lock()
        counters.removeAll(keepingCapacity: true)
        durationsNanoseconds.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    @inline(__always)
    public func record(_ counter: LunaA1AuditCounter, by amount: UInt64 = 1) {
        guard amount > 0 else { return }
        lock.lock()
        counters[counter, default: 0] &+= amount
        lock.unlock()
    }

    public func recordDuration(label: String, nanoseconds: UInt64) {
        guard !label.isEmpty else { return }
        lock.lock()
        durationsNanoseconds[label, default: 0] &+= nanoseconds
        lock.unlock()
    }

    public func snapshot() -> LunaA1AuditSnapshot {
        lock.lock()
        let result = LunaA1AuditSnapshot(
            counters: counters,
            durationsNanoseconds: durationsNanoseconds
        )
        lock.unlock()
        return result
    }

    @discardableResult
    public func measure<T>(label: String, _ body: () throws -> T) rethrows -> T {
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            let elapsed = start.duration(to: clock.now)
            recordDuration(label: label, nanoseconds: elapsed.a1Nanoseconds)
            record(.measuredOperations)
        }
        return try body()
    }
}

/// Geometry-provider decorator that counts every request without changing the
/// geometry returned to Luna's text surface.
public struct LunaA1CountingGeometryProvider: LunaStaticTextGeometryProvider, Sendable {
    private let base: any LunaStaticTextGeometryProvider
    private let recorder: LunaA1AuditRecorder

    public init(
        base: any LunaStaticTextGeometryProvider,
        recorder: LunaA1AuditRecorder = .shared
    ) {
        self.base = base
        self.recorder = recorder
    }

    public func geometry(for request: LunaStaticTextGeometryRequest) -> LunaStaticTextRowGeometry {
        recorder.record(.geometryRequests)
        if request.utf8Range.lowerBound == 0,
           request.utf8Range.upperBound == request.completeLineText.utf8.count {
            recorder.record(.completeLineGeometryRequests)
        } else if request.utf8Range.upperBound == request.completeLineText.utf8.count {
            recorder.record(.suffixGeometryRequests)
        }
        return base.geometry(for: request)
    }
}

/// Product-neutral audit probe for the current static-text implementation.
public enum LunaA1StaticTextAudit {
    @discardableResult
    public static func layout(
        _ view: LunaStaticTextView,
        recorder: LunaA1AuditRecorder = .shared,
        label: String = "luna.staticText.layout"
    ) -> LunaStaticTextViewLayout {
        recorder.record(.staticTextLayoutPasses)
        recorder.record(
            .logicalLinesPresentedToLayout,
            by: UInt64(max(0, view.document.lineCount))
        )

        let layout = recorder.measure(label: label) {
            view.layout()
        }
        recorder.record(.visualRowsProduced, by: UInt64(layout.totalVisualRowCount))
        recorder.record(.visibleRowsProduced, by: UInt64(layout.visibleLines.count))
        return layout
    }
}

/// Explicit framebuffer wrappers used by audit runners. They preserve ordinary
/// framebuffer semantics while making copied or touched byte counts observable.
public enum LunaA1FramebufferAudit {
    public static func clear(
        _ framebuffer: inout LunaFramebuffer,
        color: LunaRGBA8,
        recorder: LunaA1AuditRecorder = .shared
    ) {
        recorder.record(.framebufferClears)
        recorder.record(
            .framebufferClearBytes,
            by: UInt64(max(0, framebuffer.bytesPerRow * framebuffer.height))
        )
        framebuffer.clear(color)
    }

    public static func copyPixels(
        from source: LunaFramebuffer,
        into destination: inout LunaFramebuffer,
        recorder: LunaA1AuditRecorder = .shared
    ) {
        recorder.record(.framebufferCopies)
        recorder.record(
            .framebufferCopyBytes,
            by: UInt64(max(0, source.bytesPerRow * source.height))
        )
        destination.copyPixels(from: source)
    }

    public static func fillRect(
        _ rect: LunaRectI,
        color: LunaRGBA8,
        in framebuffer: inout LunaFramebuffer,
        recorder: LunaA1AuditRecorder = .shared
    ) {
        let clippedWidth = max(0, min(framebuffer.width, rect.x + rect.w) - max(0, rect.x))
        let clippedHeight = max(0, min(framebuffer.height, rect.y + rect.h) - max(0, rect.y))
        recorder.record(.framebufferRectangleFills)
        recorder.record(
            .framebufferRectanglePixels,
            by: UInt64(clippedWidth * clippedHeight)
        )
        framebuffer.fillRect(rect, color: color)
    }
}

private extension Duration {
    var a1Nanoseconds: UInt64 {
        let components = self.components
        let seconds = components.seconds
        let attoseconds = components.attoseconds
        guard seconds >= 0 else { return 0 }

        let secondNanos = UInt64(seconds).multipliedReportingOverflow(by: 1_000_000_000)
        if secondNanos.overflow { return UInt64.max }
        let fractionalNanos = attoseconds > 0 ? UInt64(attoseconds / 1_000_000_000) : 0
        return secondNanos.partialValue.addingReportingOverflow(fractionalNanos).partialValue
    }
}
