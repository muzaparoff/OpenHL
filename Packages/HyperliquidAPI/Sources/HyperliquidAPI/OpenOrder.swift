// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// One resting open order on Hyperliquid. Domain type — view models bind
/// directly to it. The wire-side `OpenOrderDTO` is internal and mapped
/// inside `URLSessionHyperliquidClient.openOrders(for:)`.
///
/// Conventions (binding for any future field additions):
/// - `Sendable`, `Equatable`, `Hashable`. Crosses actor boundaries from
///   the non-`@MainActor` client to `@MainActor` view models.
/// - `Identifiable` keyed on `oid` — Hyperliquid's order id, which is
///   unique per account and stable for the lifetime of the order. (For
///   view-level animation/diffing, the view model wraps the array in a
///   `ForEach(viewModel.orders)` over `Identifiable`; SwiftUI does the
///   right thing.)
/// - All money fields use `Money` (= `Decimal`). No `Double`.
/// - `side` is the canonical app-level enum (`.buy`/`.sell`). Hyperliquid
///   emits `"B"`/`"A"` on the wire; the mapper translates and the rest
///   of the app never sees the wire encoding. (Decision logged.)
/// - `placedAt` is server-stamped from the wire `timestamp` (ms epoch).
///   Views render in the device's locale/time zone.
/// - `origSize` is optional — Hyperliquid sometimes omits it for orders
///   that have not been partially filled. The mapper passes `nil`
///   through; views show `size` when `origSize == nil`.
/// - `reduceOnly` defaults to `false` when the wire field is absent.
///   This is a documented Hyperliquid convention; encoding `nil` would
///   force every view to handle a tri-state for no UX gain.
/// - `triggerPrice` is `nil` for plain limit orders; present for trigger
///   orders (stop / take-profit). The `orderType` carries the kind.
public struct OpenOrder: Sendable, Equatable, Hashable, Identifiable {

    /// Canonical app-level side. Wire encoding (`"B"`/`"A"`) does not
    /// reach this layer.
    public enum Side: Sendable, Equatable, Hashable {
        case buy
        case sell
    }

    /// Hyperliquid's order-type discriminator. Known wire strings map to named
    /// cases; any unrecognized string falls through to `.unknown(String)` so
    /// the domain model never throws on a new Hyperliquid order type. The
    /// mapper logs the unknown value via `OSLog` so it surfaces in diagnostics
    /// without crashing the user's session.
    ///
    /// Decision (2026-05-15): unknown order types use `.unknown(rawString)`,
    /// not `HyperliquidError.unexpectedResponse`. Unknown directions are
    /// informational — the order is still valid and should be displayed. This
    /// differs from `Side`, where an unknown value indicates corrupted data.
    public enum OrderType: Sendable, Equatable, Hashable {
        case limit
        case trigger
        case stopLimit
        case stopMarket
        case takeProfitLimit
        case takeProfitMarket
        /// A wire value that was not recognized at the time this version was
        /// compiled. The associated value preserves the raw string for display
        /// and debugging. Add a named case and a decision entry when the new
        /// type is confirmed.
        case unknown(String)
    }

    /// Stable id: Hyperliquid's order id.
    public var id: Int64 { oid }

    public let oid: Int64
    public let coin: String
    public let side: Side
    public let limitPrice: Money
    /// Remaining size on the order. Decreases as the order is partially
    /// filled; equals zero only momentarily before the order disappears
    /// from `openOrders`.
    public let size: Money
    /// Size at order placement time. `nil` when the wire omits it
    /// (commonly: orders with no partial fills yet).
    public let origSize: Money?
    public let orderType: OrderType
    /// `true` for reduce-only orders; defaults to `false` when the wire
    /// field is absent.
    public let reduceOnly: Bool
    /// Present for trigger / stop / TP orders; `nil` for plain limits.
    public let triggerPrice: Money?
    /// Server-stamped placement time (Hyperliquid's `timestamp` field,
    /// converted from ms-since-epoch to `Date`).
    public let placedAt: Date

    public init(
        oid: Int64,
        coin: String,
        side: Side,
        limitPrice: Money,
        size: Money,
        origSize: Money?,
        orderType: OrderType,
        reduceOnly: Bool,
        triggerPrice: Money?,
        placedAt: Date
    ) {
        self.oid = oid
        self.coin = coin
        self.side = side
        self.limitPrice = limitPrice
        self.size = size
        self.origSize = origSize
        self.orderType = orderType
        self.reduceOnly = reduceOnly
        self.triggerPrice = triggerPrice
        self.placedAt = placedAt
    }
}
