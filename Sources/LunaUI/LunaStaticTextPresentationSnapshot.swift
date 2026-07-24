// SPDX-License-Identifier: MPL-2.0
//
// LunaStaticTextPresentationSnapshot.swift
//
// C2.5A: revision-stable text presentation and viewport-bounded unwrapped
// materialization.
//
// This file is intentionally additive. It establishes the reusable presentation
// and planning contracts that LunaStaticTextView will consume in the following
// integration checkpoint, while allowing Moth to begin sharing one immutable
// source presentation across panes immediately.

import Foundation

/// Immutable presentation input for one logical document revision.
///
/// A snapshot owns the revision-stable document representation shared by all
/// consumers that display the same source revision. Viewport state such as scroll
/// position, selection, caret, and wrap width deliberately remains outside this
/// object because those values are pane-local.
///
/// The class has reference identity by design: callers can cheaply verify that
/// multiple panes and auxiliary views are consuming the same presentation.
///
/// `LunaStaticTextDocument` is a value type whose stored properties are immutable
/// through this API. The snapshot exposes only `let` properties, so sharing an
/// instance across concurrency domains is safe.
public final class LunaStaticTextPresentationSnapshot: @unchecked Sendable {
    /// Monotonically increasing revision supplied by the product document model.
    public let revision: UInt64

    /// Revision-stable logical text document.
    public let document: LunaStaticTextDocument

    /// Create a presentation snapshot for one document revision.
    ///
    /// - Parameters:
    ///   - revision: Product-owned revision number. Luna does not assign or mutate
    ///     revisions.
    ///   - document: Immutable logical-line snapshot for that revision.
    public init(revision: UInt64, document: LunaStaticTextDocument) {
        self.revision = revision
        self.document = document
    }

    /// Convenience initializer that parses source text exactly once.
    public convenience init(revision: UInt64, text: String) {
        self.init(revision: revision, document: LunaStaticTextDocument(text: text))
    }

    /// Number of logical lines in the revision.
    public var logicalLineCount: Int {
        document.lineCount
    }

    /// Build the unwrapped viewport plan for one pane.
    ///
    /// This operation is O(1). Materializing the returned range is O(V), where V
    /// is the visible row count plus bounded overscan, independent of total
    /// document length.
    public func unwrappedViewportPlan(
        requestedTopLine: Int,
        maxVisibleLineCount: Int,
        overscanLineCount: Int = 2
    ) -> LunaUnwrappedViewportPlan {
        LunaUnwrappedViewportPlan(
            documentLineCount: document.lineCount,
            requestedTopLine: requestedTopLine,
            maxVisibleLineCount: maxVisibleLineCount,
            overscanLineCount: overscanLineCount
        )
    }

    /// Materialize only the lines requested by an unwrapped viewport plan.
    ///
    /// The returned lines preserve their original document indices and absolute
    /// UTF-8 offsets. No pane-specific coordinate translation is introduced.
    public func materializedLines(
        for plan: LunaUnwrappedViewportPlan
    ) -> ArraySlice<LunaStaticTextLine> {
        document.lines[plan.materializedLineRange]
    }
}

/// Constant-time plan for an unwrapped text viewport.
///
/// In unwrapped mode every logical line maps to exactly one visual row. Therefore
/// total row count, maximum scroll position, scrollbar proportions, and the
/// viewport slice can be derived arithmetically without scanning or shaping the
/// whole document.
public struct LunaUnwrappedViewportPlan: Hashable, Sendable {
    /// Clamped first visible logical line.
    public let firstVisibleLineIndex: Int

    /// Half-open logical-line range visible inside the viewport.
    public let visibleLineRange: Range<Int>

    /// Half-open range to materialize, including bounded overscan.
    public let materializedLineRange: Range<Int>

    /// Number of rows that fit inside the viewport.
    public let maxVisibleLineCount: Int

    /// Total visual rows. In unwrapped mode this equals logical line count.
    public let totalVisualRowCount: Int

    /// Largest valid first visible row.
    public let maxScrollTopLine: Int

    /// Effective overscan requested on each side of the viewport.
    public let overscanLineCount: Int

    /// Number of logical lines that downstream geometry code needs to inspect.
    public var materializedLineCount: Int {
        materializedLineRange.count
    }

    /// Number of lines actually visible, excluding overscan.
    public var visibleLineCount: Int {
        visibleLineRange.count
    }

    public init(
        documentLineCount: Int,
        requestedTopLine: Int,
        maxVisibleLineCount: Int,
        overscanLineCount: Int = 2
    ) {
        let lineCount = max(0, documentLineCount)
        let visibleCapacity = max(0, maxVisibleLineCount)
        let overscan = max(0, overscanLineCount)
        let maximumTop = visibleCapacity > 0
            ? max(0, lineCount - visibleCapacity)
            : 0
        let clampedTop = min(max(0, requestedTopLine), maximumTop)
        let visibleEnd = min(lineCount, clampedTop + visibleCapacity)
        let materializedStart: Int
        let materializedEnd: Int
        if visibleCapacity == 0 {
            // A zero-height viewport must not trigger speculative geometry work.
            materializedStart = clampedTop
            materializedEnd = clampedTop
        } else {
            materializedStart = max(0, clampedTop - overscan)
            materializedEnd = min(lineCount, visibleEnd + overscan)
        }

        self.firstVisibleLineIndex = clampedTop
        self.visibleLineRange = clampedTop..<visibleEnd
        self.materializedLineRange = materializedStart..<materializedEnd
        self.maxVisibleLineCount = visibleCapacity
        self.totalVisualRowCount = lineCount
        self.maxScrollTopLine = maximumTop
        self.overscanLineCount = overscan
    }
}
