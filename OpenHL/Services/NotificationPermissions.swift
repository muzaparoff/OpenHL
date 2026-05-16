// SPDX-License-Identifier: MIT

import UserNotifications

// MARK: - NotificationAuthStatus

/// The result of a notification authorization check or request.
enum NotificationAuthStatus: Sendable {
    case granted
    case denied
    case notDetermined
}

// MARK: - NotificationPermissions

/// Thin, async wrapper around `UNUserNotificationCenter` authorization.
///
/// Call `request()` once before the user creates their first alert.
/// Call `current()` to read the status without prompting.
///
/// Both methods are `nonisolated async` so they can be called from any
/// actor (view models are `@MainActor`; `UNUserNotificationCenter` is
/// fine on any thread).
enum NotificationPermissions {

    /// Returns the current authorization status without prompting.
    static func current() async -> NotificationAuthStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return status(from: settings.authorizationStatus)
    }

    /// Requests authorization (alert, badge, sound). Returns the resulting
    /// status. On iOS, the system prompt appears at most once — subsequent
    /// calls return the already-stored decision without prompting again.
    @discardableResult
    static func request() async -> NotificationAuthStatus {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            return granted ? .granted : .denied
        } catch {
            return .denied
        }
    }

    // MARK: Private

    private static func status(from raw: UNAuthorizationStatus) -> NotificationAuthStatus {
        switch raw {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}
