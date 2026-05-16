// SPDX-License-Identifier: MIT

import HyperliquidAPI
import OpenHLCore
import SwiftUI

/// Wallet tab — the optional, address-scoped section.
///
/// Empty state: a single "Watch an address" CTA that opens
/// `AddressEntryView` in a sheet. No data is fetched until the user
/// enters an address.
///
/// Filled state: a segmented `Picker` switches between Portfolio
/// (`PositionsView`), Orders (`OrdersView`), and History (`FillsView`).
/// Each sub-view owns its own `SnapshotViewModel` instance with the
/// saved address, so refreshes are independent per section.
struct WalletView: View {
    let client: any HyperliquidClient
    let addressStore: any AddressStore
    let clock: any Clock
    var onOpenSettings: (() -> Void)? = nil

    @State private var savedAddress: Address?
    @State private var showAddressEntry: Bool = false
    @State private var selectedSection: Section = .portfolio

    enum Section: String, CaseIterable, Identifiable {
        case portfolio = "Portfolio"
        case balance = "Balance"
        case orders = "Orders"
        case history = "History"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let address = savedAddress {
                    connectedContent(for: address)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onOpenSettings?()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .onAppear {
                savedAddress = addressStore.load()
            }
        }
        .sheet(isPresented: $showAddressEntry) {
            AddressEntrySheet(
                client: client,
                addressStore: addressStore,
                clock: clock,
                existingAddress: savedAddress,
                onDone: { newAddress in
                    savedAddress = newAddress
                    showAddressEntry = false
                }
            )
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "wallet.pass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Watch a Hyperliquid wallet")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(
                    "Paste any public Hyperliquid wallet address to see "
                        + "its positions, open orders, and recent fills."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }

            Button {
                showAddressEntry = true
            } label: {
                Text("Watch an address")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)

            Spacer()

            Text(
                "Read-only. open-hl never asks for signing or trade execution."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Connected wallet content

    private func connectedContent(for address: Address) -> some View {
        VStack(spacing: 0) {
            // Address header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(address.rawValue.truncatedMiddle(maxLength: 16))
                        .font(.body.monospaced())
                }
                Spacer()
                Menu {
                    Button("Change address") {
                        showAddressEntry = true
                    }
                    Button("Stop watching", role: .destructive) {
                        addressStore.clear()
                        savedAddress = nil
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .accessibilityLabel("Wallet options")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Picker("Section", selection: $selectedSection) {
                ForEach(Section.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            switch selectedSection {
            case .portfolio:
                PositionsView(
                    viewModel: .positions(client: client, address: address),
                    onAddressChanged: { _ in
                        savedAddress = addressStore.load()
                    },
                    client: client,
                    addressStore: addressStore,
                    clock: clock
                )
            case .balance:
                BalanceHistoryView(
                    viewModel: .balance(client: client, address: address)
                )
            case .orders:
                OrdersView(
                    viewModel: .orders(client: client, address: address)
                )
            case .history:
                FillsView(
                    viewModel: .fills(client: client, address: address)
                )
            }
        }
    }
}

// MARK: - Address-entry sheet wrapper

/// Wraps `AddressEntryView` for presentation inside the Wallet tab.
/// Owns its own view model so the sheet has a self-contained lifecycle.
private struct AddressEntrySheet: View {
    let client: any HyperliquidClient
    let addressStore: any AddressStore
    let clock: any Clock
    let existingAddress: Address?
    let onDone: (Address?) -> Void

    var body: some View {
        NavigationStack {
            AddressEntryView(
                viewModel: AddressEntryViewModel(
                    client: client,
                    addressStore: addressStore,
                    clock: clock,
                    existingAddress: existingAddress
                ),
                onSuccess: { _ in
                    onDone(addressStore.load())
                },
                onCancel: { onDone(existingAddress) }
            )
        }
    }
}
