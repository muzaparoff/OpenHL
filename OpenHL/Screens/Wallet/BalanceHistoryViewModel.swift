// SPDX-License-Identifier: MIT

import HyperliquidAPI
import OpenHLCore

/// `BalanceHistoryViewModel` is a specialization of the generic
/// `SnapshotViewModel` for `Portfolio` data.
///
/// The factory extension below supplies the standard wiring so call-sites
/// stay one-liner:
/// ```swift
/// BalanceHistoryView(viewModel: .balance(client: client, address: address))
/// ```
typealias BalanceHistoryViewModel = SnapshotViewModel<Portfolio>

extension SnapshotViewModel where Snapshot == Portfolio {
    /// Creates a `BalanceHistoryViewModel` wired to the given client and
    /// address. No `postProcess` is supplied: the API returns series sorted
    /// ascending by time and the view renders them as-is.
    static func balance(
        client: any HyperliquidClient,
        address: Address
    ) -> BalanceHistoryViewModel {
        BalanceHistoryViewModel(
            address: address,
            category: "Balance",
            fetch: { try await client.portfolio(for: address) }
        )
    }
}
