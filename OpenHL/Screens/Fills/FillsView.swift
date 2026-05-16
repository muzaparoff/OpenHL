// SPDX-License-Identifier: MIT

import HyperliquidAPI
import OpenHLCore
import SwiftUI
import UIKit

/// The recent fills screen — Tab 3 of the main tab bar.
struct FillsView: View {
    @State var viewModel: FillsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                loadingView

            case .loaded(let fills):
                loadedView(fills: fills, errorState: nil)

            case .error(let errorState, let lastLoaded):
                if let lastLoaded {
                    loadedView(fills: lastLoaded, errorState: errorState)
                } else {
                    ErrorStateView(
                        errorState: errorState,
                        titleOverride: unexpectedResponseTitle(errorState)
                    ) {
                        await viewModel.retry()
                    }
                }
            }
        }
        .navigationTitle("open-hl")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("open-hl")
                    .font(.headline)
            }
            ToolbarItem(placement: .topBarLeading) {
                Text((viewModel.address?.rawValue ?? "").truncatedMiddle(maxLength: 12))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Wallet address \((viewModel.address?.rawValue ?? ""))")
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
            Text("Fetching fills\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fetching recent fills")
    }

    // MARK: - Loaded view

    private func loadedView(
        fills: [Fill],
        errorState: ViewErrorState?
    ) -> some View {
        let cap = URLSessionHyperliquidClient.userFillsCap
        let atCap = fills.count == cap

        return List {
            // Inline banner on refresh failure
            if let errorState {
                Section {
                    ErrorBannerView(errorState: errorState) {
                        await viewModel.retry()
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if fills.isEmpty {
                    emptyView
                } else {
                    ForEach(fills) { fill in
                        FillRowView(fill: fill)
                            .listRowBackground(
                                Color(uiColor: .secondarySystemGroupedBackground)
                            )
                            .listRowInsets(
                                EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
                            )
                    }
                }
            } header: {
                if !fills.isEmpty {
                    Text("RECENT FILLS (\(fills.count))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }
            } footer: {
                if !fills.isEmpty {
                    if atCap {
                        Text("Showing \(cap) most recent fills. Pull down to refresh.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Showing \(fills.count) fills. Pull down to refresh.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            let generator = UINotificationFeedbackGenerator()
            await viewModel.refresh()
            if case .error = viewModel.state {
                generator.notificationOccurred(.error)
            } else {
                generator.notificationOccurred(.success)
            }
        }
        .animation(reduceMotion ? nil : .default, value: fills.count)
    }

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 32)
            Text("No recent fills")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Pull down to refresh.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No recent fills. Pull down to refresh.")
    }

    // MARK: - Helpers

    private func unexpectedResponseTitle(_ state: ViewErrorState) -> String? {
        if case .unexpectedResponse = state {
            return "Could not read fills"
        }
        return nil
    }
}

// MARK: - Fill row view

struct FillRowView: View {
    let fill: Fill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isAccessibilitySize = dynamicTypeSize >= .accessibility3
        Group {
            if isAccessibilitySize {
                accessibilityLayout
            } else {
                compactLayout
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    // MARK: - Compact layout

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(fill.coin)
                    .font(.headline)
                Spacer()
                directionChip
            }
            rowField(label: "Size", value: sizeFormatted)
            rowField(label: "Price", value: MoneyFormatter.usd(fill.price))
            rowField(label: "Fee", value: feeFormatted)
            closedPnLRow
            Text(relativeAge)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Accessibility layout (AX3+)

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fill.coin)
                .font(.headline)
            directionChip
            Divider()
            verticalField(label: "Size", value: sizeFormatted)
            Divider()
            verticalField(label: "Fill price", value: MoneyFormatter.usd(fill.price))
            Divider()
            verticalField(label: "Fee", value: feeFormatted)
            Divider()
            Text("Closed PnL")
                .font(.footnote)
                .foregroundStyle(.secondary)
            closedPnLRow
            Divider()
            verticalField(label: "Filled", value: relativeAge)
        }
    }

    // MARK: - Shared subviews

    private var directionChip: some View {
        let isLiquidation = fill.direction.lowercased().contains("liquidat")
        let chipColor: Color
        if isLiquidation {
            chipColor = .red
        } else if directionIsBuySide(fill.direction) {
            chipColor = .blue
        } else {
            chipColor = .orange
        }

        return Text(fill.direction)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(chipColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(chipColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(fill.direction)
    }

    private var closedPnLRow: some View {
        let pnl = fill.closedPnL
        return HStack {
            Text("Closed PnL")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            pnlContent(pnl)
        }
    }

    @ViewBuilder
    private func pnlContent(_ value: Decimal) -> some View {
        if value > 0 {
            HStack(spacing: 2) {
                Text(MoneyFormatter.signedUSD(value))
                    .font(.body)
                    .foregroundStyle(.green)
                Image(systemName: "arrow.up")
                    .imageScale(.small)
                    .foregroundStyle(.green)
            }
        } else if value < 0 {
            HStack(spacing: 2) {
                Text(MoneyFormatter.signedUSD(value))
                    .font(.body)
                    .foregroundStyle(.red)
                Image(systemName: "arrow.down")
                    .imageScale(.small)
                    .foregroundStyle(.red)
            }
        } else {
            Text(MoneyFormatter.usd(value))
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    private func rowField(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.body)
        }
    }

    private func verticalField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }

    // MARK: - Formatting

    private var sizeFormatted: String {
        MoneyFormatter.decimal(fill.size, minimumFractionDigits: 4, maximumFractionDigits: 4)
            + " \(fill.coin)"
    }

    private var feeFormatted: String {
        MoneyFormatter.decimal(fill.fee, minimumFractionDigits: 2, maximumFractionDigits: 6)
            + " \(fill.feeToken)"
    }

    private var relativeAge: String {
        RelativeTimeFormatter.string(from: fill.executedAt)
    }

    // MARK: - Direction chip color helper

    /// Returns `true` when the fill direction is buy-side (blue chip).
    /// "Open Long" and "Close Short" are buy-side actions; everything else is
    /// sell-side (orange) unless it is a liquidation (red override in chip).
    private func directionIsBuySide(_ dir: String) -> Bool {
        let lower = dir.lowercased()
        return lower.contains("open long") || lower.contains("close short")
    }

    // MARK: - Accessibility

    private var rowAccessibilityLabel: String {
        let size = MoneyFormatter.decimal(
            fill.size, minimumFractionDigits: 2, maximumFractionDigits: 4
        )
        let price = MoneyFormatter.usd(fill.price)
        let fee = feeFormatted
        let pnl = MoneyFormatter.signedUSD(fill.closedPnL)
        let absTime = RelativeTimeFormatter.accessibilityLabel(for: fill.executedAt)

        return
            "\(fill.coin), \(fill.direction.lowercased()), size \(size) \(fill.coin), fill price \(price), fee \(fee), closed PnL \(pnl), filled \(absTime)"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FillsView(
            viewModel: .fills(
                client: PreviewHyperliquidClient(),
                address: Address(validating: "0x0000000000000000000000000000000000000001")!
            )
        )
    }
}
