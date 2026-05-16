// SPDX-License-Identifier: MIT

import HyperliquidAPI
import OpenHLCore
import SwiftUI
import UIKit

/// The open orders screen — Tab 2 of the main tab bar.
struct OrdersView: View {
    @State var viewModel: OrdersViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                loadingView

            case .loaded(let orders):
                loadedView(orders: orders, errorState: nil)

            case .error(let errorState, let lastLoaded):
                if let lastLoaded {
                    loadedView(orders: lastLoaded, errorState: errorState)
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
            Text("Fetching orders\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fetching open orders")
    }

    // MARK: - Loaded view

    private func loadedView(
        orders: [OpenOrder],
        errorState: ViewErrorState?
    ) -> some View {
        List {
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
                if orders.isEmpty {
                    emptyView
                } else {
                    ForEach(orders) { order in
                        OrderRowView(order: order)
                            .listRowBackground(
                                Color(uiColor: .secondarySystemGroupedBackground)
                            )
                            .listRowInsets(
                                EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
                            )
                    }
                }
            } header: {
                if !orders.isEmpty {
                    Text("OPEN ORDERS (\(orders.count))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
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
        .animation(reduceMotion ? nil : .default, value: orders.count)
    }

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 32)
            Text("No open orders")
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
        .accessibilityLabel("No open orders. Pull down to refresh.")
    }

    // MARK: - Helpers

    private func unexpectedResponseTitle(_ state: ViewErrorState) -> String? {
        if case .unexpectedResponse = state {
            return "Could not read orders"
        }
        return nil
    }
}

// MARK: - Order row view

struct OrderRowView: View {
    let order: OpenOrder
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
                Text(order.coin)
                    .font(.headline)
                Spacer()
                sideChip
            }
            Text(orderTypeDisplay)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            rowField(label: "Size", value: sizeFormatted)
            rowField(label: "Price", value: MoneyFormatter.usd(order.limitPrice))
            if let triggerPx = order.triggerPrice {
                rowField(label: "Trigger", value: MoneyFormatter.usd(triggerPx))
            }
            if order.reduceOnly {
                Text("Reduce only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(relativeAge)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Accessibility layout (AX3+)

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(order.coin)
                .font(.headline)
            sideChip
            Divider()
            verticalField(label: "Order type", value: orderTypeDisplay)
            Divider()
            verticalField(label: "Size", value: sizeFormatted)
            Divider()
            verticalField(label: "Price", value: MoneyFormatter.usd(order.limitPrice))
            if let triggerPx = order.triggerPrice {
                Divider()
                verticalField(label: "Trigger price", value: MoneyFormatter.usd(triggerPx))
            }
            if order.reduceOnly {
                Divider()
                Text("Reduce only: yes")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Divider()
            verticalField(label: "Placed", value: relativeAge)
        }
    }

    // MARK: - Shared subviews

    private var sideChip: some View {
        HStack(spacing: 4) {
            Text(order.side == .buy ? "Buy" : "Sell")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(order.side == .buy ? .blue : .orange)
            Image(systemName: order.side == .buy ? "arrow.up" : "arrow.down")
                .imageScale(.small)
                .foregroundStyle(order.side == .buy ? .blue : .orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((order.side == .buy ? Color.blue : Color.orange).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(order.side == .buy ? "Buy order" : "Sell order")
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

    private var orderTypeDisplay: String {
        switch order.orderType {
        case .limit: return "Limit"
        case .trigger: return "Trigger"
        case .stopLimit: return "Stop Limit"
        case .stopMarket: return "Stop Market"
        case .takeProfitLimit: return "Take Profit Limit"
        case .takeProfitMarket: return "Take Profit Market"
        case .unknown(let raw): return raw
        }
    }

    private var sizeFormatted: String {
        MoneyFormatter.decimal(order.size, minimumFractionDigits: 4, maximumFractionDigits: 4)
            + " \(order.coin)"
    }

    private var relativeAge: String {
        RelativeTimeFormatter.string(from: order.placedAt)
    }

    // MARK: - Accessibility

    private var rowAccessibilityLabel: String {
        let side = order.side == .buy ? "buy" : "sell"
        let size = MoneyFormatter.decimal(
            order.size, minimumFractionDigits: 2, maximumFractionDigits: 4
        )
        let price = MoneyFormatter.usd(order.limitPrice)
        let absTime = RelativeTimeFormatter.accessibilityLabel(for: order.placedAt)

        var label =
            "\(order.coin) \(side) order, \(orderTypeDisplay), size \(size) \(order.coin), price \(price)"

        if let triggerPx = order.triggerPrice {
            label += ", trigger \(MoneyFormatter.usd(triggerPx))"
        }
        if order.reduceOnly {
            label += ", reduce only"
        }
        label += ", placed \(absTime)"
        return label
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OrdersView(
            viewModel: .orders(
                client: PreviewHyperliquidClient(),
                address: Address(validating: "0x0000000000000000000000000000000000000001")!
            )
        )
    }
}
