// SPDX-License-Identifier: MIT

import HyperliquidAPI
import OpenHLCore
import SwiftUI

/// Sheet for creating a new alert rule.
///
/// Sections:
/// 1. **Subject** — "Coin" (picker over favorites) or "Wallet account value".
/// 2. **Condition** — segmented picker: Above / Below / 24h Change.
/// 3. **Threshold** — numeric text field.
///
/// Apply → calls `viewModel.upsert(_:)` and dismisses.
/// Cancel → dismisses without saving.
///
/// Disables the Apply button while the threshold field is empty or zero.
struct AlertEditorSheet: View {
    let viewModel: AlertsListViewModel

    @Environment(\.dismiss) private var dismiss

    // MARK: - Editor state

    private enum SubjectKind: String, CaseIterable {
        case coin = "Coin"
        case wallet = "Wallet value"
    }

    private enum ConditionKind: String, CaseIterable {
        case above = "Above"
        case below = "Below"
        case change24h = "24h Change"
    }

    private enum ChangeDir: String, CaseIterable {
        case up = "Up"
        case down = "Down"
    }

    @State private var subjectKind: SubjectKind = .coin
    @State private var selectedCoin: String = ""
    @State private var conditionKind: ConditionKind = .above
    @State private var changeDir: ChangeDir = .up
    /// Raw threshold text; validated on Apply.
    @State private var thresholdText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                subjectSection
                conditionSection
                thresholdSection
            }
            .navigationTitle("New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyRule()
                    }
                    .disabled(!canApply)
                }
            }
        }
        .onAppear {
            // Default to first favorite if available.
            if selectedCoin.isEmpty, let first = viewModel.favoriteCoins.first {
                selectedCoin = first
            }
            // If no favorites and no wallet, nothing is selectable — the
            // view disables Apply so the user cannot create a broken rule.
        }
    }

    // MARK: - Sections

    private var subjectSection: some View {
        Section {
            Picker("Subject type", selection: $subjectKind) {
                ForEach(SubjectKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Alert subject type")

            if subjectKind == .coin {
                if viewModel.favoriteCoins.isEmpty {
                    Text("Pin coins from the Markets list to use them here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Coin", selection: $selectedCoin) {
                        ForEach(viewModel.favoriteCoins, id: \.self) { coin in
                            Text(coin).tag(coin)
                        }
                    }
                    .accessibilityLabel("Select coin")
                    .onAppear {
                        if selectedCoin.isEmpty || !viewModel.favoriteCoins.contains(selectedCoin) {
                            selectedCoin = viewModel.favoriteCoins.first ?? ""
                        }
                    }
                }
            } else {
                if !viewModel.hasAddress {
                    Text("Enter a wallet address first to set a wallet-value alert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Watches your total account value (USD).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Subject")
        }
    }

    private var conditionSection: some View {
        Section {
            Picker("Condition", selection: $conditionKind) {
                ForEach(validConditionKinds, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Alert condition")
            .onChange(of: conditionKind) { _, newValue in
                // If wallet + 24h change combo — force back to Above.
                if subjectKind == .wallet && newValue == .change24h {
                    conditionKind = .above
                }
            }

            if conditionKind == .change24h {
                Picker("Direction", selection: $changeDir) {
                    ForEach(ChangeDir.allCases, id: \.self) { dir in
                        Text(dir.rawValue).tag(dir)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Change direction")
            }
        } header: {
            Text("Condition")
        }
    }

    private var thresholdSection: some View {
        Section {
            HStack {
                if conditionKind == .change24h {
                    Text("%")
                        .foregroundStyle(.secondary)
                } else {
                    Text("$")
                        .foregroundStyle(.secondary)
                }
                TextField(thresholdPlaceholder, text: $thresholdText)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel("Threshold value")
            }
        } header: {
            Text("Threshold")
        } footer: {
            if conditionKind == .change24h {
                Text("Enter the percentage change (e.g. 5 for 5%). Cooldown: 6 hours between firings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter the USD value. Cooldown: 6 hours between firings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var validConditionKinds: [ConditionKind] {
        // 24h change is not supported for wallet account value.
        subjectKind == .wallet
            ? [.above, .below]
            : ConditionKind.allCases
    }

    private var thresholdPlaceholder: String {
        conditionKind == .change24h ? "e.g. 5" : "e.g. 80000"
    }

    /// The threshold as `Decimal`, converting a percent-change entry to a ratio.
    private var thresholdDecimal: Decimal? {
        let trimmed =
            thresholdText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US")) else {
            return nil
        }
        guard value > 0 else { return nil }
        // 24h change is entered as a percent; store as a ratio.
        return conditionKind == .change24h ? value / 100 : value
    }

    private var canApply: Bool {
        guard thresholdDecimal != nil else { return false }
        switch subjectKind {
        case .coin:
            return !viewModel.favoriteCoins.isEmpty && !selectedCoin.isEmpty
        case .wallet:
            return viewModel.hasAddress
        }
    }

    private func applyRule() {
        guard let threshold = thresholdDecimal else { return }

        let subject: AlertSubject
        switch subjectKind {
        case .coin:
            guard !selectedCoin.isEmpty else { return }
            subject = .coin(selectedCoin)
        case .wallet:
            subject = .walletAccountValue
        }

        let condition: AlertCondition
        switch conditionKind {
        case .above:
            condition = .aboveAbsolute(threshold)
        case .below:
            condition = .belowAbsolute(threshold)
        case .change24h:
            condition = .percentChange24h(
                threshold,
                direction: changeDir == .up ? .up : .down
            )
        }

        let rule = AlertRule(
            subject: subject,
            condition: condition,
            isEnabled: true,
            createdAt: viewModel.now()
        )
        viewModel.upsert(rule)
        dismiss()
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Editor — with favorites") {
        AlertEditorSheet(
            viewModel: AlertsListViewModel(
                rulesStore: InMemoryAlertRulesStore(),
                favoritesStore: InMemoryFavoriteCoinsStore(initial: ["BTC", "ETH", "SOL"]),
                addressStore: InMemoryAddressStore(
                    initial: try? Address("0xabcdef1234567890abcdef1234567890abcdef12")
                ),
                clock: SystemClock()
            )
        )
    }

    #Preview("Editor — no favorites") {
        AlertEditorSheet(
            viewModel: AlertsListViewModel(
                rulesStore: InMemoryAlertRulesStore(),
                favoritesStore: InMemoryFavoriteCoinsStore(),
                addressStore: InMemoryAddressStore(),
                clock: SystemClock()
            )
        )
    }
#endif
