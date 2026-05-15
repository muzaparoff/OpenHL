// SPDX-License-Identifier: MIT

import XCTest

final class OpenHLUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPlaceholderLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["open-hl"].exists)
    }
}
