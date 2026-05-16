// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore
import Testing

@testable import HyperliquidAPI

// MARK: - Phase 2 client tests
//
// Phase2ClientTests is nested inside URLSessionClientTests (defined in
// DTODecodingTests.swift) so that it inherits the parent suite's `.serialized`
// trait. This ensures all Phase 1 and Phase 2 tests that share
// StubURLProtocol.handler run one at a time with no races.
//
// The private helpers (makeClient, stubResponse, testAddress) are duplicated
// here because they are file-private in DTODecodingTests.swift. Each is
// identical in behaviour to the Phase 1 versions.

private func p2makeClient(
    session: URLSession,
    clock: any Clock = FixedClock(Date(timeIntervalSince1970: 1_715_774_400))
) -> URLSessionHyperliquidClient {
    URLSessionHyperliquidClient(
        baseURL: URL(string: "https://api.hyperliquid.xyz")!,
        session: session,
        clock: clock
    )
}

private func p2stubResponse(
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

private let p2testAddress = try! Address("0xabcdef1234567890abcdef1234567890abcdef12")

extension URLSessionClientTests {
    @Suite("Phase 2 — openOrders + userFills client tests")
    struct Phase2ClientTests {

        // -------------------------------------------------------------------------
        // MARK: openOrders — fixture decoding
        // -------------------------------------------------------------------------

        @Suite("openOrders — fixture decoding")
        struct OpenOrdersDecodingTests {

            @Test("empty fixture decodes to empty array")
            func emptyFixtureDecodesToEmptyArray() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_empty")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let orders = try await client.openOrders(for: p2testAddress)

                #expect(orders.isEmpty)
            }

            @Test("single_limit fixture: buy side, origSize present (partially filled)")
            func singleLimitFixture() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_single_limit")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let orders = try await client.openOrders(for: p2testAddress)

                #expect(orders.count == 1)
                let order = try #require(orders.first)
                #expect(order.coin == "BTC")
                #expect(order.side == .buy)
                #expect(order.limitPrice == Decimal(string: "60000.00"))
                #expect(order.size == Decimal(string: "0.0750"))
                #expect(order.origSize == Decimal(string: "0.1000"))
                #expect(order.orderType == .limit)
                #expect(order.reduceOnly == false)
                #expect(order.triggerPrice == nil)
                // oid from fixture: 123456789
                #expect(order.oid == 123_456_789)
                // timestamp 1715774000000 ms → 1715774000.0 s
                #expect(order.placedAt == Date(timeIntervalSince1970: 1_715_774_000))
            }

            @Test("mixed_buy_sell fixture: side mapping B→buy and A→sell")
            func mixedBuySellFixture() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_mixed_buy_sell")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let orders = try await client.openOrders(for: p2testAddress)

                #expect(orders.count == 3)
                let btc = try #require(orders.first(where: { $0.coin == "BTC" }))
                #expect(btc.side == .buy)
                #expect(btc.orderType == .limit)

                let eth = try #require(orders.first(where: { $0.coin == "ETH" }))
                #expect(eth.side == .sell)
                #expect(eth.orderType == .trigger)
                #expect(eth.reduceOnly == true)

                let sol = try #require(orders.first(where: { $0.coin == "SOL" }))
                #expect(sol.side == .buy)
                // origSz absent in fixture → nil
                #expect(sol.origSize == nil)
            }

            @Test("with_trigger_price fixture: triggerPrice present on stop and TP orders")
            func withTriggerPriceFixture() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_with_trigger_price")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let orders = try await client.openOrders(for: p2testAddress)

                #expect(orders.count == 2)
                let stopLimit = try #require(orders.first(where: { $0.orderType == .stopLimit }))
                #expect(stopLimit.triggerPrice == Decimal(string: "3050.00"))

                let tpLimit = try #require(orders.first(where: { $0.orderType == .takeProfitLimit }))
                #expect(tpLimit.triggerPrice == Decimal(string: "62000.00"))
            }

            @Test("missing_optional_fields fixture: origSize and reduceOnly are nil / false")
            func missingOptionalFieldsFixture() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_missing_optional_fields")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let orders = try await client.openOrders(for: p2testAddress)

                #expect(orders.count == 1)
                let order = try #require(orders.first)
                // origSz absent in fixture → nil in domain model
                #expect(order.origSize == nil)
                // reduceOnly absent in fixture → mapper defaults to false
                #expect(order.reduceOnly == false)
                #expect(order.triggerPrice == nil)
            }

            @Test("unknown_side fixture throws HyperliquidError.unexpectedResponse")
            func unknownSideThrowsUnexpectedResponse() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_unknown_side")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                do {
                    _ = try await client.openOrders(for: p2testAddress)
                    Issue.record("Expected throw but got success")
                } catch let err as HyperliquidError {
                    guard case .unexpectedResponse = err else {
                        Issue.record("Expected .unexpectedResponse but got: \(err)")
                        return
                    }
                } catch {
                    Issue.record("Expected HyperliquidError but got: \(error)")
                }
            }

            @Test("unknown_orderType fixture maps to OrderType.unknown(...) without throwing")
            func unknownOrderTypeProducesUnknownCase() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_unknown_orderType")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                // Must NOT throw — unknown order types fall back to .unknown(rawString)
                let orders = try await client.openOrders(for: p2testAddress)

                #expect(orders.count == 1)
                let order = try #require(orders.first)
                if case .unknown(let raw) = order.orderType {
                    #expect(raw == "FutureAlgoOrder")
                } else {
                    Issue.record("Expected OrderType.unknown(\"FutureAlgoOrder\") but got: \(order.orderType)")
                }
            }
        }

        // -------------------------------------------------------------------------
        // MARK: userFills — fixture decoding
        // -------------------------------------------------------------------------

        @Suite("userFills — fixture decoding")
        struct UserFillsDecodingTests {

            @Test("empty fixture decodes to empty array")
            func emptyFixtureDecodesToEmptyArray() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_empty")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let fills = try await client.userFills(for: p2testAddress)

                #expect(fills.isEmpty)
            }

            @Test("single_open_long fixture: direction verbatim, closedPnL is zero")
            func singleOpenLongFixture() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_single_open_long")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let fills = try await client.userFills(for: p2testAddress)

                #expect(fills.count == 1)
                let fill = try #require(fills.first)
                #expect(fill.coin == "BTC")
                #expect(fill.side == .buy)
                #expect(fill.direction == "Open Long")
                #expect(fill.price == Decimal(string: "61800.00"))
                #expect(fill.size == Decimal(string: "0.1000"))
                #expect(fill.fee == Decimal(string: "0.42"))
                #expect(fill.feeToken == "USDC")
                #expect(fill.closedPnL == Decimal(string: "0.0"))
                #expect(fill.crossed == true)
                #expect(fill.tid == 9_000_000_001)
                // time 1715774350000 ms → 1715774350.0 s
                #expect(fill.executedAt == Date(timeIntervalSince1970: 1_715_774_350))
            }

            @Test("close_short_with_pnl fixture: positive closedPnL, sell-side")
            func closeShortWithPnLFixture() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_close_short_with_pnl")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let fills = try await client.userFills(for: p2testAddress)

                #expect(fills.count == 1)
                let fill = try #require(fills.first)
                #expect(fill.coin == "ETH")
                // wire side "B" → .buy (closing a short is a buy)
                #expect(fill.side == .buy)
                #expect(fill.direction == "Close Short")
                #expect(fill.closedPnL == Decimal(string: "31.00"))
            }

            @Test("liquidation fixture: direction verbatim 'Liquidated Long', domain decode succeeds")
            func liquidationFixture() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_liquidation")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let fills = try await client.userFills(for: p2testAddress)

                #expect(fills.count == 1)
                let fill = try #require(fills.first)
                // Direction is the verbatim wire string — decision logged in decisions.md
                #expect(fill.direction == "Liquidated Long")
                // Liquidations have negative closedPnL
                #expect(fill.closedPnL < 0)
                // wire side "A" → .sell (liquidation of a long is a sell)
                #expect(fill.side == .sell)
            }

            @Test("large_decimals fixture: high-precision money fields decoded without loss")
            func largeDecimalsFixture() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_large_decimals")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let fills = try await client.userFills(for: p2testAddress)

                #expect(fills.count == 1)
                let fill = try #require(fills.first)
                #expect(fill.price == Decimal(string: "99999.999999999"))
                #expect(fill.size == Decimal(string: "0.123456789"))
                #expect(fill.fee == Decimal(string: "0.061728395"))
                #expect(fill.closedPnL == Decimal(string: "1234.567890123"))
            }

            @Test("over_cap fixture (250 entries) is clamped to userFillsCap (200)")
            func overCapFixtureIsClamped() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_over_cap")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let fills = try await client.userFills(for: p2testAddress)

                #expect(fills.count == URLSessionHyperliquidClient.userFillsCap)
                // Cap constant must be 200 per architecture §17 and decisions.md
                #expect(URLSessionHyperliquidClient.userFillsCap == 200)
            }

            @Test("over_cap: first 200 entries in API order are preserved (no client-side sort)")
            func overCapPreservesApiOrder() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_over_cap")
                StubURLProtocol.handler = p2stubResponse(data: data)
                let client = p2makeClient(session: session)

                let fills = try await client.userFills(for: p2testAddress)

                // The fixture generates fills with tid = 9100000000 + i (0-based),
                // so the first 200 entries have tids 9100000000 through 9100000199.
                // The client must not re-sort — transport layer is sort-agnostic (§17.3).
                #expect(fills.first?.tid == 9_100_000_000)
                #expect(fills.last?.tid == 9_100_000_199)
            }
        }

        // -------------------------------------------------------------------------
        // MARK: openOrders — transport / request shape
        // -------------------------------------------------------------------------

        @Suite("openOrders — request shape")
        struct OpenOrdersRequestShapeTests {

            @Test("openOrders sends POST to https://api.hyperliquid.xyz/info")
            func sendsPostToInfoEndpoint() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_empty")
                var capturedRequest: URLRequest?
                StubURLProtocol.handler = { request in
                    capturedRequest = request
                    return p2stubResponse(data: data)(request)
                }
                let client = p2makeClient(session: session)
                _ = try await client.openOrders(for: p2testAddress)

                let req = try #require(capturedRequest)
                #expect(req.httpMethod == "POST")
                #expect(req.url?.absoluteString == "https://api.hyperliquid.xyz/info")
            }

            @Test("openOrders sets Content-Type: application/json")
            func setsContentTypeHeader() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_empty")
                var capturedRequest: URLRequest?
                StubURLProtocol.handler = { request in
                    capturedRequest = request
                    return p2stubResponse(data: data)(request)
                }
                let client = p2makeClient(session: session)
                _ = try await client.openOrders(for: p2testAddress)

                let req = try #require(capturedRequest)
                #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
            }

            @Test("openOrders body is {\"type\":\"openOrders\",\"user\":\"<lowercase address>\"}")
            func bodyHasCorrectShape() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_empty")
                var capturedBody: [String: String]?
                StubURLProtocol.handler = { request in
                    let bodyData = StubURLProtocol.bodyData(for: request)
                    if !bodyData.isEmpty {
                        capturedBody = try? JSONDecoder().decode([String: String].self, from: bodyData)
                    }
                    return p2stubResponse(data: data)(request)
                }
                let client = p2makeClient(session: session)
                _ = try await client.openOrders(for: p2testAddress)

                let body = try #require(capturedBody)
                #expect(body["type"] == "openOrders")
                #expect(body["user"] == p2testAddress.rawValue)
            }
        }

        // -------------------------------------------------------------------------
        // MARK: userFills — transport / request shape
        // -------------------------------------------------------------------------

        @Suite("userFills — request shape")
        struct UserFillsRequestShapeTests {

            @Test("userFills sends POST to https://api.hyperliquid.xyz/info")
            func sendsPostToInfoEndpoint() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_empty")
                var capturedRequest: URLRequest?
                StubURLProtocol.handler = { request in
                    capturedRequest = request
                    return p2stubResponse(data: data)(request)
                }
                let client = p2makeClient(session: session)
                _ = try await client.userFills(for: p2testAddress)

                let req = try #require(capturedRequest)
                #expect(req.httpMethod == "POST")
                #expect(req.url?.absoluteString == "https://api.hyperliquid.xyz/info")
            }

            @Test("userFills sets Content-Type: application/json")
            func setsContentTypeHeader() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_empty")
                var capturedRequest: URLRequest?
                StubURLProtocol.handler = { request in
                    capturedRequest = request
                    return p2stubResponse(data: data)(request)
                }
                let client = p2makeClient(session: session)
                _ = try await client.userFills(for: p2testAddress)

                let req = try #require(capturedRequest)
                #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
            }

            @Test("userFills body is {\"type\":\"userFills\",\"user\":\"<lowercase address>\"}")
            func bodyHasCorrectShape() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_empty")
                var capturedBody: [String: String]?
                StubURLProtocol.handler = { request in
                    let bodyData = StubURLProtocol.bodyData(for: request)
                    if !bodyData.isEmpty {
                        capturedBody = try? JSONDecoder().decode([String: String].self, from: bodyData)
                    }
                    return p2stubResponse(data: data)(request)
                }
                let client = p2makeClient(session: session)
                _ = try await client.userFills(for: p2testAddress)

                let body = try #require(capturedBody)
                #expect(body["type"] == "userFills")
                #expect(body["user"] == p2testAddress.rawValue)
            }
        }

        // -------------------------------------------------------------------------
        // MARK: Error mapping — openOrders and userFills (same harness as Phase 1)
        // -------------------------------------------------------------------------

        @Suite("Phase 2 endpoints — error mapping")
        struct Phase2ErrorMappingTests {

            // openOrders error paths

            @Test("openOrders: HTTP 500 throws HyperliquidError.httpStatus(500)")
            func openOrders500ThrowsHTTPStatus() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("openOrders_empty")
                StubURLProtocol.handler = p2stubResponse(data: data, statusCode: 500)
                let client = p2makeClient(session: session)

                do {
                    _ = try await client.openOrders(for: p2testAddress)
                    Issue.record("Expected throw but got success")
                } catch let err as HyperliquidError {
                    guard case .httpStatus(let code) = err else {
                        Issue.record("Expected .httpStatus but got: \(err)")
                        return
                    }
                    #expect(code == 500)
                }
            }

            @Test("openOrders: offline throws HyperliquidError.offline")
            func openOrdersOfflineThrowsOffline() async {
                let session = StubURLProtocol.makeSession()
                StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
                let client = p2makeClient(session: session)

                do {
                    _ = try await client.openOrders(for: p2testAddress)
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

            @Test("openOrders: timeout throws HyperliquidError.timeout")
            func openOrdersTimeoutThrowsTimeout() async {
                let session = StubURLProtocol.makeSession()
                StubURLProtocol.handler = { _ in .failure(URLError(.timedOut)) }
                let client = p2makeClient(session: session)

                do {
                    _ = try await client.openOrders(for: p2testAddress)
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

            @Test("openOrders: HTTP 200 with malformed JSON throws HyperliquidError.decoding")
            func openOrdersMalformedJSONThrowsDecoding() async throws {
                let session = StubURLProtocol.makeSession()
                let malformedData = Data("{not valid json}".utf8)
                StubURLProtocol.handler = p2stubResponse(data: malformedData, statusCode: 200)
                let client = p2makeClient(session: session)

                do {
                    _ = try await client.openOrders(for: p2testAddress)
                    Issue.record("Expected throw but got success")
                } catch let err as HyperliquidError {
                    guard case .decoding = err else {
                        Issue.record("Expected .decoding but got: \(err)")
                        return
                    }
                }
            }

            // userFills error paths

            @Test("userFills: HTTP 500 throws HyperliquidError.httpStatus(500)")
            func userFills500ThrowsHTTPStatus() async throws {
                let session = StubURLProtocol.makeSession()
                let data = try FixtureLoader.load("userFills_empty")
                StubURLProtocol.handler = p2stubResponse(data: data, statusCode: 500)
                let client = p2makeClient(session: session)

                do {
                    _ = try await client.userFills(for: p2testAddress)
                    Issue.record("Expected throw but got success")
                } catch let err as HyperliquidError {
                    guard case .httpStatus(let code) = err else {
                        Issue.record("Expected .httpStatus but got: \(err)")
                        return
                    }
                    #expect(code == 500)
                }
            }

            @Test("userFills: offline throws HyperliquidError.offline")
            func userFillsOfflineThrowsOffline() async {
                let session = StubURLProtocol.makeSession()
                StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
                let client = p2makeClient(session: session)

                do {
                    _ = try await client.userFills(for: p2testAddress)
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

            @Test("userFills: timeout throws HyperliquidError.timeout")
            func userFillsTimeoutThrowsTimeout() async {
                let session = StubURLProtocol.makeSession()
                StubURLProtocol.handler = { _ in .failure(URLError(.timedOut)) }
                let client = p2makeClient(session: session)

                do {
                    _ = try await client.userFills(for: p2testAddress)
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

            @Test("userFills: HTTP 200 with malformed JSON throws HyperliquidError.decoding")
            func userFillsMalformedJSONThrowsDecoding() async throws {
                let session = StubURLProtocol.makeSession()
                let malformedData = Data("{not valid json}".utf8)
                StubURLProtocol.handler = p2stubResponse(data: malformedData, statusCode: 200)
                let client = p2makeClient(session: session)

                do {
                    _ = try await client.userFills(for: p2testAddress)
                    Issue.record("Expected throw but got success")
                } catch let err as HyperliquidError {
                    guard case .decoding = err else {
                        Issue.record("Expected .decoding but got: \(err)")
                        return
                    }
                }
            }

            @Test("userFills: HTTP 422 throws HyperliquidError.httpStatus(422)")
            func userFills422ThrowsHTTPStatus() async throws {
                let session = StubURLProtocol.makeSession()
                let data = Data("".utf8)
                StubURLProtocol.handler = p2stubResponse(data: data, statusCode: 422)
                let client = p2makeClient(session: session)

                do {
                    _ = try await client.userFills(for: p2testAddress)
                    Issue.record("Expected throw but got success")
                } catch let err as HyperliquidError {
                    guard case .httpStatus(let code) = err else {
                        Issue.record("Expected .httpStatus but got: \(err)")
                        return
                    }
                    #expect(code == 422)
                }
            }
        }
    }  // end Phase2ClientTests
}  // end extension URLSessionClientTests
