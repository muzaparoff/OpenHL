// SPDX-License-Identifier: MIT

import Foundation
import HyperliquidAPI
import OpenHLCore

typealias FillsViewModel = SnapshotViewModel<[Fill]>

extension SnapshotViewModel where Snapshot == [Fill] {
    static func fills(
        client: any HyperliquidClient,
        address: Address
    ) -> FillsViewModel {
        FillsViewModel(
            address: address,
            category: "Fills",
            fetch: { try await client.userFills(for: address) },
            postProcess: sortByExecutedAt
        )
    }

    /// Sort by `executedAt` descending; stable secondary by coin.
    private static func sortByExecutedAt(_ fills: [Fill]) -> [Fill] {
        fills.sorted { lhs, rhs in
            if lhs.executedAt != rhs.executedAt {
                return lhs.executedAt > rhs.executedAt
            }
            return lhs.coin < rhs.coin
        }
    }
}
