// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// Wire shape of `POST /info` with `{"type":"portfolio","user":"0x..."}`.
///
/// Hyperliquid returns an **outer array** of 8 entries. Each entry is itself a
/// **heterogeneous 2-tuple**:
///
///   `[ "<windowName>", { accountValueHistory, pnlHistory, vlm } ]`
///
/// where `<windowName>` is one of
/// `"day" | "week" | "month" | "allTime" | "perpDay" | "perpWeek" | "perpMonth" | "perpAllTime"`,
/// and each history field inside the object is itself an array of `[ms, "decimal"]` 2-tuples.
///
/// We hand-roll an `unkeyedContainer()` decoder for the outer array of mixed-type tuples,
/// mirroring the pattern in `MetaAndAssetCtxsDTO`. Inside each entry we decode the window
/// name first (as a `String`), then the series object (as `PortfolioSeriesObjectDTO`).
///
/// Defensive behavior:
/// - **Unknown** window names (anything not in the eight known strings) are silently
///   dropped — keeps decoding alive if Hyperliquid adds a new window later.
/// - **Known but skipped** windows (`perpDay`, `perpWeek`, `perpMonth`, `perpAllTime`)
///   are also silently dropped at `toDomain()` time. They duplicate the perp-only view
///   that the four headline windows already include; v1 doesn't surface a spot/perp
///   toggle. See `docs/decisions.md` entry "Portfolio endpoint — window selection".
///
/// Decimals are parsed via `Decimal(string:)` directly rather than `@DecimalString`
/// because the points arrive inside a `[ms, "decimalString"]` mixed-type tuple, so
/// we can't attach the property wrapper to a `Decodable` field. Malformed decimal
/// strings produce a `DecodingError.dataCorrupted` — same behavior as `@DecimalString`.
internal struct PortfolioDTO: Decodable, Sendable {

    /// One entry from the outer array: `(windowName, seriesObject)`.
    /// We keep the *raw* window name string here; the mapping to
    /// `PortfolioWindow` happens in `toDomain()` so an unknown future
    /// window simply doesn't materialize in the domain model.
    internal struct Entry: Decodable, Sendable {
        let windowName: String
        let series: PortfolioSeriesObjectDTO

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            self.windowName = try container.decode(String.self)
            self.series = try container.decode(PortfolioSeriesObjectDTO.self)
        }
    }

    let entries: [Entry]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var collected: [Entry] = []
        if let count = container.count {
            collected.reserveCapacity(count)
        }
        while !container.isAtEnd {
            // Each outer slot is itself a 2-element array; let `Entry`'s
            // unkeyed-container decoder handle the inner shape.
            let entry = try container.decode(Entry.self)
            collected.append(entry)
        }
        self.entries = collected
    }
}

/// The object that lives at index 1 of every outer-tuple entry.
///
/// - `accountValueHistory` and `pnlHistory` are arrays of `[ms, "decimal"]`
///   2-tuples; `PortfolioHistoryPoint` decodes one such tuple.
/// - `vlm` is a **single decimal string** (the total notional volume for
///   the window), NOT an array. Original Phase 3e shipped with this typed
///   as `[PortfolioHistoryPoint]` and tanked decode on every real response.
///   Captured at 2026-05-16 with `curl /info {"type":"portfolio"}`.
internal struct PortfolioSeriesObjectDTO: Decodable, Sendable {
    let accountValueHistory: [PortfolioHistoryPoint]
    let pnlHistory: [PortfolioHistoryPoint]
    let vlm: String
}

/// One sample inside any of the three history arrays. Wire form:
///
///   `[ <ms:Int64>, "<decimal>" ]`
///
/// Decoded via `unkeyedContainer()`. `Decimal(string:)` validates the
/// string; failure is reported as `DecodingError.dataCorrupted` so the
/// transport pipeline maps it to `HyperliquidError.decoding`.
internal struct PortfolioHistoryPoint: Decodable, Sendable {
    let ms: Int64
    let value: Decimal

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.ms = try container.decode(Int64.self)
        let raw = try container.decode(String.self)
        guard let parsed = Decimal(string: raw) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: container.codingPath,
                    debugDescription: "portfolio: invalid decimal string '\(raw)'"
                )
            )
        }
        self.value = parsed
    }

    fileprivate var asPoint: PortfolioPoint {
        PortfolioPoint(
            time: Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0),
            value: value
        )
    }
}

extension PortfolioDTO {
    /// Map the wire entries into the public `Portfolio` domain type.
    ///
    /// - Filters out unknown window names.
    /// - Drops the `perp*` family (intentionally not surfaced in v1).
    /// - If the API returns duplicates for the same window, the last one
    ///   wins (consistent with `Dictionary(uniqueKeysWithValues:)`-style
    ///   "last writer wins"; Hyperliquid does not produce duplicates).
    func toDomain() -> Portfolio {
        var windows: [PortfolioWindow: PortfolioSeries] = [:]
        for entry in entries {
            guard let window = Self.userFacingWindow(for: entry.windowName) else {
                continue
            }
            let series = PortfolioSeries(
                accountValue: entry.series.accountValueHistory.map { $0.asPoint },
                pnl: entry.series.pnlHistory.map { $0.asPoint },
                totalVolume: Decimal(string: entry.series.vlm) ?? 0
            )
            windows[window] = series
        }
        return Portfolio(windows: windows)
    }

    /// Maps a wire window name to the user-facing enum, or `nil` if the
    /// name is unknown or in the silently-skipped `perp*` family.
    private static func userFacingWindow(for raw: String) -> PortfolioWindow? {
        switch raw {
        case "day": return .day
        case "week": return .week
        case "month": return .month
        case "allTime": return .allTime
        case "perpDay", "perpWeek", "perpMonth", "perpAllTime":
            return nil  // intentionally dropped — see file header
        default:
            return nil  // unknown / future window
        }
    }
}
