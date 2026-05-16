// SPDX-License-Identifier: MIT

import Foundation

/// Formats a past `Date` as a short relative-time string for display on
/// list rows. Exact times are available via the VoiceOver label; this
/// formatter is for the compact visual representation only.
///
/// Rules (per design spec):
/// - Under 60 seconds: `"just now"`
/// - 1–59 minutes: `"Xm ago"`
/// - 1–23 hours: `"Xh ago"`
/// - 1–29 days: `"Xd ago"`
/// - 30+ days: locale-aware short date string (e.g. `"Apr 12"`)
///
/// All computation is relative to the `now` parameter so callers can
/// inject a fixed date in tests without mocking the system clock.
public enum RelativeTimeFormatter {

    /// Returns a short relative-time string for `date` relative to `now`.
    ///
    /// - Parameters:
    ///   - date: The past moment to format.
    ///   - now: The reference point (defaults to `Date()`).
    ///   - locale: Locale for short-date formatting (defaults to
    ///     `.autoupdatingCurrent`).
    /// - Returns: A localized relative-time string.
    public static func string(
        from date: Date,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let elapsed = now.timeIntervalSince(date)

        // Guard against future dates (clock skew, test data).
        guard elapsed >= 0 else { return "just now" }

        if elapsed < 60 {
            return "just now"
        }

        let minutes = Int(elapsed / 60)
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        let hours = Int(elapsed / 3600)
        if hours < 24 {
            return "\(hours)h ago"
        }

        let days = Int(elapsed / 86400)
        if days < 30 {
            return "\(days)d ago"
        }

        // 30+ days: short date
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// Returns an absolute date/time string suitable for VoiceOver labels.
    /// Example: `"today at 2:15 PM"` or `"Tuesday at 9:42 AM"`.
    ///
    /// - Parameters:
    ///   - date: The moment to describe.
    ///   - now: The reference point (defaults to `Date()`).
    ///   - locale: Locale for formatting (defaults to `.autoupdatingCurrent`).
    ///   - timeZone: Time zone for formatting (defaults to `.current`).
    /// - Returns: A human-readable absolute time string.
    public static func accessibilityLabel(
        for date: Date,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .current
    ) -> String {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.timeZone = timeZone
        dayFormatter.timeStyle = .short

        if calendar.isDateInToday(date) {
            return "today at \(dayFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "yesterday at \(dayFormatter.string(from: date))"
        }

        let elapsed = now.timeIntervalSince(date)
        if elapsed < 7 * 86400 {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.locale = locale
            weekdayFormatter.timeZone = timeZone
            weekdayFormatter.dateFormat = "EEEE"
            return "\(weekdayFormatter.string(from: date)) at \(dayFormatter.string(from: date))"
        }

        let fullFormatter = DateFormatter()
        fullFormatter.locale = locale
        fullFormatter.timeZone = timeZone
        fullFormatter.dateStyle = .medium
        fullFormatter.timeStyle = .short
        return fullFormatter.string(from: date)
    }
}
