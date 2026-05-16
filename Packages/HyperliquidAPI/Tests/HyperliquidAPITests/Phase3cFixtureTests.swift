// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import HyperliquidAPI

/// Regression guard: the `.oneDay` and `.oneWeek` granularities used by Phase 3c's
/// "1M", "1y", and "1W" picker entries must decode correctly against real
/// captured Hyperliquid responses.
///
/// Architecture §23.8: "the wire format does not change for 1d / 1w; the
/// existing real-data fixtures already exercise the decoder. No new wire-format
/// fixture is strictly necessary." These tests assert that the decoder path used
/// by the *new* picker entries (oneMonth / oneYear / oneWeek) produces valid
/// candles from the existing fixtures.

@Suite("Phase 3c — fixture regression for 1D/1W presets")
struct Phase3cFixtureTests {

    // MARK: - 1D fixture: covers "1M" and "1y" presets

    /// The "1M" (30 days) and "1y" (365 days) picker presets both request
    /// `.oneDay` bars from Hyperliquid. The wire format is identical — only
    /// the time window differs. This test asserts the decoder produces at
    /// least 10 bars with `.oneDay` interval from the captured fixture.
    @Test("1D real fixture: at least 10 bars, all interval == .oneDay")
    func oneDayFixtureBarsDecodeForOneMAndOneY() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_1d_real")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        #expect(
            candles.count >= 10,
            "Expected at least 10 1d bars in fixture (covers 1M/1y picker entries)")
        #expect(
            candles.allSatisfy { $0.interval == .oneDay },
            "All bars from the 1d fixture must have interval .oneDay")
    }

    @Test("1D real fixture: all bars have positive OHLCV and coin == BTC")
    func oneDayFixtureAllBarsValid() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_1d_real")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        for bar in candles {
            #expect(bar.coin == "BTC")
            #expect(bar.open > 0)
            #expect(bar.close > 0)
            #expect(bar.high >= bar.low)
            #expect(bar.volume > 0)
        }
    }

    @Test("1D real fixture: openTime < closeTime on every bar")
    func oneDayFixtureTimeOrderingIsValid() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_1d_real")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        #expect(
            candles.allSatisfy { $0.openTime < $0.closeTime },
            "Each 1d bar must have openTime strictly before closeTime")
    }

    // MARK: - 1W fixture: covers "1W" preset

    /// The "1W" picker preset requests `.oneWeek` bars.
    @Test("1W real fixture: at least 10 bars, all interval == .oneWeek")
    func oneWeekFixtureBarsDecodeForOneWPreset() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_1w_real")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        #expect(
            candles.count >= 10,
            "Expected at least 10 1w bars in fixture (covers 1W picker entry)")
        #expect(
            candles.allSatisfy { $0.interval == .oneWeek },
            "All bars from the 1w fixture must have interval .oneWeek")
    }

    @Test("1W real fixture: all bars have positive OHLCV and coin == BTC")
    func oneWeekFixtureAllBarsValid() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_1w_real")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        for bar in candles {
            #expect(bar.coin == "BTC")
            #expect(bar.open > 0)
            #expect(bar.close > 0)
            #expect(bar.high >= bar.low)
            #expect(bar.volume > 0)
        }
    }

    @Test("1W real fixture: bar spans approximately 7 days (604800s ± 1 day)")
    func oneWeekFixtureBarSpanIsOneWeek() throws {
        let data = try FixtureLoader.load("candleSnapshot_btc_1w_real")
        let dtos = try JSONDecoder().decode([CandleDTO].self, from: data)
        let candles = dtos.toCandles()

        let first = try #require(candles.first)
        let span = first.closeTime.timeIntervalSince(first.openTime)
        // A weekly bar spans ~604800s (7 days). Allow ±1 day for Hyperliquid's
        // close-time fencepost (they use close = openTime + 604800 - 1ms).
        let oneWeekSeconds: TimeInterval = 604_800
        let oneDay: TimeInterval = 86_400
        #expect(span > oneWeekSeconds - oneDay)
        #expect(span < oneWeekSeconds + oneDay)
    }
}
