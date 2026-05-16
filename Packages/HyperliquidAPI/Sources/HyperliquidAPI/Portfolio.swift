// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// The four user-facing portfolio windows surfaced in the wallet balance-
/// history graph. Hyperliquid's `portfolio` endpoint returns eight named
/// windows (`day/week/month/allTime` plus the parallel `perpDay/perpWeek/
/// perpMonth/perpAllTime`); v1 displays only the first four — they include
/// perp + spot together and match what users see on hyperliquid.xyz.
///
/// The `perp*` variants are decoded-then-dropped at the DTO boundary
/// (see `PortfolioDTO`). When/if a Phase 4+ feature wants to split spot
/// from perp, it adds cases here and stops dropping at the DTO layer.
public enum PortfolioWindow: String, Sendable, CaseIterable, Identifiable, Hashable {
    case day
    case week
    case month
    case allTime

    public var id: String { rawValue }

    /// Short label for segmented pickers ("1D", "1W", "1M", "All").
    public var displayLabel: String {
        switch self {
        case .day: return "1D"
        case .week: return "1W"
        case .month: return "1M"
        case .allTime: return "All"
        }
    }
}

/// One sample point inside a portfolio time series. `time` is wall-clock
/// UTC; `value` is USD-denominated `Decimal` (e.g. account value, PnL,
/// or daily volume bucket depending on the series).
public struct PortfolioPoint: Sendable, Equatable, Hashable {
    public let time: Date
    public let value: Decimal

    public init(time: Date, value: Decimal) {
        self.time = time
        self.value = value
    }
}

/// The three parallel time series Hyperliquid returns per window:
///
/// - `accountValue` — running USD valuation of the account (perp + spot,
///   for the four surfaced windows). Drives the headline line chart.
/// - `pnl` — running cumulative PnL within the window. Used for the
///   tooltip "+ $X over this window" overlay and the up/down tint.
/// - `totalVolume` — single scalar: the total notional volume for the
///   window. Decoded for completeness; **not surfaced in v1**. The wire
///   form is a bare decimal string (one number per window), not a series.
public struct PortfolioSeries: Sendable, Equatable {
    public let accountValue: [PortfolioPoint]
    public let pnl: [PortfolioPoint]
    public let totalVolume: Decimal

    public init(
        accountValue: [PortfolioPoint],
        pnl: [PortfolioPoint],
        totalVolume: Decimal
    ) {
        self.accountValue = accountValue
        self.pnl = pnl
        self.totalVolume = totalVolume
    }
}

/// Top-level result of `POST /info` with `{"type":"portfolio","user":"0x..."}`.
///
/// Built from `PortfolioDTO.toDomain()`. Indexed by the four
/// `PortfolioWindow` cases; missing windows are simply absent from the
/// dictionary (defensive — Hyperliquid currently always returns all
/// four, but the model does not assume so).
public struct Portfolio: Sendable, Equatable {
    public let windows: [PortfolioWindow: PortfolioSeries]

    public init(windows: [PortfolioWindow: PortfolioSeries]) {
        self.windows = windows
    }

    /// Lookup by window. Returns `nil` if the API omitted that window
    /// (very rare; treat as "no data for this range").
    public subscript(window: PortfolioWindow) -> PortfolioSeries? {
        windows[window]
    }
}
