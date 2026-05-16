// SPDX-License-Identifier: MIT

import Foundation
import HyperliquidAPI
import OpenHLCore

typealias OrdersViewModel = SnapshotViewModel<[OpenOrder]>

extension SnapshotViewModel where Snapshot == [OpenOrder] {
    static func orders(
        client: any HyperliquidClient,
        address: Address
    ) -> OrdersViewModel {
        OrdersViewModel(
            address: address,
            category: "Orders",
            fetch: { try await client.openOrders(for: address) },
            postProcess: sortByPlacedAt
        )
    }

    /// Sort by `placedAt` descending; stable secondary by coin.
    private static func sortByPlacedAt(_ orders: [OpenOrder]) -> [OpenOrder] {
        orders.sorted { lhs, rhs in
            if lhs.placedAt != rhs.placedAt {
                return lhs.placedAt > rhs.placedAt
            }
            return lhs.coin < rhs.coin
        }
    }
}
