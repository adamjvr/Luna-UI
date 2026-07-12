// SPDX-License-Identifier: MPL-2.0
//
// LunaTextSelectionInteraction.swift
//
// Product-neutral pointer selection gestures for editable text surfaces.
// Applications retain ownership of document mutation and view state; Luna owns
// gesture interpretation, UTF-8-safe text ranges, pointer capture intent, and
// edge-autoscroll requests.

import Foundation
import LunaCore
import LunaHostCore
import LunaInput
import LunaRender

public enum LunaTextSelectionGranularity: String, Hashable, Sendable, CaseIterable {
    case character
    case word
    case line
}

public struct LunaTextSelectionInteractionResult: Hashable, Sendable {
    public var didConsumeEvent: Bool
    public var didChangeSelection: Bool
    public var didBeginGesture: Bool
    public var didEndGesture: Bool
    public var granularity: LunaTextSelectionGranularity?
    public var selection: LunaTextRange?
    public var hitNodeID: LunaNodeID?
    public var requestedVisualRowDelta: Int

    public init(
        didConsumeEvent: Bool = false,
        didChangeSelection: Bool = false,
        didBeginGesture: Bool = false,
        didEndGesture: Bool = false,
        granularity: LunaTextSelectionGranularity? = nil,
        selection: LunaTextRange? = nil,
        hitNodeID: LunaNodeID? = nil,
        requestedVisualRowDelta: Int = 0
    ) {
        self.didConsumeEvent = didConsumeEvent
        self.didChangeSelection = didChangeSelection
        self.didBeginGesture = didBeginGesture
        self.didEndGesture = didEndGesture
        self.granularity = granularity
        self.selection = selection
        self.hitNodeID = hitNodeID
        self.requestedVisualRowDelta = requestedVisualRowDelta
    }
}

/// Persistent state for one active text-selection gesture.
///
/// The state stores only reusable interaction mechanics. Applications map the
/// resulting Luna range into their own editor-view selection representation.
public struct LunaTextSelectionInteractionState: Hashable, Sendable {
    public private(set) var activeSurfaceID: LunaNodeID?
    public private(set) var granularity: LunaTextSelectionGranularity
    public private(set) var originRange: LunaTextRange?
    public private(set) var extensionAnchor: LunaTextLocation?
    public private(set) var lastPointerLocation: LunaPointI?
    public private(set) var autoscrollDirection: Int
    public private(set) var lastAutoscrollTimestampNanoseconds: UInt64?

    public init() {
        self.activeSurfaceID = nil
        self.granularity = .character
        self.originRange = nil
        self.extensionAnchor = nil
        self.lastPointerLocation = nil
        self.autoscrollDirection = 0
        self.lastAutoscrollTimestampNanoseconds = nil
    }

    public var isSelecting: Bool { activeSurfaceID != nil }
    public var wantsPointerCapture: Bool { isSelecting }
    public var wantsContinuousUpdates: Bool { isSelecting && autoscrollDirection != 0 }

    public mutating func cancel() {
        activeSurfaceID = nil
        granularity = .character
        originRange = nil
        extensionAnchor = nil
        lastPointerLocation = nil
        autoscrollDirection = 0
        lastAutoscrollTimestampNanoseconds = nil
    }

    fileprivate mutating func begin(
        surfaceID: LunaNodeID,
        granularity: LunaTextSelectionGranularity,
        originRange: LunaTextRange,
        extensionAnchor: LunaTextLocation?,
        pointerLocation: LunaPointI
    ) {
        self.activeSurfaceID = surfaceID
        self.granularity = granularity
        self.originRange = originRange
        self.extensionAnchor = extensionAnchor
        self.lastPointerLocation = pointerLocation
        self.autoscrollDirection = 0
        self.lastAutoscrollTimestampNanoseconds = nil
    }

    fileprivate mutating func updatePointer(
        _ point: LunaPointI,
        textViewportBounds: LunaRectI
    ) {
        lastPointerLocation = point
        if point.y < textViewportBounds.y {
            autoscrollDirection = -1
        } else if point.y >= textViewportBounds.y + textViewportBounds.h {
            autoscrollDirection = 1
        } else {
            autoscrollDirection = 0
            lastAutoscrollTimestampNanoseconds = nil
        }
    }

    fileprivate mutating func nextAutoscrollDelta(
        textViewportBounds: LunaRectI,
        lineHeight: Int,
        timestampNanoseconds: UInt64
    ) -> Int {
        guard autoscrollDirection != 0, let point = lastPointerLocation else { return 0 }

        let interval: UInt64 = 50_000_000
        if let previous = lastAutoscrollTimestampNanoseconds,
           timestampNanoseconds >= previous,
           timestampNanoseconds - previous < interval {
            return 0
        }
        lastAutoscrollTimestampNanoseconds = timestampNanoseconds

        let distance: Int
        if autoscrollDirection < 0 {
            distance = max(1, textViewportBounds.y - point.y)
        } else {
            distance = max(1, point.y - (textViewportBounds.y + textViewportBounds.h - 1))
        }
        let rows = min(6, max(1, (distance + max(1, lineHeight) - 1) / max(1, lineHeight)))
        return autoscrollDirection * rows
    }
}

public enum LunaTextSelectionInteraction {
    public static func handlePointerEvent(
        _ event: LunaPointerEvent,
        in textView: LunaStaticTextView,
        currentCaret: LunaTextLocation,
        currentSelection: LunaTextRange?,
        state: inout LunaTextSelectionInteractionState,
        timestampNanoseconds: UInt64 = LunaMonotonicClock.nowNanoseconds()
    ) -> LunaTextSelectionInteractionResult {
        guard event.button == .primary else { return LunaTextSelectionInteractionResult() }

        let layout = textView.layout()
        switch event.phase {
        case .down:
            guard layout.textViewportBounds.contains(x: event.location.x, y: event.location.y),
                  let hit = textView.clampedTextHitTest(event.location)
            else {
                state.cancel()
                return LunaTextSelectionInteractionResult()
            }

            let granularity = granularity(forClickCount: event.clickCount)
            let unitRange = selectionUnit(
                at: hit.location,
                granularity: granularity,
                document: textView.document
            )
            let extensionAnchor = event.modifiers.shift
                ? currentSelection?.anchor ?? textView.document.clampedLocation(currentCaret)
                : nil
            state.begin(
                surfaceID: textView.id,
                granularity: granularity,
                originRange: unitRange,
                extensionAnchor: extensionAnchor,
                pointerLocation: event.location
            )
            state.updatePointer(event.location, textViewportBounds: layout.textViewportBounds)

            let selection = resolvedSelection(
                candidateRange: unitRange,
                candidateLocation: hit.location,
                state: state,
                document: textView.document
            )
            return LunaTextSelectionInteractionResult(
                didConsumeEvent: true,
                didChangeSelection: true,
                didBeginGesture: true,
                granularity: granularity,
                selection: selection,
                hitNodeID: hit.nodeID,
                requestedVisualRowDelta: state.nextAutoscrollDelta(
                    textViewportBounds: layout.textViewportBounds,
                    lineHeight: textView.metrics.lineHeight,
                    timestampNanoseconds: timestampNanoseconds
                )
            )

        case .moved:
            guard state.activeSurfaceID == textView.id else { return LunaTextSelectionInteractionResult() }
            state.updatePointer(event.location, textViewportBounds: layout.textViewportBounds)
            guard let hit = textView.clampedTextHitTest(event.location) else {
                return LunaTextSelectionInteractionResult(didConsumeEvent: true)
            }
            let candidate = selectionUnit(
                at: hit.location,
                granularity: state.granularity,
                document: textView.document
            )
            return LunaTextSelectionInteractionResult(
                didConsumeEvent: true,
                didChangeSelection: true,
                granularity: state.granularity,
                selection: resolvedSelection(
                    candidateRange: candidate,
                    candidateLocation: hit.location,
                    state: state,
                    document: textView.document
                ),
                hitNodeID: hit.nodeID,
                requestedVisualRowDelta: state.nextAutoscrollDelta(
                    textViewportBounds: layout.textViewportBounds,
                    lineHeight: textView.metrics.lineHeight,
                    timestampNanoseconds: timestampNanoseconds
                )
            )

        case .up:
            guard state.activeSurfaceID == textView.id else { return LunaTextSelectionInteractionResult() }
            state.updatePointer(event.location, textViewportBounds: layout.textViewportBounds)
            let hit = textView.clampedTextHitTest(event.location)
            let selection: LunaTextRange?
            if let hit {
                let candidate = selectionUnit(
                    at: hit.location,
                    granularity: state.granularity,
                    document: textView.document
                )
                selection = resolvedSelection(
                    candidateRange: candidate,
                    candidateLocation: hit.location,
                    state: state,
                    document: textView.document
                )
            } else {
                selection = state.originRange
            }
            let hitNodeID = hit?.nodeID
            let granularity = state.granularity
            state.cancel()
            return LunaTextSelectionInteractionResult(
                didConsumeEvent: true,
                didChangeSelection: selection != nil,
                didEndGesture: true,
                granularity: granularity,
                selection: selection,
                hitNodeID: hitNodeID
            )
        }
    }

    /// Advance edge autoscroll while the pointer remains outside the viewport.
    /// Callers apply the requested visual-row delta to their view-local scroll
    /// state and apply the returned selection to their application-owned view.
    public static func advanceAutoscroll(
        in textView: LunaStaticTextView,
        state: inout LunaTextSelectionInteractionState,
        timestampNanoseconds: UInt64 = LunaMonotonicClock.nowNanoseconds()
    ) -> LunaTextSelectionInteractionResult {
        guard state.activeSurfaceID == textView.id,
              state.wantsContinuousUpdates,
              let point = state.lastPointerLocation
        else { return LunaTextSelectionInteractionResult() }

        let layout = textView.layout()
        let delta = state.nextAutoscrollDelta(
            textViewportBounds: layout.textViewportBounds,
            lineHeight: textView.metrics.lineHeight,
            timestampNanoseconds: timestampNanoseconds
        )
        guard delta != 0, let hit = textView.clampedTextHitTest(point) else {
            return LunaTextSelectionInteractionResult(didConsumeEvent: true)
        }
        let candidate = selectionUnit(
            at: hit.location,
            granularity: state.granularity,
            document: textView.document
        )
        return LunaTextSelectionInteractionResult(
            didConsumeEvent: true,
            didChangeSelection: true,
            granularity: state.granularity,
            selection: resolvedSelection(
                candidateRange: candidate,
                candidateLocation: hit.location,
                state: state,
                document: textView.document
            ),
            hitNodeID: hit.nodeID,
            requestedVisualRowDelta: delta
        )
    }

    private static func granularity(forClickCount clickCount: Int) -> LunaTextSelectionGranularity {
        if clickCount >= 3 { return .line }
        if clickCount == 2 { return .word }
        return .character
    }

    private static func selectionUnit(
        at location: LunaTextLocation,
        granularity: LunaTextSelectionGranularity,
        document: LunaStaticTextDocument
    ) -> LunaTextRange {
        switch granularity {
        case .character:
            let clamped = document.clampedLocation(location)
            return LunaTextRange(anchor: clamped, focus: clamped)
        case .word:
            return document.wordRange(at: location)
        case .line:
            return document.logicalLineRange(at: location)
        }
    }

    private static func resolvedSelection(
        candidateRange: LunaTextRange,
        candidateLocation: LunaTextLocation,
        state: LunaTextSelectionInteractionState,
        document: LunaStaticTextDocument
    ) -> LunaTextRange {
        let candidate = document.clampedRange(candidateRange)
        if let extensionAnchor = state.extensionAnchor {
            let anchor = document.clampedLocation(extensionAnchor)
            let focus = candidateLocation < anchor ? candidate.anchor : candidate.focus
            return LunaTextRange(anchor: anchor, focus: focus)
        }

        guard let origin = state.originRange.map(document.clampedRange) else {
            let clamped = document.clampedLocation(candidateLocation)
            return LunaTextRange(anchor: clamped, focus: clamped)
        }

        switch state.granularity {
        case .character:
            return LunaTextRange(anchor: origin.anchor, focus: document.clampedLocation(candidateLocation))
        case .word, .line:
            if candidate.focus <= origin.anchor {
                return LunaTextRange(anchor: origin.focus, focus: candidate.anchor)
            }
            if candidate.anchor >= origin.focus {
                return LunaTextRange(anchor: origin.anchor, focus: candidate.focus)
            }
            return origin
        }
    }
}

public extension LunaStaticTextView {
    /// Hit test after clamping a drag point into the visible text viewport.
    /// This lets a captured text gesture continue above, below, or horizontally
    /// outside the original glyph rectangle without inventing invalid positions.
    func clampedTextHitTest(_ point: LunaPointI) -> LunaStaticTextHitResult? {
        let current = layout()
        guard !current.visibleLines.isEmpty, !current.textViewportBounds.isEmpty else { return nil }
        let first = current.visibleLines.first!
        let last = current.visibleLines.last!
        let x = min(
            max(point.x, current.textViewportBounds.x),
            max(current.textViewportBounds.x, current.textViewportBounds.x + current.textViewportBounds.w - 1)
        )
        let y = min(
            max(point.y, first.rowBounds.y),
            max(first.rowBounds.y, last.rowBounds.y + last.rowBounds.h - 1)
        )
        return textHitTest(LunaPointI(x: x, y: y))
    }
}

public extension LunaStaticTextDocument {
    /// Select the contiguous editor word/whitespace/punctuation run containing
    /// the supplied UTF-8 location. All returned columns are exact Character
    /// boundaries even for multibyte text.
    func wordRange(at location: LunaTextLocation) -> LunaTextRange {
        let clamped = clampedLocation(location)
        guard let line = self[line: clamped.lineIndex], !line.text.isEmpty else {
            return LunaTextRange(anchor: clamped, focus: clamped)
        }

        struct Token {
            var start: Int
            var end: Int
            var kind: Int
        }

        func kind(of character: Character) -> Int {
            if character == "_" { return 0 }
            if character.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0) }) {
                return 0
            }
            if character.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                return 1
            }
            return 2
        }

        var tokens: [Token] = []
        var offset = 0
        for character in line.text {
            let length = String(character).utf8.count
            tokens.append(Token(start: offset, end: offset + length, kind: kind(of: character)))
            offset += length
        }
        guard !tokens.isEmpty else { return LunaTextRange(anchor: clamped, focus: clamped) }

        let targetIndex: Int
        if clamped.utf8Column >= line.utf8Length {
            targetIndex = tokens.count - 1
        } else {
            targetIndex = tokens.firstIndex {
                clamped.utf8Column >= $0.start && clamped.utf8Column < $0.end
            } ?? 0
        }

        let targetKind = tokens[targetIndex].kind
        var lower = targetIndex
        var upper = targetIndex
        while lower > 0, tokens[lower - 1].kind == targetKind { lower -= 1 }
        while upper + 1 < tokens.count, tokens[upper + 1].kind == targetKind { upper += 1 }

        return LunaTextRange(
            anchor: LunaTextLocation(lineIndex: line.index, utf8Column: tokens[lower].start),
            focus: LunaTextLocation(lineIndex: line.index, utf8Column: tokens[upper].end)
        )
    }

    /// Select one complete logical line, including its newline when another line
    /// follows. The final line ends at its own final UTF-8 column.
    func logicalLineRange(at location: LunaTextLocation) -> LunaTextRange {
        let clamped = clampedLocation(location)
        let start = LunaTextLocation(lineIndex: clamped.lineIndex, utf8Column: 0)
        if clamped.lineIndex + 1 < lineCount {
            return LunaTextRange(
                anchor: start,
                focus: LunaTextLocation(lineIndex: clamped.lineIndex + 1, utf8Column: 0)
            )
        }
        let end = LunaTextLocation(
            lineIndex: clamped.lineIndex,
            utf8Column: self[line: clamped.lineIndex]?.utf8Length ?? 0
        )
        return LunaTextRange(anchor: start, focus: end)
    }
}
