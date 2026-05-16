// SPDX-License-Identifier: MIT

import Foundation
import HyperliquidAPI
import OpenHLCore

/// View model for `AlertsListView`.
///
/// Owns no fetch logic — alerts are stored locally and evaluated by
/// `AlertScheduler`. The view model's job is to:
/// 1. Subscribe to `AlertRulesStore.didChange` for the view's lifetime.
/// 2. Provide imperative actions (delete, toggle, upsert) that the view
///    drives from gestures.
/// 3. Expose the permission status so the view can render the inline
///    "notifications are denied" banner.
@MainActor
@Observable
final class AlertsListViewModel {

    // MARK: - Observable state

    /// Live list of alert rules, updated on every store mutation.
    private(set) var rules: [AlertRule] = []

    /// Notification permission status. Updated on appear and after
    /// the user creates their first alert.
    private(set) var notificationStatus: NotificationAuthStatus = .notDetermined

    // MARK: - Dependencies

    private let rulesStore: any AlertRulesStore
    let favoritesStore: any FavoriteCoinsStore
    let addressStore: any AddressStore
    private let clock: any Clock

    // MARK: - Init

    init(
        rulesStore: any AlertRulesStore,
        favoritesStore: any FavoriteCoinsStore,
        addressStore: any AddressStore,
        clock: any Clock
    ) {
        self.rulesStore = rulesStore
        self.favoritesStore = favoritesStore
        self.addressStore = addressStore
        self.clock = clock
    }

    // MARK: - Lifecycle

    /// Subscribe to rule changes for the view's lifetime.
    func observeRules() async {
        for await updated in rulesStore.didChange {
            rules = updated
        }
    }

    /// Refresh the notification permission status (no prompt).
    func refreshPermissionStatus() async {
        notificationStatus = await NotificationPermissions.current()
    }

    // MARK: - Actions

    /// Toggle the enabled state of a rule.
    func toggle(id: UUID) {
        rulesStore.toggle(id: id)
    }

    /// Delete a rule.
    func delete(id: UUID) {
        rulesStore.remove(id: id)
    }

    /// Called when the user taps "+". Requests notification permission if
    /// not yet determined, then returns whether the editor should open.
    ///
    /// The caller should show the editor sheet regardless of the result —
    /// the rule can be created even if notifications are denied; we just
    /// show an inline warning.
    func requestPermissionIfNeeded() async {
        switch notificationStatus {
        case .notDetermined:
            notificationStatus = await NotificationPermissions.request()
        case .granted, .denied:
            break
        }
    }

    /// Persist a new or updated rule. Called from `AlertEditorSheet` on Apply.
    func upsert(_ rule: AlertRule) {
        rulesStore.upsert(rule)
    }

    // MARK: - Computed helpers

    /// The set of coin symbols the user has favorited, for the editor's
    /// subject picker.
    var favoriteCoins: [String] {
        favoritesStore.all().sorted()
    }

    /// True if a wallet address is saved (enables the "Wallet account value"
    /// subject option in the editor).
    var hasAddress: Bool {
        addressStore.load() != nil
    }

    /// The current wall-clock time. Used by the editor to stamp `createdAt`.
    func now() -> Date {
        clock.now()
    }
}
