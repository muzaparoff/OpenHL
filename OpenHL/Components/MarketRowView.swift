// SPDX-License-Identifier: MIT

import HyperliquidAPI
import OpenHLCore
import SwiftUI

/// One row in the Markets list (and, later, the Watchlist). Owns its
/// own layout but never its own data fetching — the parent screen passes
/// a `Market` and an optional `isFollowed` flag.
struct MarketRowView: View {
    let market: Market
    /// Reserved for the Watchlist phase; ignored on Markets v1.
    var isFollowed: Bool = false
    /// Optional star-toggle callback. When nil the star is hidden.
    var onToggleFollow: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Coin symbol — leading
            Text(market.coin)
                .font(.headline)
                .frame(minWidth: 60, alignment: .leading)

            Spacer(minLength: 8)

            // Price + 24h change — trailing column
            VStack(alignment: .trailing, spacing: 2) {
                Text(MoneyFormatter.usd(market.markPrice))
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 3) {
                    Image(systemName: changeGlyph)
                        .font(.caption2)
                    Text(MoneyFormatter.signedPercent(market.dayChangeRatio))
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(changeColor)
            }

            // Star — only when caller wires the toggle (Watchlist phase)
            if let onToggleFollow {
                Button(action: onToggleFollow) {
                    Image(systemName: isFollowed ? "star.fill" : "star")
                        .foregroundStyle(isFollowed ? .yellow : .secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isFollowed ? "Unfollow \(market.coin)" : "Follow \(market.coin)"
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var changeGlyph: String {
        market.dayChangeRatio >= 0 ? "arrow.up" : "arrow.down"
    }

    private var changeColor: Color {
        market.dayChangeRatio >= 0 ? .green : .red
    }

    private var accessibilityLabel: String {
        let dir = market.dayChangeRatio >= 0 ? "up" : "down"
        let pct = MoneyFormatter.signedPercent(abs(market.dayChangeRatio))
        return "\(market.coin), \(MoneyFormatter.usd(market.markPrice)), \(dir) \(pct) over 24 hours"
    }
}

#if DEBUG
    #Preview {
        List {
            MarketRowView(
                market: Market(
                    coin: "BTC",
                    maxLeverage: 50,
                    szDecimals: 3,
                    onlyIsolated: false,
                    markPrice: Decimal(string: "62401.50")!,
                    midPrice: Decimal(string: "62401.50")!,
                    prevDayPrice: Decimal(string: "61641.00")!,
                    openInterest: Decimal(string: "1234.5")!,
                    dayNotionalVolume: Decimal(string: "830000000")!,
                    fundingRate: Decimal(string: "0.0001")!
                )
            )
            MarketRowView(
                market: Market(
                    coin: "ETH",
                    maxLeverage: 50,
                    szDecimals: 4,
                    onlyIsolated: false,
                    markPrice: Decimal(string: "3194.50")!,
                    midPrice: nil,
                    prevDayPrice: Decimal(string: "3210.00")!,
                    openInterest: Decimal(string: "5678.9")!,
                    dayNotionalVolume: Decimal(string: "420000000")!,
                    fundingRate: Decimal(string: "-0.00005")!
                )
            )
        }
    }
#endif
