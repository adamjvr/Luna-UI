// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct LunaStaticTextLogicalLineRowSpan: Hashable, Sendable {
    public let logicalLineIndex: Int
    public let firstVisualRowIndex: Int
    public let visualRowCount: Int
    public init(logicalLineIndex: Int, firstVisualRowIndex: Int, visualRowCount: Int) {
        self.logicalLineIndex = max(0, logicalLineIndex)
        self.firstVisualRowIndex = max(0, firstVisualRowIndex)
        self.visualRowCount = max(1, visualRowCount)
    }
    public var visualRowRange: Range<Int> { firstVisualRowIndex..<(firstVisualRowIndex + visualRowCount) }
}

public struct LunaStaticTextVisualRowAddress: Hashable, Sendable {
    public let globalVisualRowIndex: Int
    public let logicalLineIndex: Int
    public let wrappedSegmentIndex: Int
    public init(globalVisualRowIndex: Int, logicalLineIndex: Int, wrappedSegmentIndex: Int) {
        self.globalVisualRowIndex = max(0, globalVisualRowIndex)
        self.logicalLineIndex = max(0, logicalLineIndex)
        self.wrappedSegmentIndex = max(0, wrappedSegmentIndex)
    }
}

public struct LunaStaticTextViewportRowPlan: Hashable, Sendable {
    public let firstVisibleVisualRowIndex: Int
    public let visibleVisualRowRange: Range<Int>
    public let materializedVisualRowRange: Range<Int>
    public let maxVisibleVisualRowCount: Int
    public let totalVisualRowCount: Int
    public let maxScrollTopVisualRow: Int
    public let overscanVisualRowCount: Int

    public init(totalVisualRowCount: Int, requestedTopVisualRow: Int, maxVisibleVisualRowCount: Int, overscanVisualRowCount: Int = 2) {
        let total = max(0, totalVisualRowCount)
        let capacity = max(0, maxVisibleVisualRowCount)
        let overscan = max(0, overscanVisualRowCount)
        let maximumTop = capacity > 0 ? max(0, total - capacity) : 0
        let top = min(max(0, requestedTopVisualRow), maximumTop)
        let visibleEnd = min(total, top + capacity)
        let materializedStart = capacity == 0 ? top : max(0, top - overscan)
        let materializedEnd = capacity == 0 ? top : min(total, visibleEnd + overscan)
        self.firstVisibleVisualRowIndex = top
        self.visibleVisualRowRange = top..<visibleEnd
        self.materializedVisualRowRange = materializedStart..<materializedEnd
        self.maxVisibleVisualRowCount = capacity
        self.totalVisualRowCount = total
        self.maxScrollTopVisualRow = maximumTop
        self.overscanVisualRowCount = overscan
    }
    public var materializedVisualRowCount: Int { materializedVisualRowRange.count }
}

public struct LunaStaticTextVisualRowIndexDiagnostics: Hashable, Sendable {
    public let logicalLineCount: Int
    public let prefixEntryCount: Int
    public let totalVisualRowCount: Int
}

public struct LunaStaticTextVisualRowIndex: Hashable, Sendable {
    private let prefixVisualRows: [Int]
    public let diagnostics: LunaStaticTextVisualRowIndexDiagnostics

    public init(visualRowCountsByLogicalLine counts: [Int]) {
        var prefix = [0]
        prefix.reserveCapacity(counts.count + 1)
        var running = 0
        for count in counts {
            running += max(1, count)
            prefix.append(running)
        }
        prefixVisualRows = prefix
        diagnostics = LunaStaticTextVisualRowIndexDiagnostics(logicalLineCount: counts.count, prefixEntryCount: prefix.count, totalVisualRowCount: running)
    }

    public init(wrapIndices: [LunaStaticTextWrapIndex]) {
        self.init(visualRowCountsByLogicalLine: wrapIndices.map { max(1, $0.visualRowCount) })
    }

    public init(unwrappedLogicalLineCount: Int) {
        self.init(visualRowCountsByLogicalLine: Array(repeating: 1, count: max(0, unwrappedLogicalLineCount)))
    }

    public var logicalLineCount: Int { max(0, prefixVisualRows.count - 1) }
    public var totalVisualRowCount: Int { prefixVisualRows.last ?? 0 }

    public func span(forLogicalLine requested: Int) -> LunaStaticTextLogicalLineRowSpan? {
        guard logicalLineCount > 0 else { return nil }
        let line = min(max(0, requested), logicalLineCount - 1)
        return LunaStaticTextLogicalLineRowSpan(logicalLineIndex: line, firstVisualRowIndex: prefixVisualRows[line], visualRowCount: prefixVisualRows[line + 1] - prefixVisualRows[line])
    }

    public func address(forGlobalVisualRow requested: Int) -> LunaStaticTextVisualRowAddress? {
        guard logicalLineCount > 0, totalVisualRowCount > 0 else { return nil }
        let row = min(max(0, requested), totalVisualRowCount - 1)
        var low = 0
        var high = logicalLineCount
        while low < high {
            let middle = low + (high - low) / 2
            if prefixVisualRows[middle + 1] <= row { low = middle + 1 } else { high = middle }
        }
        let line = min(low, logicalLineCount - 1)
        return LunaStaticTextVisualRowAddress(globalVisualRowIndex: row, logicalLineIndex: line, wrappedSegmentIndex: row - prefixVisualRows[line])
    }

    public func viewportPlan(requestedTopVisualRow: Int, maxVisibleVisualRowCount: Int, overscanVisualRowCount: Int = 2) -> LunaStaticTextViewportRowPlan {
        LunaStaticTextViewportRowPlan(totalVisualRowCount: totalVisualRowCount, requestedTopVisualRow: requestedTopVisualRow, maxVisibleVisualRowCount: maxVisibleVisualRowCount, overscanVisualRowCount: overscanVisualRowCount)
    }

    public func materializedAddresses(for plan: LunaStaticTextViewportRowPlan) -> [LunaStaticTextVisualRowAddress] {
        plan.materializedVisualRowRange.compactMap { address(forGlobalVisualRow: $0) }
    }
}
