// SPDX-License-Identifier: MPL-2.0
//
// LunaStaticTextScrollInteraction.swift
//
// Deterministic wheel and scrollbar mechanics for Luna text surfaces. Product
// code retains viewport ownership; Luna translates input into a requested visual
// row and preserves fractional device deltas for the caller.

import Foundation
import LunaCore
import LunaInput
import LunaRender

public struct LunaStaticTextWheelScrollResult: Hashable, Sendable {
    public var didConsumeEvent: Bool
    public var requestedScrollTopLine: Int
    public var requestedScrollTopVisualRow: Int?
    public var fractionalRowRemainder: Double

    public init(
        didConsumeEvent: Bool = false,
        requestedScrollTopLine: Int = 0,
        requestedScrollTopVisualRow: Int? = nil,
        fractionalRowRemainder: Double = 0
    ) {
        self.didConsumeEvent = didConsumeEvent
        self.requestedScrollTopLine = max(0, requestedScrollTopLine)
        self.requestedScrollTopVisualRow = requestedScrollTopVisualRow.map { max(0, $0) }
        self.fractionalRowRemainder = fractionalRowRemainder.isFinite
            ? fractionalRowRemainder
            : 0
    }
}

public struct LunaStaticTextScrollbarInteractionState: Hashable, Sendable {
    public var activeSurfaceID: LunaNodeID?
    public var pointerOffsetWithinThumb: Int

    public init(
        activeSurfaceID: LunaNodeID? = nil,
        pointerOffsetWithinThumb: Int = 0
    ) {
        self.activeSurfaceID = activeSurfaceID
        self.pointerOffsetWithinThumb = max(0, pointerOffsetWithinThumb)
    }

    public var isDragging: Bool { activeSurfaceID != nil }

    public mutating func cancel() {
        activeSurfaceID = nil
        pointerOffsetWithinThumb = 0
    }
}

public struct LunaStaticTextScrollbarInteractionResult: Hashable, Sendable {
    public var didConsumeEvent: Bool
    public var didBeginDrag: Bool
    public var didEndDrag: Bool
    public var requestedScrollTopLine: Int?
    public var requestedScrollTopVisualRow: Int?

    public init(
        didConsumeEvent: Bool = false,
        didBeginDrag: Bool = false,
        didEndDrag: Bool = false,
        requestedScrollTopLine: Int? = nil,
        requestedScrollTopVisualRow: Int? = nil
    ) {
        self.didConsumeEvent = didConsumeEvent
        self.didBeginDrag = didBeginDrag
        self.didEndDrag = didEndDrag
        self.requestedScrollTopLine = requestedScrollTopLine.map { max(0, $0) }
        self.requestedScrollTopVisualRow = requestedScrollTopVisualRow.map { max(0, $0) }
    }
}

public enum LunaStaticTextScrollInteraction {
    /// Translate a platform scroll delta into a clamped text viewport request.
    ///
    /// Conventional wheel notches move three rows. Precise devices preserve their
    /// fractional row delta across events through `fractionalRowRemainder`.
    public static func handleScrollEvent(
        _ event: LunaScrollEvent,
        in view: LunaStaticTextView,
        fractionalRowRemainder: Double = 0,
        rowsPerWheelNotch: Double = 3
    ) -> LunaStaticTextWheelScrollResult {
        guard view.bounds.contains(x: event.location.x, y: event.location.y),
              event.deltaY != 0
        else {
            return LunaStaticTextWheelScrollResult(
                fractionalRowRemainder: fractionalRowRemainder
            )
        }

        let multiplier = event.isPrecise ? 1.0 : max(1.0, rowsPerWheelNotch)
        let startingRemainder = event.isPrecise ? fractionalRowRemainder : 0
        let requestedRows = startingRemainder + event.deltaY * multiplier
        let wholeRows = Int(requestedRows.rounded(.towardZero))
        let remainder = event.isPrecise ? requestedRows - Double(wholeRows) : 0

        guard wholeRows != 0 else {
            let layout = view.layout()
            return LunaStaticTextWheelScrollResult(
                didConsumeEvent: true,
                requestedScrollTopLine: layout.firstVisibleLineIndex,
                requestedScrollTopVisualRow: view.wrapMode == .soft
                    ? layout.firstVisibleVisualRowIndex
                    : nil,
                fractionalRowRemainder: remainder
            )
        }

        let scrolled = view.scrolled(byLineDelta: wholeRows)
        let layout = scrolled.layout()
        return LunaStaticTextWheelScrollResult(
            didConsumeEvent: true,
            requestedScrollTopLine: layout.firstVisibleLineIndex,
            requestedScrollTopVisualRow: view.wrapMode == .soft
                ? layout.firstVisibleVisualRowIndex
                : nil,
            fractionalRowRemainder: remainder
        )
    }

    /// Handle thumb dragging and scrollbar-lane paging.
    public static func handlePointerEvent(
        _ event: LunaPointerEvent,
        in view: LunaStaticTextView,
        state: inout LunaStaticTextScrollbarInteractionState
    ) -> LunaStaticTextScrollbarInteractionResult {
        let layout = view.layout()

        if state.activeSurfaceID == view.id {
            switch event.phase {
            case .moved, .down:
                guard let thumb = layout.scrollbarThumbBounds else {
                    state.cancel()
                    return LunaStaticTextScrollbarInteractionResult(
                        didConsumeEvent: true,
                        didEndDrag: true
                    )
                }
                let row = visualRowForDraggedThumb(
                    pointerY: event.location.y,
                    pointerOffsetWithinThumb: state.pointerOffsetWithinThumb,
                    thumb: thumb,
                    layout: layout,
                    metrics: view.metrics
                )
                return LunaStaticTextScrollbarInteractionResult(
                    didConsumeEvent: true,
                    requestedScrollTopLine: lineIndex(
                        forVisualRow: row,
                        in: view
                    ),
                    requestedScrollTopVisualRow: view.wrapMode == .soft ? row : nil
                )

            case .up:
                state.cancel()
                return LunaStaticTextScrollbarInteractionResult(
                    didConsumeEvent: true,
                    didEndDrag: true
                )
            }
        }

        guard event.phase == .down,
              event.button == .primary,
              layout.scrollbarLaneBounds.contains(x: event.location.x, y: event.location.y),
              let thumb = layout.scrollbarThumbBounds
        else {
            return LunaStaticTextScrollbarInteractionResult()
        }

        if thumb.contains(x: event.location.x, y: event.location.y) {
            state.activeSurfaceID = view.id
            state.pointerOffsetWithinThumb = max(0, event.location.y - thumb.y)
            return LunaStaticTextScrollbarInteractionResult(
                didConsumeEvent: true,
                didBeginDrag: true,
                requestedScrollTopLine: layout.firstVisibleLineIndex,
                requestedScrollTopVisualRow: view.wrapMode == .soft
                    ? layout.firstVisibleVisualRowIndex
                    : nil
            )
        }

        let page = max(1, layout.maxVisibleLineCount - 1)
        let direction = event.location.y < thumb.y ? -1 : 1
        let targetVisualRow = min(
            max(0, layout.firstVisibleVisualRowIndex + direction * page),
            layout.maxScrollTopVisualRow
        )
        return LunaStaticTextScrollbarInteractionResult(
            didConsumeEvent: true,
            requestedScrollTopLine: lineIndex(forVisualRow: targetVisualRow, in: view),
            requestedScrollTopVisualRow: view.wrapMode == .soft ? targetVisualRow : nil
        )
    }

    private static func visualRowForDraggedThumb(
        pointerY: Int,
        pointerOffsetWithinThumb: Int,
        thumb: LunaRectI,
        layout: LunaStaticTextViewLayout,
        metrics: LunaStaticTextViewMetrics
    ) -> Int {
        let lane = layout.scrollbarLaneBounds
        let padding = min(max(0, metrics.scrollbarPadding), max(0, lane.w / 2))
        let trackTop = lane.y + padding
        let trackHeight = max(0, lane.h - padding * 2)
        let travel = max(0, trackHeight - thumb.h)
        guard travel > 0, layout.maxScrollTopVisualRow > 0 else { return 0 }

        let requestedThumbY = pointerY - pointerOffsetWithinThumb
        let offset = min(max(0, requestedThumbY - trackTop), travel)
        return Int(
            (Double(offset) * Double(layout.maxScrollTopVisualRow) / Double(travel))
                .rounded(.toNearestOrAwayFromZero)
        )
    }

    private static func lineIndex(
        forVisualRow row: Int,
        in view: LunaStaticTextView
    ) -> Int {
        let clampedRow = min(max(0, row), view.layout().maxScrollTopVisualRow)
        var copy = view
        copy.scrollTopVisualRow = view.wrapMode == .soft ? clampedRow : nil
        if view.wrapMode == .none {
            copy.scrollTopLine = clampedRow
        }
        return copy.layout().firstVisibleLineIndex
    }
}
