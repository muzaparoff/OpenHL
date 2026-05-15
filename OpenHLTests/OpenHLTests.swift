// SPDX-License-Identifier: MIT

import Foundation
import Testing

/// Phase-0 wiring proof: the test host bundle is the OpenHL app target.
/// This assertion confirms that the test bundle is correctly attached to the
/// app host and that the bundle identifier is set as expected.
@Test("App bundle identifier matches com.openhl.app")
func appBundleIdentifierIsCorrect() {
    // Bundle.main in a unit-test host bundle refers to the app under test.
    // If this fails the test target is misconfigured (wrong host target).
    #expect(Bundle.main.bundleIdentifier == "com.openhl.app")
}
