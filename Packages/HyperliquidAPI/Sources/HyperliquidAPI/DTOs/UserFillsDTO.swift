// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// Wire DTO for one entry in the `userFills` response array. The
/// endpoint returns a JSON array at the top level, so the response is
/// modeled as `[UserFillDTO]`.
///
/// DTO conventions: same as the rest of the package. See `OpenOrderDTO`
/// for the boilerplate.
///
/// Field notes:
/// - `side` is `"B"`/`"A"`. Mapper translates to `Fill.Side`.
/// - `time` is ms since epoch.
/// - `closedPnl` is a signed decimal string, present on every fill
///   (`"0.0"` on opening fills). Required, not optional.
/// - `dir` is the Hyperliquid human-readable label (`"Open Long"`,
///   `"Close Short"`, `"Liquidated Long"`, etc.). Preserved verbatim
///   in `Fill.direction`.
/// - `crossed` indicates taker vs. maker.
/// - `hash` is the on-chain transaction hash; `0x...` hex string.
/// - `fee` is signed: positive = paid, negative = rebate.
internal struct UserFillDTO: Decodable, Sendable {
    internal let coin: String
    internal let side: String  // "B" | "A"
    @DecimalString internal var px: Decimal
    @DecimalString internal var sz: Decimal
    @DecimalString internal var fee: Decimal
    internal let feeToken: String
    internal let time: Int64
    internal let tid: Int64
    internal let oid: Int64
    @DecimalString internal var closedPnl: Decimal
    internal let dir: String
    internal let crossed: Bool
    internal let hash: String
}
