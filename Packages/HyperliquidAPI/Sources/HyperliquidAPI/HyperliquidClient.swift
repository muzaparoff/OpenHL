// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// The protocol view models depend on. Constructor-injected. The
/// concrete `URLSessionHyperliquidClient` is the production implementation;
/// tests inject a fake.
///
/// All methods are `async throws`. They throw `HyperliquidError`. They
/// honor `Task.checkCancellation()` between transport and decode. They
/// do not retry — see the retry policy section in `architecture.md`.
///
/// `Sendable`: every dependency that crosses an actor boundary (the
/// composition root constructs the client on the main actor and hands
/// it to view models that are `@MainActor`) is `Sendable`.
public protocol HyperliquidClient: Sendable {

    /// `POST /info` with `{"type":"clearinghouseState","user":"0x..."}`.
    /// Returns the decoded, domain-mapped account snapshot. Throws
    /// `HyperliquidError` on any failure.
    func clearinghouseState(for user: Address) async throws -> ClearinghouseState

    /// `POST /info` with `{"type":"openOrders","user":"0x..."}`.
    /// Returns the decoded, domain-mapped resting orders for the user.
    /// Throws `HyperliquidError` on any failure.
    ///
    /// The returned array preserves the order the API returned. View
    /// models impose presentation sort (typically `placedAt` desc); the
    /// transport layer is sort-agnostic. See architecture §17.
    func openOrders(for user: Address) async throws -> [OpenOrder]

    /// `POST /info` with `{"type":"userFills","user":"0x..."}`.
    /// Returns the decoded, domain-mapped recent fills for the user.
    /// Throws `HyperliquidError` on any failure.
    ///
    /// Cap: the client returns **at most 200** fills (the most recent
    /// ones in API-supplied order). Hyperliquid does not paginate this
    /// endpoint; capping at the transport layer prevents pathological
    /// memory and render costs for very active accounts while keeping
    /// view models trivial. See architecture §17.
    func userFills(for user: Address) async throws -> [Fill]

    /// `POST /info` with `{"type":"metaAndAssetCtxs"}`. Returns the full
    /// list of Hyperliquid perpetuals with live mark / mid / prev-day
    /// prices, 24h volume, open interest, and funding rate. Used to power
    /// the Markets screen.
    ///
    /// No user parameter — this is public market data. View models impose
    /// presentation sort (typically by 24h notional volume desc).
    func markets() async throws -> [Market]

    /// `POST /info` with `{"type":"candleSnapshot","req":{...}}`. Returns
    /// OHLCV bars for one coin at one interval over `[startTime, endTime]`.
    ///
    /// The API caps each response at ~500 bars; pass a window that fits
    /// (use `CandleInterval.defaultLookback` for sensible defaults).
    func candles(
        coin: String,
        interval: CandleInterval,
        startTime: Date,
        endTime: Date
    ) async throws -> [Candle]

    /// `POST /info` with `{"type":"portfolio","user":"0x..."}`. Returns the
    /// account-value, PnL, and daily-volume time series for the four
    /// surfaced windows (`day / week / month / allTime`). Powers the
    /// wallet balance-history graph (Phase 3e).
    ///
    /// The eight-window API response is filtered to four at the DTO
    /// boundary — the `perp*` family is decoded and dropped because v1
    /// has no spot/perp toggle. See `PortfolioDTO` for the filter list.
    func portfolio(for user: Address) async throws -> Portfolio
}
