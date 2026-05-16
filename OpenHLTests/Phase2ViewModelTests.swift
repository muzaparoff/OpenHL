// SPDX-License-Identifier: MIT

// NOTE (qa-automation): These tests target OrdersViewModel and FillsViewModel,
// which are implemented by ios-developer in parallel. All suites are annotated
// .disabled so the bundle compiles against the current stub surface.
//
// When ios-developer lands:
//   1. Add the real ViewModel types (OrdersViewModel, FillsViewModel) to the
//      app target and import them here.
//   2. Remove the local stub ViewModels below.
//   3. Remove .disabled from each suite.
//   4. Uncomment the UITestStubClient contract keys noted at the bottom.
//
// Stub keys for ios-developer to implement in UITestStubClient.swift:
//   "openOrders_mixed_buy_sell" — returns two orders with known coins/sides
//   "userFills_close_short_with_pnl" — returns one fill with positive closedPnl

import Foundation
import Testing

// MARK: - Local stub types
//
// These mirror architecture §16 / §20 so the test logic compiles now.
// Delete these blocks and wire the real ViewModels once ios-developer lands them.

// ViewErrorState mirrors architecture §11.4
private enum ViewErrorState: Sendable, Equatable {
    case offline
    case timeout
    case badRequest
    case serverError
    case unexpectedResponse
    case unknown
}

// HyperliquidError mirror (enough cases for the mapper)
private enum StubHyperliquidError: Error, Sendable {
    case offline
    case timeout
    case httpStatus(Int)
    case decoding
    case unexpectedResponse(reason: String)
    case transport
}

// Minimal OpenOrder stub
private struct StubOpenOrder: Sendable, Equatable {
    let coin: String
    let placedAt: Date
}

// Minimal Fill stub
private struct StubFill: Sendable, Equatable {
    let coin: String
    let executedAt: Date
}

// Minimal Address stub
private struct StubAddress: Sendable, Hashable {
    static let test = StubAddress()
}

// Fake client for OrdersViewModel tests
private final class FakeOrdersClient: @unchecked Sendable {
    var ordersResult: Result<[StubOpenOrder], StubHyperliquidError> = .failure(.offline)
    func openOrders(for _: StubAddress) async throws -> [StubOpenOrder] {
        switch ordersResult {
        case .success(let items): return items
        case .failure(let e): throw e
        }
    }
}

// Fake client for FillsViewModel tests
private final class FakeFillsClient: @unchecked Sendable {
    var fillsResult: Result<[StubFill], StubHyperliquidError> = .failure(.offline)
    func userFills(for _: StubAddress) async throws -> [StubFill] {
        switch fillsResult {
        case .success(let items): return items
        case .failure(let e): throw e
        }
    }
}

// OrdersViewModel state enum (mirrors architecture §20)
private enum OrdersViewModelState: Equatable {
    case idle
    case loading
    case loaded([StubOpenOrder])
    case error(ViewErrorState, lastLoaded: [StubOpenOrder]?)
}

// FillsViewModel state enum (mirrors architecture §20)
private enum FillsViewModelState: Equatable {
    case idle
    case loading
    case loaded([StubFill])
    case error(ViewErrorState, lastLoaded: [StubFill]?)
}

// Stub OrdersViewModel
@MainActor
private final class StubOrdersViewModel {

    private(set) var state: OrdersViewModelState = .idle
    private let client: FakeOrdersClient
    private let address: StubAddress

    init(client: FakeOrdersClient, address: StubAddress) {
        self.client = client
        self.address = address
    }

    func load() async {
        state = .loading
        do {
            let result = try await client.openOrders(for: address)
            guard !Task.isCancelled else { return }
            // Sort by placedAt descending — architecture §17.3
            let sorted = result.sorted { $0.placedAt > $1.placedAt }
            state = .loaded(sorted)
        } catch let err as StubHyperliquidError {
            guard !Task.isCancelled else { return }
            state = .error(mapError(err), lastLoaded: nil)
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(.unknown, lastLoaded: nil)
        }
    }

    func refresh() async {
        let previous: [StubOpenOrder]?
        if case .loaded(let items) = state { previous = items } else { previous = nil }

        state = .loading
        do {
            let result = try await client.openOrders(for: address)
            guard !Task.isCancelled else { return }
            let sorted = result.sorted { $0.placedAt > $1.placedAt }
            state = .loaded(sorted)
        } catch let err as StubHyperliquidError {
            guard !Task.isCancelled else { return }
            state = .error(mapError(err), lastLoaded: previous)
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(.unknown, lastLoaded: previous)
        }
    }

    private func mapError(_ err: StubHyperliquidError) -> ViewErrorState {
        switch err {
        case .offline: return .offline
        case .timeout: return .timeout
        case .httpStatus(let code) where code >= 500: return .serverError
        case .httpStatus: return .badRequest
        case .decoding: return .unexpectedResponse
        case .unexpectedResponse: return .unexpectedResponse
        case .transport: return .unknown
        }
    }
}

// Stub FillsViewModel
@MainActor
private final class StubFillsViewModel {

    private(set) var state: FillsViewModelState = .idle
    private let client: FakeFillsClient
    private let address: StubAddress

    init(client: FakeFillsClient, address: StubAddress) {
        self.client = client
        self.address = address
    }

    func load() async {
        state = .loading
        do {
            let result = try await client.userFills(for: address)
            guard !Task.isCancelled else { return }
            // Sort by executedAt descending — architecture §17.3
            let sorted = result.sorted { $0.executedAt > $1.executedAt }
            state = .loaded(sorted)
        } catch let err as StubHyperliquidError {
            guard !Task.isCancelled else { return }
            state = .error(mapError(err), lastLoaded: nil)
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(.unknown, lastLoaded: nil)
        }
    }

    func refresh() async {
        let previous: [StubFill]?
        if case .loaded(let items) = state { previous = items } else { previous = nil }

        state = .loading
        do {
            let result = try await client.userFills(for: address)
            guard !Task.isCancelled else { return }
            let sorted = result.sorted { $0.executedAt > $1.executedAt }
            state = .loaded(sorted)
        } catch let err as StubHyperliquidError {
            guard !Task.isCancelled else { return }
            state = .error(mapError(err), lastLoaded: previous)
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(.unknown, lastLoaded: previous)
        }
    }

    private func mapError(_ err: StubHyperliquidError) -> ViewErrorState {
        switch err {
        case .offline: return .offline
        case .timeout: return .timeout
        case .httpStatus(let code) where code >= 500: return .serverError
        case .httpStatus: return .badRequest
        case .decoding: return .unexpectedResponse
        case .unexpectedResponse: return .unexpectedResponse
        case .transport: return .unknown
        }
    }
}

// MARK: - OrdersViewModel state-machine tests

@Suite(
    "OrdersViewModel — state machine",
    .disabled("Waiting for ios-developer to land OrdersViewModel")
)
@MainActor
struct OrdersViewModelStateTests {

    private func makeViewModel(
        result: Result<[StubOpenOrder], StubHyperliquidError>
    ) -> (StubOrdersViewModel, FakeOrdersClient) {
        let client = FakeOrdersClient()
        client.ordersResult = result
        let vm = StubOrdersViewModel(client: client, address: .test)
        return (vm, client)
    }

    @Test("Initial state is .idle")
    func initialStateIsIdle() {
        let (vm, _) = makeViewModel(result: .failure(.offline))
        #expect(vm.state == .idle)
    }

    @Test("load() happy path: idle → loading → loaded")
    func loadHappyPath() async {
        let orders = [
            StubOpenOrder(coin: "BTC", placedAt: Date(timeIntervalSince1970: 1_715_774_000))
        ]
        let (vm, _) = makeViewModel(result: .success(orders))

        #expect(vm.state == .idle)
        await vm.load()

        if case .loaded(let loaded) = vm.state {
            #expect(loaded.count == 1)
        } else {
            Issue.record("Expected .loaded but got: \(vm.state)")
        }
    }

    @Test("load() offline error: produces .error(.offline, lastLoaded: nil)")
    func loadOfflineError() async {
        let (vm, _) = makeViewModel(result: .failure(.offline))
        await vm.load()
        #expect(vm.state == .error(.offline, lastLoaded: nil))
    }

    @Test("load() timeout error: produces .error(.timeout, lastLoaded: nil)")
    func loadTimeoutError() async {
        let (vm, _) = makeViewModel(result: .failure(.timeout))
        await vm.load()
        #expect(vm.state == .error(.timeout, lastLoaded: nil))
    }

    @Test("load() HTTP 500: produces .error(.serverError, lastLoaded: nil)")
    func loadHttp500Error() async {
        let (vm, _) = makeViewModel(result: .failure(.httpStatus(500)))
        await vm.load()
        #expect(vm.state == .error(.serverError, lastLoaded: nil))
    }

    @Test("load() HTTP 429: produces .error(.badRequest, lastLoaded: nil)")
    func loadHttp429Error() async {
        let (vm, _) = makeViewModel(result: .failure(.httpStatus(429)))
        await vm.load()
        #expect(vm.state == .error(.badRequest, lastLoaded: nil))
    }

    @Test("refresh() after successful load preserves lastLoaded on failure")
    func refreshPreservesLastLoadedOnFailure() async {
        let initial = [
            StubOpenOrder(coin: "BTC", placedAt: Date(timeIntervalSince1970: 1_715_774_000))
        ]
        let (vm, client) = makeViewModel(result: .success(initial))

        await vm.load()
        if case .loaded(let loaded) = vm.state {
            #expect(loaded.count == 1)
        } else {
            Issue.record("Expected .loaded after first load")
            return
        }

        client.ordersResult = .failure(.offline)
        await vm.refresh()

        if case .error(let errState, let lastLoaded) = vm.state {
            #expect(errState == .offline)
            #expect(lastLoaded?.count == 1)
        } else {
            Issue.record("Expected .error with lastLoaded after refresh failure")
        }
    }

    @Test("refresh() on cold (idle) view model produces .error with lastLoaded: nil on failure")
    func refreshColdFailureHasNoLastLoaded() async {
        let (vm, _) = makeViewModel(result: .failure(.offline))
        await vm.refresh()
        #expect(vm.state == .error(.offline, lastLoaded: nil))
    }

    @Test("load() sorts orders by placedAt descending (newest first)")
    func loadSortsByPlacedAtDescending() async {
        // Deliberately unsorted: oldest first, newest last
        let unsorted: [StubOpenOrder] = [
            StubOpenOrder(coin: "SOL", placedAt: Date(timeIntervalSince1970: 1_715_770_000)),
            StubOpenOrder(coin: "ETH", placedAt: Date(timeIntervalSince1970: 1_715_772_000)),
            StubOpenOrder(coin: "BTC", placedAt: Date(timeIntervalSince1970: 1_715_774_000)),
        ]
        let (vm, _) = makeViewModel(result: .success(unsorted))
        await vm.load()

        if case .loaded(let sorted) = vm.state {
            // After sort: BTC (newest) → ETH → SOL (oldest)
            #expect(sorted[0].coin == "BTC")
            #expect(sorted[1].coin == "ETH")
            #expect(sorted[2].coin == "SOL")
        } else {
            Issue.record("Expected .loaded but got: \(vm.state)")
        }
    }

    @Test("load() with empty orders: produces .loaded([])")
    func loadEmptyOrders() async {
        let (vm, _) = makeViewModel(result: .success([]))
        await vm.load()
        #expect(vm.state == .loaded([]))
    }
}

// MARK: - FillsViewModel state-machine tests

@Suite(
    "FillsViewModel — state machine",
    .disabled("Waiting for ios-developer to land FillsViewModel")
)
@MainActor
struct FillsViewModelStateTests {

    private func makeViewModel(
        result: Result<[StubFill], StubHyperliquidError>
    ) -> (StubFillsViewModel, FakeFillsClient) {
        let client = FakeFillsClient()
        client.fillsResult = result
        let vm = StubFillsViewModel(client: client, address: .test)
        return (vm, client)
    }

    @Test("Initial state is .idle")
    func initialStateIsIdle() {
        let (vm, _) = makeViewModel(result: .failure(.offline))
        #expect(vm.state == .idle)
    }

    @Test("load() happy path: idle → loading → loaded")
    func loadHappyPath() async {
        let fills = [
            StubFill(coin: "BTC", executedAt: Date(timeIntervalSince1970: 1_715_774_000))
        ]
        let (vm, _) = makeViewModel(result: .success(fills))

        #expect(vm.state == .idle)
        await vm.load()

        if case .loaded(let loaded) = vm.state {
            #expect(loaded.count == 1)
        } else {
            Issue.record("Expected .loaded but got: \(vm.state)")
        }
    }

    @Test("load() offline error: produces .error(.offline, lastLoaded: nil)")
    func loadOfflineError() async {
        let (vm, _) = makeViewModel(result: .failure(.offline))
        await vm.load()
        #expect(vm.state == .error(.offline, lastLoaded: nil))
    }

    @Test("load() timeout error: produces .error(.timeout, lastLoaded: nil)")
    func loadTimeoutError() async {
        let (vm, _) = makeViewModel(result: .failure(.timeout))
        await vm.load()
        #expect(vm.state == .error(.timeout, lastLoaded: nil))
    }

    @Test("refresh() after successful load preserves lastLoaded on failure")
    func refreshPreservesLastLoadedOnFailure() async {
        let initial = [
            StubFill(coin: "ETH", executedAt: Date(timeIntervalSince1970: 1_715_773_000))
        ]
        let (vm, client) = makeViewModel(result: .success(initial))

        await vm.load()
        if case .loaded(let loaded) = vm.state {
            #expect(loaded.count == 1)
        } else {
            Issue.record("Expected .loaded after first load")
            return
        }

        client.fillsResult = .failure(.timeout)
        await vm.refresh()

        if case .error(let errState, let lastLoaded) = vm.state {
            #expect(errState == .timeout)
            #expect(lastLoaded?.count == 1)
        } else {
            Issue.record("Expected .error with lastLoaded after refresh failure")
        }
    }

    @Test("refresh() on cold (idle) view model produces .error with lastLoaded: nil on failure")
    func refreshColdFailureHasNoLastLoaded() async {
        let (vm, _) = makeViewModel(result: .failure(.offline))
        await vm.refresh()
        #expect(vm.state == .error(.offline, lastLoaded: nil))
    }

    @Test("load() sorts fills by executedAt descending (newest first)")
    func loadSortsByExecutedAtDescending() async {
        // Deliberately unsorted: oldest first
        let unsorted: [StubFill] = [
            StubFill(coin: "ARB", executedAt: Date(timeIntervalSince1970: 1_715_770_000)),
            StubFill(coin: "SOL", executedAt: Date(timeIntervalSince1970: 1_715_772_000)),
            StubFill(coin: "ETH", executedAt: Date(timeIntervalSince1970: 1_715_773_000)),
            StubFill(coin: "BTC", executedAt: Date(timeIntervalSince1970: 1_715_774_000)),
        ]
        let (vm, _) = makeViewModel(result: .success(unsorted))
        await vm.load()

        if case .loaded(let sorted) = vm.state {
            // After sort: BTC (newest) → ETH → SOL → ARB (oldest)
            #expect(sorted[0].coin == "BTC")
            #expect(sorted[1].coin == "ETH")
            #expect(sorted[2].coin == "SOL")
            #expect(sorted[3].coin == "ARB")
        } else {
            Issue.record("Expected .loaded but got: \(vm.state)")
        }
    }

    @Test("load() with empty fills: produces .loaded([])")
    func loadEmptyFills() async {
        let (vm, _) = makeViewModel(result: .success([]))
        await vm.load()
        #expect(vm.state == .loaded([]))
    }

    @Test("load() with exactly userFillsCap fills: all exposed (cap not exceeded)")
    func loadExactlyCapFills() async {
        // 200 fills — exactly at the cap boundary
        let cap = 200
        let fills = (0..<cap).map { i in
            StubFill(coin: "BTC", executedAt: Date(timeIntervalSince1970: Double(1_715_774_000 - i)))
        }
        let (vm, _) = makeViewModel(result: .success(fills))
        await vm.load()

        if case .loaded(let loaded) = vm.state {
            #expect(loaded.count == cap)
        } else {
            Issue.record("Expected .loaded but got: \(vm.state)")
        }
    }
}
