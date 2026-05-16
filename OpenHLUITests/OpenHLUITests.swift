// SPDX-License-Identifier: MIT

import XCTest

// MARK: - Phase 0 regression

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

// MARK: - Phase 2 tab navigation
//
// NOTE (qa-automation): These tests require:
//   1. ios-developer to implement the three-tab shell (Positions / Orders / Fills).
//   2. UITestStubClient to support the following stub keys:
//      - "tab_shell_stub": seeds the address and returns non-empty data for all
//        three endpoints so each tab shows at least one row of content.
//        Suggested ios-developer contract in UITestStubClient.swift:
//          case "tab_shell_stub":
//            clearinghouseState → makeSingleLong()
//            openOrders        → [one BTC limit order row]
//            userFills         → [one ETH close-short fill row]
//        The exact static text that the Orders and Fills tabs expose must match
//        the accessibility identifiers below. Update the assertions if the text
//        labels change.
//   3. The tab bar items must have stable accessibility identifiers or labels:
//        Positions tab: "Positions"
//        Orders tab:    "Orders"
//        Fills tab:     "Fills"
//
// When the injection point and tab shell land, remove the XCTSkip call.

final class TabNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Three-tab shell renders and each tab shows characteristic content.
    ///
    /// Stub contract key: "tab_shell_stub"
    /// - Positions tab: "Account value" label must exist (from PositionsView header).
    /// - Orders tab: at least one row; "BTC" static text must exist.
    /// - Fills tab: at least one row; "ETH" static text must exist.
    func testThreeTabShellRendersAndEachTabHasContent() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OPENHL_UI_TEST_STUB"] = "tab_shell_stub"
        app.launch()

        // --- Positions tab (default) ---
        let accountValueLabel = app.staticTexts["Account value"]
        XCTAssertTrue(
            accountValueLabel.waitForExistence(timeout: 5), "Account value header must exist on Positions tab")

        // --- Orders tab ---
        let ordersTab = app.tabBars.buttons["Orders"]
        XCTAssertTrue(ordersTab.exists, "Orders tab must exist in tab bar")
        ordersTab.tap()

        let btcOrderText = app.staticTexts["BTC"]
        XCTAssertTrue(btcOrderText.waitForExistence(timeout: 5), "BTC order row must exist on Orders tab")

        // --- Fills tab ---
        let fillsTab = app.tabBars.buttons["Fills"]
        XCTAssertTrue(fillsTab.exists, "Fills tab must exist in tab bar")
        fillsTab.tap()

        let ethFillText = app.staticTexts["ETH"]
        XCTAssertTrue(ethFillText.waitForExistence(timeout: 5), "ETH fill row must exist on Fills tab")

        // --- Navigate back to Positions ---
        let positionsTab = app.tabBars.buttons["Positions"]
        XCTAssertTrue(positionsTab.exists, "Positions tab must exist in tab bar")
        positionsTab.tap()
        XCTAssertTrue(
            accountValueLabel.waitForExistence(timeout: 3), "Positions tab content must reappear after tab switch")
    }

    /// Verify the existing Positions happy-path test still passes when the
    /// tab shell is present. "Account value" must appear on the Positions tab.
    /// This test mirrors testEntryToLoadedHappyPath in AddressEntryUITests
    /// and acts as a regression guard for any tab-shell restructuring that
    /// might move the account-value label.
    func testPositionsTabStillShowsAccountValue() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OPENHL_UI_TEST_STUB"] = "tab_shell_stub"
        app.launch()

        let accountValueLabel = app.staticTexts["Account value"]
        XCTAssertTrue(
            accountValueLabel.waitForExistence(timeout: 5),
            "Account value header must be visible on the Positions tab after the tab shell is introduced"
        )

        let btcRow = app.staticTexts["BTC"]
        XCTAssertTrue(btcRow.waitForExistence(timeout: 3), "BTC position row must still appear on Positions tab")
    }
}

// MARK: - Phase 1 critical paths

// NOTE (qa-automation): The entry → loaded happy-path UI test below requires
// the app to support a launch-environment injection point that swaps in a
// deterministic in-memory `HyperliquidClient` returning a fixture.
//
// The injection contract (to be implemented by ios-developer in OpenHLApp.swift):
//
//   1. Read `ProcessInfo.processInfo.environment["OPENHL_UI_TEST_STUB"]` at
//      app startup (in the `init()` of `OpenHLApp`).
//   2. When the value is `"clearinghouseState_single_long"`, construct an
//      `InMemoryHyperliquidClient` seeded with that fixture's data and pass
//      it to the composition root instead of `URLSessionHyperliquidClient`.
//   3. Also seed `UserDefaultsAddressStore` (or `InMemoryAddressStore`) with
//      the test address "0xabcdef1234567890abcdef1234567890abcdef12" so
//      the app skips the address-entry screen and lands directly on the
//      positions view.
//
// When the injection point lands, remove the `XCTSkip` call and uncomment
// the assertions marked TODO below.

final class AddressEntryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // -------------------------------------------------------------------------
    // Happy path: paste address → positions view is shown
    // -------------------------------------------------------------------------

    func testEntryToLoadedHappyPath() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OPENHL_UI_TEST_STUB"] = "clearinghouseState_single_long"
        app.launch()

        // The stub pre-seeds the address, so the positions screen should appear.
        let accountValueLabel = app.staticTexts["Account value"]
        XCTAssertTrue(accountValueLabel.waitForExistence(timeout: 5))

        // Verify at least one position row is visible (stub returns BTC long).
        let btcRow = app.staticTexts["BTC"]
        XCTAssertTrue(btcRow.waitForExistence(timeout: 3))
    }

    // -------------------------------------------------------------------------
    // Address entry screen: valid address advances, invalid shows inline error
    // -------------------------------------------------------------------------

    func testAddressEntryValidationInlineError() throws {
        throw XCTSkip(
            """
            TODO (qa-automation): Requires ios-developer to implement the \
            AddressEntry screen with an accessibility-identified text field \
            ("Address input") and error label ("Address error"). \
            Remove this XCTSkip when the screen exists.
            """
        )

        // let app = XCUIApplication()
        // app.launch()
        //
        // let field = app.textFields["Address input"]
        // field.tap()
        // field.typeText("not-a-valid-address")
        //
        // // Dismiss keyboard / trigger validation
        // app.buttons["Continue"].tap()
        //
        // let errorLabel = app.staticTexts["Address error"]
        // XCTAssertTrue(errorLabel.waitForExistence(timeout: 2))
    }

    // -------------------------------------------------------------------------
    // Pull-to-refresh: refresh spinner appears and positions update
    // -------------------------------------------------------------------------

    func testPullToRefresh() throws {
        throw XCTSkip(
            """
            TODO (qa-automation): Requires OPENHL_UI_TEST_STUB injection point \
            and PositionsView to exist. Remove XCTSkip when both land.
            """
        )

        // let app = XCUIApplication()
        // app.launchEnvironment["OPENHL_UI_TEST_STUB"] = "clearinghouseState_single_long"
        // app.launch()
        //
        // let list = app.scrollViews.firstMatch
        // list.swipeDown()
        // // After refresh the same positions should still be visible.
        // XCTAssertTrue(app.staticTexts["BTC"].waitForExistence(timeout: 5))
    }

    // -------------------------------------------------------------------------
    // Error state: offline error renders actionable error view
    // -------------------------------------------------------------------------

    func testOfflineErrorStateIsRendered() throws {
        throw XCTSkip(
            """
            TODO (qa-automation): Requires OPENHL_UI_TEST_STUB injection with \
            an "offline" error mode. Define a second stub mode in OpenHLApp.swift \
            (e.g. OPENHL_UI_TEST_STUB=error_offline) and remove this XCTSkip.
            """
        )
    }
}
