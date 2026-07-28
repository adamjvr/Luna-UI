// SPDX-License-Identifier: MPL-2.0

import XCTest
import LunaCore
import LunaRender
import LunaTheme
@testable import LunaUI

final class LunaC25HLazyLineIndexTests: XCTestCase {
    func testLargeDocumentMetadataAndOffsetLookupRemainExact() throws {
        let text = (0..<50_000)
            .map { "line \($0) abcdefghijklmnopqrstuvwxyz" }
            .joined(separator: "\n")
        let document = LunaStaticTextDocument(text: text)

        XCTAssertEqual(document.lineCount, 50_000)
        XCTAssertEqual(document.utf8Count, text.utf8.count)
        XCTAssertEqual(document.lineMetadata(at: 0)?.utf8Offset, 0)
        XCTAssertEqual(document.lineMetadata(at: 49_999)?.index, 49_999)

        let target = try XCTUnwrap(document.lineMetadata(at: 40_000))
        XCTAssertEqual(
            document.location(forAbsoluteUTF8Offset: target.utf8Offset + 7),
            LunaTextLocation(lineIndex: 40_000, utf8Column: 7)
        )
        XCTAssertEqual(
            document.absoluteUTF8Offset(
                for: LunaTextLocation(lineIndex: 40_000, utf8Column: 7)
            ),
            target.utf8Offset + 7
        )
    }

    func testMetadataSamplingDoesNotRequireCompatibilityLineProjection() throws {
        let text = (0..<50_000)
            .map { "sample \($0) payload" }
            .joined(separator: "\n")
        let document = LunaStaticTextDocument(text: text)
        let indices = stride(from: 0, to: 50_000, by: 500)
        let lengths = indices.compactMap {
            document.lineMetadata(at: $0)?.utf8Length
        }

        XCTAssertEqual(lengths.count, 100)
        XCTAssertTrue(lengths.allSatisfy { $0 > 0 })
        XCTAssertEqual(try XCTUnwrap(document[line: 25_000]).text, "sample 25000 payload")
    }

    func testCompatibilityLinesProjectionPreservesTrailingNewlineAndUnicode() {
        let document = LunaStaticTextDocument(text: "é\n🙂\n")

        XCTAssertEqual(document.lineCount, 3)
        XCTAssertEqual(document.lines.map(\.text), ["é", "🙂", ""])
        XCTAssertEqual(document.lineMetadata(at: 0)?.utf8Length, 2)
        XCTAssertEqual(document.lineMetadata(at: 1)?.utf8Length, 4)
        XCTAssertEqual(document.location(forAbsoluteUTF8Offset: 2), LunaTextLocation(lineIndex: 0, utf8Column: 2))
        XCTAssertEqual(document.location(forAbsoluteUTF8Offset: 3), LunaTextLocation(lineIndex: 1, utf8Column: 0))
    }

    func testVirtualizationUsesIndexedDocumentWithoutWholeLineProjection() {
        let text = (0..<50_000)
            .map { "line \($0) abcdefghijklmnopqrstuvwxyz" }
            .joined(separator: "\n")
        let presentation = LunaStaticTextPresentationSnapshot(revision: 8, text: text)
        let context = LunaStaticTextVirtualizationContext(presentation: presentation)
        let counter = C25HGeometryCounter()

        let viewport = context.viewport(
            requestedTopVisualRow: 40_000,
            maxVisibleVisualRowCount: 30,
            overscanVisualRowCount: 2,
            viewportWidth: 320,
            wrapMode: .soft,
            estimatedGlyphAdvance: 8,
            geometryProvider: C25HGeometryProvider(counter: counter)
        )

        XCTAssertEqual(viewport.visibleRows.count, 30)
        XCTAssertLessThan(counter.requestCount, 128)
        XCTAssertLessThan(context.cachedLineCount, 64)
        XCTAssertEqual(presentation.document.lineCount, 50_000)
    }
}

private final class C25HGeometryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    func record() { lock.withLock { requests += 1 } }
    var requestCount: Int { lock.withLock { requests } }
}

private struct C25HGeometryProvider: LunaStaticTextGeometryProvider {
    let counter: C25HGeometryCounter
    func geometry(for request: LunaStaticTextGeometryRequest) -> LunaStaticTextRowGeometry {
        counter.record()
        return LunaStaticTextRowGeometry.fixedAdvance(sourceText: request.sourceText, advance: 8)
    }
}
