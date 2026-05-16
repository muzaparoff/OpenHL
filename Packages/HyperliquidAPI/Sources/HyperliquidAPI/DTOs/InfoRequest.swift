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
    case openOrders(user: Address)
    case userFills(user: Address)
    /// Combined perp universe + per-asset live contexts (mark, mid, prev-day,
    /// 24h volume, funding, open interest). One call to power the Markets list.
    case metaAndAssetCtxs
    /// OHLCV bars for one coin and interval over a `[startTime, endTime]`
    /// window. Note the wire form uses a nested `req` object — see
    /// `encode(to:)`.
    case candleSnapshot(coin: String, interval: CandleInterval, startTime: Date, endTime: Date)
    /// Wallet balance-history snapshot. Same single-`user` field shape as
    /// `clearinghouseState`; response is an array of `(windowName, series)`
    /// tuples — see `PortfolioDTO`.
    case portfolio(user: Address)

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clearinghouseState(let user):
            try container.encode("clearinghouseState", forKey: .type)
            try container.encode(user.rawValue, forKey: .user)
        case .openOrders(let user):
            try container.encode("openOrders", forKey: .type)
            try container.encode(user.rawValue, forKey: .user)
        case .userFills(let user):
            try container.encode("userFills", forKey: .type)
            try container.encode(user.rawValue, forKey: .user)
        case .metaAndAssetCtxs:
            try container.encode("metaAndAssetCtxs", forKey: .type)
        case .candleSnapshot(let coin, let interval, let startTime, let endTime):
            try container.encode("candleSnapshot", forKey: .type)
            var req = container.nestedContainer(keyedBy: ReqKeys.self, forKey: .req)
            try req.encode(coin, forKey: .coin)
            try req.encode(interval.rawValue, forKey: .interval)
            try req.encode(Int64(startTime.timeIntervalSince1970 * 1000), forKey: .startTime)
            try req.encode(Int64(endTime.timeIntervalSince1970 * 1000), forKey: .endTime)
        case .portfolio(let user):
            try container.encode("portfolio", forKey: .type)
            try container.encode(user.rawValue, forKey: .user)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, user, req
    }

    private enum ReqKeys: String, CodingKey {
        case coin, interval, startTime, endTime
    }
}
