// SPDX-License-Identifier: MIT

// Tests for `CoinDetailViewModel` Phase 3c mode transitions.
//
// `CoinDetailViewModel` is in the app target (OpenHL), the test host for
// this bundle. `HyperliquidAPI` and `OpenHLCore` are linked directly as
// package dependencies of this test target.
//
// `FakeHyperliquidClient` lives in `HyperliquidAPITests` and cannot be
// imported here. A minimal local fake is defined below — it mirrors the
// same surface used by `CoinDetailViewModel`.

import Foundation
import HyperliquidAPI
import OpenHLCore
import Testing

@testable import OpenHL

// MARK: - Local fake

/// Minimal `HyperliquidClient` fake for `CoinDetailViewModel` unit tests.
/// Not `@MainActor` — mutations happen from the test's isolation context.
private final class LocalFakeHyperliquidClient: HyperliquidClient, @unchecked Sendable {

    var candlesResult: Result<[Candle], HyperliquidError> = .success([])

    private(set) var candlesCallCount: Int = 0
    private(set) var lastCandlesArgs: (coin: String, interval: CandleInterval, startTime: Date, endTime: Date)?

    func clearinghouseState(for user: Address) async throws -> ClearinghouseState {
        throw HyperliquidError.offline
    }

    func openOrders(for user: Address) async throws -> [OpenOrder] {
        throw HyperliquidError.offline
    }

    func userFills(for user: Address) async throws -> [Fill] {
        throw HyperliquidError.offline
    }

    func markets() async throws -> [Market] {
        throw HyperliquidError.offline
    }

    func candles(
        coin: String,
        interval: CandleInterval,
        startTime: Date,
        endTime: Date
    ) async throws -> [Candle] {
        candlesCallCount += 1
        lastCandlesArgs = (coin, interval, startTime, endTime)
        return try candlesResult.get()
    }

    // Phase 3e: portfolio endpoint stub — not exercised by CoinDetail tests.
    func portfolio(for user: Address) async throws -> Portfolio {
        throw HyperliquidError.offline
    }
}

// MARK: - Helpers

extension Market {
    /// Minimal BTC market for tests that need a `Market` value.
    fileprivate static func btcStub() -> Market {
        Market(
            coin: "BTC",
            maxLeverage: 40,
            szDecimals: 5,
            onlyIsolated: false,
            markPrice: 62_000,
            midPrice: 62_001,
            prevDayPrice: 61_000,
            openInterest: 1_000,
            dayNotionalVolume: 800_000_000,
            fundingRate: Decimal(string: "0.0001")!
        )
    }
}

// MARK: - Clock

/// A fixed clock whose `now` is settable by the test.
private final class FixedClock: Clock, @unchecked Sendable {
    var current: Date
    init(_ date: Date) { self.current = date }
    func now() -> Date { current }
}

// MARK: - CoinDetailViewModel mode-transition tests

@Suite("CoinDetailViewModel — Phase 3c mode transitions")
@MainActor
struct CoinDetailViewModelModeTests {

    // A reference "now" — 2026-05-16 12:00:00 UTC.
    private let referenceNow = Date(timeIntervalSince1970: 1_747_396_800)
    private var day: TimeInterval { 60 * 60 * 24 }
    private let tolerance: TimeInterval = 5  // seconds

    private func makeVM(
        initialMode: CoinDetailViewModel.Mode = .standardInterval(.oneHour),
        candlesResult: Result<[Candle], HyperliquidError> = .success([])
    ) -> (vm: CoinDetailViewModel, client: LocalFakeHyperliquidClient, clock: FixedClock) {
        let client = LocalFakeHyperliquidClient()
        client.candlesResult = candlesResult
        let clock = FixedClock(referenceNow)
        let vm = CoinDetailViewModel(
            market: .btcStub(),
            client: client,
            clock: clock,
            initialMode: initialMode
        )
        return (vm, client, clock)
    }

    // MARK: - Cold load

    @Test("Cold load() uses initial preset's interval and lookback")
    func coldLoadUsesInitialPreset() async throws {
        let (vm, client, _) = makeVM(initialMode: .standardInterval(.oneHour))
        await vm.load()

        let args = try #require(client.lastCandlesArgs)
        #expect(args.coin == "BTC")
        #expect(args.interval == .oneHour)

        // Expected window: [now - 7d, now]
        let expectedStart = referenceNow.addingTimeInterval(-7 * day)
        #expect(abs(args.startTime.timeIntervalSince(expectedStart)) <= tolerance)
        #expect(abs(args.endTime.timeIntervalSince(referenceNow)) <= tolerance)
        #expect(client.candlesCallCount == 1)
    }

    @Test("Cold load() with .oneYear preset uses .oneDay interval and 365-day lookback")
    func coldLoadOneYear() async throws {
        let (vm, client, _) = makeVM(initialMode: .standardInterval(.oneYear))
        await vm.load()

        let args = try #require(client.lastCandlesArgs)
        #expect(args.interval == .oneDay)
        let expectedStart = referenceNow.addingTimeInterval(-365 * day)
        #expect(abs(args.startTime.timeIntervalSince(expectedStart)) <= tolerance)
        #expect(abs(args.endTime.timeIntervalSince(referenceNow)) <= tolerance)
    }

    @Test("Cold load() with .oneMonth preset uses .oneDay interval and 30-day lookback")
    func coldLoadOneMonth() async throws {
        let (vm, client, _) = makeVM(initialMode: .standardInterval(.oneMonth))
        await vm.load()

        let args = try #require(client.lastCandlesArgs)
        #expect(args.interval == .oneDay)
        let expectedStart = referenceNow.addingTimeInterval(-30 * day)
        #expect(abs(args.startTime.timeIntervalSince(expectedStart)) <= tolerance)
    }

    // MARK: - setMode with standard preset

    @Test("setMode(.standardInterval(.oneYear)) triggers refetch with .oneDay / 365d window")
    func setModeOneYearTriggersRefetch() async throws {
        let (vm, client, _) = makeVM(initialMode: .standardInterval(.oneHour))

        // Prime the VM to avoid the `guard case .idle` in load().
        await vm.load()
        let callCountAfterLoad = client.candlesCallCount
        #expect(callCountAfterLoad == 1)

        // Mode switch triggers reloadForMode via didSet → Task.
        vm.setMode(.standardInterval(.oneYear))

        // Yield to allow the spawned Task to execute.
        // We loop with a small sleep to avoid flakiness on a busy CI runner.
        var waited = 0
        while client.candlesCallCount == callCountAfterLoad && waited < 50 {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            waited += 1
        }

        let args = try #require(client.lastCandlesArgs)
        #expect(args.interval == .oneDay)
        let expectedStart = referenceNow.addingTimeInterval(-365 * day)
        #expect(abs(args.startTime.timeIntervalSince(expectedStart)) <= tolerance)
        #expect(abs(args.endTime.timeIntervalSince(referenceNow)) <= tolerance)
        #expect(client.candlesCallCount == 2)
    }

    // MARK: - setMode with custom range

    @Test("setMode(.customRange(...)) triggers refetch with bestFit interval and exact window")
    func setModeCustomRangeTriggersRefetch() async throws {
        let (vm, client, _) = makeVM(initialMode: .standardInterval(.oneHour))
        await vm.load()
        let callCountAfterLoad = client.candlesCallCount

        // 90-day custom range → bestFit(.oneDay)
        let end = referenceNow.addingTimeInterval(-1 * day)  // yesterday
        let start = end.addingTimeInterval(-90 * day)
        let customRange = DateInterval(start: start, end: end)

        vm.setMode(.customRange(customRange))

        var waited = 0
        while client.candlesCallCount == callCountAfterLoad && waited < 50 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            waited += 1
        }

        let args = try #require(client.lastCandlesArgs)
        // 90 days → bestFit returns .oneDay (> 30d, ≤ 180d).
        #expect(args.interval == .oneDay)
        // Custom mode uses the exact range — no defaultLookback substitution.
        #expect(abs(args.startTime.timeIntervalSince(start)) <= tolerance)
        #expect(abs(args.endTime.timeIntervalSince(end)) <= tolerance)
        #expect(client.candlesCallCount == 2)
    }

    @Test("setMode(.customRange(...)) with 1-day span uses .oneHour via bestFit")
    func setModeCustomRangeOneDayUsesOneHour() async throws {
        let (vm, client, _) = makeVM(initialMode: .standardInterval(.oneHour))
        await vm.load()
        let callCountAfterLoad = client.candlesCallCount

        let end = referenceNow.addingTimeInterval(-1)
        let start = end.addingTimeInterval(-1 * day)
        vm.setMode(.customRange(DateInterval(start: start, end: end)))

        var waited = 0
        while client.candlesCallCount == callCountAfterLoad && waited < 50 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            waited += 1
        }

        let args = try #require(client.lastCandlesArgs)
        #expect(args.interval == .oneHour)
    }

    // MARK: - No-op on same mode

    @Test("setMode with the SAME mode is a no-op — candlesCallCount does not increase")
    func setModeSameModeIsNoop() async {
        let (vm, client, _) = makeVM(initialMode: .standardInterval(.oneHour))
        await vm.load()
        let callCountAfterLoad = client.candlesCallCount

        // Set the exact same mode — the `didSet` guard returns early.
        vm.setMode(.standardInterval(.oneHour))

        // Give time for any accidentally-spawned task to fire.
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        #expect(
            client.candlesCallCount == callCountAfterLoad,
            "setMode with same mode must not trigger an extra fetch")
    }

    // MARK: - Refresh in custom mode

    @Test("refresh() in custom mode re-uses the user-supplied range verbatim")
    func refreshInCustomModeReusesRange() async throws {
        let (vm, client, _) = makeVM(initialMode: .standardInterval(.oneHour))
        await vm.load()

        let end = referenceNow.addingTimeInterval(-2 * day)
        let start = end.addingTimeInterval(-14 * day)
        let customRange = DateInterval(start: start, end: end)

        vm.setMode(.customRange(customRange))

        var waited = 0
        while client.candlesCallCount < 2 && waited < 50 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            waited += 1
        }

        let afterModeSwitch = client.candlesCallCount

        // Now refresh — should re-use exact same (start, end).
        await vm.refresh()

        #expect(client.candlesCallCount == afterModeSwitch + 1)
        let args = try #require(client.lastCandlesArgs)
        #expect(abs(args.startTime.timeIntervalSince(start)) <= tolerance)
        #expect(abs(args.endTime.timeIntervalSince(end)) <= tolerance)
    }

    // MARK: - State transitions

    @Test("After successful load(), state is .loaded")
    func loadSetsLoadedState() async {
        let (vm, _, _) = makeVM()
        await vm.load()
        if case .loaded = vm.state {
            // pass
        } else {
            Issue.record("Expected .loaded, got \(vm.state)")
        }
    }

    @Test("After network failure, state is .error and preserves lastLoaded on refresh")
    func refreshPreservesLastLoadedOnFailure() async {
        let (vm, client, _) = makeVM(candlesResult: .success([]))
        await vm.load()

        // Switch fake to fail.
        client.candlesResult = .failure(.offline)
        await vm.refresh()

        if case .error(let errState, let lastLoaded) = vm.state {
            #expect(errState == .offline)
            // lastLoaded should be the prior (empty) success.
            #expect(lastLoaded != nil)
        } else {
            Issue.record("Expected .error, got \(vm.state)")
        }
    }
}
