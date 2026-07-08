// LunaModalTextLayout.swift
//
// Phase 2D.1: modal content reflow.
//
// Phase 2D proved modal box geometry reflows after resize. This file adds the
// matching content rule: title/body/choice text must respect the reflowed panel
// bounds instead of drawing as if infinite horizontal space exists.

import Foundation
import LunaCore
import LunaRender

/// A single visually renderable debug-font text line inside a modal overlay.
///
/// This is intentionally simple and font-metric based. LunaDisplayList does not
/// have real glyph-run commands yet, so the demo uses the same 5x7 debug font
/// metrics as these layout helpers. When real text rendering lands, this type
/// can become the bridge from modal semantic text to shaped text runs.
public struct LunaModalTextLine: Hashable, Sendable {
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

/// Text layout derived from a modal overlay's current panel/choice geometry.
///
/// Important: these bounds are *content* bounds. The modal panel remains the
/// accessibility/root bounds, while title/message children use these regions.
public struct LunaModalTextLayout: Hashable, Sendable {
    public var title: LunaModalTextLine
    public var messageLines: [LunaModalTextLine]
    public var messageRegion: LunaRectI
    public var fieldText: LunaModalTextLine?

    public init(
        title: LunaModalTextLine,
        messageLines: [LunaModalTextLine],
        messageRegion: LunaRectI,
        fieldText: LunaModalTextLine? = nil
    ) {
        self.title = title
        self.messageLines = messageLines
        self.messageRegion = messageRegion
        self.fieldText = fieldText
    }
}

public extension LunaModalOverlay {
    /// Layout title, message, and prompt-field text against the overlay's
    /// current panel bounds. Drawing, clipping, and accessibility children should
    /// consume this instead of inventing their own text rectangles.
    func textLayout() -> LunaModalTextLayout {
        let titleBounds = Self.modalTitleTextBounds(in: panelBounds)
        let titleLine = LunaModalTextLine(
            text: Self.ellipsized(title, maxCharacters: Self.characterCapacity(width: titleBounds.w, scale: Self.titleScale)),
            fullText: title,
            bounds: titleBounds,
            isClipped: title.count > Self.characterCapacity(width: titleBounds.w, scale: Self.titleScale)
        )

        let messageRegion = Self.modalMessageRegion(in: panelBounds, choices: choices, fieldBounds: fieldBounds)
        let messageLines = Self.wrapMessageLines(message ?? "", in: messageRegion)

        let fieldLine: LunaModalTextLine? = fieldBounds.map { field in
            let full = initialText?.isEmpty == false ? initialText! : (placeholder ?? "")
            let textBounds = LunaRectI(
                x: field.x + 8,
                y: field.y + max(0, (field.h - Self.debugFontHeight(scale: Self.bodyScale)) / 2),
                w: max(0, field.w - 16),
                h: Self.debugFontLineHeight(scale: Self.bodyScale)
            )
            let limit = Self.characterCapacity(width: textBounds.w, scale: Self.bodyScale)
            return LunaModalTextLine(
                text: Self.ellipsized(full, maxCharacters: limit),
                fullText: full,
                bounds: textBounds,
                isClipped: full.count > limit
            )
        }

        return LunaModalTextLayout(
            title: titleLine,
            messageLines: messageLines,
            messageRegion: messageRegion,
            fieldText: fieldLine
        )
    }

    /// The visual label for a choice constrained to its current button/list-row
    /// bounds. This keeps labels from spilling outside modal controls.
    func visualLabel(for choice: LunaModalChoice) -> LunaModalTextLine {
        let textBounds = LunaRectI(
            x: choice.bounds.x + 8,
            y: choice.bounds.y + max(0, (choice.bounds.h - Self.debugFontHeight(scale: Self.bodyScale)) / 2),
            w: max(0, choice.bounds.w - 16),
            h: Self.debugFontLineHeight(scale: Self.bodyScale)
        )
        let limit = Self.characterCapacity(width: textBounds.w, scale: Self.bodyScale)
        return LunaModalTextLine(
            text: Self.ellipsized(choice.label, maxCharacters: limit),
            fullText: choice.label,
            bounds: textBounds,
            isClipped: choice.label.count > limit
        )
    }
}

// MARK: - Modal text metrics / wrapping helpers

public extension LunaModalOverlay {
    /// Debug-font scale used for modal titles until real text display-list
    /// commands land.
    static let titleScale = 2

    /// Debug-font scale used for modal body/buttons until real text display-list
    /// commands land.
    static let bodyScale = 1

    static func debugFontAdvance(scale: Int) -> Int { max(1, scale) * 6 }
    static func debugFontHeight(scale: Int) -> Int { max(1, scale) * 7 }
    static func debugFontLineHeight(scale: Int) -> Int { max(1, scale) * 12 }

    static func characterCapacity(width: Int, scale: Int) -> Int {
        max(0, width / debugFontAdvance(scale: scale))
    }

    static func modalTitleTextBounds(in panel: LunaRectI) -> LunaRectI {
        LunaRectI(
            x: panel.x + 18,
            y: panel.y + 11,
            w: max(0, panel.w - 36),
            h: debugFontLineHeight(scale: titleScale)
        )
    }

    static func modalMessageRegion(
        in panel: LunaRectI,
        choices: [LunaModalChoice],
        fieldBounds: LunaRectI?
    ) -> LunaRectI {
        let x = panel.x + 18
        let y: Int
        if let fieldBounds {
            y = fieldBounds.y + fieldBounds.h + 8
        } else {
            y = panel.y + 52
        }

        let choiceTop = choices.map(\.bounds.y).min() ?? (panel.y + panel.h - 12)
        let bottom = min(panel.y + panel.h - 12, choiceTop - 8)
        return LunaRectI(x: x, y: y, w: max(0, panel.w - 36), h: max(0, bottom - y))
    }

    static func ellipsized(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        if text.count <= maxCharacters { return text }
        if maxCharacters <= 3 { return String(repeating: ".", count: maxCharacters) }
        return String(text.prefix(maxCharacters - 3)) + "..."
    }

    static func wrapMessageLines(_ message: String, in region: LunaRectI) -> [LunaModalTextLine] {
        guard !message.isEmpty, region.w > 0, region.h > 0 else { return [] }

        let maxChars = characterCapacity(width: region.w, scale: bodyScale)
        let maxLines = max(0, region.h / debugFontLineHeight(scale: bodyScale))
        guard maxChars > 0, maxLines > 0 else { return [] }

        let allLines = wrapped(message, maxCharactersPerLine: maxChars)
        guard !allLines.isEmpty else { return [] }

        var visible = Array(allLines.prefix(maxLines))
        let clipped = allLines.count > maxLines
        if clipped, let last = visible.indices.last {
            visible[last] = ellipsized(visible[last], maxCharacters: maxChars)
        }

        return visible.enumerated().map { index, text in
            LunaModalTextLine(
                text: text,
                fullText: message,
                bounds: LunaRectI(
                    x: region.x,
                    y: region.y + index * debugFontLineHeight(scale: bodyScale),
                    w: region.w,
                    h: debugFontLineHeight(scale: bodyScale)
                ),
                isClipped: clipped && index == visible.count - 1
            )
        }
    }

    /// Estimated number of visual body lines needed for a message at a given
    /// width. Used by modal construction/reflow so narrow panels can grow taller
    /// when viewport height allows it.
    static func estimatedWrappedLineCount(for message: String?, width: Int) -> Int {
        guard let message, !message.isEmpty else { return 0 }
        let maxChars = characterCapacity(width: width, scale: bodyScale)
        guard maxChars > 0 else { return 0 }
        return max(1, wrapped(message, maxCharactersPerLine: maxChars).count)
    }

    static func wrapped(_ message: String, maxCharactersPerLine: Int) -> [String] {
        guard maxCharactersPerLine > 0 else { return [] }

        let tokens = message
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map(String.init)

        guard !tokens.isEmpty else { return [] }

        var lines: [String] = []
        var current = ""

        func appendHardWrapped(_ word: String) {
            var remainder = word
            while remainder.count > maxCharactersPerLine {
                let chunk = String(remainder.prefix(maxCharactersPerLine))
                lines.append(chunk)
                remainder = String(remainder.dropFirst(maxCharactersPerLine))
            }
            current = remainder
        }

        for token in tokens {
            if current.isEmpty {
                if token.count > maxCharactersPerLine {
                    appendHardWrapped(token)
                } else {
                    current = token
                }
                continue
            }

            let candidate = current + " " + token
            if candidate.count <= maxCharactersPerLine {
                current = candidate
            } else {
                lines.append(current)
                current = ""
                if token.count > maxCharactersPerLine {
                    appendHardWrapped(token)
                } else {
                    current = token
                }
            }
        }

        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
