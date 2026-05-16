// SPDX-License-Identifier: MIT

import Foundation

// MARK: - AlertMarketSnapshot (boundary value type)

/// Minimal snapshot of market data needed to evaluate a single coin alert.
/// The app target builds one of these per relevant coin (from a
/// `HyperliquidAPI.Market`) before calling the evaluator.
///
/// **Why a dedicated struct (not `Market`):** `Market` lives in
/// `HyperliquidAPI`, which depends on `OpenHLCore`. `OpenHLCore` cannot
/// import `HyperliquidAPI` without inverting the package graph (§2 of
/// `architecture.md`). The evaluator lives in `OpenHLCore` so the alert
/// subsystem stays unit-testable without spinning up the API package's
/// URLSession plumbing. The adapter that maps `Market -> AlertMarketSnapshot`
/// is a one-liner in the app target.
public struct AlertMarketSnapshot: Sendable, Equatable {
    /// Coin symbol, e.g. `"BTC"`.
    public let coin: String
    /// Hyperliquid's authoritative mark price.
    public let markPrice: Decimal
    /// Signed 24h change as a raw ratio (`0.0124` = +1.24%). Used by
    /// `.percentChange24h` rules.
    public let dayChangeRatio: Decimal

    public init(coin: String, markPrice: Decimal, dayChangeRatio: Decimal) {
        self.coin = coin
        self.markPrice = markPrice
        self.dayChangeRatio = dayChangeRatio
    }
}

// MARK: - AlertFiring

/// One result of an evaluator pass — a rule that matched its condition
/// against the current data and is past its cooldown.
///
/// Pure value type. The scheduler turns each firing into a
/// `UNNotificationRequest`; the view layer can also display recent
/// firings without re-evaluating.
public struct AlertFiring: Sendable, Equatable {
    public let rule: AlertRule
    /// The current value of the subject at firing time. For
    /// `.percentChange24h` this is the signed ratio (`0.0124` = +1.24%),
    /// not a price. For absolute conditions it is the matched value
    /// (mark price or account value).
    public let currentValue: Decimal
    public let firedAt: Date

    public init(rule: AlertRule, currentValue: Decimal, firedAt: Date) {
        self.rule = rule
        self.currentValue = currentValue
        self.firedAt = firedAt
    }

    /// User-facing notification body. POC-grade formatting using
    /// `Decimal.description`; the app layer can swap in a richer
    /// formatter when it renders into a `UNMutableNotificationContent`.
    public var displayBody: String {
        let subjectLabel = Self.subjectLabel(for: rule.subject)
        switch rule.condition {
        case .aboveAbsolute(let threshold):
            return "\(subjectLabel) is \(currentValue) (above \(threshold))"
        case .belowAbsolute(let threshold):
            return "\(subjectLabel) is \(currentValue) (below \(threshold))"
        case .percentChange24h(let threshold, let direction):
            let percent = currentValue * 100
            let thresholdPct = threshold * 100
            switch direction {
            case .up:
                return "\(subjectLabel) is up \(percent)% in 24h (>= \(thresholdPct)%)"
            case .down:
                return "\(subjectLabel) is down \(percent)% in 24h (<= -\(thresholdPct)%)"
            }
        }
    }

    private static func subjectLabel(for subject: AlertSubject) -> String {
        switch subject {
        case .coin(let symbol):
            return "\(symbol) mark price"
        case .walletAccountValue:
            return "Account value"
        }
    }
}

// MARK: - AlertEvaluator

/// Pure, deterministic evaluator. No I/O, no clock side-effects, no
/// hidden state. Takes `now` as a parameter so tests can pin time.
///
/// **Inputs:**
/// - `rules` — every rule the store currently holds (enabled and not).
/// - `markets` — current Hyperliquid perp snapshots.
/// - `walletAccountValue` — current `accountValue` if an address is saved,
///   otherwise `nil`. Rules with `.walletAccountValue` subject are
///   skipped when this is `nil`.
/// - `now` — the wall-clock to stamp firings with and to compare against
///   `lastFiredAt + cooldown`.
///
/// **Outputs:**
/// - `firings` — one entry per rule that matched and was past cooldown.
/// - `rulesToUpdate` — the same rules with `lastFiredAt = now` stamped.
///   The scheduler passes each through `AlertRulesStore.upsert(_:)`.
///
/// **Skips (no firing, no update):**
/// - `isEnabled == false`.
/// - Cooldown not elapsed (`lastFiredAt != nil && now - lastFiredAt < cooldown`).
/// - `.coin(symbol)` subject with no matching entry in `markets`.
/// - `.walletAccountValue` subject when `walletAccountValue == nil`.
/// - `.percentChange24h` against `.walletAccountValue` (no 24h baseline
///   exposed by the API; treated as an immediate non-match). The UI
///   prevents this combination upstream.
///
/// **Determinism:** for the same `(rules, markets, walletAccountValue, now)`
/// tuple the output is identical. Order of `firings` matches the order
/// of `rules` on input — stable, no hashing, no sorting.
public enum AlertEvaluator {

    public static func evaluate(
        rules: [AlertRule],
        markets: [AlertMarketSnapshot],
        walletAccountValue: Decimal?,
        now: Date
    ) -> (firings: [AlertFiring], rulesToUpdate: [AlertRule]) {
        // Build a `coin -> snapshot` lookup once. O(rules + markets) total.
        let marketsByCoin: [String: AlertMarketSnapshot] = Dictionary(
            markets.map { ($0.coin, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var firings: [AlertFiring] = []
        var updates: [AlertRule] = []

        for rule in rules {
            guard rule.isEnabled else { continue }
            if let lastFired = rule.lastFiredAt {
                let elapsed = now.timeIntervalSince(lastFired)
                guard elapsed >= rule.cooldown else { continue }
            }

            guard
                let currentValue = currentValue(
                    for: rule,
                    marketsByCoin: marketsByCoin,
                    walletAccountValue: walletAccountValue
                )
            else {
                continue
            }

            guard matches(condition: rule.condition, currentValue: currentValue) else {
                continue
            }

            firings.append(AlertFiring(rule: rule, currentValue: currentValue, firedAt: now))
            var stamped = rule
            stamped.lastFiredAt = now
            updates.append(stamped)
        }

        return (firings, updates)
    }

    // MARK: - Helpers

    /// Returns the value to compare against the condition's threshold,
    /// or `nil` if the rule's subject can't be evaluated against the
    /// current data.
    ///
    /// For `.percentChange24h` against a coin, this returns the
    /// `dayChangeRatio`. For `.aboveAbsolute` and `.belowAbsolute`
    /// against a coin, this returns the `markPrice`. For wallet account
    /// value, absolute conditions return the current account value; the
    /// `.percentChange24h` condition is unsupported and returns `nil`.
    private static func currentValue(
        for rule: AlertRule,
        marketsByCoin: [String: AlertMarketSnapshot],
        walletAccountValue: Decimal?
    ) -> Decimal? {
        switch rule.subject {
        case .coin(let symbol):
            guard let snapshot = marketsByCoin[symbol] else { return nil }
            switch rule.condition {
            case .percentChange24h:
                return snapshot.dayChangeRatio
            case .aboveAbsolute, .belowAbsolute:
                return snapshot.markPrice
            }
        case .walletAccountValue:
            guard let value = walletAccountValue else { return nil }
            switch rule.condition {
            case .percentChange24h:
                return nil
            case .aboveAbsolute, .belowAbsolute:
                return value
            }
        }
    }

    /// Checks `currentValue` against `condition`. For `.percentChange24h`,
    /// the threshold is a positive ratio; direction `.up` requires
    /// `currentValue >= threshold`, `.down` requires
    /// `currentValue <= -threshold`.
    private static func matches(condition: AlertCondition, currentValue: Decimal) -> Bool {
        switch condition {
        case .aboveAbsolute(let threshold):
            return currentValue > threshold
        case .belowAbsolute(let threshold):
            return currentValue < threshold
        case .percentChange24h(let threshold, let direction):
            switch direction {
            case .up:
                return currentValue >= threshold
            case .down:
                return currentValue <= -threshold
            }
        }
    }
}
