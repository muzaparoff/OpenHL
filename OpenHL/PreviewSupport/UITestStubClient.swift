// SPDX-License-Identifier: MIT

#if DEBUG
    import Foundation
    import HyperliquidAPI
    import OpenHLCore

    /// A deterministic `HyperliquidClient` injected when the app is launched
    /// with the `OPENHL_UI_TEST_STUB` environment variable set. Bypasses the
    /// network entirely so UI tests can assert against known values without
    /// a live API connection.
    ///
    /// Supported `stubKey` values:
    ///
    /// - `"clearinghouseState_single_long"`: Returns one open BTC long position
    ///   with known numbers that UI tests can assert against (BTC row visible,
    ///   positive PnL, account summary populated). Orders and fills return empty
    ///   arrays.
    ///
    /// - `"openOrders_two_resting"`: Returns two resting open orders (BTC-USD
    ///   limit buy and ETH-USD stop-limit sell). Positions and fills return
    ///   empty/minimal data.
    ///
    /// - `"userFills_recent_three"`: Returns three recent fills (Open Long BTC,
    ///   Close Short ETH, Close Long BTC with negative PnL). Positions and
    ///   orders return empty/minimal data.
    ///
    /// - `"error_offline"`: Throws `HyperliquidError.offline` on all endpoints,
    ///   so UI tests can verify that the offline error state is rendered.
    ///
    /// - `"tab_shell_stub"`: Seeds all three endpoints with non-empty data so
    ///   the three-tab shell test can assert each tab renders content
    ///   (Positions → BTC long, Orders → BTC limit buy, Fills → ETH close short).
    ///
    /// Any unrecognized `stubKey` falls back to `clearinghouseState_single_long`.
    struct UITestStubClient: HyperliquidClient, Sendable {
        let stubKey: String
        let clock: any Clock

        // MARK: - Protocol methods

        func portfolio(for user: Address) async throws -> Portfolio {
            if stubKey == "error_offline" {
                throw HyperliquidError.offline
            }
            return Self.makeStubPortfolio()
        }

        /// Tiny deterministic portfolio used by UI tests. No randomness;
        /// values come straight from arithmetic so XCTest assertions stay
        /// stable across runs.
        private static func makeStubPortfolio() -> Portfolio {
            // Fixed end anchor mirrors `makeSingleLong()` — every fixture
            // in this file shares the same wall-clock so cross-tab tests
            // can reason about it.
            let end = Date(timeIntervalSince1970: 1_715_774_400)

            func line(
                points: Int,
                step: TimeInterval,
                start: Double,
                slopePerStep: Double
            ) -> [PortfolioPoint] {
                (0..<points).map { i in
                    let time = end.addingTimeInterval(-Double(points - 1 - i) * step)
                    let v = start + slopePerStep * Double(i)
                    return PortfolioPoint(time: time, value: Decimal(v))
                }
            }

            func pnl(from s: [PortfolioPoint]) -> [PortfolioPoint] {
                guard let first = s.first else { return [] }
                return s.map { PortfolioPoint(time: $0.time, value: $0.value - first.value) }
            }

            let day = line(points: 24, step: 3_600, start: 12_000, slopePerStep: 27)
            let week = line(points: 28, step: 6 * 3_600, start: 11_600, slopePerStep: 38)
            let month = line(points: 30, step: 86_400, start: 10_800, slopePerStep: 62)
            let allTime = line(points: 52, step: 7 * 86_400, start: 5_000, slopePerStep: 147)

            return Portfolio(windows: [
                .day: PortfolioSeries(accountValue: day, pnl: pnl(from: day), totalVolume: 42_500),
                .week: PortfolioSeries(accountValue: week, pnl: pnl(from: week), totalVolume: 215_000),
                .month: PortfolioSeries(accountValue: month, pnl: pnl(from: month), totalVolume: 830_000),
                .allTime: PortfolioSeries(accountValue: allTime, pnl: pnl(from: allTime), totalVolume: 1_250_000),
            ])
        }

        func candles(
            coin: String,
            interval: CandleInterval,
            startTime: Date,
            endTime: Date
        ) async throws -> [Candle] {
            if stubKey == "error_offline" {
                throw HyperliquidError.offline
            }
            // Minimal deterministic 24-bar series. No randomness — UI tests
            // assert on stable text.
            var bars: [Candle] = []
            var price = Decimal(string: "60000")!
            for i in 0..<24 {
                let openTime = Date(timeIntervalSince1970: 1_715_700_000 + Double(i) * 3600)
                let open = price
                let close = open + (i.isMultiple(of: 2) ? Decimal(150) : Decimal(-100))
                price = close
                bars.append(
                    Candle(
                        coin: coin,
                        interval: interval,
                        openTime: openTime,
                        closeTime: openTime.addingTimeInterval(3600),
                        open: open,
                        close: close,
                        high: max(open, close) + 50,
                        low: min(open, close) - 50,
                        volume: 1000,
                        tradeCount: 200
                    )
                )
            }
            return bars
        }

        func markets() async throws -> [Market] {
            switch stubKey {
            case "error_offline":
                throw HyperliquidError.offline
            default:
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
                ]
            }
        }

        func clearinghouseState(for user: Address) async throws -> ClearinghouseState {
            switch stubKey {
            case "error_offline":
                throw HyperliquidError.offline
            default:
                return makeSingleLong()
            }
        }

        func openOrders(for user: Address) async throws -> [OpenOrder] {
            switch stubKey {
            case "error_offline":
                throw HyperliquidError.offline
            case "openOrders_two_resting":
                return makeTwoRestingOrders()
            case "tab_shell_stub":
                return [makeTabShellOrder()]
            default:
                return []
            }
        }

        func userFills(for user: Address) async throws -> [Fill] {
            switch stubKey {
            case "error_offline":
                throw HyperliquidError.offline
            case "userFills_recent_three":
                return makeThreeRecentFills()
            case "tab_shell_stub":
                return [makeTabShellFill()]
            default:
                return []
            }
        }

        // MARK: - Fixture builders

        private func makeSingleLong() -> ClearinghouseState {
            ClearinghouseState(
                summary: ClearinghouseState.AccountSummary(
                    accountValue: Decimal(string: "12500.50")!,
                    totalNotionalPosition: Decimal(string: "10000.00")!,
                    totalRawUSD: Decimal(string: "12500.50")!,
                    totalMarginUsed: Decimal(string: "1000.00")!,
                    withdrawable: Decimal(string: "11500.50")!
                ),
                positions: [
                    ClearinghouseState.Position(
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
                    ),
                    ClearinghouseState.Position(
                        coin: "ETH",
                        size: Decimal(string: "-5.0")!,
                        side: .short,
                        entryPrice: Decimal(string: "2000.00")!,
                        positionValue: Decimal(string: "10000.00")!,
                        unrealizedPnL: Decimal(string: "-250.00")!,
                        returnOnEquity: Decimal(string: "-0.025")!,
                        liquidationPrice: Decimal(string: "2200.00")!,
                        marginUsed: Decimal(string: "1000.00")!,
                        leverage: .isolated(10)
                    ),
                ],
                serverTime: Date(timeIntervalSince1970: 1_715_774_400),
                fetchedAt: clock.now()
            )
        }

        private func makeTwoRestingOrders() -> [OpenOrder] {
            [
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
                    placedAt: Date(timeIntervalSince1970: 1_715_774_220)
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
                    placedAt: Date(timeIntervalSince1970: 1_715_773_680)
                ),
            ]
        }

        private func makeTabShellOrder() -> OpenOrder {
            OpenOrder(
                oid: 1_000_010,
                coin: "BTC",
                side: .buy,
                limitPrice: Decimal(string: "60000.00")!,
                size: Decimal(string: "0.1000")!,
                origSize: nil,
                orderType: .limit,
                reduceOnly: false,
                triggerPrice: nil,
                placedAt: Date(timeIntervalSince1970: 1_715_774_220)
            )
        }

        private func makeTabShellFill() -> Fill {
            Fill(
                tid: 9_000_010,
                oid: 8_000_010,
                coin: "ETH",
                side: .buy,
                direction: "Close Short",
                price: Decimal(string: "3194.50")!,
                size: Decimal(string: "2.0000")!,
                fee: Decimal(string: "1.28")!,
                feeToken: "USDC",
                closedPnL: Decimal(string: "31.00")!,
                crossed: false,
                hash: "0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321fe",
                executedAt: Date(timeIntervalSince1970: 1_715_774_160)
            )
        }

        private func makeThreeRecentFills() -> [Fill] {
            [
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
                    executedAt: Date(timeIntervalSince1970: 1_715_774_370)
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
                    executedAt: Date(timeIntervalSince1970: 1_715_774_160)
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
                    executedAt: Date(timeIntervalSince1970: 1_715_763_600)
                ),
            ]
        }
    }
#endif
