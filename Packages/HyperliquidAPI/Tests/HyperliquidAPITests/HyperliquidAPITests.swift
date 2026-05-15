// SPDX-License-Identifier: MIT

import HyperliquidAPI
import Testing

@Test("hyperliquidAPIVersion is a non-empty semver string")
func hyperliquidAPIVersionIsValid() {
    // Verify the constant is reachable and matches the Phase-0 placeholder value.
    // This will be updated when the first real release is cut.
    #expect(hyperliquidAPIVersion == "0.0.0")
    #expect(!hyperliquidAPIVersion.isEmpty)
}
