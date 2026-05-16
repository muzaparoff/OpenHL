// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore
import Testing

@testable import HyperliquidAPI

// MARK: - metaAndAssetCtxs tests

@Suite("metaAndAssetCtxs — real-data fixture")
struct MetaAndAssetCtxsDecodingTests {

    @Test("Decodes 15-entry trimmed real response (active + delisted perps)")
    func decodesTrimmedRealFixture() throws {
        let data = try FixtureLoader.load("metaAndAssetCtxs_real_subset")
        let dto = try JSONDecoder().decode(MetaAndAssetCtxsDTO.self, from: data)

        // 15 entries total = 10 active + 5 delisted (null premium)
        #expect(dto.meta.universe.count == 15)
        #expect(dto.assetCtxs.count == 15)

        let markets = dto.toMarkets()
        #expect(markets.count == 15)

        // BTC: active perp, all fields populated.
        let btc = try #require(markets.first { $0.coin == "BTC" })
        #expect(btc.markPrice > 0)
        #expect(btc.prevDayPrice > 0)
        #expect(btc.dayNotionalVolume > 0)

        // MATIC: delisted, has null premium and null midPx. Must still
        // decode and produce a usable Market (this is the regression the
        // user hit in the live simulator).
        let matic = try #require(markets.first { $0.coin == "MATIC" })
        #expect(matic.midPrice == nil)
    }

    @Test("Universe entries with isDelisted flag still decode")
    func delistedFlagDoesNotBreak() throws {
        // marginTableId, isDelisted, marginMode and similar extra keys
        // must be ignored by the decoder.
        let raw = """
            [
              {
                "universe": [
                  {"name":"BTC","szDecimals":5,"maxLeverage":40,"marginTableId":56},
                  {"name":"OLD","szDecimals":2,"maxLeverage":3,"marginTableId":1,"isDelisted":true,"marginMode":"isolated"}
                ],
                "marginTables": [],
                "collateralToken": 0
              },
              [
                {"funding":"0.0001","openInterest":"100","prevDayPx":"80000","markPx":"81000","midPx":"81000","oraclePx":"81000","premium":"0","dayNtlVlm":"1000"},
                {"funding":"0","openInterest":"0","prevDayPx":"1","markPx":"0.5","midPx":null,"oraclePx":null,"premium":null,"dayNtlVlm":"0"}
              ]
            ]
            """
        let data = Data(raw.utf8)
        let dto = try JSONDecoder().decode(MetaAndAssetCtxsDTO.self, from: data)
        let markets = dto.toMarkets()
        #expect(markets.count == 2)
        #expect(markets[0].coin == "BTC")
        #expect(markets[1].coin == "OLD")
        #expect(markets[1].midPrice == nil)
    }
}

// MARK: - candleSnapshot tests

@Suite("candleSnapshot — decoder + request shape")
struct CandleSnapshotDecodingTests {

    @Test("Decodes fixture into Candle domain values, in API order")
    func decodesFixture() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_1h")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        #expect(candles.count == 3)

        let first = candles[0]
        #expect(first.coin == "BTC")
        #expect(first.interval == .oneHour)
        #expect(first.open == Decimal(string: "61500.0"))
        #expect(first.close == Decimal(string: "61750.5"))
        #expect(first.high == Decimal(string: "61820.0"))
        #expect(first.low == Decimal(string: "61410.0"))
        #expect(first.volume == Decimal(string: "120.5"))
        #expect(first.tradeCount == 842)
        #expect(first.isUp == true)

        let second = candles[1]
        #expect(second.isUp == false)  // 61750.5 → 61620.25 = down

        // openTime: 1715760000000 ms = 2024-05-15 08:00:00 UTC
        #expect(first.openTime == Date(timeIntervalSince1970: 1_715_760_000))
        #expect(first.closeTime == Date(timeIntervalSince1970: 1_715_763_600))
    }

    @Test("Unknown interval string makes the bar drop (defensive)")
    func unknownIntervalDropsBar() throws {
        let raw = """
            [
              {"t":1715760000000,"T":1715763600000,"s":"BTC","i":"42x",
               "o":"100","c":"101","h":"102","l":"99","v":"1","n":1}
            ]
            """
        let data = Data(raw.utf8)
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()
        #expect(candles.isEmpty)
    }

    @Test("InfoRequest.candleSnapshot encodes the nested req object correctly")
    func requestEncoding() throws {
        let start = Date(timeIntervalSince1970: 1_715_760_000)
        let end = Date(timeIntervalSince1970: 1_715_770_800)
        let req = InfoRequest.candleSnapshot(
            coin: "BTC",
            interval: .oneHour,
            startTime: start,
            endTime: end
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "candleSnapshot")
        let nested = json["req"] as! [String: Any]
        #expect(nested["coin"] as? String == "BTC")
        #expect(nested["interval"] as? String == "1h")
        #expect(nested["startTime"] as? Int == 1_715_760_000_000)
        #expect(nested["endTime"] as? Int == 1_715_770_800_000)
    }
}
