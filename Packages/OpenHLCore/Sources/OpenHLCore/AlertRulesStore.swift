// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Protocol

/// Persistence for user-configured `AlertRule`s.
///
/// **Where this lives:** `OpenHLCore`, sibling to `FavoriteCoinsStore` and
/// `ICloudBackupToggle`. Same package-placement rationale as favorites:
/// alerts are a pure preference, not address-scoped, never travel over
/// the wire to Hyperliquid.
///
/// **Shape:** array of `AlertRule` (not a set — rules are not de-duplicated
/// by identity; two rules can watch the same `(subject, condition)` pair
/// with different `id`s and that is allowed and even useful — e.g. two
/// "BTC above" alerts at different price levels).
///
/// **Observation:** `didChange` emits the current array immediately on
/// subscription, then a new array on every mutation. Same fan-out pattern
/// as `FavoriteCoinsStore`.
///
/// **Sendable:** the protocol is `Sendable`. Concrete impls declare
/// `@unchecked Sendable` with an internal `NSLock`.
public protocol AlertRulesStore: Sendable {
    /// Snapshot of all rules. Used for evaluator runs and for initial UI
    /// render. Order is the insertion order from the most recent `upsert`
    /// pass; consumers that need a different sort impose it themselves.
    func all() -> [AlertRule]

    /// Insert if `id` is new, replace in place if it already exists.
    /// Preserves array position on replace. Emits `didChange`.
    func upsert(_ rule: AlertRule)

    /// Remove the rule with `id`. No-op if not present. Emits `didChange`
    /// only on actual removal.
    func remove(id: UUID)

    /// Flip `isEnabled` on the rule with `id`. No-op if not present.
    /// Convenience wrapper around `upsert`.
    func toggle(id: UUID)

    /// Async sequence of the rules array. Emits the current array
    /// immediately on subscription, then a new array on every mutation.
    var didChange: AsyncStream<[AlertRule]> { get }
}

// MARK: - Production: UserDefaults-backed

/// Production implementation. Stores rules as a JSON-encoded `[AlertRule]`
/// under `"openhl.alertRules"` in the injected `UserDefaults`.
///
/// **Key:** `"openhl.alertRules"`. Namespaced under `openhl.` like every
/// other defaults key the app writes.
///
/// **Encoding:** `JSONEncoder` / `JSONDecoder`. `AlertRule` is `Codable`;
/// the default round-trip is stable enough for v1 — we do not need a
/// schema-version stamp until the first time we add a non-optional field.
///
/// **Malformed payload:** treated as "no rules saved." The next mutation
/// overwrites with a well-formed payload, exactly as `FavoriteCoinsStore`
/// handles its own corruption path.
///
/// **`@unchecked Sendable`:** the class holds a `[AlertRule]` cache behind
/// an `NSLock`. `UserDefaults` is thread-safe but read-modify-write
/// (`upsert`, `remove`, `toggle`) requires our own serialization.
public final class UserDefaultsAlertRulesStore: AlertRulesStore, @unchecked Sendable {
    /// The key under which the rules array is stored. Public so tests can
    /// pre-seed a defaults instance without depending on this class.
    public static let storageKey: String = "openhl.alertRules"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cached: [AlertRule]
    private let continuations: AlertRulesContinuations

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cached = Self.read(from: defaults)
        self.continuations = AlertRulesContinuations()
    }

    public func all() -> [AlertRule] {
        lock.withLock { cached }
    }

    public func upsert(_ rule: AlertRule) {
        let updated: [AlertRule] = lock.withLock {
            if let index = cached.firstIndex(where: { $0.id == rule.id }) {
                cached[index] = rule
            } else {
                cached.append(rule)
            }
            let snapshot = cached
            Self.write(snapshot, to: defaults)
            return snapshot
        }
        continuations.yield(updated)
    }

    public func remove(id: UUID) {
        let result: [AlertRule]? = lock.withLock {
            guard let index = cached.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            cached.remove(at: index)
            let snapshot = cached
            Self.write(snapshot, to: defaults)
            return snapshot
        }
        if let result {
            continuations.yield(result)
        }
    }

    public func toggle(id: UUID) {
        let result: [AlertRule]? = lock.withLock {
            guard let index = cached.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            cached[index].isEnabled.toggle()
            let snapshot = cached
            Self.write(snapshot, to: defaults)
            return snapshot
        }
        if let result {
            continuations.yield(result)
        }
    }

    public var didChange: AsyncStream<[AlertRule]> {
        let initial = all()
        return AsyncStream<[AlertRule]> { continuation in
            let token = continuations.register(continuation)
            continuation.yield(initial)
            continuation.onTermination = { [continuations] _ in
                continuations.unregister(token)
            }
        }
    }

    // MARK: Storage helpers

    private static func read(from defaults: UserDefaults) -> [AlertRule] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        guard let rules = try? JSONDecoder().decode([AlertRule].self, from: data) else {
            // Defensive: malformed legacy data is treated as empty. The
            // next mutation overwrites it with a well-formed payload.
            return []
        }
        return rules
    }

    private static func write(_ rules: [AlertRule], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

// MARK: - Test/preview: In-memory

/// In-memory implementation for tests and SwiftUI previews.
public final class InMemoryAlertRulesStore: AlertRulesStore, @unchecked Sendable {
    private var cached: [AlertRule]
    private let lock = NSLock()
    private let continuations: AlertRulesContinuations

    public init(initial: [AlertRule] = []) {
        self.cached = initial
        self.continuations = AlertRulesContinuations()
    }

    public func all() -> [AlertRule] {
        lock.withLock { cached }
    }

    public func upsert(_ rule: AlertRule) {
        let updated: [AlertRule] = lock.withLock {
            if let index = cached.firstIndex(where: { $0.id == rule.id }) {
                cached[index] = rule
            } else {
                cached.append(rule)
            }
            return cached
        }
        continuations.yield(updated)
    }

    public func remove(id: UUID) {
        let result: [AlertRule]? = lock.withLock {
            guard let index = cached.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            cached.remove(at: index)
            return cached
        }
        if let result {
            continuations.yield(result)
        }
    }

    public func toggle(id: UUID) {
        let result: [AlertRule]? = lock.withLock {
            guard let index = cached.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            cached[index].isEnabled.toggle()
            return cached
        }
        if let result {
            continuations.yield(result)
        }
    }

    public var didChange: AsyncStream<[AlertRule]> {
        let initial = all()
        return AsyncStream<[AlertRule]> { continuation in
            let token = continuations.register(continuation)
            continuation.yield(initial)
            continuation.onTermination = { [continuations] _ in
                continuations.unregister(token)
            }
        }
    }
}

// MARK: - Continuations bookkeeping

/// Multi-subscriber fan-out for `AsyncStream<[AlertRule]>` continuations.
/// Mirrors the helpers in `FavoriteCoinsStore.swift` and `ICloudBackup.swift`.
private final class AlertRulesContinuations: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<[AlertRule]>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ continuation: AsyncStream<[AlertRule]>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = continuation }
        return token
    }

    func unregister(_ token: UUID) {
        lock.withLock { _ = subscribers.removeValue(forKey: token) }
    }

    func yield(_ value: [AlertRule]) {
        let snapshot: [AsyncStream<[AlertRule]>.Continuation] = lock.withLock {
            Array(subscribers.values)
        }
        for continuation in snapshot {
            continuation.yield(value)
        }
    }
}
