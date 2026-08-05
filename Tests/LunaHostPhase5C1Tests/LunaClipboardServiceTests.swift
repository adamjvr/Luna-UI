// SPDX-License-Identifier: MPL-2.0

import XCTest
@testable import LunaHostCore

final class LunaClipboardServiceTests: XCTestCase {
    func testInMemoryClipboardRoundTripsUnicodeAndMultilineText() throws {
        let clipboard = LunaInMemoryClipboardService()
        let value = "café\nΚαλημέρα\ne\u{301}"

        try clipboard.writeText(value)

        XCTAssertEqual(try clipboard.readText(), value)
    }

    func testScriptedWriteFailureDoesNotReplaceExistingClipboard() throws {
        let clipboard = LunaInMemoryClipboardService(text: "before")
        clipboard.failNextWrite()

        XCTAssertThrowsError(try clipboard.writeText("after"))
        XCTAssertEqual(try clipboard.readText(), "before")
    }

    func testScriptedReadFailureIsOneShot() throws {
        let clipboard = LunaInMemoryClipboardService(text: "stable")
        clipboard.failNextRead()

        XCTAssertThrowsError(try clipboard.readText())
        XCTAssertEqual(try clipboard.readText(), "stable")
    }

    func testUnavailableClipboardReportsCapabilityAndThrows() {
        let clipboard = LunaUnavailableClipboardService()
        XCTAssertFalse(clipboard.isAvailable)
        XCTAssertThrowsError(try clipboard.readText())
        XCTAssertThrowsError(try clipboard.writeText("x"))
    }
}
