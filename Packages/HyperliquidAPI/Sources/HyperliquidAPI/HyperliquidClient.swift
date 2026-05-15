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

    // TODO Phase 2: openOrders(for:) -> [OpenOrder]
    // TODO Phase 2: userFills(for:) -> [Fill]
}
