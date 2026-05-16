// SPDX-License-Identifier: MIT

import Charts
import HyperliquidAPI
import OpenHLCore
import SwiftUI

/// Wallet → Balance segment.
///
/// Shows a native Swift Charts line + area chart of the connected address's
/// account-value history across four lookback windows (1D / 1W / 1M / All).
/// A stat row above the chart surfaces the current value, period change
/// ($ and %), period high, and period low — all derived from the
/// `accountValue` series of the selected window.
///
/// v1 scope:
/// - `accountValue` series only (PnL and volume are decoded but not rendered).
/// - No chart interaction / scrubbing.
/// - Standard loading / empty / error states via `SnapshotViewModel`.
struct BalanceHistoryView: View {
    @State var viewModel: BalanceHistoryViewModel
    @State private var selectedWindow: PortfolioWindow = .day

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                loadingPlaceholder

            case .loading where viewModel.lastLoaded == nil:
                loadingPlaceholder

            case .loading:
                loadedContent(viewModel.lastLoaded!, isFaded: true)

            case .loaded(let portfolio):
                loadedContent(portfolio, isFaded: false)

            case .error(let errorState, let lastLoaded):
                if let lastLoaded {
                    VStack(spacing: 8) {
                        loadedContent(lastLoaded, isFaded: false)
                        ErrorBannerView(errorState: errorState) {
                            await viewModel.retry()
                        }
                        .padding(.horizontal)
                    }
                } else {
                    ErrorStateView(
                        errorState: errorState,
                        titleOverride: "Could not load balance history"
                    ) {
                        await viewModel.retry()
                    }
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onChange(of: viewModel.state) { _, newState in
            // Foreground alert evaluation. BalanceHistoryView fetches the
            // portfolio (time series), not a point-in-time account value.
            // We pass `nil` for walletAccountValue so only coin-price rules
            // are evaluated here; the Positions tab handles wallet-value rules.
            if case .loaded = newState {
                AlertScheduler.shared.evaluate(
                    markets: [],
                    accountValue: nil,
                    now: Date()
                )
            }
        }
    }

    // MARK: - Loading placeholder

    private var loadingPlaceholder: some View {
        ProgressView()
            .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func loadedContent(_ portfolio: Portfolio, isFaded: Bool) -> some View {
        VStack(spacing: 0) {
            windowPicker
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

            let series = portfolio[selectedWindow]
            let points = series?.accountValue ?? []

            if points.isEmpty {
                emptyState
                    .frame(minHeight: 280)
            } else {
                VStack(spacing: 12) {
                    statsRow(points: points)
                        .padding(.horizontal)

                    lineChart(points: points)
                        .frame(height: 240)
                        .padding(.horizontal)
                        .opacity(isFaded ? 0.5 : 1)
                        .overlay {
                            if isFaded { ProgressView() }
                        }
                }
            }
        }
    }

    // MARK: - Window picker

    private var windowPicker: some View {
        Picker("Window", selection: $selectedWindow) {
            ForEach(PortfolioWindow.allCases) { window in
                Text(window.displayLabel).tag(window)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Balance history window")
    }

    // MARK: - Stat row

    private func statsRow(points: [PortfolioPoint]) -> some View {
        let current = points.last?.value ?? .zero
        let first = points.first?.value ?? .zero
        let change = current - first
        let changeRatio: Decimal = first != .zero ? change / first : .zero
        let high = points.map(\.value).max() ?? .zero
        let low = points.map(\.value).min() ?? .zero
        let isPositive = change >= .zero

        return HStack(spacing: 0) {
            statCell(
                label: "Current",
                value: MoneyFormatter.usd(current),
                color: .primary
            )
            Divider().frame(height: 32)
            statCell(
                label: "Change",
                value: "\(MoneyFormatter.signedUSD(change)) (\(MoneyFormatter.signedPercent(changeRatio)))",
                color: isPositive ? .green : .red
            )
            Divider().frame(height: 32)
            statCell(label: "High", value: MoneyFormatter.usd(high), color: .primary)
            Divider().frame(height: 32)
            statCell(label: "Low", value: MoneyFormatter.usd(low), color: .primary)
        }
        .accessibilityElement(children: .contain)
    }

    private func statCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Line + area chart

    private func lineChart(points: [PortfolioPoint]) -> some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Account Value", point.value.asDouble)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)

                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Account Value", point.value.asDouble)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.25), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                if let d = value.as(Double.self) {
                    AxisValueLabel(
                        MoneyFormatter.usd(Decimal(d))
                    )
                    .font(.caption2)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                if let date = value.as(Date.self) {
                    AxisValueLabel(xAxisLabel(for: date))
                        .font(.caption2)
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel("Account value chart for the \(selectedWindow.displayLabel) window")
    }

    // MARK: - X-axis formatting

    private func xAxisLabel(for date: Date) -> String {
        let f = DateFormatter()
        switch selectedWindow {
        case .day:
            f.dateFormat = "HH:mm"
        case .week, .month:
            f.dateFormat = "MMM d"
        case .allTime:
            f.dateFormat = "MMM yyyy"
        }
        return f.string(from: date)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No balance history yet")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text(
                "Balance history appears once the account has been active "
                    + "within the selected window. Try a longer range."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "No balance history yet. Try a longer window range."
        )
    }
}

// MARK: - Decimal → Double for chart Y-values

// Swift Charts requires Double (not Decimal) for plottable values.
// The conversion is lossy at extreme precision but charts only need
// a visual approximation; all displayed values still use MoneyFormatter.
extension Decimal {
    fileprivate var asDouble: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

// MARK: - Preview

#if DEBUG
    import Foundation

    private func makePreviewPortfolio() -> Portfolio {
        let now = Date()
        func series(count: Int, step: TimeInterval, base: Double) -> PortfolioSeries {
            let points = (0..<count).map { i in
                let drift = Double.random(in: -200...250)
                return PortfolioPoint(
                    time: now.addingTimeInterval(-TimeInterval(count - i) * step),
                    value: Decimal(base + drift * Double(i) / Double(count))
                )
            }
            return PortfolioSeries(accountValue: points, pnl: [], totalVolume: 0)
        }
        return Portfolio(windows: [
            .day: series(count: 48, step: 1800, base: 12_000),
            .week: series(count: 56, step: 3_600 * 3, base: 11_500),
            .month: series(count: 60, step: 86_400 / 2, base: 10_000),
            .allTime: series(count: 72, step: 86_400 * 7, base: 8_000),
        ])
    }

    #Preview("Balance loaded") {
        let vm = BalanceHistoryViewModel(
            address: nil,
            category: "Balance",
            fetch: { makePreviewPortfolio() }
        )
        return BalanceHistoryView(viewModel: vm)
            .task { await vm.load() }
    }

    #Preview("Balance empty") {
        let vm = BalanceHistoryViewModel(
            address: nil,
            category: "Balance",
            fetch: { Portfolio(windows: [:]) }
        )
        return BalanceHistoryView(viewModel: vm)
            .task { await vm.load() }
    }

    #Preview("Balance error") {
        let vm = BalanceHistoryViewModel(
            address: nil,
            category: "Balance",
            fetch: { throw HyperliquidError.offline }
        )
        return BalanceHistoryView(viewModel: vm)
            .task { await vm.load() }
    }
#endif
