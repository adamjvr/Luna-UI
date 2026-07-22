// SPDX-License-Identifier: MPL-2.0
//
// LunaStaticTextGeometry.swift
//
// Product-neutral horizontal geometry consumed by Luna text surfaces. Concrete
// shapers live outside LunaUI; editor widgets receive immutable insertion
// positions so rendering, caret, selection, hit testing, and wrapping share one
// coordinate system.

import Foundation

public struct LunaStaticTextInsertionPosition: Hashable, Sendable {
    public var utf8Offset: Int
    public var x26Dot6: Int32

    public init(utf8Offset: Int, x26Dot6: Int32) {
        self.utf8Offset = max(0, utf8Offset)
        self.x26Dot6 = x26Dot6
    }
}

/// Immutable horizontal geometry for one source substring.
///
/// `sourceText` preserves editor coordinates. `renderedText` may differ when a
/// product expands presentation-only characters such as tabs. Every insertion
/// position is expressed in source UTF-8 offsets and HarfBuzz-style 26.6 pixels.
public struct LunaStaticTextRowGeometry: Hashable, Sendable {
    public var sourceText: String
    public var renderedText: String
    public var insertionPositions: [LunaStaticTextInsertionPosition]
    public var advance26Dot6: Int32

    public init(
        sourceText: String,
        renderedText: String? = nil,
        insertionPositions: [LunaStaticTextInsertionPosition],
        advance26Dot6: Int32
    ) {
        let sourceLength = sourceText.utf8.count
        self.sourceText = sourceText
        self.renderedText = renderedText ?? sourceText
        self.advance26Dot6 = max(0, advance26Dot6)

        var normalized = insertionPositions
            .map {
                LunaStaticTextInsertionPosition(
                    utf8Offset: min(max(0, $0.utf8Offset), sourceLength),
                    x26Dot6: min(max(0, $0.x26Dot6), max(0, advance26Dot6))
                )
            }
            .sorted {
                if $0.utf8Offset != $1.utf8Offset { return $0.utf8Offset < $1.utf8Offset }
                return $0.x26Dot6 < $1.x26Dot6
            }

        var deduplicated: [LunaStaticTextInsertionPosition] = []
        deduplicated.reserveCapacity(normalized.count + 2)
        for position in normalized {
            if deduplicated.last?.utf8Offset == position.utf8Offset {
                deduplicated[deduplicated.count - 1] = position
            } else {
                deduplicated.append(position)
            }
        }
        normalized = deduplicated

        if normalized.first?.utf8Offset != 0 {
            normalized.insert(LunaStaticTextInsertionPosition(utf8Offset: 0, x26Dot6: 0), at: 0)
        }
        if normalized.last?.utf8Offset != sourceLength {
            normalized.append(
                LunaStaticTextInsertionPosition(
                    utf8Offset: sourceLength,
                    x26Dot6: max(0, advance26Dot6)
                )
            )
        }

        var previousX: Int32 = 0
        for index in normalized.indices {
            let x = min(max(previousX, normalized[index].x26Dot6), max(0, advance26Dot6))
            normalized[index] = LunaStaticTextInsertionPosition(
                utf8Offset: normalized[index].utf8Offset,
                x26Dot6: x
            )
            previousX = x
        }
        self.insertionPositions = normalized
    }

    public var advancePixels: Int { Self.ceil26Dot6(advance26Dot6) }

    public func x26Dot6(forUTF8Offset requestedOffset: Int) -> Int32 {
        guard !insertionPositions.isEmpty else { return 0 }
        let target = min(max(0, requestedOffset), sourceText.utf8.count)
        var low = 0
        var high = insertionPositions.count
        while low < high {
            let mid = (low + high) / 2
            if insertionPositions[mid].utf8Offset <= target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return insertionPositions[max(0, low - 1)].x26Dot6
    }

    public func x(forUTF8Offset offset: Int) -> Int {
        Self.round26Dot6(x26Dot6(forUTF8Offset: offset))
    }

    public func closestUTF8Offset(toX26Dot6 requestedX: Int32) -> Int {
        guard let first = insertionPositions.first else { return 0 }
        guard insertionPositions.count > 1 else { return first.utf8Offset }
        let x = min(max(0, requestedX), max(0, advance26Dot6))
        for index in 0..<(insertionPositions.count - 1) {
            let current = insertionPositions[index]
            let next = insertionPositions[index + 1]
            let midpoint = current.x26Dot6 + (next.x26Dot6 - current.x26Dot6) / 2
            if x < midpoint { return current.utf8Offset }
        }
        return insertionPositions.last?.utf8Offset ?? sourceText.utf8.count
    }

    public func closestUTF8Offset(toX x: Int) -> Int {
        closestUTF8Offset(toX26Dot6: Int32(max(0, x) * 64))
    }

    /// Last stable insertion boundary whose shaped X position fits in the width.
    public func farthestUTF8Offset(fittingWidth width: Int) -> Int {
        let limit = Int32(max(0, width) * 64)
        return insertionPositions.last(where: { $0.x26Dot6 <= limit })?.utf8Offset ?? 0
    }

    public static func fixedAdvance(
        sourceText: String,
        renderedText: String? = nil,
        advance: Int
    ) -> LunaStaticTextRowGeometry {
        let cellAdvance = max(1, advance)
        var positions = [LunaStaticTextInsertionPosition(utf8Offset: 0, x26Dot6: 0)]
        var sourceOffset = 0
        var x: Int32 = 0
        for character in sourceText {
            sourceOffset += String(character).utf8.count
            x += Int32(cellAdvance * 64)
            positions.append(
                LunaStaticTextInsertionPosition(utf8Offset: sourceOffset, x26Dot6: x)
            )
        }
        return LunaStaticTextRowGeometry(
            sourceText: sourceText,
            renderedText: renderedText,
            insertionPositions: positions,
            advance26Dot6: x
        )
    }

    private static func ceil26Dot6(_ value: Int32) -> Int {
        value <= 0 ? 0 : Int((value + 63) / 64)
    }

    private static func round26Dot6(_ value: Int32) -> Int {
        value >= 0 ? Int((value + 32) / 64) : Int((value - 32) / 64)
    }
}

/// One geometry request for a source range inside its complete logical line.
///
/// Supplying the full line preserves presentation context such as tab stops when
/// a soft-wrapped continuation row begins in the middle of that line. The range
/// is normalized to valid UTF-8 string-index boundaries and remains local to the
/// complete line.
public struct LunaStaticTextGeometryRequest: Hashable, Sendable {
    public let completeLineText: String
    public let utf8Range: Range<Int>

    public init(completeLineText: String, utf8Range: Range<Int>) {
        let length = completeLineText.utf8.count
        let lower = Self.validUTF8Boundary(
            atOrBefore: min(max(0, utf8Range.lowerBound), length),
            in: completeLineText
        )
        let upper = Self.validUTF8Boundary(
            atOrBefore: min(max(lower, utf8Range.upperBound), length),
            in: completeLineText
        )
        self.completeLineText = completeLineText
        self.utf8Range = lower..<upper
    }

    public init(sourceText: String) {
        self.init(
            completeLineText: sourceText,
            utf8Range: 0..<sourceText.utf8.count
        )
    }

    public var sourceText: String {
        Self.substring(completeLineText, utf8Range: utf8Range)
    }

    public var precedingSourceText: String {
        Self.substring(completeLineText, utf8Range: 0..<utf8Range.lowerBound)
    }

    private static func substring(_ text: String, utf8Range: Range<Int>) -> String {
        let lowerUTF8 = text.utf8.index(text.utf8.startIndex, offsetBy: utf8Range.lowerBound)
        let upperUTF8 = text.utf8.index(text.utf8.startIndex, offsetBy: utf8Range.upperBound)
        let lower = String.Index(lowerUTF8, within: text) ?? text.startIndex
        let upper = String.Index(upperUTF8, within: text) ?? text.endIndex
        return String(text[lower..<upper])
    }

    private static func validUTF8Boundary(atOrBefore offset: Int, in text: String) -> Int {
        let target = min(max(0, offset), text.utf8.count)
        var boundary = 0
        for character in text {
            let next = boundary + String(character).utf8.count
            if next > target { break }
            boundary = next
        }
        return boundary
    }
}

/// Shaping boundary injected into Luna's product-neutral text surface.
///
/// Implementations may wrap HarfBuzz/FreeType, platform text APIs, or a fixed
/// diagnostic font. The returned value is immutable and contains no product
/// document state.
public protocol LunaStaticTextGeometryProvider: Sendable {
    func geometry(for request: LunaStaticTextGeometryRequest) -> LunaStaticTextRowGeometry
}

public extension LunaStaticTextGeometryProvider {
    func geometry(for sourceText: String) -> LunaStaticTextRowGeometry {
        geometry(for: LunaStaticTextGeometryRequest(sourceText: sourceText))
    }
}
