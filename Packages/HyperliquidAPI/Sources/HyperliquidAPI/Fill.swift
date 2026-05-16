// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// One executed trade ("fill") on the user's account. Domain type — view
/// models bind directly. The wire-side `UserFillDTO` is internal and
/// mapped inside `URLSessionHyperliquidClient.userFills(for:)`.
///
/// Conventions:
/// - `Sendable`, `Equatable`, `Hashable`. `Identifiable` keyed on `tid`
///   (trade id), which is globally unique on Hyperliquid. `oid` is the
///   parent order's id and is not unique across fills of the same
///   order — do not use it as the SwiftUI list identity.
/// - Money fields use `Money` (= `Decimal`).
/// - `side` is the canonical app-level enum (`.buy`/`.sell`) — same rule
///   as `OpenOrder.Side`. The mapper translates `"B"`/`"A"`.
/// - `direction` carries Hyperliquid's richer label (`"Open Long"`,
///   `"Close Short"`, `"Liquidated Short"`, etc.) preserved as a
///   `String`. The fills view prefers `direction` for display because
///   it is more informative than a bare side; `side` remains available
///   for code that needs the binary distinction. (Decision logged:
///   `direction` is the primary descriptor in the UI.)
/// - `closedPnL` is **signed** and **non-optional**: Hyperliquid sends
///   `"0.0"` for opening fills, so the field is always present on the
///   wire. The mapper decodes the string as-is.
/// - `feeToken` is a `String` (e.g. `"USDC"`). v1 displays it verbatim;
///   no asset registry yet.
/// - `crossed` indicates the fill crossed the spread (taker). View
///   models may use this to badge maker vs. taker fills.
/// - `hash` is the on-chain transaction hash for the fill. Phase 2 does
///   not link out to an explorer; the field is preserved for a future
///   phase.
/// - `executedAt` is server-stamped from the wire `time` (ms epoch).
public struct Fill: Sendable, Equatable, Hashable, Identifiable {

    /// Canonical app-level side. Wire encoding does not reach this
    /// layer. Note: the fills UI prefers `direction` for display.
    public enum Side: Sendable, Equatable, Hashable {
        case buy
        case sell
    }

    /// Stable id: Hyperliquid's trade id. Unique per fill.
    public var id: Int64 { tid }

    public let tid: Int64
    /// The parent order's id. Multiple fills can share an `oid` when one
    /// order is filled in pieces.
    public let oid: Int64
    public let coin: String
    public let side: Side
    /// Hyperliquid's `dir` label, preserved verbatim. Examples:
    /// `"Open Long"`, `"Open Short"`, `"Close Long"`, `"Close Short"`,
    /// `"Liquidated Long"`, `"Liquidated Short"`. The fills view binds
    /// to this for display; downstream code that needs a closed enum
    /// can add one in a future phase with a decision entry.
    public let direction: String
    public let price: Money
    public let size: Money
    /// Signed fee. Positive = paid; negative = rebate. Denominated in
    /// `feeToken`.
    public let fee: Money
    public let feeToken: String
    /// Signed realized PnL closed by this fill. `0` for opening fills.
    public let closedPnL: Money
    /// `true` if the fill crossed the spread (taker fill).
    public let crossed: Bool
    /// On-chain transaction hash. Hex string, including `0x` prefix.
    public let hash: String
    /// Server-stamped execution time (Hyperliquid's `time`, ms epoch).
    public let executedAt: Date

    public init(
        tid: Int64,
        oid: Int64,
        coin: String,
        side: Side,
        direction: String,
        price: Money,
        size: Money,
        fee: Money,
        feeToken: String,
        closedPnL: Money,
        crossed: Bool,
        hash: String,
        executedAt: Date
    ) {
        self.tid = tid
        self.oid = oid
        self.coin = coin
        self.side = side
        self.direction = direction
        self.price = price
        self.size = size
        self.fee = fee
        self.feeToken = feeToken
        self.closedPnL = closedPnL
        self.crossed = crossed
        self.hash = hash
        self.executedAt = executedAt
    }
}
