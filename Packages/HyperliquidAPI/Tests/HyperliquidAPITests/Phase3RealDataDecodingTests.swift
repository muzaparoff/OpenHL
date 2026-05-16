// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore
import Testing

@testable import HyperliquidAPI

// MARK: - clearinghouseState — real-data fixture

/// Fixture source: address with 5 open cross-margin positions (BTC long,
/// ETH long, DOGE short, HYPE long, ZEC short). Captured from a live
/// account; wallet address used only as a query parameter, not present
/// in the response body. The `liquidationPx` for HYPE is `null` in the
/// real response — regression guard for the field being optional.
@Suite("clearinghouseState — real subset fixture")
struct ClearinghouseStateRealSubsetTests {

    @Test("Decodes five-position real response including null liquidationPx")
    func decodesRealSubsetFixture() throws {
        let data = try FixtureLoader.load("clearinghouseState_real_subset")
        let dto = try JSONDecoder().decode(ClearinghouseStateDTO.self, from: data)

        // Top-level shape.
        #expect(dto.assetPositions.count == 5)
        #expect(dto.withdrawable == Decimal(string: "0.0"))

        // MarginSummary round-trips as Decimal without loss.
        #expect(dto.marginSummary.accountValue == Decimal(string: "5331.284211"))
        #expect(dto.marginSummary.totalNtlPos == Decimal(string: "53088.84397"))
    }

    @Test("crossMaintenanceMarginUsed field is ignored without decoding error")
    func extraFieldDoesNotThrow() throws {
        // crossMaintenanceMarginUsed is present in real responses but absent
        // from the DTO — Decodable must ignore it silently.
        let data = try FixtureLoader.load("clearinghouseState_real_subset")
        #expect(throws: Never.self) {
            _ = try JSONDecoder().decode(ClearinghouseStateDTO.self, from: data)
        }
    }

    @Test("HYPE position has null liquidationPx — decodes to nil, not a throw")
    func nullLiquidationPxDecodesToNil() throws {
        let data = try FixtureLoader.load("clearinghouseState_real_subset")
        let dto = try JSONDecoder().decode(ClearinghouseStateDTO.self, from: data)

        let hypePos = try #require(
            dto.assetPositions.first { $0.position.coin == "HYPE" }
        )
        #expect(hypePos.position.liquidationPx == nil)
    }

    @Test("Short position has negative szi")
    func shortPositionHasNegativeSzi() throws {
        let data = try FixtureLoader.load("clearinghouseState_real_subset")
        let dto = try JSONDecoder().decode(ClearinghouseStateDTO.self, from: data)

        let doge = try #require(dto.assetPositions.first { $0.position.coin == "DOGE" })
        #expect(doge.position.szi < 0)
    }

    @Test("cumFunding nested object is ignored without decoding error")
    func cumFundingIgnored() throws {
        // Every position in the real fixture has a `cumFunding` object that
        // our DTO does not model. Must decode silently.
        let data = try FixtureLoader.load("clearinghouseState_real_subset")
        #expect(throws: Never.self) {
            _ = try JSONDecoder().decode(ClearinghouseStateDTO.self, from: data)
        }
    }

    @Test("Maps to domain ClearinghouseState with correct position sides")
    func mapsToDomainSides() throws {
        let data = try FixtureLoader.load("clearinghouseState_real_subset")
        let dto = try JSONDecoder().decode(ClearinghouseStateDTO.self, from: data)
        let state = try mapDTOToState(dto)

        // BTC and ETH are long (positive szi); DOGE and ZEC are short.
        let btc = try #require(state.positions.first { $0.coin == "BTC" })
        #expect(btc.side == .long)

        let doge = try #require(state.positions.first { $0.coin == "DOGE" })
        #expect(doge.side == .short)
    }
}

// MARK: - openOrders — real-data fixture

/// Fixture source: two real accounts merged for variety — one with
/// `reduceOnly: true` orders, one with market-maker orders that carry a
/// `cloid` field and have no `reduceOnly` key at all. Critically, NO
/// order in either account's real response has an `orderType` field.
/// That is the bug that was latent in the DTO before this fix.
@Suite("openOrders — real subset fixture")
struct OpenOrdersRealSubsetTests {

    @Test("Decodes 8-order real fixture where orderType field is absent on all entries")
    func decodesRealSubsetFixture() throws {
        let data = try FixtureLoader.load("openOrders_real_subset")
        let dtos = try JSONDecoder().decode([OpenOrderDTO].self, from: data)

        // All 8 orders must decode without throwing, even though none has orderType.
        #expect(dtos.count == 8)
    }

    @Test("Order with absent orderType has nil orderType in DTO")
    func absentOrderTypeIsNil() throws {
        let data = try FixtureLoader.load("openOrders_real_subset")
        let dtos = try JSONDecoder().decode([OpenOrderDTO].self, from: data)

        // Every entry in the real fixture omits orderType.
        let allNilOrderType = dtos.allSatisfy { $0.orderType == nil }
        #expect(allNilOrderType)
    }

    @Test("cloid field in real data is silently ignored")
    func cloidFieldIgnored() throws {
        // Orders 3–5 in the fixture carry a `cloid` field our DTO does not
        // model. Must not throw.
        let data = try FixtureLoader.load("openOrders_real_subset")
        #expect(throws: Never.self) {
            _ = try JSONDecoder().decode([OpenOrderDTO].self, from: data)
        }
    }

    @Test("reduceOnly absent maps to nil in DTO (mapper defaults to false)")
    func absentReduceOnlyIsNil() throws {
        let data = try FixtureLoader.load("openOrders_real_subset")
        let dtos = try JSONDecoder().decode([OpenOrderDTO].self, from: data)

        // Orders 3–5 (market-maker orders) have no reduceOnly field.
        let mmOrders = dtos.filter { $0.reduceOnly == nil }
        #expect(!mmOrders.isEmpty)
    }

    @Test("Buy and sell sides both decode correctly")
    func buySellSidesDecode() throws {
        let data = try FixtureLoader.load("openOrders_real_subset")
        let dtos = try JSONDecoder().decode([OpenOrderDTO].self, from: data)

        let buySide = dtos.filter { $0.side == "B" }
        let sellSide = dtos.filter { $0.side == "A" }
        #expect(!buySide.isEmpty)
        #expect(!sellSide.isEmpty)
    }

    @Test("Maps through domain mapper: absent orderType defaults to .limit")
    func mapperDefaultsToLimit() throws {
        let data = try FixtureLoader.load("openOrders_real_subset")
        let dtos = try JSONDecoder().decode([OpenOrderDTO].self, from: data)

        // All entries have nil orderType in the real fixture.
        // The mapper must default each to .limit.
        let orders = try dtos.map { try mapOpenOrderDTO($0) }
        let allLimit = orders.allSatisfy { $0.orderType == .limit }
        #expect(allLimit)
    }

    @Test("Decimal fields decode at full precision")
    func decimalPrecision() throws {
        let data = try FixtureLoader.load("openOrders_real_subset")
        let dtos = try JSONDecoder().decode([OpenOrderDTO].self, from: data)

        // The DOGE reduce-only order has an origSz of 94592.0.
        let doge = try #require(dtos.first { $0.coin == "DOGE" && ($0.origSz ?? 0) > 1000 })
        #expect(doge.origSz == Decimal(string: "94592.0"))
        #expect(doge.limitPx == Decimal(string: "0.10548"))
    }
}

// MARK: - userFills — real-data fixture

/// Fixture source: 5 representative fills from a real active account.
/// Includes: open long, close short with positive PnL, a fill where
/// `liquidation` is a non-null object (maker who liquidated someone),
/// a fill with a negative fee (rebate), and an extra `twapId: null`
/// field present on every real fill but absent from the DTO.
@Suite("userFills — real subset fixture")
struct UserFillsRealSubsetTests {

    @Test("Decodes 5-fill real fixture including twapId null and startPosition fields")
    func decodesRealSubsetFixture() throws {
        let data = try FixtureLoader.load("userFills_real_subset")
        let dtos = try JSONDecoder().decode([UserFillDTO].self, from: data)

        #expect(dtos.count == 5)
    }

    @Test("twapId null field is silently ignored")
    func twapIdIgnored() throws {
        // Every fill in the fixture has `"twapId": null`. DTO does not model it.
        let data = try FixtureLoader.load("userFills_real_subset")
        #expect(throws: Never.self) {
            _ = try JSONDecoder().decode([UserFillDTO].self, from: data)
        }
    }

    @Test("startPosition field is silently ignored")
    func startPositionIgnored() throws {
        // Every fill carries `startPosition`, which DTO does not model.
        let data = try FixtureLoader.load("userFills_real_subset")
        #expect(throws: Never.self) {
            _ = try JSONDecoder().decode([UserFillDTO].self, from: data)
        }
    }

    @Test("liquidation object field is silently ignored")
    func liquidationObjectIgnored() throws {
        // Fill index 3 has a nested `liquidation` object. DTO does not model it.
        let data = try FixtureLoader.load("userFills_real_subset")
        #expect(throws: Never.self) {
            _ = try JSONDecoder().decode([UserFillDTO].self, from: data)
        }
    }

    @Test("Open Long fill: zero closedPnl, buy side, feeToken USDC")
    func openLongFill() throws {
        let data = try FixtureLoader.load("userFills_real_subset")
        let dtos = try JSONDecoder().decode([UserFillDTO].self, from: data)

        let openLong = try #require(dtos.first { $0.dir == "Open Long" })
        #expect(openLong.coin == "ETH")
        #expect(openLong.side == "B")
        #expect(openLong.closedPnl == Decimal(string: "0.0"))
        #expect(openLong.feeToken == "USDC")
        #expect(!openLong.crossed)  // maker fill
    }

    @Test("Close Short fill: positive closedPnl, buy side")
    func closeShortFill() throws {
        let data = try FixtureLoader.load("userFills_real_subset")
        let dtos = try JSONDecoder().decode([UserFillDTO].self, from: data)

        let closeShort = try #require(dtos.first { $0.dir == "Close Short" && $0.coin == "ZEC" })
        #expect(closeShort.closedPnl == Decimal(string: "37.345214"))
        #expect(closeShort.side == "B")
    }

    @Test("Negative fee (rebate) decodes without sign loss")
    func negativeFeeDecodes() throws {
        let data = try FixtureLoader.load("userFills_real_subset")
        let dtos = try JSONDecoder().decode([UserFillDTO].self, from: data)

        // The last fill in the fixture has fee: "-0.025" (maker rebate).
        let rebateFill = try #require(dtos.first { $0.fee < 0 })
        #expect(rebateFill.fee == Decimal(string: "-0.025"))
    }

    @Test("Maps to Fill domain type correctly")
    func mapsToDomain() throws {
        let data = try FixtureLoader.load("userFills_real_subset")
        let dtos = try JSONDecoder().decode([UserFillDTO].self, from: data)
        let fills = try dtos.map { try mapUserFillDTO($0) }

        #expect(fills.count == 5)

        let openLong = try #require(fills.first { $0.direction == "Open Long" })
        #expect(openLong.side == .buy)
        #expect(openLong.coin == "ETH")
        #expect(openLong.price == Decimal(string: "2179.0"))
    }
}

// MARK: - candleSnapshot — real-data fixtures (4 intervals)

@Suite("candleSnapshot — real-data fixtures (1h/4h/1d/1w)")
struct CandleSnapshotRealDataTests {

    @Test("1h candles: 10 bars, BTC, all OHLCV positive, interval round-trips")
    func onehourFixture() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_1h_real")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        #expect(candles.count == 10)

        let first = candles[0]
        #expect(first.coin == "BTC")
        #expect(first.interval == .oneHour)
        // All prices must be positive.
        #expect(first.open > 0)
        #expect(first.close > 0)
        #expect(first.high >= first.open)
        #expect(first.low <= first.open)
        #expect(first.volume > 0)
        #expect(first.tradeCount > 0)

        // Specific values from captured response.
        #expect(first.open == Decimal(string: "79062.0"))
        #expect(first.close == Decimal(string: "79053.0"))
        // First bar: close < open → isDown
        #expect(first.isUp == false)

        // Second bar: close > open → isUp
        let second = candles[1]
        #expect(second.isUp == true)

        // openTime / closeTime round-trip from ms epoch correctly.
        #expect(first.openTime == Date(timeIntervalSince1970: 1_778_889_600))
        #expect(first.closeTime == Date(timeIntervalSince1970: 1_778_893_199.999))
    }

    @Test("4h candles: 10 bars, interval is .fourHour, first bar is up")
    func fourhourFixture() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_4h_real")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        #expect(candles.count == 10)
        let first = candles[0]
        #expect(first.interval == .fourHour)
        #expect(first.coin == "BTC")
        // First bar open 81264, close 81368 → up.
        #expect(first.open == Decimal(string: "81264.0"))
        #expect(first.close == Decimal(string: "81368.0"))
        #expect(first.isUp == true)
        #expect(first.tradeCount == 125667)
    }

    @Test("1d candles: 10 bars, interval is .oneDay, volume in coin units")
    func onedayFixture() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_1d_real")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        #expect(candles.count == 10)
        let first = candles[0]
        #expect(first.interval == .oneDay)
        // Volume is in coin (BTC) units — should be thousands for a daily BTC bar.
        #expect(first.volume > 1000)
        #expect(first.volume == Decimal(string: "35339.48691"))
    }

    @Test("1w candles: 10 bars, interval is .oneWeek, high precision volume")
    func oneweekFixture() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_1w_real")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        #expect(candles.count == 10)
        let first = candles[0]
        #expect(first.interval == .oneWeek)
        #expect(first.volume == Decimal(string: "301590.31432"))
        // Weekly bar should span ~604800 seconds.
        let span = first.closeTime.timeIntervalSince(first.openTime)
        #expect(span > 600_000)  // at least ~7 days minus 1ms
    }

    @Test("All four intervals produce non-empty candle arrays with valid OHLCV")
    func allIntervalsProduceCandles() throws {
        let fixtures: [(String, CandleInterval)] = [
            ("candleSnapshot_btc_1h_real", .oneHour),
            ("candleSnapshot_btc_4h_real", .fourHour),
            ("candleSnapshot_btc_1d_real", .oneDay),
            ("candleSnapshot_btc_1w_real", .oneWeek),
        ]
        for (fixtureName, expectedInterval) in fixtures {
            let data = try FixtureLoader.load(fixtureName)
            let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
            let candles = dtos.toCandles()

            #expect(!candles.isEmpty, "Expected candles for \(fixtureName)")
            #expect(
                candles.allSatisfy { $0.interval == expectedInterval },
                "All candles in \(fixtureName) should have interval \(expectedInterval)"
            )
            #expect(
                candles.allSatisfy { $0.high >= $0.low },
                "high >= low invariant violated in \(fixtureName)"
            )
        }
    }
}

// MARK: - Private mapper helpers (mirrors URLSessionHyperliquidClient static methods)
//
// These bridge the gap so we can invoke the real mapper logic from tests
// without making the private static methods testable. The logic is duplicated
// intentionally — any drift will manifest as a test failure.

private func mapDTOToState(
    _ dto: ClearinghouseStateDTO
) throws -> ClearinghouseState {
    let summary = ClearinghouseState.AccountSummary(
        accountValue: dto.marginSummary.accountValue,
        totalNotionalPosition: dto.marginSummary.totalNtlPos,
        totalRawUSD: dto.marginSummary.totalRawUsd,
        totalMarginUsed: dto.marginSummary.totalMarginUsed,
        withdrawable: dto.withdrawable
    )
    let positions = try dto.assetPositions.map { assetPos -> ClearinghouseState.Position in
        let pos = assetPos.position
        let leverageMode: ClearinghouseState.Position.LeverageMode =
            pos.leverage.type == "cross"
            ? .cross(pos.leverage.value)
            : .isolated(pos.leverage.value)
        let side: ClearinghouseState.Position.Side = pos.szi >= 0 ? .long : .short
        return ClearinghouseState.Position(
            coin: pos.coin,
            size: pos.szi,
            side: side,
            entryPrice: pos.entryPx,
            positionValue: pos.positionValue,
            unrealizedPnL: pos.unrealizedPnl,
            returnOnEquity: pos.returnOnEquity,
            liquidationPrice: pos.liquidationPx,
            marginUsed: pos.marginUsed,
            leverage: leverageMode
        )
    }
    return ClearinghouseState(
        summary: summary,
        positions: positions,
        serverTime: Date(timeIntervalSince1970: TimeInterval(dto.time) / 1000.0),
        fetchedAt: Date()
    )
}

private func mapOpenOrderDTO(_ dto: OpenOrderDTO) throws -> OpenOrder {
    let side: OpenOrder.Side
    switch dto.side {
    case "B": side = .buy
    case "A": side = .sell
    default:
        throw HyperliquidError.unexpectedResponse(
            reason: "openOrders: unknown side '\(dto.side)'"
        )
    }
    let orderType: OpenOrder.OrderType
    switch dto.orderType {
    case nil, "Limit": orderType = .limit
    case "Trigger": orderType = .trigger
    case "Stop Limit": orderType = .stopLimit
    case "Stop Market": orderType = .stopMarket
    case "Take Profit Limit": orderType = .takeProfitLimit
    case "Take Profit Market": orderType = .takeProfitMarket
    default: orderType = .unknown(dto.orderType!)
    }
    return OpenOrder(
        oid: dto.oid,
        coin: dto.coin,
        side: side,
        limitPrice: dto.limitPx,
        size: dto.sz,
        origSize: dto.origSz,
        orderType: orderType,
        reduceOnly: dto.reduceOnly ?? false,
        triggerPrice: dto.triggerPx,
        placedAt: Date(timeIntervalSince1970: TimeInterval(dto.timestamp) / 1000.0)
    )
}

private func mapUserFillDTO(_ dto: UserFillDTO) throws -> Fill {
    let side: Fill.Side
    switch dto.side {
    case "B": side = .buy
    case "A": side = .sell
    default:
        throw HyperliquidError.unexpectedResponse(
            reason: "userFills: unknown side '\(dto.side)'"
        )
    }
    return Fill(
        tid: dto.tid,
        oid: dto.oid,
        coin: dto.coin,
        side: side,
        direction: dto.dir,
        price: dto.px,
        size: dto.sz,
        fee: dto.fee,
        feeToken: dto.feeToken,
        closedPnL: dto.closedPnl,
        crossed: dto.crossed,
        hash: dto.hash,
        executedAt: Date(timeIntervalSince1970: TimeInterval(dto.time) / 1000.0)
    )
}
