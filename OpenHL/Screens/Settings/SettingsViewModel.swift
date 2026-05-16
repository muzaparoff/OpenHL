// SPDX-License-Identifier: MIT

import HyperliquidAPI
import OpenHLCore
import SwiftUI

/// View model for the Settings sheet.
///
/// **Architecture notes:**
/// - `@MainActor @Observable final class` per §5 of architecture.md.
/// - Owns no long-running tasks itself. The view drives subscriptions via
///   `.task` blocks tied to the sheet's lifetime (§3 / §13.2).
/// - No default values on init — all dependencies are injected.
@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - Published state

    /// Mirrors the iCloud backup toggle. The setter calls through to the
    /// toggle; the view binds `$viewModel.iCloudEnabled` directly.
    var iCloudEnabled: Bool {
        didSet {
            guard iCloudEnabled != toggle.isEnabled else { return }
            toggle.setEnabled(iCloudEnabled)
        }
    }

    // MARK: - Dependencies

    private let toggle: any ICloudBackupToggle
    let addressStore: any AddressStore
    let favoritesStore: any FavoriteCoinsStore
    /// iCloud-backed address decorator — exposes `applyToggle(_:)` so the
    /// Settings sheet can drive reconciliation when the toggle flips.
    private let backedAddressStore: ICloudBackedAddressStore?
    /// iCloud-backed favorites decorator — same.
    private let backedFavoritesStore: ICloudBackedFavoriteCoinsStore?

    // MARK: - Init

    /// Full production init. Pass `nil` for the backed decorators in
    /// environments (tests, previews) where iCloud is unavailable.
    init(
        toggle: any ICloudBackupToggle,
        addressStore: any AddressStore,
        favoritesStore: any FavoriteCoinsStore,
        backedAddressStore: ICloudBackedAddressStore? = nil,
        backedFavoritesStore: ICloudBackedFavoriteCoinsStore? = nil
    ) {
        self.toggle = toggle
        self.addressStore = addressStore
        self.favoritesStore = favoritesStore
        self.backedAddressStore = backedAddressStore
        self.backedFavoritesStore = backedFavoritesStore
        self.iCloudEnabled = toggle.isEnabled
    }

    // MARK: - Actions

    /// Called from the view's `.task` to keep `iCloudEnabled` in sync with
    /// external changes (e.g., the toggle value changing on another device
    /// via iCloud, or another sheet session setting it directly).
    func observeToggle() async {
        for await value in toggle.didChange {
            if iCloudEnabled != value {
                iCloudEnabled = value
            }
            backedAddressStore?.applyToggle(value)
            backedFavoritesStore?.applyToggle(value)
        }
    }

    /// Removes the saved wallet address from all stores.
    func clearAddress() {
        addressStore.clear()
    }

    /// Clears all pinned favorites from the store.
    func clearFavorites() {
        let all = favoritesStore.all()
        for coin in all {
            favoritesStore.toggle(coin)
        }
    }

    /// App version string for the About section.
    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(version) (\(build))"
    }
}
