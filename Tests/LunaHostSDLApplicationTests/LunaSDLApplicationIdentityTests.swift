// SPDX-License-Identifier: MPL-2.0

#if os(Linux)

import XCTest
@testable import LunaHostSDL

final class LunaSDLApplicationIdentityTests: XCTestCase {
    func testConfigurationRetainsProductSuppliedApplicationIdentity() {
        let configuration = LunaSDLApplicationConfiguration(
            title: "Moth Text",
            applicationID: "io.github.adamjvr.MothText",
            windowClass: "MothTextLinux"
        )

        XCTAssertEqual(configuration.applicationID, "io.github.adamjvr.MothText")
        XCTAssertEqual(configuration.windowClass, "MothTextLinux")
    }
}

#endif
