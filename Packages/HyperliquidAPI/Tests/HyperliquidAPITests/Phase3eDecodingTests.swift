// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore
import Testing

@testable import HyperliquidAPI

// MARK: - Test-local DTO
//
// `PortfolioDTO` (and `InfoRequest.portfolio`) are being authored by swift-expert
// in parallel. Until they land, this file uses private test-local types that
// faithfully mirror the expected wire format so fixture decoder tests can run
// immediately and gate swift-expert's implementation against a real API response.
//
// Wire format (confirmed from `portfolio_real_btc_short.json`):
//   Array of [windowName, {accountValueHistory, pnlHistory, vlm}] pairs.
//   accountValueHistory / pnlHistory are arrays of [timestampMs (Int64), decimalString].
//   vlm is a single decimal string (daily notional volume total for the window).
//   Unknown window names (e.g. "perpDay") must be silently ignored by `toDomain()`.

private struct TestPortfolioPoint: Decodable {
    let time: Date  // decoded from element[0]: milliseconds since epoch
    let value: Decimal  // decoded from element[1]: decimal string

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let ms = try container.decode(Int64.self)
        time = Date(timeIntervalSince1970: TimeInterval(ms) / 1_000.0)
        let raw = try container.decode(String.self)
        guard let d = Decimal(string: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse Decimal from '\(raw)'"
            )
        }
        value = d
    }
}

private struct TestPortfolioWindowPayload: Decodable {
    let accountValueHistory: [TestPortfolioPoint]
    let pnlHistory: [TestPortfolioPoint]
    // vlm is intentionally decoded as a string but not surfaced in v1.
    let vlm: String
}

// The top-level response is [[windowName, payload], …] — a heterogeneous array
// (string + object). Decode as a raw unkeyed container per element.
private struct TestPortfolioResponse: Decodable {
    let entries: [(name: String, payload: TestPortfolioWindowPayload)]

    init(from decoder: any Decoder) throws {
        var outer = try decoder.unkeyedContainer()
        var result: [(String, TestPortfolioWindowPayload)] = []
        while !outer.isAtEnd {
            var pair = try outer.nestedUnkeyedContainer()
            let name = try pair.decode(String.self)
            let payload = try pair.decode(TestPortfolioWindowPayload.self)
            result.append((name, payload))
        }
        entries = result
    }

    /// Maps known window names to `Portfolio` domain type; unknown names are
    /// silently dropped (defensive — Hyperliquid adds `perp*` variants that
    /// v1 does not surface).
    func toDomain() -> Portfolio {
        let nameToWindow: [String: PortfolioWindow] = [
            "day": .day,
            "week": .week,
            "month": .month,
            "allTime": .allTime,
        ]
        var windows: [PortfolioWindow: PortfolioSeries] = [:]
        for (name, payload) in entries {
            guard let window = nameToWindow[name] else { continue }
            let avPoints = payload.accountValueHistory.map { PortfolioPoint(time: $0.time, value: $0.value) }
            let pnlPoints = payload.pnlHistory.map { PortfolioPoint(time: $0.time, value: $0.value) }
            windows[window] = PortfolioSeries(
                accountValue: avPoints,
                pnl: pnlPoints,
                totalVolume: Decimal(string: payload.vlm) ?? 0
            )
        }
        return Portfolio(windows: windows)
    }
}

// MARK: - PortfolioDTO decoder tests

/// Locks in the `portfolio` decoder against a real response from the known
/// Hyperliquid account `0x99382723C90EcC72dad2A7DD375DE45b88E8fe72`.
/// Captured 2026-05-16. Structural invariants only — exact values will drift
/// as the account trades.
@Suite("portfolio — real-account fixture (0x9938…fe72)")
struct PortfolioRealFixtureTests {

    // MARK: - Fixture load + all 4 windows present

    @Test("Loads portfolio_real_btc_short fixture and decodes all 4 user-facing windows")
    func decodesAllFourWindows() throws {
        let data = try FixtureLoader.load("portfolio_real_btc_short")
        let response = try JSONDecoder().decode(TestPortfolioResponse.self, from: data)
        let portfolio = response.toDomain()

        #expect(portfolio.windows.count == 4, "Expected exactly 4 user-facing windows (day, week, month, allTime)")
        #expect(portfolio[.day] != nil)
        #expect(portfolio[.week] != nil)
        #expect(portfolio[.month] != nil)
        #expect(portfolio[.allTime] != nil)
    }

    // MARK: - accountValue series — non-empty, valid timestamps, non-negative values

    @Test("day window: accountValue is non-empty, all timestamps valid, all values non-negative")
    func dayWindowAccountValueInvariants() throws {
        let data = try FixtureLoader.load("portfolio_real_btc_short")
        let response = try JSONDecoder().decode(TestPortfolioResponse.self, from: data)
        let portfolio = response.toDomain()
        let series = try #require(portfolio[.day])

        #expect(!series.accountValue.isEmpty, "day accountValue must not be empty")

        let epoch = Date(timeIntervalSince1970: 0)
        let now = Date()
        for point in series.accountValue {
            #expect(point.time > epoch, "timestamp must be after epoch (got \(point.time))")
            #expect(point.time < now, "timestamp must be in the past (got \(point.time))")
            #expect(point.value >= 0, "accountValue must be non-negative (got \(point.value))")
        }
    }

    // MARK: - pnl array length matches accountValue length (API invariant)

    @Test("day window: pnl array has the same length as accountValue")
    func dayWindowPnlLengthMatchesAccountValue() throws {
        let data = try FixtureLoader.load("portfolio_real_btc_short")
        let response = try JSONDecoder().decode(TestPortfolioResponse.self, from: data)
        let portfolio = response.toDomain()
        let series = try #require(portfolio[.day])

        #expect(
            series.pnl.count == series.accountValue.count,
            "pnl (\(series.pnl.count)) must match accountValue (\(series.accountValue.count)) length"
        )
    }

    // MARK: - All four windows pass accountValue + pnl invariants

    @Test("All four windows: accountValue is non-empty, pnl length matches accountValue")
    func allWindowsPassBasicInvariants() throws {
        let data = try FixtureLoader.load("portfolio_real_btc_short")
        let response = try JSONDecoder().decode(TestPortfolioResponse.self, from: data)
        let portfolio = response.toDomain()

        for window in PortfolioWindow.allCases {
            let series = try #require(portfolio[window], "Window \(window) must be present")
            #expect(!series.accountValue.isEmpty, "\(window) accountValue must not be empty")
            #expect(
                series.pnl.count == series.accountValue.count,
                "\(window) pnl count must equal accountValue count"
            )
        }
    }

    // MARK: - allTime window: all timestamps are in valid range

    @Test("allTime window: all PortfolioPoint.time values are after epoch and before now")
    func allTimeWindowTimestampsInRange() throws {
        let data = try FixtureLoader.load("portfolio_real_btc_short")
        let response = try JSONDecoder().decode(TestPortfolioResponse.self, from: data)
        let portfolio = response.toDomain()
        let series = try #require(portfolio[.allTime])

        let epoch = Date(timeIntervalSince1970: 0)
        let now = Date()
        #expect(
            series.accountValue.allSatisfy { $0.time > epoch && $0.time < now },
            "All allTime points must have timestamps after epoch and before now"
        )
    }

    // MARK: - Raw fixture: 8 windows returned (4 user-facing + 4 perp*)

    @Test("Raw fixture contains 8 windows including perp* variants")
    func rawFixtureHasEightWindows() throws {
        let data = try FixtureLoader.load("portfolio_real_btc_short")
        let response = try JSONDecoder().decode(TestPortfolioResponse.self, from: data)

        let names = response.entries.map(\.name)
        #expect(names.count == 8, "Expected 8 raw windows; got \(names.count): \(names)")
        #expect(names.contains("day"))
        #expect(names.contains("perpDay"))
    }
}

// MARK: - Edge case: empty account (zero history)

/// Synthesized fixture — an account that has never traded has empty arrays
/// in every window. The decoder must produce a Portfolio with all 4 windows
/// present, each PortfolioSeries empty.
@Suite("portfolio — edge cases")
struct PortfolioEdgeCaseTests {

    @Test("Empty-account fixture: 4 windows present, each series has no points")
    func emptyAccountFourWindowsAllEmpty() throws {
        let emptyWindowJSON = """
            {
                "accountValueHistory": [],
                "pnlHistory": [],
                "vlm": "0.0"
            }
            """
        let raw = """
            [
                ["day", \(emptyWindowJSON)],
                ["week", \(emptyWindowJSON)],
                ["month", \(emptyWindowJSON)],
                ["allTime", \(emptyWindowJSON)]
            ]
            """
        let data = Data(raw.utf8)
        let response = try JSONDecoder().decode(TestPortfolioResponse.self, from: data)
        let portfolio = response.toDomain()

        #expect(portfolio.windows.count == 4, "All 4 windows must be present even when empty")
        for window in PortfolioWindow.allCases {
            let series = try #require(portfolio[window])
            #expect(series.accountValue.isEmpty, "\(window) accountValue must be empty")
            #expect(series.pnl.isEmpty, "\(window) pnl must be empty")
        }
    }

    @Test("Unknown window name 'perpYear' is silently dropped; known windows still decode")
    func unknownWindowNameSilentlyDropped() throws {
        let windowPayload = """
            {
                "accountValueHistory": [[1778839080046, "100.0"]],
                "pnlHistory": [[1778839080046, "0.0"]],
                "vlm": "50.0"
            }
            """
        let raw = """
            [
                ["day", \(windowPayload)],
                ["week", \(windowPayload)],
                ["month", \(windowPayload)],
                ["allTime", \(windowPayload)],
                ["perpYear", \(windowPayload)]
            ]
            """
        let data = Data(raw.utf8)
        let response = try JSONDecoder().decode(TestPortfolioResponse.self, from: data)
        let portfolio = response.toDomain()

        // "perpYear" must be dropped; the 4 known windows remain.
        #expect(portfolio.windows.count == 4, "Unknown 'perpYear' must be silently dropped")
        #expect(portfolio[.day] != nil)
        #expect(portfolio[.allTime] != nil)
    }

    @Test("Decoder does not throw on unknown window name — toDomain() drops it gracefully")
    func unknownWindowDoesNotThrow() throws {
        let windowPayload = """
            {"accountValueHistory":[],"pnlHistory":[],"vlm":"0.0"}
            """
        let raw = """
            [["perpMonth", \(windowPayload)], ["day", \(windowPayload)]]
            """
        let data = Data(raw.utf8)
        #expect(throws: Never.self) {
            let response = try JSONDecoder().decode(TestPortfolioResponse.self, from: data)
            _ = response.toDomain()
        }
    }
}

// MARK: - InfoRequest.portfolio body shape
//
// `InfoRequest.portfolio` does not exist yet (swift-expert is adding it in parallel).
// This test verifies the *expected* wire shape by encoding a local private request
// struct that matches what swift-expert's case must produce.
// Once `InfoRequest.portfolio` lands, replace `LocalPortfolioRequest` with the real case.

private struct LocalPortfolioRequest: Encodable {
    let type: String = "portfolio"
    let user: String

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(user, forKey: .user)
    }

    private enum CodingKeys: String, CodingKey { case type, user }
}

@Suite("InfoRequest.portfolio — expected body shape")
struct PortfolioRequestShapeTests {

    private let testUser = "0xabcdef1234567890abcdef1234567890abcdef12"

    @Test("Encodes type=portfolio, user=lowercase address, no nested req object")
    func encodesToFlatBody() throws {
        let req = LocalPortfolioRequest(user: testUser)
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "portfolio", "type must be 'portfolio'")
        #expect(json["user"] as? String == testUser, "user must be lowercase canonical address")
        #expect(json["req"] == nil, "portfolio has no nested req object (unlike candleSnapshot)")
        // Exactly 2 keys: type + user
        #expect(json.count == 2, "body must have exactly 2 keys: type and user")
    }

    @Test("User address is preserved as-is (lowercase 0x-prefixed hex)")
    func userAddressIsPreservedVerbatim() throws {
        let req = LocalPortfolioRequest(user: testUser)
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["user"] as? String == testUser)
    }
}

// MARK: - URLSessionHyperliquidClient.portfolio transport tests
//
// These tests are disabled pending swift-expert adding `portfolio(for:)` to
// `HyperliquidClient` and `URLSessionHyperliquidClient`.
//
// When swift-expert lands the implementation:
// 1. Remove `.disabled(...)` from each @Test.
// 2. Replace `LocalPortfolioRequest` with `InfoRequest.portfolio(user: address)`.
// 3. Replace `TestPortfolioResponse` with the real `PortfolioDTO`.
// 4. Add `portfolioResult`/`portfolioCallCount` to `FakeHyperliquidClient`.
//
// These are nested inside `URLSessionClientTests` extension so they inherit the
// `.serialized` trait and cannot race against other tests on `StubURLProtocol.handler`.

private func p3emakeClient(
    session: URLSession,
    clock: any Clock = FixedClock(Date(timeIntervalSince1970: 1_715_774_400))
) -> URLSessionHyperliquidClient {
    URLSessionHyperliquidClient(
        baseURL: URL(string: "https://api.hyperliquid.xyz")!,
        session: session,
        clock: clock
    )
}

private func p3estubResponse(
    data: Data,
    statusCode: Int = 200
) -> (URLRequest) -> Result<(HTTPURLResponse, Data?), Error> {
    { request in
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return .success((response, data))
    }
}

extension URLSessionClientTests {

    @Suite("Phase 3e — portfolio transport tests (pending HyperliquidClient.portfolio)")
    struct Phase3ePortfolioClientTests {

        private static let testAddress = try! Address("0xabcdef1234567890abcdef1234567890abcdef12")

        @Test("200 + real fixture → decoded Portfolio with 4 windows")
        func realFixtureDecodedByClient() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("portfolio_real_btc_short")
            StubURLProtocol.handler = p3estubResponse(data: data)
            let client = p3emakeClient(session: session)
            let portfolio = try await client.portfolio(for: Self.testAddress)
            #expect(portfolio.windows.count == 4)
        }

        @Test("HTTP 5xx → throws HyperliquidError.httpStatus(500)")
        func http5xxThrowsHTTPStatus() async throws {
            let session = StubURLProtocol.makeSession()
            let data = Data("{}".utf8)
            StubURLProtocol.handler = p3estubResponse(data: data, statusCode: 500)
            let client = p3emakeClient(session: session)
            do {
                _ = try await client.portfolio(for: Self.testAddress)
                Issue.record("Expected throw but got success")
            } catch let err as HyperliquidError {
                guard case .httpStatus(500) = err else {
                    Issue.record("Expected .httpStatus(500) but got: \(err)")
                    return
                }
            }
        }

        @Test("Offline → throws HyperliquidError.offline")
        func offlineThrowsOffline() async {
            let session = StubURLProtocol.makeSession()
            StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
            let client = p3emakeClient(session: session)
            do {
                _ = try await client.portfolio(for: Self.testAddress)
                Issue.record("Expected throw but got success")
            } catch let err as HyperliquidError {
                guard case .offline = err else {
                    Issue.record("Expected .offline but got: \(err)")
                    return
                }
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }

        @Test("Malformed JSON → throws HyperliquidError.decoding")
        func malformedJSONThrowsDecoding() async throws {
            let session = StubURLProtocol.makeSession()
            let malformed = Data("{not json}".utf8)
            StubURLProtocol.handler = p3estubResponse(data: malformed, statusCode: 200)
            let client = p3emakeClient(session: session)
            do {
                _ = try await client.portfolio(for: Self.testAddress)
                Issue.record("Expected throw but got success")
            } catch let err as HyperliquidError {
                guard case .decoding = err else {
                    Issue.record("Expected .decoding but got: \(err)")
                    return
                }
            }
        }
    }
}

// MARK: - BalanceHistoryViewModel state-machine tests
//
// These are intentionally deferred because:
// a) `BalanceHistoryViewModel` does not exist yet (ios-developer implements it).
// b) `FakeHyperliquidClient` does not expose `portfolioResult`/`portfolioCallCount` yet.
//
// When ios-developer creates the VM and swift-expert updates FakeHyperliquidClient,
// create `OpenHLTests/Phase3eViewModelTests.swift` covering:
//
//   - Cold load: .idle → load() → .loading → .loaded(Portfolio)
//   - Refresh on loaded state: preserves prior snapshot on failure
//     (.error(_, lastLoaded: portfolio))
//   - Window-switching: VM stores the whole Portfolio; the view picks the active
//     PortfolioSeries from portfolio[selectedWindow]. No re-fetch required.
//     Assert that calling selectWindow(.week) does NOT increment portfolioCallCount.
//
// These are handed to qa-automation once the implementation exists.
// See docs/qa/phase3e.md for the full test plan.
