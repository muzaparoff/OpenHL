// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// A single OHLCV bar for a Hyperliquid perpetual at a given interval.
///
/// Decoded from `POST /info` with `{"type":"candleSnapshot", "req": {...}}`.
/// `volume` is in **coin units**, not USD — multiply by close price for
/// USD-equivalent.
public struct Candle: Sendable, Equatable, Identifiable, Hashable {
    public let coin: String
    public let interval: CandleInterval
    public let openTime: Date
    public let closeTime: Date
    public let open: Money
    public let close: Money
    public let high: Money
    public let low: Money
    public let volume: Money
    public let tradeCount: Int

    /// Identity = the bar's open time as epoch seconds. Two bars at the
    /// same coin+interval+openTime are the same bar.
    public var id: TimeInterval { openTime.timeIntervalSince1970 }

    /// Convenience: did this bar close at or above its open?
    public var isUp: Bool { close >= open }

    public init(
        coin: String,
        interval: CandleInterval,
        openTime: Date,
        closeTime: Date,
        open: Money,
        close: Money,
        high: Money,
        low: Money,
        volume: Money,
        tradeCount: Int
    ) {
        self.coin = coin
        self.interval = interval
        self.openTime = openTime
        self.closeTime = closeTime
        self.open = open
        self.close = close
        self.high = high
        self.low = low
        self.volume = volume
        self.tradeCount = tradeCount
    }
}

/// The intervals Hyperliquid supports for `candleSnapshot`. v1 exposes a
/// curated subset to the user (Phase 3b coin-detail picker uses the four
/// `userFacing` cases); the full set is here for completeness so future
/// features (alerts, indicators) can request finer-grained data.
public enum CandleInterval: String, Sendable, CaseIterable, Identifiable, Hashable {
    case oneMinute = "1m"
    case threeMinute = "3m"
    case fiveMinute = "5m"
    case fifteenMinute = "15m"
    case thirtyMinute = "30m"
    case oneHour = "1h"
    case twoHour = "2h"
    case fourHour = "4h"
    case eightHour = "8h"
    case twelveHour = "12h"
    case oneDay = "1d"
    case threeDay = "3d"
    case oneWeek = "1w"
    case oneMonth = "1M"

    public var id: String { rawValue }

    /// Cases surfaced in the v1 coin-detail interval picker.
    ///
    /// Phase 3c expanded this from four entries (`1h / 4h / 1d / 1w`) to a
    /// five-entry standard set spanning hour through year. `.fourHour` was
    /// dropped from the user-facing list — it sat awkwardly between the
    /// hourly and daily views and is now reachable only through Custom mode
    /// (see `bestFit(for:)`). The enum case is retained for completeness and
    /// for Custom-mode auto-clamping.
    ///
    /// The intervals are paired with these implied lookback windows
    /// (see `defaultLookback` for the canonical mapping):
    /// - `.oneHour` → 7 days   (≈168 bars; well under the API's ~500-bar cap)
    /// - `.oneDay`  → 30 days  ("1M" in the picker)
    /// - `.oneDay`  → 90 days  (legacy default — see Phase 3c docs)
    /// - `.oneWeek` → 1 year   ("1W" granularity for the weekly picker entry)
    /// - `.oneDay`  → 365 days ("1y" in the picker; 365 1d-bars < 500-cap)
    ///
    /// Note: "1M" (one month, calendar) and "1y" (one year) are *picker
    /// labels*, not new `CandleInterval` cases. They reuse `.oneDay` with a
    /// 30-day / 365-day lookback respectively. The display label is owned by
    /// `CoinDetailViewModel.Mode.label`, not by `CandleInterval.displayLabel`.
    public static let userFacing: [CandleInterval] = [
        .oneHour, .oneDay, .oneWeek,
    ]

    /// The pure granularity-for-span lookup used in Custom date-range mode.
    ///
    /// Given a user-selected `DateInterval`, return the `CandleInterval` that
    /// keeps the resulting bar count visually useful (roughly 50–500 bars) and
    /// safely under Hyperliquid's per-response cap (~500 bars). Ranges are
    /// clamped inclusively at the upper bound:
    ///
    /// | Span                    | Interval     | Bar count (approx) |
    /// |-------------------------|--------------|--------------------|
    /// | ≤ 2 days                | `.oneHour`   | ≤ 48               |
    /// | ≤ 30 days               | `.fourHour`  | ≤ 180              |
    /// | ≤ 180 days              | `.oneDay`    | ≤ 180              |
    /// | ≤ 2 years (≤ 730 days)  | `.oneWeek`   | ≤ 104              |
    /// | > 2 years               | `.oneDay`    | (caller must cap)  |
    ///
    /// The final "> 2 years" branch deliberately returns `.oneDay` — the
    /// caller (`CoinDetailViewModel`) is responsible for clamping the span
    /// itself to the validation cap (3 years). The function never returns
    /// `.oneMonth` or `.threeDay`: those cases exist on the enum but aren't
    /// part of the Custom-mode granularity ladder. Pure; no side effects;
    /// uses `interval.duration` (seconds) so it's locale- and calendar-free.
    public static func bestFit(for range: DateInterval) -> CandleInterval {
        let span = range.duration
        let day: TimeInterval = 60 * 60 * 24
        switch span {
        case ..<(2 * day + 1): return .oneHour
        case ..<(30 * day + 1): return .fourHour
        case ..<(180 * day + 1): return .oneDay
        case ..<(730 * day + 1): return .oneWeek
        default: return .oneDay
        }
    }

    /// Short label for buttons / pickers (e.g. "1h", "1D", "1W").
    public var displayLabel: String {
        switch self {
        case .oneMinute: return "1m"
        case .threeMinute: return "3m"
        case .fiveMinute: return "5m"
        case .fifteenMinute: return "15m"
        case .thirtyMinute: return "30m"
        case .oneHour: return "1h"
        case .twoHour: return "2h"
        case .fourHour: return "4h"
        case .eightHour: return "8h"
        case .twelveHour: return "12h"
        case .oneDay: return "1D"
        case .threeDay: return "3D"
        case .oneWeek: return "1W"
        case .oneMonth: return "1M"
        }
    }

    /// Sensible default lookback window for this interval (e.g. "1h"
    /// shows the last 7 days, "1D" shows the last 90 days). Returned as
    /// a `TimeInterval` (seconds) so callers can offset from `now`.
    public var defaultLookback: TimeInterval {
        switch self {
        case .oneMinute, .threeMinute, .fiveMinute:
            return 60 * 60 * 6  // 6h of 1–5m bars
        case .fifteenMinute, .thirtyMinute:
            return 60 * 60 * 24 * 2  // 2 days
        case .oneHour, .twoHour:
            return 60 * 60 * 24 * 7  // 7 days
        case .fourHour, .eightHour, .twelveHour:
            return 60 * 60 * 24 * 30  // 30 days
        case .oneDay:
            return 60 * 60 * 24 * 90  // 90 days
        case .threeDay, .oneWeek:
            return 60 * 60 * 24 * 365  // 1 year
        case .oneMonth:
            return 60 * 60 * 24 * 365 * 3  // 3 years
        }
    }
}
