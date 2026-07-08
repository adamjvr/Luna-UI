// LunaBoundedText.swift
//
// Phase 2D.2: universal bounded text primitive.
//
// Phase 2D.1 fixed modal title/body wrapping locally. This file promotes that
// behavior into a reusable Luna primitive so every text-bearing control follows
// the same rule: visual text respects assigned bounds, while accessibility keeps
// the full semantic string.

import Foundation
import LunaCore
import LunaRender

/// How a text-bearing Luna control should handle text that is wider/taller than
/// its assigned visual bounds.
public enum LunaTextOverflowMode: String, Hashable, Sendable {
    /// Draw as many characters as fit and drop the rest with no ellipsis.
    case clip

    /// Draw a single visual line and replace the tail with `...` when needed.
    case ellipsizeTail

    /// Wrap at word boundaries, then clip/ellipsize the final visible line when
    /// the bounded region cannot fit all wrapped lines.
    case wrap
}

/// Horizontal placement for text inside a bounded visual line.
public enum LunaTextHorizontalAlignment: String, Hashable, Sendable {
    case leading
    case center
    case trailing
}

/// Monospaced debug-font metrics used until LunaDisplayList grows real text run
/// commands. These metrics intentionally match the demo 5x7 font renderer.
public struct LunaDebugTextMetrics: Hashable, Sendable {
    public var scale: Int
    public var glyphWidth: Int
    public var glyphHeight: Int
    public var advance: Int
    public var lineHeight: Int

    public init(
        scale: Int = 1,
        glyphWidth: Int = 5,
        glyphHeight: Int = 7,
        advance: Int? = nil,
        lineHeight: Int? = nil
    ) {
        let s = max(1, scale)
        self.scale = s
        self.glyphWidth = max(1, glyphWidth) * s
        self.glyphHeight = max(1, glyphHeight) * s
        self.advance = max(1, advance ?? 6) * s
        self.lineHeight = max(1, lineHeight ?? 12) * s
    }

    public static let body = LunaDebugTextMetrics(scale: 1)
    public static let title = LunaDebugTextMetrics(scale: 2)

    public func characterCapacity(width: Int) -> Int {
        max(0, width / advance)
    }

    public func visualWidth(of text: String) -> Int {
        text.count * advance
    }
}

/// One visual line produced by bounded text layout.
///
/// `text` is what should be drawn. `fullText` is the semantic source string that
/// accessibility should expose even if the visual text was clipped/ellipsized.
public struct LunaBoundedTextLine: Hashable, Sendable {
    public var text: String
    public var fullText: String
    public var bounds: LunaRectI
    public var isClipped: Bool

    public init(text: String, fullText: String, bounds: LunaRectI, isClipped: Bool = false) {
        self.text = text
        self.fullText = fullText
        self.bounds = bounds
        self.isClipped = isClipped
    }
}

/// Result of laying semantic text into a bounded visual rectangle.
public struct LunaBoundedTextLayout: Hashable, Sendable {
    public var fullText: String
    public var bounds: LunaRectI
    public var lines: [LunaBoundedTextLine]
    public var overflowMode: LunaTextOverflowMode
    public var didClip: Bool

    public init(
        fullText: String,
        bounds: LunaRectI,
        lines: [LunaBoundedTextLine],
        overflowMode: LunaTextOverflowMode,
        didClip: Bool
    ) {
        self.fullText = fullText
        self.bounds = bounds
        self.lines = lines
        self.overflowMode = overflowMode
        self.didClip = didClip
    }

    public var firstLine: LunaBoundedTextLine? { lines.first }

    public static func layout(
        _ text: String,
        in bounds: LunaRectI,
        metrics: LunaDebugTextMetrics = .body,
        overflow: LunaTextOverflowMode = .ellipsizeTail,
        alignment: LunaTextHorizontalAlignment = .leading,
        maximumLines requestedMaximumLines: Int? = nil
    ) -> LunaBoundedTextLayout {
        guard !text.isEmpty, !bounds.isEmpty, bounds.w > 0, bounds.h > 0 else {
            return LunaBoundedTextLayout(fullText: text, bounds: bounds, lines: [], overflowMode: overflow, didClip: !text.isEmpty)
        }

        let maxChars = metrics.characterCapacity(width: bounds.w)
        let lineCapacity = max(0, bounds.h / metrics.lineHeight)
        let maxLines = max(0, min(requestedMaximumLines ?? lineCapacity, lineCapacity))

        guard maxChars > 0, maxLines > 0 else {
            return LunaBoundedTextLayout(fullText: text, bounds: bounds, lines: [], overflowMode: overflow, didClip: true)
        }

        switch overflow {
        case .clip:
            let visual = String(text.prefix(maxChars))
            let clipped = text.count > visual.count
            let line = makeLine(visual, fullText: text, bounds: bounds, index: 0, metrics: metrics, alignment: alignment, isClipped: clipped)
            return LunaBoundedTextLayout(fullText: text, bounds: bounds, lines: [line], overflowMode: overflow, didClip: clipped)

        case .ellipsizeTail:
            let visual = ellipsized(text, maxCharacters: maxChars)
            let clipped = text.count > maxChars
            let line = makeLine(visual, fullText: text, bounds: bounds, index: 0, metrics: metrics, alignment: alignment, isClipped: clipped)
            return LunaBoundedTextLayout(fullText: text, bounds: bounds, lines: [line], overflowMode: overflow, didClip: clipped)

        case .wrap:
            let wrapped = wrap(text, maxCharactersPerLine: maxChars)
            guard !wrapped.isEmpty else {
                return LunaBoundedTextLayout(fullText: text, bounds: bounds, lines: [], overflowMode: overflow, didClip: !text.isEmpty)
            }

            var visible = Array(wrapped.prefix(maxLines))
            let clipped = wrapped.count > maxLines
            if clipped, let last = visible.indices.last {
                visible[last] = ellipsized(visible[last], maxCharacters: maxChars)
            }

            let lines = visible.enumerated().map { index, visualText in
                makeLine(
                    visualText,
                    fullText: text,
                    bounds: bounds,
                    index: index,
                    metrics: metrics,
                    alignment: alignment,
                    isClipped: clipped && index == visible.count - 1
                )
            }

            return LunaBoundedTextLayout(fullText: text, bounds: bounds, lines: lines, overflowMode: overflow, didClip: clipped)
        }
    }

    public static func characterCapacity(width: Int, metrics: LunaDebugTextMetrics = .body) -> Int {
        metrics.characterCapacity(width: width)
    }

    public static func ellipsized(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        if text.count <= maxCharacters { return text }
        if maxCharacters <= 3 { return String(repeating: ".", count: maxCharacters) }
        return String(text.prefix(maxCharacters - 3)) + "..."
    }

    public static func wrap(_ text: String, maxCharactersPerLine: Int) -> [String] {
        guard maxCharactersPerLine > 0 else { return [] }

        // Preserve paragraph boundaries enough for editor UI copy while keeping
        // the implementation deliberately simple until real shaped text layout
        // arrives.
        let paragraphs = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        var lines: [String] = []

        for paragraph in paragraphs {
            let words = paragraph
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)

            if words.isEmpty {
                if !lines.isEmpty { lines.append("") }
                continue
            }

            var current = ""

            func flushCurrent() {
                if !current.isEmpty {
                    lines.append(current)
                    current = ""
                }
            }

            func appendHardWrapped(_ word: String) {
                var remainder = word
                while remainder.count > maxCharactersPerLine {
                    let chunk = String(remainder.prefix(maxCharactersPerLine))
                    lines.append(chunk)
                    remainder.removeFirst(chunk.count)
                }
                current = remainder
            }

            for word in words {
                if word.count > maxCharactersPerLine {
                    flushCurrent()
                    appendHardWrapped(word)
                    continue
                }

                if current.isEmpty {
                    current = word
                } else if current.count + 1 + word.count <= maxCharactersPerLine {
                    current += " " + word
                } else {
                    flushCurrent()
                    current = word
                }
            }

            flushCurrent()
        }

        return lines
    }

    public static func estimatedWrappedLineCount(
        for text: String?,
        width: Int,
        metrics: LunaDebugTextMetrics = .body
    ) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        let maxChars = metrics.characterCapacity(width: width)
        guard maxChars > 0 else { return 0 }
        return max(1, wrap(text, maxCharactersPerLine: maxChars).count)
    }

    private static func makeLine(
        _ visualText: String,
        fullText: String,
        bounds: LunaRectI,
        index: Int,
        metrics: LunaDebugTextMetrics,
        alignment: LunaTextHorizontalAlignment,
        isClipped: Bool
    ) -> LunaBoundedTextLine {
        let visualW = min(bounds.w, metrics.visualWidth(of: visualText))
        let x: Int
        switch alignment {
        case .leading:
            x = bounds.x
        case .center:
            x = bounds.x + max(0, (bounds.w - visualW) / 2)
        case .trailing:
            x = bounds.x + max(0, bounds.w - visualW)
        }

        return LunaBoundedTextLine(
            text: visualText,
            fullText: fullText,
            bounds: LunaRectI(
                x: x,
                y: bounds.y + index * metrics.lineHeight,
                w: bounds.w - max(0, x - bounds.x),
                h: metrics.lineHeight
            ),
            isClipped: isClipped
        )
    }
}

public extension LunaRectI {
    /// Shared integer inset helper for Luna UI/content layout.
    func lunaInset(by amount: Int) -> LunaRectI {
        let a = max(0, amount)
        return LunaRectI(x: x + a, y: y + a, w: max(0, w - a * 2), h: max(0, h - a * 2))
    }

    /// Shared edge-aware inset helper for content bounds.
    func lunaInset(top: Int = 0, right: Int = 0, bottom: Int = 0, left: Int = 0) -> LunaRectI {
        let l = max(0, left)
        let r = max(0, right)
        let t = max(0, top)
        let b = max(0, bottom)
        return LunaRectI(x: x + l, y: y + t, w: max(0, w - l - r), h: max(0, h - t - b))
    }
}
