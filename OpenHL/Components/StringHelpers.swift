// SPDX-License-Identifier: MIT

import Foundation

extension String {
    /// Truncates the string to `maxLength` characters by replacing the
    /// middle characters with an ellipsis. Used for address display in
    /// navigation bars.
    func truncatedMiddle(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let half = maxLength / 2 - 1
        return "\(prefix(half + 2))\u{2026}\(suffix(half))"
    }
}
