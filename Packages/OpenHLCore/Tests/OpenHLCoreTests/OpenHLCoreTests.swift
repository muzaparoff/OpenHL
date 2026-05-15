// SPDX-License-Identifier: MIT

import OpenHLCore
import Testing

@Test("openHLCoreVersion is a non-empty semver string")
func openHLCoreVersionIsValid() {
    // Verify the constant is reachable and matches the Phase-0 placeholder value.
    // This will be updated when the first real release is cut.
    #expect(openHLCoreVersion == "0.0.0")
    #expect(!openHLCoreVersion.isEmpty)
}
