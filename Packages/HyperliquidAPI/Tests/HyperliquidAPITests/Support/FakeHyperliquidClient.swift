// SPDX-License-Identifier: MIT

import Foundation
import HyperliquidAPI
import OpenHLCore

/// A deterministic fake `HyperliquidClient` for use in view-model unit tests.
///
/// Configure `result` before calling `clearinghouseState(for:)`. The fake
/// records the last address it received so tests can assert on the call.
final class FakeHyperliquidClient: HyperliquidClient, @unchecked Sendable {

    /// The result to return from the next `clearinghouseState` call.
    /// Defaults to throwing `HyperliquidError.offline` to catch tests that
    /// forgot to configure the fake.
    var result: Result<ClearinghouseState, HyperliquidError> = .failure(.offline)

    /// The address passed to the most recent call, or `nil` if never called.
    private(set) var lastQueriedAddress: Address?

    /// Number of times `clearinghouseState` was called.
    private(set) var callCount: Int = 0

    /// Optional delay (in nanoseconds) to simulate network latency.
    var artificialDelay: UInt64 = 0

    func clearinghouseState(for user: Address) async throws -> ClearinghouseState {
        lastQueriedAddress = user
        callCount += 1
        if artificialDelay > 0 {
            try await Task.sleep(nanoseconds: artificialDelay)
        }
        return try result.get()
    }
}

// MARK: - Factory helpers

extension FakeHyperliquidClient {

    /// Convenience: configure the fake to return a minimal empty state.
    func returnEmpty(fetchedAt: Date = Date()) {
        result = .success(ClearinghouseState.makeEmpty(fetchedAt: fetchedAt))
    }

    /// Convenience: configure the fake to return a single-long-position state.
    func returnSingleLong(fetchedAt: Date = Date()) {
        result = .success(ClearinghouseState.makeSingleLong(fetchedAt: fetchedAt))
    }

    func throwOffline() {
        result = .failure(.offline)
    }

    func throwTimeout() {
        result = .failure(.timeout)
    }

    func throwDecoding() {
        result = .failure(
            .decoding(
                underlying: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Fake decoding error")
                )))
    }

    func throwHTTP(status: Int) {
        result = .failure(.httpStatus(status))
    }
}

// MARK: - ClearinghouseState test fixtures

extension ClearinghouseState {

    static func makeEmpty(fetchedAt: Date = Date()) -> ClearinghouseState {
        ClearinghouseState(
            summary: AccountSummary(
                accountValue: 0,
                totalNotionalPosition: 0,
                totalRawUSD: 0,
                totalMarginUsed: 0,
                withdrawable: 0
            ),
            positions: [],
            serverTime: Date(timeIntervalSince1970: 1_715_774_400),
            fetchedAt: fetchedAt
        )
    }

    static func makeSingleLong(fetchedAt: Date = Date()) -> ClearinghouseState {
        ClearinghouseState(
            summary: AccountSummary(
                accountValue: Decimal(string: "12500.50")!,
                totalNotionalPosition: Decimal(string: "10000.00")!,
                totalRawUSD: Decimal(string: "12500.50")!,
                totalMarginUsed: Decimal(string: "1000.00")!,
                withdrawable: Decimal(string: "11500.50")!
            ),
            positions: [
                Position(
                    coin: "BTC",
                    size: Decimal(string: "0.25")!,
                    side: .long,
                    entryPrice: Decimal(string: "38000.00")!,
                    positionValue: Decimal(string: "10000.00")!,
                    unrealizedPnL: Decimal(string: "500.00")!,
                    returnOnEquity: Decimal(string: "0.05")!,
                    liquidationPrice: Decimal(string: "30000.00")!,
                    marginUsed: Decimal(string: "1000.00")!,
                    leverage: .cross(10)
                )
            ],
            serverTime: Date(timeIntervalSince1970: 1_715_774_400),
            fetchedAt: fetchedAt
        )
    }

    static func makeMultipleMixed(fetchedAt: Date = Date()) -> ClearinghouseState {
        ClearinghouseState(
            summary: AccountSummary(
                accountValue: Decimal(string: "55000.00")!,
                totalNotionalPosition: Decimal(string: "40000.00")!,
                totalRawUSD: Decimal(string: "55000.00")!,
                totalMarginUsed: Decimal(string: "4000.00")!,
                withdrawable: Decimal(string: "51000.00")!
            ),
            positions: [
                Position(
                    coin: "BTC",
                    size: Decimal(string: "0.5")!,
                    side: .long,
                    entryPrice: Decimal(string: "40000.00")!,
                    positionValue: Decimal(string: "20000.00")!,
                    unrealizedPnL: Decimal(string: "1200.00")!,
                    returnOnEquity: Decimal(string: "0.06")!,
                    liquidationPrice: Decimal(string: "32000.00")!,
                    marginUsed: Decimal(string: "2000.00")!,
                    leverage: .cross(10)
                ),
                Position(
                    coin: "ETH",
                    size: Decimal(string: "-10.0")!,
                    side: .short,
                    entryPrice: Decimal(string: "1900.00")!,
                    positionValue: Decimal(string: "20000.00")!,
                    unrealizedPnL: Decimal(string: "-800.00")!,
                    returnOnEquity: Decimal(string: "-0.04")!,
                    liquidationPrice: Decimal(string: "2100.00")!,
                    marginUsed: Decimal(string: "2000.00")!,
                    leverage: .isolated(10)
                ),
                Position(
                    coin: "SOL",
                    size: Decimal(string: "100.0")!,
                    side: .long,
                    entryPrice: Decimal(0),
                    positionValue: Decimal(0),
                    unrealizedPnL: Decimal(0),
                    returnOnEquity: Decimal(0),
                    liquidationPrice: nil,
                    marginUsed: Decimal(0),
                    leverage: .cross(3)
                ),
            ],
            serverTime: Date(timeIntervalSince1970: 1_715_774_400),
            fetchedAt: fetchedAt
        )
    }
}
