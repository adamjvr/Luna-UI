// SPDX-License-Identifier: MPL-2.0
//
// LunaStaticTextVirtualizedLayout.swift
//
// C2.5F: viewport-bounded text shaping and incremental visual-row indexing.

import Foundation

/// Stable viewport position that survives refinement of estimated wrap counts.
///
/// The logical line is authoritative. `wrappedSegmentIndex` is local to that line,
/// so discovering the exact wrap count of unrelated lines cannot move the anchor.
public struct LunaStaticTextViewportAnchor: Hashable, Sendable {
    public var logicalLineIndex: Int
    public var wrappedSegmentIndex: Int

    public init(logicalLineIndex: Int, wrappedSegmentIndex: Int = 0) {
        self.logicalLineIndex = max(0, logicalLineIndex)
        self.wrappedSegmentIndex = max(0, wrappedSegmentIndex)
    }
}

/// Deterministic operation counts for one virtualized viewport request.
public struct LunaStaticTextVirtualizedLayoutDiagnostics: Hashable, Sendable {
    public var logicalLineCount: Int
    public var visibleVisualRowCount: Int
    public var materializedLogicalLineCount: Int
    public var materializedVisualRowCount: Int
    public var fullLineGeometryRequestCount: Int
    public var segmentGeometryRequestCount: Int
    public var wrapIndexBuildCount: Int
    public var cacheHitCount: Int
    public var estimatedVisualRowCount: Int

    public init(
        logicalLineCount: Int = 0,
        visibleVisualRowCount: Int = 0,
        materializedLogicalLineCount: Int = 0,
        materializedVisualRowCount: Int = 0,
        fullLineGeometryRequestCount: Int = 0,
        segmentGeometryRequestCount: Int = 0,
        wrapIndexBuildCount: Int = 0,
        cacheHitCount: Int = 0,
        estimatedVisualRowCount: Int = 0
    ) {
        self.logicalLineCount = max(0, logicalLineCount)
        self.visibleVisualRowCount = max(0, visibleVisualRowCount)
        self.materializedLogicalLineCount = max(0, materializedLogicalLineCount)
        self.materializedVisualRowCount = max(0, materializedVisualRowCount)
        self.fullLineGeometryRequestCount = max(0, fullLineGeometryRequestCount)
        self.segmentGeometryRequestCount = max(0, segmentGeometryRequestCount)
        self.wrapIndexBuildCount = max(0, wrapIndexBuildCount)
        self.cacheHitCount = max(0, cacheHitCount)
        self.estimatedVisualRowCount = max(0, estimatedVisualRowCount)
    }
}

/// One shaped row emitted by the virtualized layout context.
public struct LunaStaticTextVirtualizedRow: Hashable, Sendable {
    public let globalVisualRowIndex: Int
    public let line: LunaStaticTextLine
    public let wrappedSegmentIndex: Int
    public let utf8Range: Range<Int>
    public let geometry: LunaStaticTextRowGeometry

    public init(
        globalVisualRowIndex: Int,
        line: LunaStaticTextLine,
        wrappedSegmentIndex: Int,
        utf8Range: Range<Int>,
        geometry: LunaStaticTextRowGeometry
    ) {
        self.globalVisualRowIndex = max(0, globalVisualRowIndex)
        self.line = line
        self.wrappedSegmentIndex = max(0, wrappedSegmentIndex)
        let lower = min(max(0, utf8Range.lowerBound), line.utf8Length)
        let upper = min(max(lower, utf8Range.upperBound), line.utf8Length)
        self.utf8Range = lower..<upper
        self.geometry = geometry
    }

    public var startUTF8Column: Int { utf8Range.lowerBound }
    public var endUTF8Column: Int { utf8Range.upperBound }
}

/// Viewport-bounded result returned to `LunaStaticTextView`.
public struct LunaStaticTextVirtualizedViewport: Hashable, Sendable {
    public let firstVisibleAnchor: LunaStaticTextViewportAnchor
    public let firstVisibleVisualRowIndex: Int
    public let visibleRows: [LunaStaticTextVirtualizedRow]
    public let totalVisualRowCount: Int
    public let maxScrollTopVisualRow: Int
    public let maxScrollTopLine: Int
    public let diagnostics: LunaStaticTextVirtualizedLayoutDiagnostics

    public init(
        firstVisibleAnchor: LunaStaticTextViewportAnchor,
        firstVisibleVisualRowIndex: Int,
        visibleRows: [LunaStaticTextVirtualizedRow],
        totalVisualRowCount: Int,
        maxScrollTopVisualRow: Int,
        maxScrollTopLine: Int,
        diagnostics: LunaStaticTextVirtualizedLayoutDiagnostics
    ) {
        self.firstVisibleAnchor = firstVisibleAnchor
        self.firstVisibleVisualRowIndex = max(0, firstVisibleVisualRowIndex)
        self.visibleRows = visibleRows
        self.totalVisualRowCount = max(0, totalVisualRowCount)
        self.maxScrollTopVisualRow = max(0, maxScrollTopVisualRow)
        self.maxScrollTopLine = max(0, maxScrollTopLine)
        self.diagnostics = diagnostics
    }
}

/// Revision-stable cache for lazy line shaping, wrapping, and row materialization.
///
/// A context belongs to exactly one immutable presentation snapshot and one text
/// geometry generation. Width-specific state is retained inside the context, so
/// equal-width panes share line geometry and wrap records without sharing scroll,
/// caret, selection, or focus state.
public final class LunaStaticTextVirtualizationContext: @unchecked Sendable {
    private struct WidthKey: Hashable {
        let viewportWidth: Int
        let wrapMode: LunaStaticTextWrapMode
        let estimatedGlyphAdvance: Int
    }

    private struct LineKey: Hashable {
        let width: WidthKey
        let logicalLineIndex: Int
    }

    private struct SegmentKey: Hashable {
        let line: LineKey
        let wrappedSegmentIndex: Int
    }

    private struct CachedLine: Sendable {
        let fullGeometry: LunaStaticTextRowGeometry
        let wrapIndex: LunaStaticTextWrapIndex
    }

    private final class WidthState: @unchecked Sendable {
        var fenwick: FenwickTree

        init(lineCount: Int, estimatedRowsPerLine: Int) {
            self.fenwick = FenwickTree(
                count: max(0, lineCount),
                baseValue: max(1, estimatedRowsPerLine)
            )
        }

        var lineCount: Int { fenwick.count }

        func rowCount(at index: Int) -> Int {
            fenwick.value(at: index)
        }
    }

    /// Sparse Fenwick tree over a uniform estimate.
    ///
    /// A new pane width allocates no O(document length) row-count array. The base
    /// estimate applies to every logical line, and only lines whose exact wrap
    /// count has been materialized contribute sparse deltas.
    private struct FenwickTree: Sendable {
        let count: Int
        let baseValue: Int
        private var overrides: [Int: Int] = [:]
        private var deltaTree: [Int: Int] = [:]

        init(count: Int, baseValue: Int) {
            self.count = max(0, count)
            self.baseValue = max(1, baseValue)
        }

        var total: Int {
            let base = Self.saturatedMultiply(count, baseValue)
            return Self.saturatedAdd(base, prefixDelta(exclusiveUpperBound: count))
        }

        func value(at index: Int) -> Int {
            guard index >= 0, index < count else { return 0 }
            return overrides[index] ?? baseValue
        }

        mutating func replaceValue(at index: Int, with newValue: Int) {
            guard index >= 0, index < count else { return }
            let normalized = max(1, newValue)
            let old = value(at: index)
            guard old != normalized else { return }
            if normalized == baseValue {
                overrides.removeValue(forKey: index)
            } else {
                overrides[index] = normalized
            }
            addDelta(normalized - old, at: index)
        }

        func prefixSum(exclusiveUpperBound requested: Int) -> Int {
            let upper = min(max(0, requested), count)
            let base = Self.saturatedMultiply(upper, baseValue)
            return Self.saturatedAdd(base, prefixDelta(exclusiveUpperBound: upper))
        }

        /// Return the index whose half-open prefix range contains `row`.
        func index(containingRow requested: Int) -> Int? {
            guard count > 0, total > 0 else { return nil }
            let target = min(max(0, requested), total - 1)
            var low = 0
            var high = count
            while low < high {
                let middle = low + (high - low) / 2
                if prefixSum(exclusiveUpperBound: middle + 1) <= target {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return min(low, count - 1)
        }

        private func prefixDelta(exclusiveUpperBound requested: Int) -> Int {
            var index = min(max(0, requested), count)
            var result = 0
            while index > 0 {
                result = Self.saturatedSignedAdd(result, deltaTree[index] ?? 0)
                index -= index & -index
            }
            return result
        }

        private mutating func addDelta(_ delta: Int, at zeroBasedIndex: Int) {
            var index = zeroBasedIndex + 1
            while index <= count {
                deltaTree[index, default: 0] += delta
                if deltaTree[index] == 0 {
                    deltaTree.removeValue(forKey: index)
                }
                index += index & -index
            }
        }

        private static func saturatedMultiply(_ lhs: Int, _ rhs: Int) -> Int {
            let result = lhs.multipliedReportingOverflow(by: rhs)
            return result.overflow ? Int.max : result.partialValue
        }

        private static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
            let result = lhs.addingReportingOverflow(rhs)
            if !result.overflow { return max(0, result.partialValue) }
            return rhs >= 0 ? Int.max : 0
        }

        private static func saturatedSignedAdd(_ lhs: Int, _ rhs: Int) -> Int {
            let result = lhs.addingReportingOverflow(rhs)
            if !result.overflow { return result.partialValue }
            return rhs >= 0 ? Int.max : Int.min
        }
    }

    public let presentation: LunaStaticTextPresentationSnapshot
    public let geometryGeneration: UInt64
    private let totalDocumentUTF8Length: Int

    private let lock = NSLock()
    private let maximumRetainedWidthCount: Int
    private let maximumRetainedLineCount: Int
    private let maximumRetainedSegmentGeometryCount: Int
    private var accessGeneration: UInt64 = 0
    private var widthStates: [WidthKey: WidthState] = [:]
    private var widthAccess: [WidthKey: UInt64] = [:]
    private var lineCache: [LineKey: CachedLine] = [:]
    private var lineAccess: [LineKey: UInt64] = [:]
    private var segmentGeometryCache: [SegmentKey: LunaStaticTextRowGeometry] = [:]
    private var segmentAccess: [SegmentKey: UInt64] = [:]

    public init(
        presentation: LunaStaticTextPresentationSnapshot,
        geometryGeneration: UInt64 = 0,
        maximumRetainedWidthCount: Int = 4,
        maximumRetainedLineCount: Int = 512,
        maximumRetainedSegmentGeometryCount: Int = 2_048
    ) {
        self.presentation = presentation
        self.geometryGeneration = geometryGeneration
        self.totalDocumentUTF8Length = presentation.document.utf8Count
        self.maximumRetainedWidthCount = max(1, maximumRetainedWidthCount)
        self.maximumRetainedLineCount = max(1, maximumRetainedLineCount)
        self.maximumRetainedSegmentGeometryCount = max(1, maximumRetainedSegmentGeometryCount)
    }

    /// Estimated total rows without shaping any line.
    public func estimatedTotalVisualRowCount(
        viewportWidth: Int,
        wrapMode: LunaStaticTextWrapMode,
        estimatedGlyphAdvance: Int
    ) -> Int {
        let key = widthKey(
            viewportWidth: viewportWidth,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: estimatedGlyphAdvance
        )
        return lock.withLock {
            widthStateLocked(for: key).fenwick.total
        }
    }

    /// Convert a stable line/segment anchor to the current estimated global row.
    public func globalVisualRow(
        for requestedAnchor: LunaStaticTextViewportAnchor,
        viewportWidth: Int,
        wrapMode: LunaStaticTextWrapMode,
        estimatedGlyphAdvance: Int
    ) -> Int {
        let key = widthKey(
            viewportWidth: viewportWidth,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: estimatedGlyphAdvance
        )
        return lock.withLock {
            let state = widthStateLocked(for: key)
            guard state.lineCount > 0 else { return 0 }
            let line = min(max(0, requestedAnchor.logicalLineIndex), state.lineCount - 1)
            let segment = min(
                max(0, requestedAnchor.wrappedSegmentIndex),
                max(0, state.rowCount(at: line) - 1)
            )
            return state.fenwick.prefixSum(exclusiveUpperBound: line) + segment
        }
    }

    /// Convert an estimated global row to a stable logical line/segment anchor.
    public func anchor(
        forGlobalVisualRow requestedRow: Int,
        viewportWidth: Int,
        wrapMode: LunaStaticTextWrapMode,
        estimatedGlyphAdvance: Int
    ) -> LunaStaticTextViewportAnchor {
        let key = widthKey(
            viewportWidth: viewportWidth,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: estimatedGlyphAdvance
        )
        return lock.withLock {
            let state = widthStateLocked(for: key)
            guard let line = state.fenwick.index(containingRow: requestedRow) else {
                return LunaStaticTextViewportAnchor(logicalLineIndex: 0)
            }
            let prefix = state.fenwick.prefixSum(exclusiveUpperBound: line)
            return LunaStaticTextViewportAnchor(
                logicalLineIndex: line,
                wrappedSegmentIndex: max(0, requestedRow - prefix)
            )
        }
    }

    /// Return the estimated global visual row containing a logical text location.
    /// Only the target line is shaped.
    public func globalVisualRow(
        containing location: LunaTextLocation,
        viewportWidth: Int,
        wrapMode: LunaStaticTextWrapMode,
        estimatedGlyphAdvance: Int,
        geometryProvider: (any LunaStaticTextGeometryProvider)?
    ) -> Int {
        let line = min(
            max(0, location.lineIndex),
            max(0, presentation.document.lineCount - 1)
        )
        let result = materializedLine(
            logicalLineIndex: line,
            viewportWidth: viewportWidth,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: estimatedGlyphAdvance,
            geometryProvider: geometryProvider
        )
        let segment = result.cached.wrapIndex.visualRowIndex(
            containingUTF8Column: location.utf8Column
        )
        return globalVisualRow(
            for: LunaStaticTextViewportAnchor(
                logicalLineIndex: line,
                wrappedSegmentIndex: segment
            ),
            viewportWidth: viewportWidth,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: estimatedGlyphAdvance
        )
    }

    /// Materialize only the rows needed for one viewport plus bounded overscan.
    public func viewport(
        requestedTopVisualRow: Int,
        maxVisibleVisualRowCount: Int,
        overscanVisualRowCount: Int = 2,
        viewportWidth: Int,
        wrapMode: LunaStaticTextWrapMode,
        estimatedGlyphAdvance: Int,
        geometryProvider: (any LunaStaticTextGeometryProvider)?
    ) -> LunaStaticTextVirtualizedViewport {
        let lineCount = presentation.document.lineCount
        let visibleCapacity = max(0, maxVisibleVisualRowCount)
        let overscan = max(0, overscanVisualRowCount)
        let width = max(0, viewportWidth)
        let advance = max(1, estimatedGlyphAdvance)
        let widthKey = widthKey(
            viewportWidth: width,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: advance
        )

        var diagnostics = LunaStaticTextVirtualizedLayoutDiagnostics(
            logicalLineCount: lineCount
        )

        let initialTotal = lock.withLock {
            widthStateLocked(for: widthKey).fenwick.total
        }
        diagnostics.estimatedVisualRowCount = initialTotal

        guard visibleCapacity > 0, lineCount > 0 else {
            let maxTop = max(0, initialTotal - visibleCapacity)
            let maxLine = anchor(
                forGlobalVisualRow: maxTop,
                viewportWidth: width,
                wrapMode: wrapMode,
                estimatedGlyphAdvance: advance
            ).logicalLineIndex
            return LunaStaticTextVirtualizedViewport(
                firstVisibleAnchor: LunaStaticTextViewportAnchor(logicalLineIndex: 0),
                firstVisibleVisualRowIndex: 0,
                visibleRows: [],
                totalVisualRowCount: initialTotal,
                maxScrollTopVisualRow: maxTop,
                maxScrollTopLine: maxLine,
                diagnostics: diagnostics
            )
        }

        let initialMaxTop = max(0, initialTotal - visibleCapacity)
        let requested = min(max(0, requestedTopVisualRow), initialMaxTop)
        var firstAnchor = anchor(
            forGlobalVisualRow: requested,
            viewportWidth: width,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: advance
        )

        // Keep the logical anchor stable while its estimated row count is replaced
        // by exact wrapping. This avoids a visible jump when another line is first
        // materialized.
        _ = materializedLine(
            logicalLineIndex: firstAnchor.logicalLineIndex,
            viewportWidth: width,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: advance,
            geometryProvider: geometryProvider,
            diagnostics: &diagnostics
        )
        firstAnchor = normalizedAnchor(
            firstAnchor,
            widthKey: widthKey
        )

        let desiredCount = visibleCapacity + overscan
        var rows: [LunaStaticTextVirtualizedRow] = []
        rows.reserveCapacity(desiredCount)
        var lineIndex = firstAnchor.logicalLineIndex
        var segmentIndex = firstAnchor.wrappedSegmentIndex

        while lineIndex < lineCount, rows.count < desiredCount {
            let result = materializedLine(
                logicalLineIndex: lineIndex,
                viewportWidth: width,
                wrapMode: wrapMode,
                estimatedGlyphAdvance: advance,
                geometryProvider: geometryProvider,
                diagnostics: &diagnostics
            )
            let records = result.cached.wrapIndex.records
            guard !records.isEmpty else {
                lineIndex += 1
                segmentIndex = 0
                continue
            }

            let start = min(max(0, segmentIndex), records.count - 1)
            for recordIndex in start..<records.count where rows.count < desiredCount {
                let record = records[recordIndex]
                let geometryResult = segmentGeometry(
                    logicalLineIndex: lineIndex,
                    record: record,
                    widthKey: widthKey,
                    geometryProvider: geometryProvider
                )
                diagnostics.segmentGeometryRequestCount += geometryResult.didBuild ? 1 : 0
                diagnostics.cacheHitCount += geometryResult.didBuild ? 0 : 1
                let global = globalVisualRow(
                    for: LunaStaticTextViewportAnchor(
                        logicalLineIndex: lineIndex,
                        wrappedSegmentIndex: recordIndex
                    ),
                    viewportWidth: width,
                    wrapMode: wrapMode,
                    estimatedGlyphAdvance: advance
                )
                rows.append(
                    LunaStaticTextVirtualizedRow(
                        globalVisualRowIndex: global,
                        line: result.line,
                        wrappedSegmentIndex: recordIndex,
                        utf8Range: record.utf8Range,
                        geometry: geometryResult.geometry
                    )
                )
            }
            lineIndex += 1
            segmentIndex = 0
        }

        // Near the end of a document, backfill preceding rows so the last page is
        // full rather than leaving a large blank tail.
        if rows.count < visibleCapacity, firstAnchor.logicalLineIndex > 0 {
            var prefix: [LunaStaticTextVirtualizedRow] = []
            var previousLine = firstAnchor.logicalLineIndex - 1
            let needed = visibleCapacity - rows.count
            while previousLine >= 0, prefix.count < needed {
                let result = materializedLine(
                    logicalLineIndex: previousLine,
                    viewportWidth: width,
                    wrapMode: wrapMode,
                    estimatedGlyphAdvance: advance,
                    geometryProvider: geometryProvider,
                    diagnostics: &diagnostics
                )
                for recordIndex in result.cached.wrapIndex.records.indices.reversed()
                    where prefix.count < needed {
                    let record = result.cached.wrapIndex.records[recordIndex]
                    let geometryResult = segmentGeometry(
                        logicalLineIndex: previousLine,
                        record: record,
                        widthKey: widthKey,
                        geometryProvider: geometryProvider
                    )
                    diagnostics.segmentGeometryRequestCount += geometryResult.didBuild ? 1 : 0
                    diagnostics.cacheHitCount += geometryResult.didBuild ? 0 : 1
                    let global = globalVisualRow(
                        for: LunaStaticTextViewportAnchor(
                            logicalLineIndex: previousLine,
                            wrappedSegmentIndex: recordIndex
                        ),
                        viewportWidth: width,
                        wrapMode: wrapMode,
                        estimatedGlyphAdvance: advance
                    )
                    prefix.append(
                        LunaStaticTextVirtualizedRow(
                            globalVisualRowIndex: global,
                            line: result.line,
                            wrappedSegmentIndex: recordIndex,
                            utf8Range: record.utf8Range,
                            geometry: geometryResult.geometry
                        )
                    )
                }
                previousLine -= 1
            }
            prefix.reverse()
            rows.insert(contentsOf: prefix, at: 0)
            if let first = rows.first {
                firstAnchor = LunaStaticTextViewportAnchor(
                    logicalLineIndex: first.line.index,
                    wrappedSegmentIndex: first.wrappedSegmentIndex
                )
            }
        }

        let finalTotal = lock.withLock {
            widthStateLocked(for: widthKey).fenwick.total
        }
        let maxTop = max(0, finalTotal - visibleCapacity)
        let firstGlobal = min(
            globalVisualRow(
                for: firstAnchor,
                viewportWidth: width,
                wrapMode: wrapMode,
                estimatedGlyphAdvance: advance
            ),
            maxTop
        )
        let visibleRows = Array(rows.prefix(visibleCapacity))
        diagnostics.visibleVisualRowCount = visibleRows.count
        diagnostics.materializedVisualRowCount = rows.count
        diagnostics.estimatedVisualRowCount = finalTotal

        let maxLine = anchor(
            forGlobalVisualRow: maxTop,
            viewportWidth: width,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: advance
        ).logicalLineIndex

        return LunaStaticTextVirtualizedViewport(
            firstVisibleAnchor: firstAnchor,
            firstVisibleVisualRowIndex: firstGlobal,
            visibleRows: visibleRows,
            totalVisualRowCount: finalTotal,
            maxScrollTopVisualRow: maxTop,
            maxScrollTopLine: maxLine,
            diagnostics: diagnostics
        )
    }

    public func removeAllCachedGeometry() {
        lock.withLock {
            widthStates.removeAll(keepingCapacity: false)
            widthAccess.removeAll(keepingCapacity: false)
            lineCache.removeAll(keepingCapacity: false)
            lineAccess.removeAll(keepingCapacity: false)
            segmentGeometryCache.removeAll(keepingCapacity: false)
            segmentAccess.removeAll(keepingCapacity: false)
        }
    }

    public var cachedWidthCount: Int {
        lock.withLock { widthStates.count }
    }

    public var cachedLineCount: Int {
        lock.withLock { lineCache.count }
    }

    public var cachedSegmentGeometryCount: Int {
        lock.withLock { segmentGeometryCache.count }
    }

    private func widthKey(
        viewportWidth: Int,
        wrapMode: LunaStaticTextWrapMode,
        estimatedGlyphAdvance: Int
    ) -> WidthKey {
        WidthKey(
            viewportWidth: max(0, viewportWidth),
            wrapMode: wrapMode,
            estimatedGlyphAdvance: max(1, estimatedGlyphAdvance)
        )
    }

    private func normalizedAnchor(
        _ anchor: LunaStaticTextViewportAnchor,
        widthKey: WidthKey
    ) -> LunaStaticTextViewportAnchor {
        lock.withLock {
            let state = widthStateLocked(for: widthKey)
            guard state.lineCount > 0 else {
                return LunaStaticTextViewportAnchor(logicalLineIndex: 0)
            }
            let line = min(max(0, anchor.logicalLineIndex), state.lineCount - 1)
            let segment = min(
                max(0, anchor.wrappedSegmentIndex),
                max(0, state.rowCount(at: line) - 1)
            )
            return LunaStaticTextViewportAnchor(
                logicalLineIndex: line,
                wrappedSegmentIndex: segment
            )
        }
    }

    private func widthStateLocked(for key: WidthKey) -> WidthState {
        if let existing = widthStates[key] {
            touchWidthLocked(key)
            return existing
        }
        let estimatedRowsPerLine: Int
        switch key.wrapMode {
        case .none:
            estimatedRowsPerLine = 1
        case .soft:
            let capacity = max(1, key.viewportWidth / key.estimatedGlyphAdvance)
            let averageUTF8Length = presentation.document.lineCount > 0
                ? max(1, totalDocumentUTF8Length / presentation.document.lineCount)
                : 1
            estimatedRowsPerLine = max(
                1,
                (averageUTF8Length + capacity - 1) / capacity
            )
        }
        let created = WidthState(
            lineCount: presentation.document.lineCount,
            estimatedRowsPerLine: estimatedRowsPerLine
        )
        widthStates[key] = created
        touchWidthLocked(key)
        evictWidthStatesIfNeededLocked(protecting: key)
        return created
    }

    private func materializedLine(
        logicalLineIndex: Int,
        viewportWidth: Int,
        wrapMode: LunaStaticTextWrapMode,
        estimatedGlyphAdvance: Int,
        geometryProvider: (any LunaStaticTextGeometryProvider)?,
        diagnostics: inout LunaStaticTextVirtualizedLayoutDiagnostics
    ) -> (line: LunaStaticTextLine, cached: CachedLine) {
        let result = materializedLine(
            logicalLineIndex: logicalLineIndex,
            viewportWidth: viewportWidth,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: estimatedGlyphAdvance,
            geometryProvider: geometryProvider
        )
        diagnostics.materializedLogicalLineCount += result.didBuild ? 1 : 0
        diagnostics.fullLineGeometryRequestCount += result.didBuild ? 1 : 0
        diagnostics.wrapIndexBuildCount += result.didBuild ? 1 : 0
        diagnostics.cacheHitCount += result.didBuild ? 0 : 1
        return (result.line, result.cached)
    }

    private func materializedLine(
        logicalLineIndex: Int,
        viewportWidth: Int,
        wrapMode: LunaStaticTextWrapMode,
        estimatedGlyphAdvance: Int,
        geometryProvider: (any LunaStaticTextGeometryProvider)?
    ) -> (line: LunaStaticTextLine, cached: CachedLine, didBuild: Bool) {
        let widthKey = widthKey(
            viewportWidth: viewportWidth,
            wrapMode: wrapMode,
            estimatedGlyphAdvance: estimatedGlyphAdvance
        )
        let lineIndex = min(
            max(0, logicalLineIndex),
            max(0, presentation.document.lineCount - 1)
        )
        let lineKey = LineKey(width: widthKey, logicalLineIndex: lineIndex)
        if let cached = lock.withLock({ () -> CachedLine? in
            guard let cached = lineCache[lineKey] else { return nil }
            touchLineLocked(lineKey)
            return cached
        }), let line = presentation.document[line: lineIndex] {
            return (line, cached, false)
        }

        let line = presentation.document[line: lineIndex]
            ?? LunaStaticTextLine(index: 0, text: "", utf8Offset: 0, utf8Length: 0)
        let fullGeometry = geometryProvider?.geometry(
            for: LunaStaticTextGeometryRequest(
                completeLineText: line.text,
                utf8Range: 0..<line.utf8Length
            )
        ) ?? LunaStaticTextRowGeometry.fixedAdvance(
            sourceText: line.text,
            advance: max(1, estimatedGlyphAdvance)
        )
        let wrapIndex: LunaStaticTextWrapIndex
        switch wrapMode {
        case .none:
            wrapIndex = LunaStaticTextWrapIndex(
                sourceUTF8Length: line.utf8Length,
                viewportWidth: viewportWidth,
                records: [
                    LunaStaticTextWrapRecord(
                        visualRowIndex: 0,
                        utf8Range: 0..<line.utf8Length
                    ),
                ],
                diagnostics: LunaStaticTextWrapBuildDiagnostics(
                    graphemeBoundaryCount: line.text.count + 1,
                    widthProbeCount: 0,
                    emittedRecordCount: 1
                )
            )
        case .soft:
            wrapIndex = LunaStaticTextWrapIndex.build(
                sourceText: line.text,
                geometry: fullGeometry,
                viewportWidth: viewportWidth
            )
        }
        let built = CachedLine(fullGeometry: fullGeometry, wrapIndex: wrapIndex)

        let insertion = lock.withLock { () -> (cached: CachedLine, didInsert: Bool) in
            if let existing = lineCache[lineKey] {
                return (existing, false)
            }
            lineCache[lineKey] = built
            touchLineLocked(lineKey)
            let state = widthStateLocked(for: widthKey)
            if lineIndex >= 0, lineIndex < state.lineCount {
                let exact = max(1, built.wrapIndex.visualRowCount)
                state.fenwick.replaceValue(at: lineIndex, with: exact)
            }
            evictLineCacheIfNeededLocked(protecting: lineKey)
            return (built, true)
        }
        return (line, insertion.cached, insertion.didInsert)
    }

    private func segmentGeometry(
        logicalLineIndex: Int,
        record: LunaStaticTextWrapRecord,
        widthKey: WidthKey,
        geometryProvider: (any LunaStaticTextGeometryProvider)?
    ) -> (geometry: LunaStaticTextRowGeometry, didBuild: Bool) {
        let lineKey = LineKey(width: widthKey, logicalLineIndex: logicalLineIndex)
        let segmentKey = SegmentKey(
            line: lineKey,
            wrappedSegmentIndex: record.visualRowIndex
        )
        if let cached = lock.withLock({ () -> LunaStaticTextRowGeometry? in
            guard let cached = segmentGeometryCache[segmentKey] else { return nil }
            touchSegmentLocked(segmentKey)
            return cached
        }) {
            return (cached, false)
        }

        let line = presentation.document[line: logicalLineIndex]
            ?? LunaStaticTextLine(index: 0, text: "", utf8Offset: 0, utf8Length: 0)
        let built = geometryProvider?.geometry(
            for: LunaStaticTextGeometryRequest(
                completeLineText: line.text,
                utf8Range: record.utf8Range
            )
        ) ?? LunaStaticTextRowGeometry.fixedAdvance(
            sourceText: Self.substring(line.text, utf8Range: record.utf8Range),
            advance: widthKey.estimatedGlyphAdvance
        )

        let insertion = lock.withLock { () -> (geometry: LunaStaticTextRowGeometry, didInsert: Bool) in
            if let existing = segmentGeometryCache[segmentKey] {
                touchSegmentLocked(segmentKey)
                return (existing, false)
            }
            segmentGeometryCache[segmentKey] = built
            touchSegmentLocked(segmentKey)
            evictSegmentCacheIfNeededLocked(protecting: segmentKey)
            return (built, true)
        }
        return (insertion.geometry, insertion.didInsert)
    }

    private func nextAccessGenerationLocked() -> UInt64 {
        accessGeneration &+= 1
        return accessGeneration
    }

    private func touchWidthLocked(_ key: WidthKey) {
        widthAccess[key] = nextAccessGenerationLocked()
    }

    private func touchLineLocked(_ key: LineKey) {
        lineAccess[key] = nextAccessGenerationLocked()
        touchWidthLocked(key.width)
    }

    private func touchSegmentLocked(_ key: SegmentKey) {
        segmentAccess[key] = nextAccessGenerationLocked()
        touchLineLocked(key.line)
    }

    private func evictWidthStatesIfNeededLocked(protecting protectedKey: WidthKey) {
        while widthStates.count > maximumRetainedWidthCount {
            guard let victim = widthAccess
                .filter({ $0.key != protectedKey })
                .min(by: { $0.value < $1.value })?.key
            else { break }
            widthStates.removeValue(forKey: victim)
            widthAccess.removeValue(forKey: victim)
            let lineVictims = lineCache.keys.filter { $0.width == victim }
            for lineKey in lineVictims {
                removeLineLocked(lineKey)
            }
        }
    }

    private func evictLineCacheIfNeededLocked(protecting protectedKey: LineKey) {
        while lineCache.count > maximumRetainedLineCount {
            guard let victim = lineAccess
                .filter({ $0.key != protectedKey })
                .min(by: { $0.value < $1.value })?.key
            else { break }
            removeLineLocked(victim)
        }
    }

    private func evictSegmentCacheIfNeededLocked(protecting protectedKey: SegmentKey) {
        while segmentGeometryCache.count > maximumRetainedSegmentGeometryCount {
            guard let victim = segmentAccess
                .filter({ $0.key != protectedKey })
                .min(by: { $0.value < $1.value })?.key
            else { break }
            segmentGeometryCache.removeValue(forKey: victim)
            segmentAccess.removeValue(forKey: victim)
        }
    }

    private func removeLineLocked(_ key: LineKey) {
        lineCache.removeValue(forKey: key)
        lineAccess.removeValue(forKey: key)
        let segmentVictims = segmentGeometryCache.keys.filter { $0.line == key }
        for segmentKey in segmentVictims {
            segmentGeometryCache.removeValue(forKey: segmentKey)
            segmentAccess.removeValue(forKey: segmentKey)
        }
    }

    private static func substring(_ text: String, utf8Range: Range<Int>) -> String {
        let request = LunaStaticTextGeometryRequest(
            completeLineText: text,
            utf8Range: utf8Range
        )
        return request.sourceText
    }
}
