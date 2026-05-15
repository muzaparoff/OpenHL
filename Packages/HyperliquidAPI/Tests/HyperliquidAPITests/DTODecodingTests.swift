// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore
import Testing

@testable import HyperliquidAPI

// MARK: - Shared helpers

/// Builds a client whose URLSession is backed by StubURLProtocol. The caller
/// is responsible for setting StubURLProtocol.handler before invoking the
/// client; all tests in this file do so inline.
///
/// `baseURL` is the Hyperliquid production URL; the stub intercepts every
/// request so no real network call is ever made.
private func makeClient(
    session: URLSession,
    clock: any Clock = FixedClock(Date(timeIntervalSince1970: 1_715_774_400))
) -> URLSessionHyperliquidClient {
    URLSessionHyperliquidClient(
        baseURL: URL(string: "https://api.hyperliquid.xyz")!,
        session: session,
        clock: clock
    )
}

/// Returns a stub that delivers the given data with the given HTTP status.
private func stubResponse(data: Data, statusCode: Int = 200) -> (URLRequest) -> Result<(HTTPURLResponse, Data?), Error>
{
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

private let testAddress = try! Address("0xabcdef1234567890abcdef1234567890abcdef12")

// MARK: - Top-level serialized wrapper
//
// All three nested suites (fixture decoding, error mapping, request shape)
// write to StubURLProtocol.handler, which is a process-global static var.
// Wrapping them in a single parent @Suite(.serialized) guarantees that every
// @Test in every nested suite runs one at a time, regardless of Swift Testing's
// parallel scheduler. This is the correct pattern when multiple suites share
// one piece of global mutable state.
@Suite("URLSessionHyperliquidClient — all client tests", .serialized)
struct URLSessionClientTests {

    // MARK: - Fixture decoding

    @Suite("ClearinghouseState — fixture decoding")
    struct FixtureDecodingTests {

        @Test("empty fixture: no positions, zero account value")
        func emptyFixture() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_empty")
            StubURLProtocol.handler = stubResponse(data: data)
            let client = makeClient(session: session)

            let state = try await client.clearinghouseState(for: testAddress)

            #expect(state.positions.isEmpty)
            #expect(state.summary.accountValue >= 0)
        }

        @Test("single_long fixture: one long position with positive PnL")
        func singleLongFixture() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_single_long")
            StubURLProtocol.handler = stubResponse(data: data)
            let client = makeClient(session: session)

            let state = try await client.clearinghouseState(for: testAddress)

            #expect(state.positions.count == 1)
            let position = try #require(state.positions.first)
            #expect(position.coin == "BTC")
            #expect(position.side == .long)
            #expect(position.size > 0)
            #expect(position.unrealizedPnL == Decimal(string: "500.00"))
            #expect(position.entryPrice == Decimal(string: "38000.00"))
            #expect(position.liquidationPrice == Decimal(string: "30000.00"))
            #expect(position.leverage == .cross(10))
        }

        @Test("single_short_negative_pnl fixture: one short position with negative PnL")
        func singleShortNegativePnLFixture() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_single_short_negative_pnl")
            StubURLProtocol.handler = stubResponse(data: data)
            let client = makeClient(session: session)

            let state = try await client.clearinghouseState(for: testAddress)

            #expect(state.positions.count == 1)
            let position = try #require(state.positions.first)
            #expect(position.coin == "ETH")
            #expect(position.side == .short)
            #expect(position.size < 0)
            #expect(position.unrealizedPnL == Decimal(string: "-250.00"))
            #expect(position.leverage == .isolated(10))
        }

        @Test("multiple_mixed fixture: three positions (long BTC, short ETH, long SOL with no liquidation price)")
        func multipleMixedFixture() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_multiple_mixed")
            StubURLProtocol.handler = stubResponse(data: data)
            let client = makeClient(session: session)

            let state = try await client.clearinghouseState(for: testAddress)

            #expect(state.positions.count == 3)
            let btc = try #require(state.positions.first(where: { $0.coin == "BTC" }))
            #expect(btc.side == .long)
            let eth = try #require(state.positions.first(where: { $0.coin == "ETH" }))
            #expect(eth.side == .short)
            let sol = try #require(state.positions.first(where: { $0.coin == "SOL" }))
            #expect(sol.liquidationPrice == nil)
        }

        @Test("large_decimals fixture: high-precision values decoded without precision loss")
        func largeDecimalsFixture() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_large_decimals")
            StubURLProtocol.handler = stubResponse(data: data)
            let client = makeClient(session: session)

            let state = try await client.clearinghouseState(for: testAddress)

            #expect(state.summary.accountValue == Decimal(string: "123456789.123456789")!)
            let position = try #require(state.positions.first)
            #expect(position.coin == "BTC")
            #expect(position.entryPrice == Decimal(string: "99999.999999999"))
        }

        @Test("with_liquidation_price fixture: liquidation price is present and decoded")
        func withLiquidationPriceFixture() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_with_liquidation_price")
            StubURLProtocol.handler = stubResponse(data: data)
            let client = makeClient(session: session)

            let state = try await client.clearinghouseState(for: testAddress)

            let position = try #require(state.positions.first)
            #expect(position.liquidationPrice != nil)
            #expect(position.liquidationPrice == Decimal(string: "28500.00"))
        }

        @Test("without_liquidation_price fixture: liquidation price is nil")
        func withoutLiquidationPriceFixture() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_without_liquidation_price")
            StubURLProtocol.handler = stubResponse(data: data)
            let client = makeClient(session: session)

            let state = try await client.clearinghouseState(for: testAddress)

            let position = try #require(state.positions.first)
            #expect(position.liquidationPrice == nil)
        }

        @Test("serverTime is decoded from the `time` field (milliseconds → Date)")
        func serverTimeIsDecoded() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_single_long")
            StubURLProtocol.handler = stubResponse(data: data)
            let client = makeClient(session: session)

            let state = try await client.clearinghouseState(for: testAddress)

            // The fixture has time: 1715774400000 ms → 1715774400.0 s
            #expect(state.serverTime == Date(timeIntervalSince1970: 1_715_774_400))
        }

        @Test("fetchedAt is stamped with the injected clock's time")
        func fetchedAtIsStamped() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_empty")
            StubURLProtocol.handler = stubResponse(data: data)
            let fixedDate = Date(timeIntervalSince1970: 1_715_774_400)
            let client = makeClient(session: session, clock: FixedClock(fixedDate))

            let state = try await client.clearinghouseState(for: testAddress)

            #expect(state.fetchedAt == fixedDate)
        }
    }

    // MARK: - Error mapping

    @Suite("URLSessionHyperliquidClient — error mapping")
    struct ErrorMappingTests {

        @Test("HTTP 500 throws HyperliquidError.httpStatus(500)")
        func http500ThrowsHTTPStatus() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_empty")
            StubURLProtocol.handler = stubResponse(data: data, statusCode: 500)
            let client = makeClient(session: session)

            do {
                _ = try await client.clearinghouseState(for: testAddress)
                Issue.record("Expected throw but got success")
            } catch let err as HyperliquidError {
                guard case .httpStatus(let code) = err else {
                    Issue.record("Expected .httpStatus(500) but got: \(err)")
                    return
                }
                #expect(code == 500)
            }
        }

        @Test("HTTP 200 with malformed JSON throws HyperliquidError.decoding")
        func malformedJSONThrowsDecoding() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_malformed_decimal")
            StubURLProtocol.handler = { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return .success((response, data))
            }
            let client = makeClient(session: session)

            do {
                _ = try await client.clearinghouseState(for: testAddress)
                Issue.record("Expected throw but got success")
            } catch let err as HyperliquidError {
                guard case .decoding = err else {
                    Issue.record("Expected .decoding but got: \(err)")
                    return
                }
            }
        }

        @Test("URLError.notConnectedToInternet throws HyperliquidError.offline")
        func notConnectedToInternetThrowsOffline() async {
            let session = StubURLProtocol.makeSession()
            StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
            let client = makeClient(session: session)

            do {
                _ = try await client.clearinghouseState(for: testAddress)
                Issue.record("Expected throw but got success")
            } catch let err as HyperliquidError {
                guard case .offline = err else {
                    Issue.record("Expected .offline but got: \(err)")
                    return
                }
            } catch {
                Issue.record("Expected HyperliquidError.offline but got: \(error)")
            }
        }

        @Test("URLError.timedOut throws HyperliquidError.timeout")
        func timedOutThrowsTimeout() async {
            let session = StubURLProtocol.makeSession()
            StubURLProtocol.handler = { _ in .failure(URLError(.timedOut)) }
            let client = makeClient(session: session)

            do {
                _ = try await client.clearinghouseState(for: testAddress)
                Issue.record("Expected throw but got success")
            } catch let err as HyperliquidError {
                guard case .timeout = err else {
                    Issue.record("Expected .timeout but got: \(err)")
                    return
                }
            } catch {
                Issue.record("Expected HyperliquidError.timeout but got: \(error)")
            }
        }
    }

    // MARK: - Request shape verification

    @Suite("URLSessionHyperliquidClient — request shape")
    struct RequestShapeTests {

        @Test("Sends POST to https://api.hyperliquid.xyz/info")
        func sendsPostToInfoEndpoint() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_empty")
            var capturedRequest: URLRequest?
            StubURLProtocol.handler = { request in
                capturedRequest = request
                return stubResponse(data: data)(request)
            }
            let client = makeClient(session: session)
            _ = try await client.clearinghouseState(for: testAddress)

            let req = try #require(capturedRequest)
            #expect(req.httpMethod == "POST")
            #expect(req.url?.absoluteString == "https://api.hyperliquid.xyz/info")
        }

        @Test("Sets Content-Type: application/json header")
        func setsContentTypeHeader() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_empty")
            var capturedRequest: URLRequest?
            StubURLProtocol.handler = { request in
                capturedRequest = request
                return stubResponse(data: data)(request)
            }
            let client = makeClient(session: session)
            _ = try await client.clearinghouseState(for: testAddress)

            let req = try #require(capturedRequest)
            #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        }

        @Test("Body is {\"type\":\"clearinghouseState\",\"user\":\"<lowercase address>\"}")
        func bodyHasCorrectShape() async throws {
            let session = StubURLProtocol.makeSession()
            let data = try FixtureLoader.load("clearinghouseState_empty")
            var capturedBody: [String: String]?
            StubURLProtocol.handler = { request in
                // URLSession moves httpBody → httpBodyStream before the protocol
                // sees the request. Drain the stream to recover the bytes.
                let bodyData = StubURLProtocol.bodyData(for: request)
                if !bodyData.isEmpty {
                    capturedBody = try? JSONDecoder().decode([String: String].self, from: bodyData)
                }
                return stubResponse(data: data)(request)
            }
            let client = makeClient(session: session)
            _ = try await client.clearinghouseState(for: testAddress)

            let body = try #require(capturedBody)
            #expect(body["type"] == "clearinghouseState")
            // Address must be the lowercase canonical form.
            #expect(body["user"] == testAddress.rawValue)
        }
    }
}
