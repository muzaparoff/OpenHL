// SPDX-License-Identifier: MIT

import HyperliquidAPI
import OpenHLCore
import SwiftUI

/// Full-screen Settings sheet, presented from both the Markets toolbar
/// and the Wallet toolbar as a `.large` detent sheet.
///
/// Sections:
/// 1. **iCloud** — opt-in backup toggle with a caption.
/// 2. **Wallet** — destructive "Clear saved address" with a confirmation dialog.
/// 3. **Favorites** — destructive "Clear all favorites" with a confirmation dialog.
/// 4. **About** — app version, GitHub link, privacy assurance.
struct SettingsView: View {
    @State var viewModel: SettingsViewModel
    let rulesStore: any AlertRulesStore
    let clock: any Clock
    @Environment(\.dismiss) private var dismiss

    @State private var showClearAddressConfirm = false
    @State private var showClearFavoritesConfirm = false

    // Convenience init for previews that don't need the Alerts row wired.
    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self.rulesStore = InMemoryAlertRulesStore()
        self.clock = SystemClock()
    }

    init(viewModel: SettingsViewModel, rulesStore: any AlertRulesStore, clock: any Clock) {
        self.viewModel = viewModel
        self.rulesStore = rulesStore
        self.clock = clock
    }

    var body: some View {
        NavigationStack {
            List {
                alertsSection
                iCloudSection
                walletSection
                favoritesSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.observeToggle()
            }
        }
        // Clear address confirmation
        .confirmationDialog(
            "Clear saved address?",
            isPresented: $showClearAddressConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Address", role: .destructive) {
                viewModel.clearAddress()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app will return to the address-entry screen.")
        }
        // Clear favorites confirmation
        .confirmationDialog(
            "Clear all favorites?",
            isPresented: $showClearFavoritesConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Favorites", role: .destructive) {
                viewModel.clearFavorites()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All pinned coins will be unpinned.")
        }
    }

    // MARK: - Sections

    private var alertsSection: some View {
        Section {
            NavigationLink {
                AlertsListView(
                    viewModel: AlertsListViewModel(
                        rulesStore: rulesStore,
                        favoritesStore: viewModel.favoritesStore,
                        addressStore: viewModel.addressStore,
                        clock: clock
                    )
                )
            } label: {
                Label("Alerts", systemImage: "bell.badge")
            }
            .accessibilityLabel("Alerts settings")
        } header: {
            Text("Notifications")
        }
    }

    private var iCloudSection: some View {
        Section {
            Toggle("Sync with iCloud", isOn: $viewModel.iCloudEnabled)
                .accessibilityLabel("Sync with iCloud")
                .accessibilityHint("Backs up your saved address and favorite coins via iCloud Key-Value Storage.")
            Text(
                "Your saved address and favorite coins, via iCloud Key-Value Storage. Defaults off."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("iCloud")
        }
    }

    private var walletSection: some View {
        Section {
            Button(role: .destructive) {
                showClearAddressConfirm = true
            } label: {
                Text("Clear saved address")
            }
            .accessibilityLabel("Clear saved wallet address")
        } header: {
            Text("Wallet")
        }
    }

    private var favoritesSection: some View {
        Section {
            Button(role: .destructive) {
                showClearFavoritesConfirm = true
            } label: {
                Text("Clear all favorites")
            }
            .accessibilityLabel("Clear all pinned favorite coins")
        } header: {
            Text("Favorites")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: viewModel.appVersion)

            Link(destination: URL(string: "https://github.com/your-org/open-hl")!) {
                HStack {
                    Text("Source code")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("View source code on GitHub")

            Text("MIT licensed, open source.")
                .foregroundStyle(.secondary)

            Text("Read-only. No tracking. No analytics. No backend.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("About")
        }
    }
}

#if DEBUG
    #Preview {
        SettingsView(
            viewModel: SettingsViewModel(
                toggle: InMemoryICloudBackupToggle(),
                addressStore: InMemoryAddressStore(
                    initial: try? Address("0xabcdef1234567890abcdef1234567890abcdef12")
                ),
                favoritesStore: InMemoryFavoriteCoinsStore(initial: ["BTC", "ETH"])
            )
        )
    }
#endif
