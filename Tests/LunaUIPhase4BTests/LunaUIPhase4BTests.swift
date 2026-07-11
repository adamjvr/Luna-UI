// SPDX-License-Identifier: MPL-2.0
import Testing
import LunaAccessibility
import LunaCore
import LunaInput
import LunaRender
import LunaTheme
import LunaUI

@Suite("Phase 4B find and replace panel")
struct LunaUIPhase4BTests {
    private func document() -> LunaStaticTextDocument {
        LunaStaticTextDocument(text: "Alpha beta alpha\nBeta alphabet beta\nalpha")
    }

    @Test("literal search returns stable UTF-8 ranges in document order")
    func literalSearchRanges() {
        let results = LunaFindScanner.results(
            in: document(),
            query: LunaFindQuery(text: "alpha", options: LunaFindOptions(isCaseSensitive: false))
        )
        #expect(results.count == 4)
        #expect(results.matches.map(\.matchedText) == ["Alpha", "alpha", "alpha", "alpha"])
        #expect(results.matches[0].range.anchor == LunaTextLocation(lineIndex: 0, utf8Column: 0))
        #expect(results.matches[1].range.anchor == LunaTextLocation(lineIndex: 0, utf8Column: 11))
        #expect(results.statusText == "1 of 4")
    }

    @Test("case sensitive and whole word options narrow matches")
    func optionsNarrowMatches() {
        let caseSensitive = LunaFindScanner.results(
            in: document(),
            query: LunaFindQuery(text: "alpha", options: LunaFindOptions(isCaseSensitive: true))
        )
        #expect(caseSensitive.count == 3)

        let wholeWord = LunaFindScanner.results(
            in: document(),
            query: LunaFindQuery(text: "alpha", options: LunaFindOptions(matchesWholeWord: true))
        )
        #expect(wholeWord.count == 3)
        #expect(!wholeWord.matches.contains { $0.matchedText == "alpha" && $0.range.anchor.lineIndex == 1 })
    }

    @Test("regex search supports Foundation regular expressions")
    func regexSearch() {
        let results = LunaFindScanner.results(
            in: document(),
            query: LunaFindQuery(text: "b[a-z]+a", options: LunaFindOptions(usesRegularExpression: true))
        )
        #expect(results.count == 2)
        #expect(results.matches.map(\.matchedText) == ["beta", "Beta"])
    }

    @Test("find panel state edits query and navigates results")
    func stateInputAndNavigation() {
        var state = LunaFindPanelState()
        let input = state.handleTextInput(LunaTextInputEvent(text: "beta"), document: document())
        #expect(input.didConsumeEvent)
        #expect(input.didChangeState)
        #expect(state.queryText == "beta")
        #expect(state.results.count == 3)

        let next = state.handleKeyboardEvent(LunaKeyboardEvent(key: .enter), document: document())
        #expect(next.requestedAction == .findNext)
        state.selectNext()
        #expect(state.results.selectedMatchIndex == 1)

        let previous = state.handleKeyboardEvent(LunaKeyboardEvent(key: .enter, modifiers: LunaKeyboardModifiers(shift: true)), document: document())
        #expect(previous.requestedAction == .findPrevious)
    }

    @Test("tab focuses replace field and backspace edits focused field")
    func focusedFields() {
        var state = LunaFindPanelState(queryText: "alpha", replaceText: "omega")
        let tab = state.handleKeyboardEvent(LunaKeyboardEvent(key: .tab), document: document())
        #expect(tab.didConsumeEvent)
        #expect(state.focusedField == .replace)
        let backspace = state.handleKeyboardEvent(LunaKeyboardEvent(key: .backspace), document: document())
        #expect(backspace.didConsumeEvent)
        #expect(state.replaceText == "omeg")
        #expect(state.queryText == "alpha")
    }

    @Test("replace current mutates editable text and refreshes results")
    func replaceCurrent() {
        var text = LunaEditableTextState(text: "one two one two")
        var state = LunaFindPanelState(queryText: "one", replaceText: "ONE")
        state.refreshResults(in: text.document.staticDocument)
        #expect(state.results.count == 2)
        let result = LunaFindReplaceController.replaceCurrent(state: &state, text: &text)
        #expect(result?.didChange == true)
        #expect(text.document.text == "ONE two one two")
        #expect(text.editRevision == 1)
        #expect(state.results.count == 1)
    }

    @Test("replace all mutates all current matches")
    func replaceAll() {
        var text = LunaEditableTextState(text: "cat dog cat dog cat")
        var state = LunaFindPanelState(queryText: "cat", replaceText: "fox")
        state.refreshResults(in: text.document.staticDocument)
        let count = LunaFindReplaceController.replaceAll(state: &state, text: &text)
        #expect(count == 3)
        #expect(text.document.text == "fox dog fox dog fox")
        #expect(state.results.count == 0)
    }

    @Test("text view can render generic app-supplied highlight ranges")
    func textViewHighlights() {
        let doc = LunaStaticTextDocument(text: "find me\nfind me too")
        let results = LunaFindScanner.results(in: doc, query: LunaFindQuery(text: "find"))
        let color = LunaColor.hex("#003CFF88")
        let view = LunaStaticTextView(
            id: "text",
            bounds: LunaRectI(x: 0, y: 0, w: 320, h: 160),
            document: doc,
            theme: .lunaDefaultDark,
            highlights: results.matches.map { LunaStaticTextHighlight(range: $0.range, color: color) }
        )
        let layout = view.layout()
        #expect(layout.highlightRects.count == 2)
        var displayList = LunaDisplayList()
        view.buildDisplayList(into: &displayList)
        #expect(displayList.commands.contains { command in
            if case .rect(_, color.asRenderColor) = command { return true }
            return false
        })
    }

    @Test("panel layout, hit testing, display list, and accessibility are theme driven")
    func panelLayoutDisplayAndAccessibility() {
        var state = LunaFindPanelState(queryText: "alpha", replaceText: "omega")
        state.refreshResults(in: document())
        let panel = LunaFindPanel(
            id: "find",
            bounds: LunaRectI(x: 0, y: 0, w: 900, h: 600),
            state: state,
            theme: .highContrastProof
        )
        let layout = panel.layout()
        #expect(layout.panelBounds.w <= panel.metrics.maxPanelWidth)
        #expect(layout.queryFieldBounds.w > 0)
        #expect(panel.hitTest(LunaPointI(x: layout.nextButtonBounds.x + 2, y: layout.nextButtonBounds.y + 2)) == panel.nextButtonNodeID)

        var displayList = LunaDisplayList()
        panel.buildDisplayList(into: &displayList)
        #expect(displayList.commands.contains { command in
            if case .rect(_, LunaTextFieldVisualStyle(theme: .highContrastProof).background) = command { return true }
            return false
        })

        let root = panel.buildAccessibilityNode()
        let children = panel.buildAccessibilityChildren()
        #expect(root.role == .dialog)
        #expect(children.contains { $0.id == panel.queryFieldNodeID && $0.role == .textArea && $0.isEditable })
        #expect(children.contains { $0.id == panel.nextButtonNodeID && $0.role == .button })
        #expect(children.contains { $0.id == panel.caseToggleNodeID && $0.role == .toggleButton })
    }
}
