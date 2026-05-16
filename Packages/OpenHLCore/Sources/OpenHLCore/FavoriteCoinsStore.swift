// SPDX-License-Identifier: MIT

import Foundation

/// Persists the user's pinned (favorite) coins across launches.
///
/// **Where this lives:** `OpenHLCore`, not `HyperliquidAPI`. Rationale:
/// favorites are a pure UI preference — they are not address-scoped,
/// they never travel over the wire, and the API has no concept of
/// "favorite." Co-locating with `AddressStore` (which lives in
/// `HyperliquidAPI` because it traffics in `Address` and may grow a
/// Keychain implementation) would import persistence concerns into a
/// package that has no other reason to know about them. `OpenHLCore`
/// already exposes value-type-flavored utilities (`Clock`,
/// `MoneyFormatter`); a value-store keyed by coin symbol fits the
/// same shape. (Logged as a decision.)
///
/// **Shape:** `Set<String>` of coin symbols (`"BTC"`, `"ETH"`, …). Not
/// `[Address]` because favorites are not address-scoped — the same
/// pinned set follows the user across any wallet address they enter.
/// Not a richer struct (e.g. `FavoriteCoin { symbol, pinnedAt }`)
/// because Phase 3d ships only the binary pinned/unpinned state; ordering
/// within the pinned section is alphabetical, not insertion-order. If a
/// future phase wants "most recently pinned first," we revisit with a
/// decision entry.
///
/// **Observation:** `didChange` is an `AsyncStream<Set<String>>` that
/// emits the new set on every mutation. Consumers (the Markets view
/// model) `for await` on it inside a `.task` block, which ties the
/// subscription to view lifetime — no manual unsubscribe, no notification
/// center, no Combine. The current set is emitted at subscription time
/// so the consumer doesn't need a separate "read once + then listen"
/// dance.
///
/// **Sendable:** the protocol is `Sendable`. Concrete implementations
/// declare `@unchecked Sendable` and use an internal `NSLock` to
/// serialize mutation, mirroring `UserDefaultsAddressStore` /
/// `InMemoryAddressStore`.
public protocol FavoriteCoinsStore: Sendable {
    /// O(1) membership check.
    func isFavorite(_ coin: String) -> Bool

    /// Flip the pin state for `coin`. Idempotent at the set level — a
    /// coin is either in the set or not. Emits the new set on
    /// `didChange`.
    func toggle(_ coin: String)

    /// Snapshot of the current set. Used for the initial render of the
    /// Markets list before the observation stream begins.
    func all() -> Set<String>

    /// Async sequence of the favorites set. Emits the current set
    /// immediately on subscription, then a new set on every mutation.
    /// Multiple concurrent subscribers are supported; each gets an
    /// independent stream.
    var didChange: AsyncStream<Set<String>> { get }
}

// MARK: - Production: UserDefaults-backed

/// Production implementation. Backed by a `UserDefaults` instance
/// (`.standard` by default; tests inject a suite-backed instance).
///
/// Storage format: a JSON-encoded `[String]` (sorted at write time for
/// stable on-disk bytes). `Set` is not directly a property-list type and
/// is not the natural top-level Codable value; encoding to `Data` via
/// `JSONEncoder` sidesteps both issues and keeps the on-disk format
/// human-readable in the defaults plist.
///
/// `@unchecked Sendable`: the class holds a `Set<String>` cache behind
/// an `NSLock`. `UserDefaults` is documented thread-safe, but we serialize
/// our own read-modify-write (toggle) ourselves rather than relying on
/// the framework's ordering between `array(forKey:)` and `set(_:forKey:)`.
public final class UserDefaultsFavoriteCoinsStore: FavoriteCoinsStore, @unchecked Sendable {
    /// The key under which the favorites are stored. Public so tests
    /// can pre-seed a defaults instance without depending on this class.
    public static let storageKey: String = "openhl.favoriteCoins"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cached: Set<String>
    private let continuations: Continuations

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cached = Self.read(from: defaults)
        self.continuations = Continuations()
    }

    public func isFavorite(_ coin: String) -> Bool {
        lock.withLock { cached.contains(coin) }
    }

    public func toggle(_ coin: String) {
        let updated: Set<String> = lock.withLock {
            if cached.contains(coin) {
                cached.remove(coin)
            } else {
                cached.insert(coin)
            }
            let snapshot = cached
            Self.write(snapshot, to: defaults)
            return snapshot
        }
        continuations.yield(updated)
    }

    public func all() -> Set<String> {
        lock.withLock { cached }
    }

    public var didChange: AsyncStream<Set<String>> {
        let initial = all()
        return AsyncStream<Set<String>> { continuation in
            let token = continuations.register(continuation)
            continuation.yield(initial)
            continuation.onTermination = { [continuations] _ in
                continuations.unregister(token)
            }
        }
    }

    // MARK: Storage helpers

    private static func read(from defaults: UserDefaults) -> Set<String> {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        guard let array = try? JSONDecoder().decode([String].self, from: data) else {
            // Defensive: malformed legacy data is treated as empty. The
            // next toggle overwrites it with a well-formed payload.
            return []
        }
        return Set(array)
    }

    private static func write(_ set: Set<String>, to defaults: UserDefaults) {
        let sorted = set.sorted()
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

// MARK: - Test/preview: In-memory

/// In-memory implementation for tests and SwiftUI previews. Thread-safe
/// via an internal lock; `Sendable` via `@unchecked Sendable` with the
/// lock as justification.
public final class InMemoryFavoriteCoinsStore: FavoriteCoinsStore, @unchecked Sendable {
    private var cached: Set<String>
    private let lock = NSLock()
    private let continuations: Continuations

    public init(initial: Set<String> = []) {
        self.cached = initial
        self.continuations = Continuations()
    }

    public func isFavorite(_ coin: String) -> Bool {
        lock.withLock { cached.contains(coin) }
    }

    public func toggle(_ coin: String) {
        let updated: Set<String> = lock.withLock {
            if cached.contains(coin) {
                cached.remove(coin)
            } else {
                cached.insert(coin)
            }
            return cached
        }
        continuations.yield(updated)
    }

    public func all() -> Set<String> {
        lock.withLock { cached }
    }

    public var didChange: AsyncStream<Set<String>> {
        let initial = all()
        return AsyncStream<Set<String>> { continuation in
            let token = continuations.register(continuation)
            continuation.yield(initial)
            continuation.onTermination = { [continuations] _ in
                continuations.unregister(token)
            }
        }
    }
}

// MARK: - Continuations bookkeeping

/// Multi-subscriber fan-out for `AsyncStream` continuations. Internal
/// to this file; both store implementations share the same helper.
///
/// Each call to `register(_:)` returns a token; `unregister(_:)` removes
/// the matching continuation. `yield(_:)` broadcasts to every live
/// subscriber. `@unchecked Sendable` because the dictionary is guarded
/// by `NSLock`.
private final class Continuations: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<Set<String>>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ continuation: AsyncStream<Set<String>>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = continuation }
        return token
    }

    func unregister(_ token: UUID) {
        lock.withLock { _ = subscribers.removeValue(forKey: token) }
    }

    func yield(_ value: Set<String>) {
        let snapshot: [AsyncStream<Set<String>>.Continuation] = lock.withLock {
            Array(subscribers.values)
        }
        for continuation in snapshot {
            continuation.yield(value)
        }
    }
}
