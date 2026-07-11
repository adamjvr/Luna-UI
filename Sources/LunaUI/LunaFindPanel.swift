// SPDX-License-Identifier: MPL-2.0
// LunaFindPanel.swift
//
// Phase 4B: generic Find / Replace panel foundation.
//
// This file intentionally remains product-neutral. Luna supplies the reusable
// search/replace model, panel state, geometry, input handling, display-list
// output, and accessibility shape. Applications such as Moth Text can skin it,
// place it, and bind it to app-specific commands without putting product names
// into Luna's public API.

import Foundation
import LunaAccessibility
import LunaCore
import LunaInput
import LunaRender
import LunaTheme

// MARK: - Search model

/// Options that affect textual search behavior.
public struct LunaFindOptions: Hashable, Sendable {
    public var isCaseSensitive: Bool
    public var matchesWholeWord: Bool
    public var usesRegularExpression: Bool

    public init(
        isCaseSensitive: Bool = false,
        matchesWholeWord: Bool = false,
        usesRegularExpression: Bool = false
    ) {
        self.isCaseSensitive = isCaseSensitive
        self.matchesWholeWord = matchesWholeWord
        self.usesRegularExpression = usesRegularExpression
    }

    public static let `default` = LunaFindOptions()
}

/// User-entered find query plus behavior flags.
public struct LunaFindQuery: Hashable, Sendable {
    public var text: String
    public var options: LunaFindOptions

    public init(text: String = "", options: LunaFindOptions = .default) {
        self.text = text
        self.options = options
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One search match in a text document.
public struct LunaFindMatch: Hashable, Sendable {
    public var id: LunaNodeID
    public var index: Int
    public var range: LunaTextRange
    public var matchedText: String
    public var utf8Offset: Int
    public var utf8Length: Int

    public init(
        id: LunaNodeID,
        index: Int,
        range: LunaTextRange,
        matchedText: String,
        utf8Offset: Int,
        utf8Length: Int
    ) {
        self.id = id
        self.index = max(0, index)
        self.range = range.normalized
        self.matchedText = matchedText
        self.utf8Offset = max(0, utf8Offset)
        self.utf8Length = max(0, utf8Length)
    }
}

/// Complete result set for a query in one document snapshot.
public struct LunaFindResultSet: Hashable, Sendable {
    public var query: LunaFindQuery
    public var matches: [LunaFindMatch]
    public var selectedMatchIndex: Int?

    public init(query: LunaFindQuery, matches: [LunaFindMatch], selectedMatchIndex: Int? = nil) {
        self.query = query
        self.matches = matches
        if let selectedMatchIndex, matches.indices.contains(selectedMatchIndex) {
            self.selectedMatchIndex = selectedMatchIndex
        } else {
            self.selectedMatchIndex = matches.isEmpty ? nil : 0
        }
    }

    public var count: Int { matches.count }
    public var isEmpty: Bool { matches.isEmpty }

    public var selectedMatch: LunaFindMatch? {
        guard let selectedMatchIndex, matches.indices.contains(selectedMatchIndex) else { return nil }
        return matches[selectedMatchIndex]
    }

    public var statusText: String {
        guard !query.isEmpty else { return "No query" }
        guard let selectedMatchIndex else { return "No matches" }
        return "\(selectedMatchIndex + 1) of \(matches.count)"
    }

    public func selectingNext(wrapping: Bool = true) -> LunaFindResultSet {
        guard !matches.isEmpty else { return LunaFindResultSet(query: query, matches: matches, selectedMatchIndex: nil) }
        let current = selectedMatchIndex ?? -1
        let next = current + 1
        let index = next < matches.count ? next : (wrapping ? 0 : matches.count - 1)
        return LunaFindResultSet(query: query, matches: matches, selectedMatchIndex: index)
    }

    public func selectingPrevious(wrapping: Bool = true) -> LunaFindResultSet {
        guard !matches.isEmpty else { return LunaFindResultSet(query: query, matches: matches, selectedMatchIndex: nil) }
        let current = selectedMatchIndex ?? matches.count
        let previous = current - 1
        let index = previous >= 0 ? previous : (wrapping ? matches.count - 1 : 0)
        return LunaFindResultSet(query: query, matches: matches, selectedMatchIndex: index)
    }

    public func selectingMatch(containing location: LunaTextLocation) -> LunaFindResultSet {
        guard !matches.isEmpty else { return self }
        let docLocation = location
        if let index = matches.firstIndex(where: { match in
            let range = match.range.normalized
            return docLocation >= range.anchor && docLocation <= range.focus
        }) {
            return LunaFindResultSet(query: query, matches: matches, selectedMatchIndex: index)
        }
        return self
    }
}

/// Deterministic literal/regex scanner for Luna text documents.
public enum LunaFindScanner {
    public static func results(in document: LunaStaticTextDocument, query: LunaFindQuery) -> LunaFindResultSet {
        guard !query.isEmpty else {
            return LunaFindResultSet(query: query, matches: [], selectedMatchIndex: nil)
        }

        let matches: [LunaFindMatch]
        if query.options.usesRegularExpression {
            matches = regexMatches(in: document, query: query)
        } else {
            matches = literalMatches(in: document, query: query)
        }
        return LunaFindResultSet(query: query, matches: matches, selectedMatchIndex: matches.isEmpty ? nil : 0)
    }

    private static func literalMatches(in document: LunaStaticTextDocument, query: LunaFindQuery) -> [LunaFindMatch] {
        let needle = query.text
        guard !needle.isEmpty else { return [] }

        let haystack = document.text
        let compareOptions: String.CompareOptions = query.options.isCaseSensitive ? [] : [.caseInsensitive]
        var searchStart = haystack.startIndex
        var found: [LunaFindMatch] = []

        while searchStart <= haystack.endIndex,
              let range = haystack.range(of: needle, options: compareOptions, range: searchStart..<haystack.endIndex) {
            if !range.isEmpty, acceptsWordBoundary(in: haystack, range: range, options: query.options) {
                found.append(makeMatch(document: document, textRange: range, matchedText: String(haystack[range]), index: found.count))
            }

            if range.isEmpty {
                break
            }
            searchStart = range.upperBound
        }

        return found
    }

    private static func regexMatches(in document: LunaStaticTextDocument, query: LunaFindQuery) -> [LunaFindMatch] {
        let pattern = query.text
        guard !pattern.isEmpty else { return [] }

        let options: NSRegularExpression.Options = query.options.isCaseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }

        let text = document.text
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result: [LunaFindMatch] = []
        regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, match.range.length > 0, let range = Range(match.range, in: text) else { return }
            guard acceptsWordBoundary(in: text, range: range, options: query.options) else { return }
            result.append(makeMatch(document: document, textRange: range, matchedText: String(text[range]), index: result.count))
        }
        return result
    }

    private static func makeMatch(
        document: LunaStaticTextDocument,
        textRange: Range<String.Index>,
        matchedText: String,
        index: Int
    ) -> LunaFindMatch {
        let startOffset = utf8Offset(of: textRange.lowerBound, in: document.text)
        let endOffset = utf8Offset(of: textRange.upperBound, in: document.text)
        let start = document.location(forAbsoluteUTF8Offset: startOffset)
        let end = document.location(forAbsoluteUTF8Offset: endOffset)
        return LunaFindMatch(
            id: LunaNodeID(rawValue: "find.match.\(index + 1)"),
            index: index,
            range: LunaTextRange(anchor: start, focus: end),
            matchedText: matchedText,
            utf8Offset: startOffset,
            utf8Length: max(0, endOffset - startOffset)
        )
    }

    private static func utf8Offset(of index: String.Index, in text: String) -> Int {
        guard let utf8Index = index.samePosition(in: text.utf8) else { return 0 }
        return text.utf8.distance(from: text.utf8.startIndex, to: utf8Index)
    }

    private static func acceptsWordBoundary(
        in text: String,
        range: Range<String.Index>,
        options: LunaFindOptions
    ) -> Bool {
        guard options.matchesWholeWord else { return true }
        let before: Character? = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
        let after: Character? = range.upperBound < text.endIndex ? text[range.upperBound] : nil
        return !isWordCharacter(before) && !isWordCharacter(after)
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        if character == "_" { return true }
        return character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
    }
}

// MARK: - Panel state and interaction

public enum LunaFindPanelField: String, Hashable, Sendable {
    case query
    case replace
}

public enum LunaFindPanelAction: Hashable, Sendable {
    case findNext
    case findPrevious
    case replaceCurrent
    case replaceAll
}


/// Injected search provider used by the reusable panel state.
///
/// Luna ships a static-document provider for its proof model, while products may
/// provide indexed, incremental, multi-buffer, or syntax-aware search without
/// moving that policy into the panel implementation.
public protocol LunaFindResultsProviding: Sendable {
    func results(for query: LunaFindQuery) -> LunaFindResultSet
}

/// Default provider backed by Luna's deterministic proof scanner.
public struct LunaStaticTextFindResultsProvider: LunaFindResultsProviding, Sendable {
    public var document: LunaStaticTextDocument

    public init(document: LunaStaticTextDocument) {
        self.document = document
    }

    public func results(for query: LunaFindQuery) -> LunaFindResultSet {
        LunaFindScanner.results(in: document, query: query)
    }
}

/// Product-session response after Luna requests a find or replace action.
public struct LunaFindSessionActionResult: Hashable, Sendable {
    public var results: LunaFindResultSet
    public var didChangeDocument: Bool
    public var replacementCount: Int

    public init(
        results: LunaFindResultSet,
        didChangeDocument: Bool = false,
        replacementCount: Int = 0
    ) {
        self.results = results
        self.didChangeDocument = didChangeDocument
        self.replacementCount = max(0, replacementCount)
    }
}

/// Optional product-owned find session behind Luna's panel presentation.
///
/// Applications decide how scanning, replacement, undo grouping, and document
/// transactions work. Luna only owns panel state and forwards semantic actions.
public protocol LunaFindPanelSession: LunaFindResultsProviding {
    mutating func perform(
        action: LunaFindPanelAction,
        query: LunaFindQuery,
        selectedMatch: LunaFindMatch?,
        replacementText: String
    ) -> LunaFindSessionActionResult
}

public struct LunaFindPanelInteractionResult: Hashable, Sendable {
    public var didConsumeEvent: Bool
    public var didDismiss: Bool
    public var didChangeState: Bool
    public var requestedAction: LunaFindPanelAction?

    public init(
        didConsumeEvent: Bool = false,
        didDismiss: Bool = false,
        didChangeState: Bool = false,
        requestedAction: LunaFindPanelAction? = nil
    ) {
        self.didConsumeEvent = didConsumeEvent
        self.didDismiss = didDismiss
        self.didChangeState = didChangeState
        self.requestedAction = requestedAction
    }
}

/// Mutable state for a find/replace panel.
public struct LunaFindPanelState: Hashable, Sendable {
    public var queryText: String
    public var replaceText: String
    public var options: LunaFindOptions
    public var results: LunaFindResultSet
    public var focusedField: LunaFindPanelField
    public var isReplaceVisible: Bool

    public init(
        queryText: String = "",
        replaceText: String = "",
        options: LunaFindOptions = .default,
        results: LunaFindResultSet? = nil,
        focusedField: LunaFindPanelField = .query,
        isReplaceVisible: Bool = true
    ) {
        self.queryText = queryText
        self.replaceText = replaceText
        self.options = options
        self.focusedField = focusedField
        self.isReplaceVisible = isReplaceVisible
        self.results = results ?? LunaFindResultSet(query: LunaFindQuery(text: queryText, options: options), matches: [])
    }

    public var query: LunaFindQuery { LunaFindQuery(text: queryText, options: options) }

    public mutating func refreshResults<P: LunaFindResultsProviding>(
        using provider: P,
        preservingSelectionNear location: LunaTextLocation? = nil
    ) {
        var newResults = provider.results(for: query)
        if let location {
            newResults = newResults.selectingMatch(containing: location)
        } else if let old = results.selectedMatch,
                  let candidate = newResults.matches.firstIndex(where: { $0.utf8Offset >= old.utf8Offset }) {
            newResults = LunaFindResultSet(
                query: newResults.query,
                matches: newResults.matches,
                selectedMatchIndex: candidate
            )
        }
        results = newResults
    }

    public mutating func refreshResults(
        in document: LunaStaticTextDocument,
        preservingSelectionNear location: LunaTextLocation? = nil
    ) {
        refreshResults(
            using: LunaStaticTextFindResultsProvider(document: document),
            preservingSelectionNear: location
        )
    }

    /// Forward a semantic panel action to a product-owned session.
    @discardableResult
    public mutating func perform<S: LunaFindPanelSession>(
        _ action: LunaFindPanelAction,
        using session: inout S
    ) -> LunaFindSessionActionResult {
        let result = session.perform(
            action: action,
            query: query,
            selectedMatch: results.selectedMatch,
            replacementText: replaceText
        )
        results = result.results
        return result
    }

    public mutating func appendCommittedText(_ text: String) {
        guard !text.isEmpty else { return }
        switch focusedField {
        case .query:
            queryText.append(text)
        case .replace:
            replaceText.append(text)
        }
    }

    public mutating func deleteBackwardInFocusedField() {
        switch focusedField {
        case .query:
            guard !queryText.isEmpty else { return }
            queryText.removeLast()
        case .replace:
            guard !replaceText.isEmpty else { return }
            replaceText.removeLast()
        }
    }

    public mutating func focusNextField() {
        focusedField = focusedField == .query ? .replace : .query
    }

    public mutating func toggleCaseSensitive() { options.isCaseSensitive.toggle() }
    public mutating func toggleWholeWord() { options.matchesWholeWord.toggle() }
    public mutating func toggleRegex() { options.usesRegularExpression.toggle() }
}

public extension LunaFindPanelState {
    mutating func handleTextInput<P: LunaFindResultsProviding>(
        _ event: LunaTextInputEvent,
        provider: P
    ) -> LunaFindPanelInteractionResult {
        guard !event.text.isEmpty else { return LunaFindPanelInteractionResult() }
        appendCommittedText(event.text)
        refreshResults(using: provider)
        return LunaFindPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
    }

    mutating func handleTextInput(
        _ event: LunaTextInputEvent,
        document: LunaStaticTextDocument
    ) -> LunaFindPanelInteractionResult {
        handleTextInput(event, provider: LunaStaticTextFindResultsProvider(document: document))
    }

    mutating func handleKeyboardEvent<P: LunaFindResultsProviding>(
        _ event: LunaKeyboardEvent,
        provider: P
    ) -> LunaFindPanelInteractionResult {
        switch event.key {
        case .escape:
            return LunaFindPanelInteractionResult(didConsumeEvent: true, didDismiss: true)
        case .tab:
            focusNextField()
            return LunaFindPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .backspace:
            deleteBackwardInFocusedField()
            refreshResults(using: provider)
            return LunaFindPanelInteractionResult(didConsumeEvent: true, didChangeState: true)
        case .enter:
            return LunaFindPanelInteractionResult(
                didConsumeEvent: true,
                didChangeState: true,
                requestedAction: event.modifiers.shift ? .findPrevious : .findNext
            )
        default:
            return LunaFindPanelInteractionResult()
        }
    }

    mutating func handleKeyboardEvent(
        _ event: LunaKeyboardEvent,
        document: LunaStaticTextDocument
    ) -> LunaFindPanelInteractionResult {
        handleKeyboardEvent(event, provider: LunaStaticTextFindResultsProvider(document: document))
    }

    mutating func selectNext() {
        results = results.selectingNext()
    }

    mutating func selectPrevious() {
        results = results.selectingPrevious()
    }
}

/// Search/replace operations that mutate an editable text state.
public enum LunaFindReplaceController {
    @discardableResult
    public static func replaceCurrent(state: inout LunaFindPanelState, text: inout LunaEditableTextState) -> LunaTextEditResult? {
        guard let match = state.results.selectedMatch else { return nil }
        let result = text.replaceRange(match.range, with: state.replaceText)
        state.refreshResults(in: text.document.staticDocument, preservingSelectionNear: result.newCaret.location)
        if !state.results.isEmpty {
            state.selectNext()
        }
        return result
    }

    @discardableResult
    public static func replaceAll(state: inout LunaFindPanelState, text: inout LunaEditableTextState) -> Int {
        let matches = state.results.matches
        guard !matches.isEmpty else { return 0 }
        for match in matches.reversed() {
            _ = text.replaceRange(match.range, with: state.replaceText)
        }
        state.refreshResults(in: text.document.staticDocument)
        return matches.count
    }
}

// MARK: - Panel layout and widget

public struct LunaFindPanelMetrics: Hashable, Sendable {
    public var maxPanelWidth: Int
    public var minPanelWidth: Int
    public var bottomMargin: Int
    public var sideMargin: Int
    public var panelPadding: Int
    public var fieldHeight: Int
    public var rowGap: Int
    public var buttonHeight: Int
    public var optionWidth: Int
    public var actionButtonWidth: Int
    public var textScale: Int
    public var titleScale: Int
    public var glyphMetrics: LunaDebugTextMetrics

    public init(
        maxPanelWidth: Int = 760,
        minPanelWidth: Int = 420,
        bottomMargin: Int = 54,
        sideMargin: Int = 18,
        panelPadding: Int = 10,
        fieldHeight: Int = 24,
        rowGap: Int = 6,
        buttonHeight: Int = 22,
        optionWidth: Int = 76,
        actionButtonWidth: Int = 86,
        textScale: Int = 1,
        titleScale: Int = 1,
        glyphMetrics: LunaDebugTextMetrics = .body
    ) {
        self.maxPanelWidth = max(120, maxPanelWidth)
        self.minPanelWidth = max(80, minPanelWidth)
        self.bottomMargin = max(0, bottomMargin)
        self.sideMargin = max(0, sideMargin)
        self.panelPadding = max(0, panelPadding)
        self.fieldHeight = max(14, fieldHeight)
        self.rowGap = max(0, rowGap)
        self.buttonHeight = max(14, buttonHeight)
        self.optionWidth = max(42, optionWidth)
        self.actionButtonWidth = max(54, actionButtonWidth)
        self.textScale = max(1, textScale)
        self.titleScale = max(1, titleScale)
        self.glyphMetrics = glyphMetrics
    }

    public static let demo = LunaFindPanelMetrics()
}

public struct LunaFindPanelButton: Hashable, Sendable {
    public var nodeID: LunaNodeID
    public var label: String
    public var bounds: LunaRectI
    public var isSelected: Bool

    public init(nodeID: LunaNodeID, label: String, bounds: LunaRectI, isSelected: Bool = false) {
        self.nodeID = nodeID
        self.label = label
        self.bounds = bounds
        self.isSelected = isSelected
    }
}

public struct LunaFindPanelLayout: Hashable, Sendable {
    public var bounds: LunaRectI
    public var panelBounds: LunaRectI
    public var titleBounds: LunaRectI
    public var queryFieldBounds: LunaRectI
    public var replaceFieldBounds: LunaRectI
    public var optionsRowBounds: LunaRectI
    public var actionsRowBounds: LunaRectI
    public var statusBounds: LunaRectI
    public var caseToggleBounds: LunaRectI
    public var wholeWordToggleBounds: LunaRectI
    public var regexToggleBounds: LunaRectI
    public var previousButtonBounds: LunaRectI
    public var nextButtonBounds: LunaRectI
    public var replaceButtonBounds: LunaRectI
    public var replaceAllButtonBounds: LunaRectI

    public init(
        bounds: LunaRectI,
        panelBounds: LunaRectI,
        titleBounds: LunaRectI,
        queryFieldBounds: LunaRectI,
        replaceFieldBounds: LunaRectI,
        optionsRowBounds: LunaRectI,
        actionsRowBounds: LunaRectI,
        statusBounds: LunaRectI,
        caseToggleBounds: LunaRectI,
        wholeWordToggleBounds: LunaRectI,
        regexToggleBounds: LunaRectI,
        previousButtonBounds: LunaRectI,
        nextButtonBounds: LunaRectI,
        replaceButtonBounds: LunaRectI,
        replaceAllButtonBounds: LunaRectI
    ) {
        self.bounds = bounds
        self.panelBounds = panelBounds
        self.titleBounds = titleBounds
        self.queryFieldBounds = queryFieldBounds
        self.replaceFieldBounds = replaceFieldBounds
        self.optionsRowBounds = optionsRowBounds
        self.actionsRowBounds = actionsRowBounds
        self.statusBounds = statusBounds
        self.caseToggleBounds = caseToggleBounds
        self.wholeWordToggleBounds = wholeWordToggleBounds
        self.regexToggleBounds = regexToggleBounds
        self.previousButtonBounds = previousButtonBounds
        self.nextButtonBounds = nextButtonBounds
        self.replaceButtonBounds = replaceButtonBounds
        self.replaceAllButtonBounds = replaceAllButtonBounds
    }
}

public struct LunaFindPanelTextLayout: Hashable, Sendable {
    public var title: LunaBoundedTextLine
    public var query: LunaBoundedTextLine
    public var replace: LunaBoundedTextLine
    public var status: LunaBoundedTextLine
    public var buttons: [LunaFindPanelButton]

    public init(
        title: LunaBoundedTextLine,
        query: LunaBoundedTextLine,
        replace: LunaBoundedTextLine,
        status: LunaBoundedTextLine,
        buttons: [LunaFindPanelButton]
    ) {
        self.title = title
        self.query = query
        self.replace = replace
        self.status = status
        self.buttons = buttons
    }
}

public struct LunaFindPanel: Hashable, Sendable {
    public var id: LunaNodeID
    public var bounds: LunaRectI
    public var title: String
    public var queryPlaceholder: String
    public var replacePlaceholder: String
    public var state: LunaFindPanelState
    public var theme: LunaTheme
    public var metrics: LunaFindPanelMetrics

    public init(
        id: LunaNodeID,
        bounds: LunaRectI,
        title: String = "Find / Replace",
        queryPlaceholder: String = "Find…",
        replacePlaceholder: String = "Replace…",
        state: LunaFindPanelState,
        theme: LunaTheme = .lunaDefaultDark,
        metrics: LunaFindPanelMetrics = .demo
    ) {
        self.id = id
        self.bounds = bounds
        self.title = title
        self.queryPlaceholder = queryPlaceholder
        self.replacePlaceholder = replacePlaceholder
        self.state = state
        self.theme = theme
        self.metrics = metrics
    }

    public var queryFieldNodeID: LunaNodeID { id.child("query") }
    public var replaceFieldNodeID: LunaNodeID { id.child("replace") }
    public var caseToggleNodeID: LunaNodeID { id.child("option.case-sensitive") }
    public var wholeWordToggleNodeID: LunaNodeID { id.child("option.whole-word") }
    public var regexToggleNodeID: LunaNodeID { id.child("option.regex") }
    public var previousButtonNodeID: LunaNodeID { id.child("action.previous") }
    public var nextButtonNodeID: LunaNodeID { id.child("action.next") }
    public var replaceButtonNodeID: LunaNodeID { id.child("action.replace") }
    public var replaceAllButtonNodeID: LunaNodeID { id.child("action.replace-all") }
    public var statusNodeID: LunaNodeID { id.child("status") }

    public func layout() -> LunaFindPanelLayout {
        guard !bounds.isEmpty else {
            let zero = LunaRectI(x: bounds.x, y: bounds.y, w: 0, h: 0)
            return LunaFindPanelLayout(bounds: bounds, panelBounds: zero, titleBounds: zero, queryFieldBounds: zero, replaceFieldBounds: zero, optionsRowBounds: zero, actionsRowBounds: zero, statusBounds: zero, caseToggleBounds: zero, wholeWordToggleBounds: zero, regexToggleBounds: zero, previousButtonBounds: zero, nextButtonBounds: zero, replaceButtonBounds: zero, replaceAllButtonBounds: zero)
        }

        let availableW = max(1, bounds.w - metrics.sideMargin * 2)
        let panelW = min(metrics.maxPanelWidth, max(min(metrics.minPanelWidth, availableW), availableW))
        let titleH = 16
        let panelH = metrics.panelPadding * 2
            + titleH
            + metrics.rowGap
            + metrics.fieldHeight
            + metrics.rowGap
            + (state.isReplaceVisible ? metrics.fieldHeight + metrics.rowGap : 0)
            + metrics.buttonHeight
        let panelX = bounds.x + max(0, (bounds.w - panelW) / 2)
        let panelY = bounds.y + max(0, bounds.h - metrics.bottomMargin - panelH)
        let panel = LunaRectI(x: panelX, y: panelY, w: panelW, h: min(panelH, bounds.h))
        let contentX = panel.x + metrics.panelPadding
        let contentW = max(1, panel.w - metrics.panelPadding * 2)
        let titleBounds = LunaRectI(x: contentX, y: panel.y + metrics.panelPadding, w: contentW, h: titleH)
        let queryBounds = LunaRectI(x: contentX, y: titleBounds.y + titleBounds.h + metrics.rowGap, w: contentW, h: metrics.fieldHeight)
        let replaceBounds = state.isReplaceVisible
            ? LunaRectI(x: contentX, y: queryBounds.y + queryBounds.h + metrics.rowGap, w: contentW, h: metrics.fieldHeight)
            : LunaRectI(x: contentX, y: queryBounds.y + queryBounds.h, w: contentW, h: 0)
        let controlsY = state.isReplaceVisible ? replaceBounds.y + replaceBounds.h + metrics.rowGap : queryBounds.y + queryBounds.h + metrics.rowGap
        let controls = LunaRectI(x: contentX, y: controlsY, w: contentW, h: metrics.buttonHeight)

        let gap = 6
        let caseToggle = LunaRectI(x: controls.x, y: controls.y, w: metrics.optionWidth, h: controls.h)
        let wordToggle = LunaRectI(x: caseToggle.x + caseToggle.w + gap, y: controls.y, w: metrics.optionWidth, h: controls.h)
        let regexToggle = LunaRectI(x: wordToggle.x + wordToggle.w + gap, y: controls.y, w: metrics.optionWidth, h: controls.h)
        let right = controls.x + controls.w
        let replaceAll = LunaRectI(x: right - metrics.actionButtonWidth, y: controls.y, w: metrics.actionButtonWidth, h: controls.h)
        let replace = LunaRectI(x: replaceAll.x - gap - metrics.actionButtonWidth, y: controls.y, w: metrics.actionButtonWidth, h: controls.h)
        let next = LunaRectI(x: replace.x - gap - metrics.actionButtonWidth, y: controls.y, w: metrics.actionButtonWidth, h: controls.h)
        let previous = LunaRectI(x: next.x - gap - metrics.actionButtonWidth, y: controls.y, w: metrics.actionButtonWidth, h: controls.h)
        let status = LunaRectI(x: regexToggle.x + regexToggle.w + gap, y: controls.y + 5, w: max(1, previous.x - regexToggle.x - regexToggle.w - gap * 2), h: max(1, controls.h - 8))

        return LunaFindPanelLayout(
            bounds: bounds,
            panelBounds: panel,
            titleBounds: titleBounds,
            queryFieldBounds: queryBounds,
            replaceFieldBounds: replaceBounds,
            optionsRowBounds: controls,
            actionsRowBounds: controls,
            statusBounds: status,
            caseToggleBounds: caseToggle,
            wholeWordToggleBounds: wordToggle,
            regexToggleBounds: regexToggle,
            previousButtonBounds: previous,
            nextButtonBounds: next,
            replaceButtonBounds: replace,
            replaceAllButtonBounds: replaceAll
        )
    }

    public func textLayout() -> LunaFindPanelTextLayout {
        let layout = layout()
        let titleLine = bounded(title, in: layout.titleBounds)
        let queryText = state.queryText.isEmpty ? queryPlaceholder : state.queryText
        let replaceText = state.replaceText.isEmpty ? replacePlaceholder : state.replaceText
        let queryLine = bounded(queryText, in: layout.queryFieldBounds.insetForFindText(x: 8, y: 6))
        let replaceLine = bounded(replaceText, in: layout.replaceFieldBounds.insetForFindText(x: 8, y: 6))
        let statusLine = bounded(state.results.statusText, in: layout.statusBounds)
        let buttons = [
            LunaFindPanelButton(nodeID: caseToggleNodeID, label: "Aa", bounds: layout.caseToggleBounds, isSelected: state.options.isCaseSensitive),
            LunaFindPanelButton(nodeID: wholeWordToggleNodeID, label: "Word", bounds: layout.wholeWordToggleBounds, isSelected: state.options.matchesWholeWord),
            LunaFindPanelButton(nodeID: regexToggleNodeID, label: ".*", bounds: layout.regexToggleBounds, isSelected: state.options.usesRegularExpression),
            LunaFindPanelButton(nodeID: previousButtonNodeID, label: "Prev", bounds: layout.previousButtonBounds),
            LunaFindPanelButton(nodeID: nextButtonNodeID, label: "Next", bounds: layout.nextButtonBounds),
            LunaFindPanelButton(nodeID: replaceButtonNodeID, label: "Replace", bounds: layout.replaceButtonBounds),
            LunaFindPanelButton(nodeID: replaceAllButtonNodeID, label: "All", bounds: layout.replaceAllButtonBounds),
        ]
        return LunaFindPanelTextLayout(title: titleLine, query: queryLine, replace: replaceLine, status: statusLine, buttons: buttons)
    }

    private func bounded(_ text: String, in bounds: LunaRectI) -> LunaBoundedTextLine {
        LunaBoundedTextLayout.layout(text, in: bounds, metrics: metrics.glyphMetrics, overflow: .ellipsizeTail).firstLine
            ?? LunaBoundedTextLine(text: "", fullText: text, bounds: bounds, isClipped: !text.isEmpty)
    }

    public func buildDisplayList(into displayList: inout LunaDisplayList) {
        guard !bounds.isEmpty else { return }
        let layout = layout()
        let panel = LunaPanelVisualStyle(theme: theme)
        let field = LunaTextFieldVisualStyle(theme: theme)
        let controls = LunaControlVisualStyle(theme: theme)

        displayList.append(.rect(layout.panelBounds, panel.border))
        displayList.append(.rect(layout.panelBounds.insetForFind(by: 1), panel.background))
        displayList.append(.rect(LunaRectI(x: layout.panelBounds.x, y: layout.panelBounds.y, w: layout.panelBounds.w, h: 1), field.focusedBorder))

        appendField(layout.queryFieldBounds, focused: state.focusedField == .query, displayList: &displayList, field: field)
        if state.isReplaceVisible {
            appendField(layout.replaceFieldBounds, focused: state.focusedField == .replace, displayList: &displayList, field: field)
        }

        for button in textLayout().buttons where !button.bounds.isEmpty {
            let background = button.isSelected ? controls.controlSelected : controls.controlNormal
            displayList.append(.rect(button.bounds, background))
            displayList.appendStroke(button.bounds, color: button.isSelected ? controls.accent : controls.panelBorder, thickness: 1)
        }
    }

    private func appendField(
        _ bounds: LunaRectI,
        focused: Bool,
        displayList: inout LunaDisplayList,
        field: LunaTextFieldVisualStyle
    ) {
        guard !bounds.isEmpty else { return }
        displayList.append(.rect(bounds, focused ? field.focusedBorder : field.border))
        displayList.append(.rect(bounds.insetForFind(by: 1), field.background))
    }

    public func buildAccessibilityNode() -> LunaAccessibilityNode {
        let layout = layout()
        return LunaAccessibilityNode(
            id: id,
            role: .dialog,
            label: title,
            value: state.results.statusText,
            bounds: layout.panelBounds.asAccessibilityRect,
            isEnabled: true,
            isFocused: true,
            children: [queryFieldNodeID, replaceFieldNodeID, statusNodeID, caseToggleNodeID, wholeWordToggleNodeID, regexToggleNodeID, previousButtonNodeID, nextButtonNodeID, replaceButtonNodeID, replaceAllButtonNodeID],
            actions: [.focus]
        )
    }

    public func buildAccessibilityChildren() -> [LunaAccessibilityNode] {
        let layout = layout()
        return [
            LunaAccessibilityNode(id: queryFieldNodeID, role: .textArea, label: queryPlaceholder, value: state.queryText, bounds: layout.queryFieldBounds.asAccessibilityRect, isEnabled: true, isFocused: state.focusedField == .query, isEditable: true, actions: [.focus]),
            LunaAccessibilityNode(id: replaceFieldNodeID, role: .textArea, label: replacePlaceholder, value: state.replaceText, bounds: layout.replaceFieldBounds.asAccessibilityRect, isEnabled: true, isFocused: state.focusedField == .replace, isEditable: true, actions: [.focus]),
            LunaAccessibilityNode(id: statusNodeID, role: .status, label: "Find result count", value: state.results.statusText, bounds: layout.statusBounds.asAccessibilityRect),
            toggleNode(id: caseToggleNodeID, label: "Case sensitive", selected: state.options.isCaseSensitive, bounds: layout.caseToggleBounds),
            toggleNode(id: wholeWordToggleNodeID, label: "Whole word", selected: state.options.matchesWholeWord, bounds: layout.wholeWordToggleBounds),
            toggleNode(id: regexToggleNodeID, label: "Regular expression", selected: state.options.usesRegularExpression, bounds: layout.regexToggleBounds),
            buttonNode(id: previousButtonNodeID, label: "Find previous", bounds: layout.previousButtonBounds),
            buttonNode(id: nextButtonNodeID, label: "Find next", bounds: layout.nextButtonBounds),
            buttonNode(id: replaceButtonNodeID, label: "Replace current", bounds: layout.replaceButtonBounds),
            buttonNode(id: replaceAllButtonNodeID, label: "Replace all", bounds: layout.replaceAllButtonBounds),
        ]
    }

    private func toggleNode(id: LunaNodeID, label: String, selected: Bool, bounds: LunaRectI) -> LunaAccessibilityNode {
        LunaAccessibilityNode(id: id, role: .toggleButton, label: label, value: selected ? "on" : "off", bounds: bounds.asAccessibilityRect, isEnabled: true, isFocused: false, actions: [.press, .focus])
    }

    private func buttonNode(id: LunaNodeID, label: String, bounds: LunaRectI) -> LunaAccessibilityNode {
        LunaAccessibilityNode(id: id, role: .button, label: label, bounds: bounds.asAccessibilityRect, isEnabled: true, isFocused: false, actions: [.press, .focus])
    }

    public func hitTest(_ point: LunaPointI) -> LunaNodeID? {
        let layout = layout()
        let ordered = [
            previousButtonNodeID: layout.previousButtonBounds,
            nextButtonNodeID: layout.nextButtonBounds,
            replaceButtonNodeID: layout.replaceButtonBounds,
            replaceAllButtonNodeID: layout.replaceAllButtonBounds,
            caseToggleNodeID: layout.caseToggleBounds,
            wholeWordToggleNodeID: layout.wholeWordToggleBounds,
            regexToggleNodeID: layout.regexToggleBounds,
            queryFieldNodeID: layout.queryFieldBounds,
            replaceFieldNodeID: layout.replaceFieldBounds,
        ]
        for (id, rect) in ordered where rect.contains(x: point.x, y: point.y) { return id }
        if layout.panelBounds.contains(x: point.x, y: point.y) { return id }
        return nil
    }
}

// MARK: - Local draw helpers

private extension LunaRectI {
    func insetForFind(by amount: Int) -> LunaRectI {
        let a = max(0, amount)
        return LunaRectI(x: x + a, y: y + a, w: max(0, w - a * 2), h: max(0, h - a * 2))
    }

    func insetForFindText(x dx: Int, y dy: Int) -> LunaRectI {
        LunaRectI(x: x + max(0, dx), y: y + max(0, dy), w: max(1, w - max(0, dx) * 2), h: max(1, h - max(0, dy) * 2))
    }
}

private extension LunaDisplayList {
    mutating func appendStroke(_ rect: LunaRectI, color: LunaRender.LunaRGBA8, thickness: Int) {
        guard !rect.isEmpty else { return }
        let t = max(1, thickness)
        append(.rect(LunaRectI(x: rect.x, y: rect.y, w: rect.w, h: t), color))
        append(.rect(LunaRectI(x: rect.x, y: rect.y + rect.h - t, w: rect.w, h: t), color))
        append(.rect(LunaRectI(x: rect.x, y: rect.y, w: t, h: rect.h), color))
        append(.rect(LunaRectI(x: rect.x + rect.w - t, y: rect.y, w: t, h: rect.h), color))
    }
}
