// SPDX-License-Identifier: MIT

import UIKit
import XCTest

/// End-to-end test that drives the app like a user:
///   1. Launches without any stub injection — the production
///      `URLSessionHyperliquidClient` hits `api.hyperliquid.xyz` for real.
///   2. Switches to the Wallet tab.
///   3. Taps "Watch an address".
///   4. Types `0x99382723C90EcC72dad2A7DD375DE45b88E8fe72` into the
///      address field.
///   5. Submits.
///   6. Waits for "Account value" to appear in the Wallet → Portfolio
///      section. If it does, the address was accepted, the network
///      request succeeded, the response decoded, and the view rendered.
///
/// This is a **live-network** test. It will fail offline. CI runners
/// without network access should skip this suite (see `setUpWithError`
/// — set `OPENHL_SKIP_LIVE_TESTS=1` in the runner env to bypass).
///
/// Why bother with live: when this test passes, the *entire* read path
/// is exercised end-to-end. When my DTO had a `null premium` bug last
/// week, every hand-authored fixture test was green but a real address
/// would have failed. This is the test that would have caught it.
final class WatchAddressLiveTests: XCTestCase {

    private static let testAddress = "0x99382723C90EcC72dad2A7DD375DE45b88E8fe72"

    override func setUpWithError() throws {
        continueAfterFailure = false
        if ProcessInfo.processInfo.environment["OPENHL_SKIP_LIVE_TESTS"] == "1" {
            throw XCTSkip("Skipped because OPENHL_SKIP_LIVE_TESTS=1.")
        }
    }

    func testWatchKnownAddressShowsAccountValue() throws {
        let app = XCUIApplication()
        // OPENHL_UI_TEST_RESET=1 — empty in-memory address store + real
        //   URLSession client.
        // OPENHL_UI_TEST_PRESEED_ADDRESS — pre-fills the field when the
        //   AddressEntry sheet is presented, sidestepping XCUITest's flaky
        //   typeText on monospaced fields. The submit + fetch + render
        //   path is still fully exercised.
        app.launchEnvironment["OPENHL_UI_TEST_RESET"] = "1"
        app.launchEnvironment["OPENHL_UI_TEST_PRESEED_ADDRESS"] = Self.testAddress
        app.launch()

        // 1. Switch to the Wallet tab.
        let walletTab = app.tabBars.buttons["Wallet"]
        XCTAssertTrue(walletTab.waitForExistence(timeout: 5), "Wallet tab must exist")
        walletTab.tap()

        // 2. Empty-state CTA opens the address-entry sheet.
        let watchButton = app.buttons["Watch an address"]
        XCTAssertTrue(
            watchButton.waitForExistence(timeout: 5),
            "Empty wallet state must show a 'Watch an address' button"
        )
        watchButton.tap()

        // 3. The address-entry field is pre-filled with the test address via
        // OPENHL_UI_TEST_PRESEED_ADDRESS. Verify the field exists and that
        // submission becomes possible (validation accepted the pre-seeded
        // value).
        let addressField = app.textFields["Hyperliquid wallet address"]
        XCTAssertTrue(
            addressField.waitForExistence(timeout: 5),
            "Address text field must exist after sheet presents"
        )

        // 4. Submit — the View account button uses an accessibilityLabel.
        let submitButton = app.buttons["View account"]
        XCTAssertTrue(
            submitButton.waitForExistence(timeout: 3),
            "'View account' submit button must be present"
        )
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        let enabledExpectation = expectation(
            for: enabledPredicate, evaluatedWith: submitButton
        )
        wait(for: [enabledExpectation], timeout: 5)
        submitButton.tap()

        // 5. Wait for the Portfolio section to render. The clearinghouseState
        // fetch goes over the real network — allow up to 30s for slow CI.
        let accountValueLabel = app.staticTexts["Account value"]
        let appeared = accountValueLabel.waitForExistence(timeout: 30)
        if !appeared {
            // Capture diagnostic context to help debug XCUITest flakes.
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            attachment.name = "post-submit-no-account-value"
            add(attachment)
        }
        XCTAssertTrue(
            appeared,
            "After submitting a valid address, 'Account value' must appear "
                + "(real Hyperliquid API). If this fails: check the screenshot "
                + "attachment, then run the HyperliquidAPI fixture tests."
        )

        // 6. As of capture (2026-05-16), this address holds a BTC short.
        // We don't assert on the position value (the account may change),
        // only that *some* coin name renders, confirming the position list
        // path is wired and decoded.
        let btcRow = app.staticTexts["BTC"]
        XCTAssertTrue(
            btcRow.waitForExistence(timeout: 5),
            "Expected a BTC position row for this address as of capture date. "
                + "If the account no longer holds BTC, update the fixture."
        )
    }
}
