// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaInput
import LunaRender
@testable import LunaUI

final class LunaUIPhase5ETests: XCTestCase {
    private struct FixtureStorage: LunaTextStorageAdapter {
        var documentID: LunaDocumentID
        var contentRevision: LunaDocumentContentRevision
        var text: String

        func textSnapshot() -> LunaTextStorageSnapshot {
            LunaTextStorageSnapshot(
                documentID: documentID,
                revision: contentRevision,
                text: text
            )
        }
    }

    private struct FixtureProvider: LunaFindResultsProviding {
        var expectedQuery: String

        func results(for query: LunaFindQuery) -> LunaFindResultSet {
            let match = LunaFindMatch(
                id: "fixture.match",
                index: 0,
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 0, utf8Column: 1),
                    focus: LunaTextLocation(lineIndex: 0, utf8Column: 3)
                ),
                matchedText: expectedQuery,
                utf8Offset: 1,
                utf8Length: 2
            )
            return LunaFindResultSet(query: query, matches: query.text == expectedQuery ? [match] : [])
        }
    }

    private struct FixtureSession: LunaFindPanelSession {
        var performedActions: [LunaFindPanelAction] = []

        func results(for query: LunaFindQuery) -> LunaFindResultSet {
            LunaFindResultSet(query: query, matches: [])
        }

        mutating func perform(
            action: LunaFindPanelAction,
            query: LunaFindQuery,
            selectedMatch: LunaFindMatch?,
            replacementText: String
        ) -> LunaFindSessionActionResult {
            performedActions.append(action)
            return LunaFindSessionActionResult(
                results: LunaFindResultSet(query: query, matches: []),
                didChangeDocument: action == .replaceCurrent,
                replacementCount: action == .replaceCurrent ? 1 : 0
            )
        }
    }

    func testStorageSnapshotReadsClampedUTF8Ranges() {
        let snapshot = LunaTextStorageSnapshot(
            documentID: "shared",
            revision: LunaDocumentContentRevision(rawValue: 4),
            text: "AéZ"
        )

        XCTAssertEqual(snapshot.utf8Count, 4)
        XCTAssertEqual(snapshot.text(in: LunaUTF8TextRange(startOffset: 1, endOffset: 3)), "é")
        XCTAssertEqual(snapshot.text(in: LunaUTF8TextRange(startOffset: 999, endOffset: 1200)), "")
    }

    func testOneDocumentCanBackTwoIndependentViewStates() {
        let storage = FixtureStorage(
            documentID: "shared",
            contentRevision: .initial,
            text: "zero\none\ntwo\nthree"
        )
        let snapshot = storage.textSnapshot()

        var first = LunaDocumentViewPresentationState(
            id: "view.first",
            documentID: storage.documentID,
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 1, utf8Column: 2)),
            preferredUTF8Column: 7,
            scrollState: LunaStaticTextScrollState(scrollTopLine: 0)
        )
        var second = LunaDocumentViewPresentationState(
            id: "view.second",
            documentID: storage.documentID,
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 3, utf8Column: 5)),
            selection: LunaStaticTextSelection(
                range: LunaTextRange(
                    anchor: LunaTextLocation(lineIndex: 2, utf8Column: 0),
                    focus: LunaTextLocation(lineIndex: 3, utf8Column: 5)
                )
            ),
            preferredUTF8Column: 2,
            scrollState: LunaStaticTextScrollState(scrollTopLine: 2)
        )

        XCTAssertEqual(first.synchronize(with: snapshot)?.reason, .initialObservation)
        XCTAssertEqual(second.synchronize(with: snapshot)?.reason, .initialObservation)
        XCTAssertEqual(first.documentID, second.documentID)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.caret, second.caret)
        XCTAssertNotEqual(first.scrollState, second.scrollState)
        XCTAssertEqual(first.preferredUTF8Column, 7)
        XCTAssertEqual(second.preferredUTF8Column, 2)
    }

    func testRevisionChangeInvalidatesEachViewWithoutMergingPresentationState() {
        let initial = LunaTextStorageSnapshot(
            documentID: "shared",
            revision: .initial,
            text: "alpha\nbeta\ngamma"
        )
        let changed = LunaTextStorageSnapshot(
            documentID: "shared",
            revision: LunaDocumentContentRevision(rawValue: 1),
            text: "short"
        )

        var first = LunaDocumentViewPresentationState(
            id: "a",
            documentID: "shared",
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 2, utf8Column: 5)),
            preferredUTF8Column: 9,
            scrollState: LunaStaticTextScrollState(scrollTopLine: 2)
        )
        var second = LunaDocumentViewPresentationState(
            id: "b",
            documentID: "shared",
            caret: LunaStaticTextCaret(location: LunaTextLocation(lineIndex: 0, utf8Column: 1)),
            preferredUTF8Column: 1
        )

        _ = first.synchronize(with: initial)
        _ = second.synchronize(with: initial)
        let firstInvalidation = first.synchronize(with: changed, maxVisibleLineCount: 10)
        let secondInvalidation = second.synchronize(with: changed, maxVisibleLineCount: 10)

        XCTAssertEqual(firstInvalidation?.reason, .contentRevisionChanged)
        XCTAssertEqual(secondInvalidation?.reason, .contentRevisionChanged)
        XCTAssertEqual(first.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 5))
        XCTAssertEqual(second.caret.location, LunaTextLocation(lineIndex: 0, utf8Column: 1))
        XCTAssertEqual(first.preferredUTF8Column, 9)
        XCTAssertEqual(second.preferredUTF8Column, 1)
        XCTAssertNil(first.synchronize(with: changed))
    }

    func testFindPanelCanRefreshThroughInjectedProvider() {
        var state = LunaFindPanelState(queryText: "needle")
        state.refreshResults(using: FixtureProvider(expectedQuery: "needle"))

        XCTAssertEqual(state.results.count, 1)
        XCTAssertEqual(state.results.selectedMatch?.matchedText, "needle")

        let input = state.handleTextInput(
            LunaTextInputEvent(text: "!"),
            provider: FixtureProvider(expectedQuery: "needle")
        )
        XCTAssertTrue(input.didConsumeEvent)
        XCTAssertTrue(state.results.isEmpty)
    }

    func testFindPanelDelegatesReplacementPolicyToInjectedSession() {
        var state = LunaFindPanelState(queryText: "cat", replaceText: "fox")
        var session = FixtureSession()

        let result = state.perform(.replaceCurrent, using: &session)

        XCTAssertEqual(session.performedActions, [.replaceCurrent])
        XCTAssertTrue(result.didChangeDocument)
        XCTAssertEqual(result.replacementCount, 1)
    }

    func testLunaSourcesDoNotImportMothProductModules() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = repositoryRoot.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: nil
        )

        var violations: [String] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.range(of: #"(?m)^\s*(?:@_exported\s+)?import\s+Moth"#, options: .regularExpression) != nil {
                violations.append(fileURL.path.replacingOccurrences(of: repositoryRoot.path + "/", with: ""))
            }
        }

        XCTAssertTrue(violations.isEmpty, "Luna must not import Moth product modules: \(violations)")
    }

    func testPublicDebugBitmapRendererDrawsReadablePixels() {
        var framebuffer = LunaFramebuffer(width: 80, height: 20)
        framebuffer.clear(LunaRGBA8(r: 0, g: 0, b: 0))

        LunaDebugBitmapTextRenderer.draw(
            "Moth",
            atX: 2,
            y: 2,
            color: LunaRGBA8(r: 255, g: 255, b: 255),
            into: &framebuffer
        )

        var nonBlackPixelCount = 0
        framebuffer.withUnsafePixelBytes { bytes, stride in
            for y in 0..<framebuffer.height {
                for x in 0..<framebuffer.width {
                    let pixel = bytes.advanced(by: y * stride + x * 4)
                    if pixel[0] != 0 || pixel[1] != 0 || pixel[2] != 0 {
                        nonBlackPixelCount += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(nonBlackPixelCount, 0)
    }
}
