// SPDX-License-Identifier: MIT

import Foundation

// MARK: - AlertRule

/// A single alert rule the user has configured. Pure value type, fully
/// `Codable`, lives in `OpenHLCore` so the evaluator (also in `OpenHLCore`)
/// can reason about it without importing the API or the app target.
///
/// **Identity:** `id` is a stable `UUID` minted at creation time. The view
/// layer keys list rows by it; the store keys persistence by it.
///
/// **`isEnabled`:** disabled rules are kept in the store (so the user can
/// flip them back on without re-entering threshold values) but the
/// evaluator skips them. This is the cheap "snooze" affordance.
///
/// **Cooldown:** `cooldown` defaults to 6 hours (`6 * 3600`). The evaluator
/// will not produce a firing for a rule whose `lastFiredAt` is within
/// `cooldown` seconds of `now`. Rationale lives in `architecture.md` §27
/// — short version: BG refresh windows are unpredictable, the same
/// threshold can stay crossed for hours, and we'd rather under-notify
/// than spam. Six hours is the lowest interval that survives a typical
/// market session without firing twice for the same threshold crossing.
///
/// **`lastFiredAt`:** stamped by the evaluator. Persisted via the store so
/// cooldowns survive an app relaunch (and a BG refresh that the user
/// never sees).
public struct AlertRule: Sendable, Equatable, Hashable, Identifiable, Codable {
    public let id: UUID
    public let subject: AlertSubject
    public let condition: AlertCondition
    public var isEnabled: Bool
    public let createdAt: Date
    public var lastFiredAt: Date?
    /// Minimum seconds between two firings of *this same rule*. Defaults
    /// to 6 hours. Stored as `TimeInterval` (i.e. `Double` seconds).
    public var cooldown: TimeInterval

    public init(
        id: UUID = UUID(),
        subject: AlertSubject,
        condition: AlertCondition,
        isEnabled: Bool = true,
        createdAt: Date,
        lastFiredAt: Date? = nil,
        cooldown: TimeInterval = 6 * 3600
    ) {
        self.id = id
        self.subject = subject
        self.condition = condition
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastFiredAt = lastFiredAt
        self.cooldown = cooldown
    }
}

// MARK: - AlertSubject

/// What the alert watches.
///
/// - `.coin(symbol)` — a Hyperliquid perp's `markPrice` (or a derived 24h
///   percent change). Symbol is the same string used everywhere else
///   ("BTC", "ETH", …), matching `FavoriteCoinsStore`.
/// - `.walletAccountValue` — the connected wallet's `accountValue` from
///   `clearinghouseState`. There is exactly one such subject per device;
///   if no address is saved, the evaluator skips any rule with this
///   subject. The percent-change-24h condition is *not* meaningful for
///   wallet account value (the API does not expose a 24h baseline); the
///   evaluator treats it as an immediate non-match. We do not reject it
///   at the type level because the UI prevents the combination upstream.
public enum AlertSubject: Sendable, Equatable, Hashable, Codable {
    case coin(String)
    case walletAccountValue
}

// MARK: - AlertCondition

/// How the subject's current value is compared.
///
/// All thresholds are `Decimal` (i.e. `Money`) for parity with the rest
/// of the domain. Percent-change-24h takes a `Decimal` ratio (0.05 = 5%)
/// and a direction; the rule fires when |dayChange| meets the threshold
/// *in the direction asked*. The evaluator computes day-change for coin
/// subjects from a `AlertMarketSnapshot.dayChangeRatio` value.
public enum AlertCondition: Sendable, Equatable, Hashable, Codable {
    case aboveAbsolute(Decimal)
    case belowAbsolute(Decimal)
    case percentChange24h(Decimal, direction: ChangeDirection)
}

/// Direction qualifier for `.percentChange24h`. `.up` means "fires when
/// the 24h change is *at least* the threshold in the positive direction";
/// `.down` means "fires when the 24h change is *at most* the negated
/// threshold." The threshold itself is stored as a positive ratio.
public enum ChangeDirection: String, Sendable, Codable {
    case up
    case down
}
