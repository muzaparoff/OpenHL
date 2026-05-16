// SPDX-License-Identifier: MIT

import XCTest

// MARK: - Phase 3d UI tests — Favorite coins pinned to top of Markets
//
// STATUS: Disabled pending two prerequisites from ios-developer:
//
//   1. Star button on each MarketRowView with a stable accessibility identifier.
//      Required format: "Favorite <coin>" (e.g. "Favorite BTC"), so the test can
//      resolve it via `app.buttons["Favorite BTC"]`. An `accessibilityLabel` set
//      on the button (toggling between "Favorite BTC" / "Unfavorite BTC") is the
//      preferred approach because it is readable by VoiceOver and stable across
//      layout changes.
//
//   2. The PINNED section header rendered as a visible static text element with
//      the exact string "PINNED" and `accessibilityIdentifier = "pinned-section-header"`.
//
//   3. A stub key that seeds Markets with at least BTC, ETH, SOL and seeds the
//      FavoriteCoinsStore with an empty initial set, so the test starts clean.
//      Suggested key: "markets_stub_no_favorites".
//
// UNLOCK CHECKLIST — remove XCTSkip when all items below are checked:
//   [ ] ios-developer: star button with accessibilityLabel "Favorite <coin>"
//   [ ] ios-developer: PINNED header with accessibilityIdentifier "pinned-section-header"
//   [ ] ios-developer: UITestStubClient handles "markets_stub_no_favorites"
//   [ ] ios-developer: OPENHL_UI_TEST_STUB injection also resets FavoriteCoinsStore
//       to InMemoryFavoriteCoinsStore (no cross-test state leakage via UserDefaults)

final class Phase3dFavoriteCoinsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // -------------------------------------------------------------------------
    // CRITICAL PATH: tap BTC star → BTC row appears under "PINNED" header
    // -------------------------------------------------------------------------

    func testTapStarMovesCoinToPinnedSection() throws {
        throw XCTSkip(
            """
            TODO (qa-automation/Phase 3d): Requires ios-developer to implement:
              1. Star button per market row with accessibilityLabel "Favorite <coin>".
              2. PINNED section header with accessibilityIdentifier "pinned-section-header".
              3. UITestStubClient stub key "markets_stub_no_favorites".
            Remove this XCTSkip when all three are in place.
            """
        )

        // Implementation (uncomment when unlocked):
        //
        // let app = XCUIApplication()
        // app.launchEnvironment["OPENHL_UI_TEST_STUB"] = "markets_stub_no_favorites"
        // app.launch()
        //
        // // 1. Markets tab should already be active (it is the default tab).
        // let marketsTab = app.tabBars.buttons["Markets"]
        // XCTAssertTrue(marketsTab.waitForExistence(timeout: 5), "Markets tab must exist")
        //
        // // 2. Confirm no PINNED header before any toggle.
        // let pinnedHeader = app.staticTexts.matching(
        //     identifier: "pinned-section-header").firstMatch
        // XCTAssertFalse(pinnedHeader.exists, "PINNED header must not appear before any coin is starred")
        //
        // // 3. Tap the BTC star button.
        // let btcStarButton = app.buttons["Favorite BTC"]
        // XCTAssertTrue(btcStarButton.waitForExistence(timeout: 5),
        //               "BTC favourite button must exist in Markets list")
        // btcStarButton.tap()
        //
        // // 4. PINNED section header must now appear.
        // XCTAssertTrue(pinnedHeader.waitForExistence(timeout: 3),
        //               "PINNED header must appear after favouriting BTC")
        //
        // // 5. BTC row must be the first row inside the PINNED section.
        // //    We assert that a "BTC" static text appears ABOVE the first
        // //    row of the MARKETS section. Using coordinate-ordering is
        // //    fragile; instead, rely on the accessibility element order
        // //    in the scroll view's children.
        // let firstMarketCellLabel = app.cells.firstMatch.staticTexts.firstMatch.label
        // XCTAssertEqual(firstMarketCellLabel, "BTC",
        //                "BTC must be the first visible cell after being pinned")
    }

    // -------------------------------------------------------------------------
    // Un-star removes the coin from PINNED and it returns to MARKETS
    // -------------------------------------------------------------------------

    func testUnstarCoinMovesBackToMarkets() throws {
        throw XCTSkip(
            """
            TODO (qa-automation/Phase 3d): Same prerequisites as testTapStarMovesCoinToPinnedSection.
            Remove this XCTSkip when all prerequisites land.
            """
        )

        // Implementation (uncomment when unlocked):
        //
        // let app = XCUIApplication()
        // app.launchEnvironment["OPENHL_UI_TEST_STUB"] = "markets_stub_no_favorites"
        // app.launch()
        //
        // // Star BTC.
        // app.buttons["Favorite BTC"].tap()
        //
        // let pinnedHeader = app.staticTexts.matching(
        //     identifier: "pinned-section-header").firstMatch
        // XCTAssertTrue(pinnedHeader.waitForExistence(timeout: 3))
        //
        // // Un-star BTC. After toggling, the label flips to "Unfavorite BTC".
        // let btcUnstarButton = app.buttons["Unfavorite BTC"]
        // XCTAssertTrue(btcUnstarButton.waitForExistence(timeout: 3))
        // btcUnstarButton.tap()
        //
        // // PINNED header must disappear (no more pinned coins).
        // let pinnedGone = !pinnedHeader.waitForExistence(timeout: 3)
        // XCTAssertTrue(pinnedGone, "PINNED header must disappear after un-starring the last pinned coin")
    }
}
