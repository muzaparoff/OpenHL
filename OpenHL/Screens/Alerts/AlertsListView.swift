// SPDX-License-Identifier: MIT

import HyperliquidAPI
import OpenHLCore
import SwiftUI

/// List of the user's configured alert rules, reached from Settings → Alerts.
///
/// States:
/// - **Empty** — friendly copy with a call to tap "+".
/// - **Populated** — one row per rule; swipe-to-delete; enable/disable toggle.
/// - **Permission denied** — inline banner with a Settings deep-link.
///
/// A "+" button in the top-trailing toolbar presents `AlertEditorSheet`.
struct AlertsListView: View {
    @State var viewModel: AlertsListViewModel
    @State private var showEditor = false

    var body: some View {
        List {
            // Notification-denied banner
            if viewModel.notificationStatus == .denied {
                deniedBanner
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if viewModel.rules.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.rules) { rule in
                    AlertRuleRow(rule: rule) { id in
                        viewModel.toggle(id: id)
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        let rule = viewModel.rules[offset]
                        viewModel.delete(id: rule.id)
                    }
                }

                footerSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.requestPermissionIfNeeded()
                        showEditor = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add alert")
            }
        }
        .sheet(isPresented: $showEditor) {
            AlertEditorSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.refreshPermissionStatus()
        }
        .task {
            await viewModel.observeRules()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 32)
            Image(systemName: "bell.badge")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No alerts yet")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text(
                "Tap + to set up an alert on a favorite coin or your wallet's balance."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No alerts yet. Tap the add button to create an alert.")
    }

    // MARK: - Permission denied banner

    private var deniedBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Notifications are off", systemImage: "bell.slash.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(
                "Alerts can't be delivered because notifications are disabled for OpenHL."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemOrange).opacity(0.12))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Notifications are disabled. Open Settings to enable them for OpenHL."
        )
    }

    // MARK: - Honest disclaimer footer

    private var footerSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text(
                "Alerts check in the background when iOS allows — usually within an hour or two. Open the app for an immediate check."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - AlertRuleRow

private struct AlertRuleRow: View {
    let rule: AlertRule
    let onToggle: (UUID) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(subjectLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(conditionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastFired = rule.lastFiredAt {
                    Text("Last fired \(RelativeTimeFormatter.string(from: lastFired))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(
                            "Last fired \(RelativeTimeFormatter.accessibilityLabel(for: lastFired))"
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { _ in onToggle(rule.id) }
                )
            ) {
                EmptyView()
            }
            .labelsHidden()
            .accessibilityLabel(rule.isEnabled ? "Disable alert" : "Enable alert")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(subjectLabel), \(conditionLabel)\(rule.isEnabled ? "" : ", disabled")")
    }

    private var subjectLabel: String {
        switch rule.subject {
        case .coin(let symbol): return "\(symbol) price"
        case .walletAccountValue: return "Wallet value"
        }
    }

    private var conditionLabel: String {
        switch rule.condition {
        case .aboveAbsolute(let t):
            return "above \(MoneyFormatter.usd(t))"
        case .belowAbsolute(let t):
            return "below \(MoneyFormatter.usd(t))"
        case .percentChange24h(let pct, let direction):
            let formatted = MoneyFormatter.decimal(
                pct * 100,
                minimumFractionDigits: 1,
                maximumFractionDigits: 1
            )
            return (direction == .up ? "+" : "-") + "\(formatted)% in 24h"
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Empty") {
        NavigationStack {
            AlertsListView(
                viewModel: AlertsListViewModel(
                    rulesStore: InMemoryAlertRulesStore(),
                    favoritesStore: InMemoryFavoriteCoinsStore(initial: ["BTC", "ETH"]),
                    addressStore: InMemoryAddressStore(),
                    clock: SystemClock()
                )
            )
        }
    }

    #Preview("Populated") {
        let store = InMemoryAlertRulesStore(initial: [
            AlertRule(
                subject: .coin("BTC"),
                condition: .aboveAbsolute(80_000),
                isEnabled: true,
                createdAt: Date().addingTimeInterval(-3600 * 2),
                lastFiredAt: Date().addingTimeInterval(-3600)
            ),
            AlertRule(
                subject: .coin("ETH"),
                condition: .belowAbsolute(2_000),
                isEnabled: false,
                createdAt: Date().addingTimeInterval(-86400)
            ),
            AlertRule(
                subject: .walletAccountValue,
                condition: .aboveAbsolute(50_000),
                isEnabled: true,
                createdAt: Date().addingTimeInterval(-3600 * 5)
            ),
        ])
        NavigationStack {
            AlertsListView(
                viewModel: AlertsListViewModel(
                    rulesStore: store,
                    favoritesStore: InMemoryFavoriteCoinsStore(initial: ["BTC", "ETH"]),
                    addressStore: InMemoryAddressStore(
                        initial: try? Address("0xabcdef1234567890abcdef1234567890abcdef12")
                    ),
                    clock: SystemClock()
                )
            )
        }
    }
#endif
