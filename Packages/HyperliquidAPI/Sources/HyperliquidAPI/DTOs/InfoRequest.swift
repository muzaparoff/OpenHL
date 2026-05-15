// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// Request body for `POST /info`. Hyperliquid uses a discriminator field
/// `type` plus per-type parameters. Phase 1 implements only the
/// `clearinghouseState` variant; Phase 2 will add `openOrders` and
/// `userFills` as additional cases.
///
/// Encoded as a flat JSON object: `{"type": "clearinghouseState",
/// "user": "0x..."}`. We do **not** wrap parameters in a nested object —
/// Hyperliquid expects them at the top level alongside `type`.
///
/// Modeled as an `enum` rather than a `struct` so the discriminator and
/// the parameters cannot drift apart at compile time. The custom
/// `Encodable` conformance flattens the case into the wire form.
public enum InfoRequest: Encodable, Sendable {
    case clearinghouseState(user: Address)
    // TODO Phase 2: case openOrders(user: Address)
    // TODO Phase 2: case userFills(user: Address)

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clearinghouseState(let user):
            try container.encode("clearinghouseState", forKey: .type)
            try container.encode(user.rawValue, forKey: .user)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, user
    }
}
