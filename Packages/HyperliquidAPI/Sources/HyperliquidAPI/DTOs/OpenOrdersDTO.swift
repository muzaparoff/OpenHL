// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// Wire DTO for one entry in the `openOrders` response array. The
/// endpoint returns a JSON array at the top level, so the response is
/// modeled as `[OpenOrderDTO]` — no wrapping struct.
///
/// DTO conventions (same as `ClearinghouseStateDTO`):
/// - Suffix `DTO`. `internal` access — DTOs do not leak across the
///   package boundary.
/// - `Decodable, Sendable`. No `Encodable` in production code.
/// - Money fields use `@DecimalString` / `@OptionalDecimalString`.
/// - Coding keys mirror wire names exactly.
/// - No computed properties, no validation. Validation and translation
///   live in the DTO -> domain mapper inside the client.
///
/// Field notes:
/// - `side` is `"B"` (buy) or `"A"` (ask/sell) on the wire. The mapper
///   translates to `OpenOrder.Side.buy`/`.sell`. Unknown values throw
///   `HyperliquidError.unexpectedResponse`.
/// - `origSz` is sometimes absent — `Optional`.
/// - `reduceOnly` is sometimes absent — `Optional<Bool>`, defaulted to
///   `false` by the mapper.
/// - `orderType` is `"Limit"` / `"Trigger"` / `"Stop Limit"` / etc. when
///   present, but the Hyperliquid API often omits this field entirely for
///   plain limit orders. `Optional` — the mapper defaults to `.limit` when
///   absent. Unknown values map to `.unknown(rawString)` (no throw).
/// - `triggerPx` is present only for trigger orders — `Optional`.
/// - `timestamp` is ms since epoch.
///
/// A hand-written `init(from:)` is required because `@OptionalDecimalString`
/// and `Bool?` property wrappers synthesize `init(from:)` calls that expect
/// their coding key to be present in the JSON — they cannot handle a
/// completely absent key (only `null`). `decodeIfPresent` handles the
/// key-absent case correctly.
internal struct OpenOrderDTO: Decodable, Sendable {
    internal let coin: String
    internal let side: String  // "B" | "A"
    @DecimalString internal var limitPx: Decimal
    @DecimalString internal var sz: Decimal
    internal let oid: Int64
    internal let timestamp: Int64

    @OptionalDecimalString internal var origSz: Decimal?
    internal let reduceOnly: Bool?
    /// `nil` when the API omits the field (common for plain limit orders).
    /// Mapper defaults to `.limit` in that case.
    internal let orderType: String?
    @OptionalDecimalString internal var triggerPx: Decimal?

    private enum CodingKeys: String, CodingKey {
        case coin, side, limitPx, sz, oid, timestamp, origSz, reduceOnly, orderType, triggerPx
    }

    internal init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        coin = try c.decode(String.self, forKey: .coin)
        side = try c.decode(String.self, forKey: .side)
        oid = try c.decode(Int64.self, forKey: .oid)
        timestamp = try c.decode(Int64.self, forKey: .timestamp)
        // orderType is absent for plain limit orders — treat as optional
        orderType = try c.decodeIfPresent(String.self, forKey: .orderType)
        reduceOnly = try c.decodeIfPresent(Bool.self, forKey: .reduceOnly)

        // Required decimal strings — decode via property wrapper's init
        _limitPx = try c.decode(DecimalString.self, forKey: .limitPx)
        _sz = try c.decode(DecimalString.self, forKey: .sz)

        // Optional decimal strings — use decodeIfPresent so a missing key
        // (not just null) correctly produces nil without throwing keyNotFound
        if let wrapper = try c.decodeIfPresent(OptionalDecimalString.self, forKey: .origSz) {
            _origSz = wrapper
        } else {
            _origSz = OptionalDecimalString(wrappedValue: nil)
        }

        if let wrapper = try c.decodeIfPresent(OptionalDecimalString.self, forKey: .triggerPx) {
            _triggerPx = wrapper
        } else {
            _triggerPx = OptionalDecimalString(wrappedValue: nil)
        }
    }
}
