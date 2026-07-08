// LunaModalTextLayout.swift
//
// Phase 2D.1/2D.2: modal content reflow.
//
// Phase 2D.1 fixed modal content locally. Phase 2D.2 routes modal title,
// message, prompt field, and choice labels through LunaBoundedText so modal
// controls share the same bounded-text primitive as every other widget.

import Foundation
import LunaCore
import LunaRender

/// Backward-compatible modal line name used by Phase 2D tests and demo code.
/// The implementation is now the universal bounded-text line primitive.
public typealias LunaModalTextLine = LunaBoundedTextLine

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
        let titleLayout = LunaBoundedTextLayout.layout(
            title,
            in: titleBounds,
            metrics: .title,
            overflow: .ellipsizeTail
        )
        let titleLine = titleLayout.firstLine ?? LunaModalTextLine(text: "", fullText: title, bounds: titleBounds, isClipped: !title.isEmpty)

        let messageRegion = Self.modalMessageRegion(in: panelBounds, choices: choices, fieldBounds: fieldBounds)
        let messageOverflow: LunaTextOverflowMode = messageRegion.w >= Self.minimumReadableTextWidth ? .wrap : .ellipsizeTail
        let messageLayout = LunaBoundedTextLayout.layout(
            message ?? "",
            in: messageRegion,
            metrics: .body,
            overflow: messageOverflow
        )

        let fieldLine: LunaModalTextLine? = fieldBounds.map { field in
            let full = initialText?.isEmpty == false ? initialText! : (placeholder ?? "")
            let fieldInset = Self.controlTextInset(forWidth: field.w)
            let textBounds = LunaRectI(
                x: field.x + fieldInset,
                y: field.y + max(0, (field.h - Self.debugFontHeight(scale: Self.bodyScale)) / 2),
                w: max(0, field.w - fieldInset * 2),
                h: Self.debugFontLineHeight(scale: Self.bodyScale)
            )
            return LunaBoundedTextLayout.layout(
                full,
                in: textBounds,
                metrics: .body,
                overflow: .ellipsizeTail
            ).firstLine ?? LunaModalTextLine(text: "", fullText: full, bounds: textBounds, isClipped: !full.isEmpty)
        }

        return LunaModalTextLayout(
            title: titleLine,
            messageLines: messageLayout.lines,
            messageRegion: messageRegion,
            fieldText: fieldLine
        )
    }

    /// The visual label for a choice constrained to its current button/list-row
    /// bounds. This keeps labels from spilling outside modal controls.
    func visualLabel(for choice: LunaModalChoice) -> LunaModalTextLine {
        let inset = Self.controlTextInset(forWidth: choice.bounds.w)
        let textBounds = choice.bounds.lunaInset(top: 0, right: inset, bottom: 0, left: inset)
        let centeredBounds = LunaRectI(
            x: textBounds.x,
            y: choice.bounds.y + max(0, (choice.bounds.h - Self.debugFontHeight(scale: Self.bodyScale)) / 2),
            w: textBounds.w,
            h: Self.debugFontLineHeight(scale: Self.bodyScale)
        )
        return LunaBoundedTextLayout.layout(
            choice.label,
            in: centeredBounds,
            metrics: .body,
            overflow: .ellipsizeTail,
            alignment: .center
        ).firstLine ?? LunaModalTextLine(text: "", fullText: choice.label, bounds: centeredBounds, isClipped: !choice.label.isEmpty)
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

    static func debugFontAdvance(scale: Int) -> Int { LunaDebugTextMetrics(scale: scale).advance }
    static func debugFontHeight(scale: Int) -> Int { LunaDebugTextMetrics(scale: scale).glyphHeight }
    static func debugFontLineHeight(scale: Int) -> Int { LunaDebugTextMetrics(scale: scale).lineHeight }

    static func characterCapacity(width: Int, scale: Int) -> Int {
        LunaDebugTextMetrics(scale: scale).characterCapacity(width: width)
    }


    /// Minimum body-message width before the modal attempts word wrapping. Below
    /// this, wrapping into one-character columns is worse than clipping/ellipsizing.
    static let minimumReadableTextWidth = 96

    /// Adaptive panel/content inset. Narrow windows must still keep controls
    /// inside the panel; fixed 18 px insets can erase all usable width.
    static func modalContentInset(forPanelWidth width: Int) -> Int {
        if width >= 180 { return 18 }
        if width >= 96 { return 12 }
        if width >= 48 { return 6 }
        return max(1, width / 8)
    }

    /// Content rectangle shared by title/body/fields/buttons. This makes modal
    /// text and controls agree on the same available horizontal space.
    static func modalContentBounds(in panel: LunaRectI) -> LunaRectI {
        let inset = modalContentInset(forPanelWidth: panel.w)
        return LunaRectI(
            x: panel.x + inset,
            y: panel.y,
            w: max(0, panel.w - inset * 2),
            h: panel.h
        )
    }

    /// Adaptive text inset for control labels. A fixed 8 px inset is fine for
    /// normal buttons, but ridiculous for emergency-narrow controls.
    static func controlTextInset(forWidth width: Int) -> Int {
        if width >= 48 { return 8 }
        if width >= 24 { return 4 }
        return max(0, width / 8)
    }

    static func modalTitleTextBounds(in panel: LunaRectI) -> LunaRectI {
        let content = modalContentBounds(in: panel)
        return LunaRectI(
            x: content.x,
            y: panel.y + 11,
            w: content.w,
            h: debugFontLineHeight(scale: titleScale)
        )
    }

    static func modalMessageRegion(
        in panel: LunaRectI,
        choices: [LunaModalChoice],
        fieldBounds: LunaRectI?
    ) -> LunaRectI {
        let content = modalContentBounds(in: panel)
        let x = content.x
        let y: Int
        if let fieldBounds {
            y = fieldBounds.y + fieldBounds.h + 8
        } else {
            y = panel.y + 52
        }

        let choiceTop = choices.map(\.bounds.y).min() ?? (panel.y + panel.h - 12)
        let bottom = min(panel.y + panel.h - 12, choiceTop - 8)
        return LunaRectI(x: x, y: y, w: content.w, h: max(0, bottom - y))
    }

    static func ellipsized(_ text: String, maxCharacters: Int) -> String {
        LunaBoundedTextLayout.ellipsized(text, maxCharacters: maxCharacters)
    }

    static func wrapMessageLines(_ message: String, in region: LunaRectI) -> [LunaModalTextLine] {
        LunaBoundedTextLayout.layout(message, in: region, metrics: .body, overflow: .wrap).lines
    }

    /// Estimated number of visual body lines needed for a message at a given
    /// width. Used by modal construction/reflow so narrow panels can grow taller
    /// when viewport height allows it.
    static func estimatedWrappedLineCount(for message: String?, width: Int) -> Int {
        guard width >= minimumReadableTextWidth else {
            return (message?.isEmpty == false) ? 1 : 0
        }
        return LunaBoundedTextLayout.estimatedWrappedLineCount(for: message, width: width, metrics: .body)
    }

    static func wrapped(_ message: String, maxCharactersPerLine: Int) -> [String] {
        LunaBoundedTextLayout.wrap(message, maxCharactersPerLine: maxCharactersPerLine)
    }
}
