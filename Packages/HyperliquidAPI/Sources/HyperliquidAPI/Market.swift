// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// One row on the Markets screen: a Hyperliquid perpetual contract with its
/// current live context (mark price, 24h volume, etc.).
///
/// Built by combining `metaAndAssetCtxs` response shards: the `meta.universe`
/// array gives static info (coin name, leverage); the parallel `assetCtxs`
/// array gives live prices. Both arrays are in the same order — the mapper
/// `zip`s them.
public struct Market: Sendable, Equatable, Identifiable, Hashable {
    /// Coin symbol, e.g. "BTC", "ETH", "SOL".
    public let coin: String

    /// Maximum allowed leverage, e.g. 50 for BTC.
    public let maxLeverage: Int

    /// Size-decimals for this perp (affects display precision).
    public let szDecimals: Int

    /// True if this perp can only be traded with isolated margin.
    public let onlyIsolated: Bool

    /// Hyperliquid's authoritative mark price (used for liquidations/PnL).
    public let markPrice: Money

    /// Current mid (bid+ask)/2 between the top of book. Nil if the book is
    /// empty / one-sided.
    public let midPrice: Money?

    /// Mark price at the start of the rolling 24h window. Drives `dayChange`.
    public let prevDayPrice: Money

    /// Open interest in coin units.
    public let openInterest: Money

    /// 24h notional volume in USDC.
    public let dayNotionalVolume: Money

    /// Current funding rate (per-hour, signed).
    public let fundingRate: Money

    public var id: String { coin }

    /// Signed 24h price change in quote units (USDC).
    public var dayChange: Money {
        markPrice - prevDayPrice
    }

    /// Signed 24h price change as a raw ratio (e.g. 0.0124 = +1.24%).
    /// Caller is responsible for percent formatting.
    public var dayChangeRatio: Money {
        guard prevDayPrice > 0 else { return 0 }
        return (markPrice - prevDayPrice) / prevDayPrice
    }

    public init(
        coin: String,
        maxLeverage: Int,
        szDecimals: Int,
        onlyIsolated: Bool,
        markPrice: Money,
        midPrice: Money?,
        prevDayPrice: Money,
        openInterest: Money,
        dayNotionalVolume: Money,
        fundingRate: Money
    ) {
        self.coin = coin
        self.maxLeverage = maxLeverage
        self.szDecimals = szDecimals
        self.onlyIsolated = onlyIsolated
        self.markPrice = markPrice
        self.midPrice = midPrice
        self.prevDayPrice = prevDayPrice
        self.openInterest = openInterest
        self.dayNotionalVolume = dayNotionalVolume
        self.fundingRate = fundingRate
    }
}
