// SPDX-License-Identifier: MIT

import Foundation
import HyperliquidAPI
import OpenHLCore

typealias MarketsViewModel = SnapshotViewModel<[Market]>

extension SnapshotViewModel where Snapshot == [Market] {
    /// Build a `MarketsViewModel` wired to `client.markets()`.
    /// Sorted by 24h notional volume descending so the most-traded
    /// perps surface first; stable secondary by coin name.
    static func markets(client: any HyperliquidClient) -> MarketsViewModel {
        MarketsViewModel(
            category: "Markets",
            fetch: { try await client.markets() },
            postProcess: sortByDayVolume
        )
    }

    private static func sortByDayVolume(_ markets: [Market]) -> [Market] {
        markets.sorted { lhs, rhs in
            if lhs.dayNotionalVolume != rhs.dayNotionalVolume {
                return lhs.dayNotionalVolume > rhs.dayNotionalVolume
            }
            return lhs.coin < rhs.coin
        }
    }
}
