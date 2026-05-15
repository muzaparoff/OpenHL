// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// The domain model returned by `HyperliquidClient.clearinghouseState`.
/// View models bind directly to these types.
///
/// Domain models:
/// - Are `Sendable`, `Equatable` (for SwiftUI diffing and tests),
///   `Hashable` where they appear in `ForEach` / `List`.
/// - Use Swift-idiomatic names, never the wire names.
/// - Use `Decimal` (aliased as `Money`) for all monetary quantities.
/// - Carry a `fetchedAt: Date` stamp injected by the client so views can
///   render staleness without re-reading the system clock.
/// - Never import SwiftUI.
public struct ClearinghouseState: Sendable, Equatable {

    /// Aggregate account-level figures, all denominated in USD.
    public struct AccountSummary: Sendable, Equatable {
        public let accountValue: Money
        public let totalNotionalPosition: Money
        public let totalRawUSD: Money
        public let totalMarginUsed: Money
        public let withdrawable: Money

        public init(
            accountValue: Money,
            totalNotionalPosition: Money,
            totalRawUSD: Money,
            totalMarginUsed: Money,
            withdrawable: Money
        ) {
            self.accountValue = accountValue
            self.totalNotionalPosition = totalNotionalPosition
            self.totalRawUSD = totalRawUSD
            self.totalMarginUsed = totalMarginUsed
            self.withdrawable = withdrawable
        }
    }

    /// One open position. `size` is signed: positive = long, negative =
    /// short. `side` is derived; views prefer it for clarity.
    public struct Position: Sendable, Equatable, Identifiable {
        public enum Side: Sendable, Equatable {
            case long, short
        }

        public enum LeverageMode: Sendable, Equatable {
            case cross(Int)
            case isolated(Int)
        }

        /// Stable id derived from `coin`. Hyperliquid returns at most one
        /// position per coin per account.
        public var id: String { coin }

        public let coin: String
        public let size: Money  // signed
        public let side: Side  // derived from sign of size
        public let entryPrice: Money
        public let positionValue: Money
        public let unrealizedPnL: Money
        public let returnOnEquity: Money  // ratio, e.g. 0.1234 = +12.34%
        public let liquidationPrice: Money?
        public let marginUsed: Money
        public let leverage: LeverageMode

        public init(
            coin: String,
            size: Money,
            side: Side,
            entryPrice: Money,
            positionValue: Money,
            unrealizedPnL: Money,
            returnOnEquity: Money,
            liquidationPrice: Money?,
            marginUsed: Money,
            leverage: LeverageMode
        ) {
            self.coin = coin
            self.size = size
            self.side = side
            self.entryPrice = entryPrice
            self.positionValue = positionValue
            self.unrealizedPnL = unrealizedPnL
            self.returnOnEquity = returnOnEquity
            self.liquidationPrice = liquidationPrice
            self.marginUsed = marginUsed
            self.leverage = leverage
        }
    }

    public let summary: AccountSummary
    public let positions: [Position]
    /// Server-reported time of the snapshot (Hyperliquid's `time` field,
    /// converted to `Date`).
    public let serverTime: Date
    /// Wall-clock time at which the client received the snapshot,
    /// stamped via the injected `Clock`. Used by views to render
    /// "Updated Ns ago".
    public let fetchedAt: Date

    public init(
        summary: AccountSummary,
        positions: [Position],
        serverTime: Date,
        fetchedAt: Date
    ) {
        self.summary = summary
        self.positions = positions
        self.serverTime = serverTime
        self.fetchedAt = fetchedAt
    }
}
