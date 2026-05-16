// SPDX-License-Identifier: MIT

#if DEBUG
    import Foundation
    import HyperliquidAPI
    import OpenHLCore

    /// A fake `HyperliquidClient` for SwiftUI previews and basic manual testing.
    /// Returns hard-coded data with a couple of positions, two orders, and three fills.
    struct PreviewHyperliquidClient: HyperliquidClient {
        var delay: TimeInterval = 0.5
        var shouldFail: Bool = false

        func portfolio(for user: Address) async throws -> Portfolio {
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }
            if shouldFail { throw HyperliquidError.offline }
            return Self.makePreviewPortfolio()
        }

        /// Deterministic-ish portfolio: linear up-trend with a small sinusoidal
        /// wobble so SwiftUI Charts previews show a recognizable curve rather
        /// than a flat or near-flat line. `Int.random` is intentionally avoided
        /// for the up-trend slope so successive preview renders match.
        private static func makePreviewPortfolio() -> Portfolio {
            // Anchor end at a fixed timestamp so previews and snapshot tests
            // don't drift with wall-clock time.
            let end = Date(timeIntervalSince1970: 1_715_774_400)

            func series(
                points: Int,
                stepSeconds: TimeInterval,
                startValue: Double,
                endValue: Double
            ) -> [PortfolioPoint] {
                // Linear interpolation + ~1.5% sine wobble. Visibly a curve
                // without random noise.
                (0..<points).map { i in
                    let t = Double(i) / Double(max(points - 1, 1))
                    let base = startValue + (endValue - startValue) * t
                    let wobble = sin(Double(i) * 0.6) * (startValue * 0.015)
                    let time = end.addingTimeInterval(-Double(points - 1 - i) * stepSeconds)
                    let value = Decimal(base + wobble)
                    return PortfolioPoint(time: time, value: value)
                }
            }

            func pnlSeries(from accountValue: [PortfolioPoint]) -> [PortfolioPoint] {
                guard let first = accountValue.first else { return [] }
                return accountValue.map {
                    PortfolioPoint(time: $0.time, value: $0.value - first.value)
                }
            }

            let day = series(points: 24, stepSeconds: 3_600, startValue: 12_000, endValue: 12_650)
            let week = series(points: 28, stepSeconds: 6 * 3_600, startValue: 11_600, endValue: 12_650)
            let month = series(points: 30, stepSeconds: 86_400, startValue: 10_800, endValue: 12_650)
            let allTime = series(points: 52, stepSeconds: 7 * 86_400, startValue: 5_000, endValue: 12_650)

            return Portfolio(windows: [
                .day: PortfolioSeries(
                    accountValue: day,
                    pnl: pnlSeries(from: day),
                    totalVolume: Decimal(string: "42500.50")!
                ),
                .week: PortfolioSeries(
                    accountValue: week,
                    pnl: pnlSeries(from: week),
                    totalVolume: Decimal(string: "215000.0")!
                ),
                .month: PortfolioSeries(
                    accountValue: month,
                    pnl: pnlSeries(from: month),
                    totalVolume: Decimal(string: "830000.0")!
                ),
                .allTime: PortfolioSeries(
                    accountValue: allTime,
                    pnl: pnlSeries(from: allTime),
                    totalVolume: Decimal(string: "1250000.0")!
                ),
            ])
        }

        func candles(
            coin: String,
            interval: CandleInterval,
            startTime: Date,
            endTime: Date
        ) async throws -> [Candle] {
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            if shouldFail { throw HyperliquidError.offline }
            // Build 48 sample bars stepping back from now at the requested interval.
            let step: TimeInterval
            switch interval {
            case .oneHour: step = 3600
            case .fourHour: step = 14400
            case .oneDay: step = 86400
            case .oneWeek: step = 604_800
            default: step = 3600
            }
            var price = Decimal(string: "61500")!
            let end = endTime
            return (0..<48).reversed().map { i in
                let openTime = end.addingTimeInterval(TimeInterval(-i) * step)
                let drift = Decimal(Int.random(in: -200...220))
                let open = price
                let close = open + drift
                let high = max(open, close) + Decimal(Int.random(in: 30...160))
                let low = min(open, close) - Decimal(Int.random(in: 30...160))
                price = close
                return Candle(
                    coin: coin,
                    interval: interval,
                    openTime: openTime,
                    closeTime: openTime.addingTimeInterval(step),
                    open: open,
                    close: close,
                    high: high,
                    low: low,
                    volume: Decimal(Int.random(in: 100...5000)),
                    tradeCount: Int.random(in: 50...500)
                )
            }
        }

        func markets() async throws -> [Market] {
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            if shouldFail { throw HyperliquidError.offline }
            return [
                Market(
                    coin: "BTC", maxLeverage: 50, szDecimals: 3, onlyIsolated: false,
                    markPrice: Decimal(string: "62401.50")!,
                    midPrice: Decimal(string: "62401.50")!,
                    prevDayPrice: Decimal(string: "61641.00")!,
                    openInterest: Decimal(string: "1234.5")!,
                    dayNotionalVolume: Decimal(string: "830000000")!,
                    fundingRate: Decimal(string: "0.0001")!
                ),
                Market(
                    coin: "ETH", maxLeverage: 50, szDecimals: 4, onlyIsolated: false,
                    markPrice: Decimal(string: "3194.50")!,
                    midPrice: nil,
                    prevDayPrice: Decimal(string: "3210.00")!,
                    openInterest: Decimal(string: "5678.9")!,
                    dayNotionalVolume: Decimal(string: "420000000")!,
                    fundingRate: Decimal(string: "-0.00005")!
                ),
                Market(
                    coin: "SOL", maxLeverage: 50, szDecimals: 2, onlyIsolated: false,
                    markPrice: Decimal(string: "144.30")!,
                    midPrice: Decimal(string: "144.30")!,
                    prevDayPrice: Decimal(string: "145.55")!,
                    openInterest: Decimal(string: "98765.0")!,
                    dayNotionalVolume: Decimal(string: "210000000")!,
                    fundingRate: Decimal(string: "0.00012")!
                ),
            ]
        }

        func openOrders(for user: Address) async throws -> [OpenOrder] {
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }
            if shouldFail { throw HyperliquidError.offline }
            return [
                OpenOrder(
                    oid: 1_000_001,
                    coin: "BTC-USD",
                    side: .buy,
                    limitPrice: Decimal(string: "60000.00")!,
                    size: Decimal(string: "0.1000")!,
                    origSize: nil,
                    orderType: .limit,
                    reduceOnly: false,
                    triggerPrice: nil,
                    placedAt: Date().addingTimeInterval(-180)
                ),
                OpenOrder(
                    oid: 1_000_002,
                    coin: "ETH-USD",
                    side: .sell,
                    limitPrice: Decimal(string: "3100.00")!,
                    size: Decimal(string: "1.0000")!,
                    origSize: Decimal(string: "2.0000")!,
                    orderType: .stopLimit,
                    reduceOnly: true,
                    triggerPrice: Decimal(string: "3050.00")!,
                    placedAt: Date().addingTimeInterval(-720)
                ),
            ]
        }

        func userFills(for user: Address) async throws -> [Fill] {
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }
            if shouldFail { throw HyperliquidError.offline }
            return [
                Fill(
                    tid: 9_000_001,
                    oid: 8_000_001,
                    coin: "BTC-USD",
                    side: .buy,
                    direction: "Open Long",
                    price: Decimal(string: "61800.00")!,
                    size: Decimal(string: "0.1000")!,
                    fee: Decimal(string: "0.42")!,
                    feeToken: "USDC",
                    closedPnL: Decimal(string: "0.0")!,
                    crossed: true,
                    hash: "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab",
                    executedAt: Date().addingTimeInterval(-30)
                ),
                Fill(
                    tid: 9_000_002,
                    oid: 8_000_002,
                    coin: "ETH-USD",
                    side: .buy,
                    direction: "Close Short",
                    price: Decimal(string: "3194.50")!,
                    size: Decimal(string: "2.0000")!,
                    fee: Decimal(string: "1.28")!,
                    feeToken: "USDC",
                    closedPnL: Decimal(string: "31.00")!,
                    crossed: false,
                    hash: "0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fe",
                    executedAt: Date().addingTimeInterval(-240)
                ),
                Fill(
                    tid: 9_000_003,
                    oid: 8_000_003,
                    coin: "BTC-USD",
                    side: .sell,
                    direction: "Close Long",
                    price: Decimal(string: "62100.00")!,
                    size: Decimal(string: "0.0500")!,
                    fee: Decimal(string: "0.16")!,
                    feeToken: "USDC",
                    closedPnL: Decimal(string: "-150.00")!,
                    crossed: true,
                    hash: "0x1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd12",
                    executedAt: Date().addingTimeInterval(-10800)
                ),
            ]
        }

        func clearinghouseState(for user: Address) async throws -> ClearinghouseState {
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }
            if shouldFail {
                throw HyperliquidError.offline
            }
            return ClearinghouseState(
                summary: ClearinghouseState.AccountSummary(
                    accountValue: Decimal(string: "12453.21")!,
                    totalNotionalPosition: Decimal(string: "9800.00")!,
                    totalRawUSD: Decimal(string: "12000.00")!,
                    totalMarginUsed: Decimal(string: "4201.10")!,
                    withdrawable: Decimal(string: "8252.11")!
                ),
                positions: [
                    ClearinghouseState.Position(
                        coin: "BTC",
                        size: Decimal(string: "0.5")!,
                        side: .long,
                        entryPrice: Decimal(string: "62400.00")!,
                        positionValue: Decimal(string: "30590.00")!,
                        unrealizedPnL: Decimal(string: "-610.00")!,
                        returnOnEquity: Decimal(string: "-0.0098")!,
                        liquidationPrice: Decimal(string: "58200.00")!,
                        marginUsed: Decimal(string: "2100.00")!,
                        leverage: .cross(10)
                    ),
                    ClearinghouseState.Position(
                        coin: "ETH",
                        size: Decimal(string: "-2.0")!,
                        side: .short,
                        entryPrice: Decimal(string: "3210.00")!,
                        positionValue: Decimal(string: "6389.00")!,
                        unrealizedPnL: Decimal(string: "31.00")!,
                        returnOnEquity: Decimal(string: "0.0048")!,
                        liquidationPrice: Decimal(string: "3480.00")!,
                        marginUsed: Decimal(string: "1100.00")!,
                        leverage: .cross(5)
                    ),
                    ClearinghouseState.Position(
                        coin: "SOL",
                        size: Decimal(string: "10.0")!,
                        side: .long,
                        entryPrice: Decimal(string: "142.80")!,
                        positionValue: Decimal(string: "1430.00")!,
                        unrealizedPnL: Decimal(string: "15.00")!,
                        returnOnEquity: Decimal(string: "0.0105")!,
                        liquidationPrice: nil,
                        marginUsed: Decimal(string: "144.30")!,
                        leverage: .isolated(5)
                    ),
                ],
                serverTime: Date(),
                fetchedAt: Date()
            )
        }
    }
#endif
