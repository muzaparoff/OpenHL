// SPDX-License-Identifier: MIT

import Foundation

// MARK: - Toggle

/// User-facing on/off for iCloud Key-Value backup. Owned by the
/// Settings screen, read by the composition root, observed by the
/// decorator stores so they can pause/resume their dual-write logic
/// without the app having to rebuild the store graph.
///
/// **Default is OFF.** Wallet addresses are public on-chain, but the
/// privacy posture of this app says nothing leaves the device unless
/// the user opts in. Toggling OFF does NOT delete iCloud data — the
/// user can re-enable later to recover (see §26.3 for the reconciliation
/// rules).
///
/// **Observation:** `didChange` emits the *current* value on subscription,
/// then a new value on every flip. The decorators subscribe inside their
/// own initializers and update a local `_isEnabled` flag; this avoids
/// reading from the toggle on every `save(_:)` and keeps the dual-write
/// path branch-free under steady state.
///
/// **Sendable:** the protocol is `Sendable`. Concrete impls declare
/// `@unchecked Sendable` and guard mutation with `NSLock`, matching the
/// existing stores.
public protocol ICloudBackupToggle: Sendable {
    /// Snapshot of the current state. The decorators use this once at
    /// init, then track changes via `didChange`.
    var isEnabled: Bool { get }

    /// Flip the state. Idempotent: setting to the current value is a
    /// no-op (no `didChange` emission).
    func setEnabled(_ enabled: Bool)

    /// Async sequence of the toggle state. Emits the current value
    /// immediately on subscription, then a new value on every change.
    var didChange: AsyncStream<Bool> { get }
}

/// Production implementation. Backed by `UserDefaults` so the user's
/// preference itself survives reinstalls *only via* the system's
/// defaults-restore behavior. We deliberately do NOT store the toggle
/// state in iCloud KVS: doing so would mean "you turned on iCloud
/// backup on device A; device B now opportunistically dual-writes to
/// iCloud without you ever opening Settings on device B." Even though
/// the data is identical, that is a surprise the user did not consent
/// to per device.
///
/// **Storage key:** `"openhl.iCloudBackup.enabled"` — namespaced under
/// `openhl.` like every other UserDefaults key.
public final class UserDefaultsICloudBackupToggle: ICloudBackupToggle, @unchecked Sendable {
    /// The key under which the toggle state is stored. Public so tests
    /// can pre-seed a defaults instance without depending on this class.
    public static let storageKey: String = "openhl.iCloudBackup.enabled"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cached: Bool
    private let continuations: BoolContinuations

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `bool(forKey:)` returns `false` for a missing key, which is
        // exactly the default-OFF semantics we want.
        self.cached = defaults.bool(forKey: Self.storageKey)
        self.continuations = BoolContinuations()
    }

    public var isEnabled: Bool {
        lock.withLock { cached }
    }

    public func setEnabled(_ enabled: Bool) {
        let didChange: Bool = lock.withLock {
            guard cached != enabled else { return false }
            cached = enabled
            defaults.set(enabled, forKey: Self.storageKey)
            return true
        }
        if didChange {
            continuations.yield(enabled)
        }
    }

    public var didChange: AsyncStream<Bool> {
        let initial = isEnabled
        return AsyncStream<Bool> { continuation in
            let token = continuations.register(continuation)
            continuation.yield(initial)
            continuation.onTermination = { [continuations] _ in
                continuations.unregister(token)
            }
        }
    }
}

/// In-memory toggle for tests and previews.
public final class InMemoryICloudBackupToggle: ICloudBackupToggle, @unchecked Sendable {
    private var cached: Bool
    private let lock = NSLock()
    private let continuations: BoolContinuations

    public init(initial: Bool = false) {
        self.cached = initial
        self.continuations = BoolContinuations()
    }

    public var isEnabled: Bool {
        lock.withLock { cached }
    }

    public func setEnabled(_ enabled: Bool) {
        let didChange: Bool = lock.withLock {
            guard cached != enabled else { return false }
            cached = enabled
            return true
        }
        if didChange {
            continuations.yield(enabled)
        }
    }

    public var didChange: AsyncStream<Bool> {
        let initial = isEnabled
        return AsyncStream<Bool> { continuation in
            let token = continuations.register(continuation)
            continuation.yield(initial)
            continuation.onTermination = { [continuations] _ in
                continuations.unregister(token)
            }
        }
    }
}

// MARK: - KVS key layout

/// Centralised key constants for everything written to iCloud KVS.
/// Two namespaces: the payload key and a companion `updatedAt` epoch-ms
/// key used for last-writer-wins reconciliation on app launch.
///
/// Keys are kept short — KVS imposes a 1 MB total-store quota and a
/// 1024-key cap. We are nowhere near either, but shorter keys are also
/// less likely to collide with any future namespace addition.
public enum ICloudBackupKey {
    /// Saved wallet address (canonical lowercase 0x-hex string),
    /// JSON-encoded as a `String` for parity with the favorites payload.
    public static let address: String = "openhl.address"

    /// Last-write timestamp for `address`, in epoch milliseconds, stored
    /// as a JSON-encoded `Int64`.
    public static let addressUpdatedAt: String = "openhl.address.updatedAt"

    /// Favorite coins set, JSON-encoded as a sorted `[String]` (sorted at
    /// write time for stable on-disk bytes; matches the on-disk format
    /// used by `UserDefaultsFavoriteCoinsStore`).
    public static let favoriteCoins: String = "openhl.favoriteCoins"

    /// Last-write timestamp for `favoriteCoins`, epoch milliseconds.
    public static let favoriteCoinsUpdatedAt: String = "openhl.favoriteCoins.updatedAt"
}

// MARK: - Reconciliation helpers

/// Decodes an `updatedAt` epoch-ms value out of a JSON-encoded `Int64`
/// blob, returning `nil` for missing or malformed payloads. Shared by
/// the address and favorites decorators. `public` so the
/// `ICloudBackedAddressStore` (which lives in `HyperliquidAPI`) can
/// call it.
public func iCloudDecodeUpdatedAt(_ data: Data?) -> Int64? {
    guard let data else { return nil }
    return try? JSONDecoder().decode(Int64.self, from: data)
}

/// Encodes an `updatedAt` epoch-ms value as JSON.
public func iCloudEncodeUpdatedAt(_ value: Int64) -> Data? {
    try? JSONEncoder().encode(value)
}

/// Current wall-clock time in epoch milliseconds. Lifted out for testability:
/// the decorators receive a `() -> Int64` closure so tests can pin time.
public typealias EpochMillisClock = @Sendable () -> Int64

/// Default production clock: `Date().timeIntervalSince1970 * 1000`,
/// truncated to `Int64`. We do not use `OpenHLCore.Clock` here because
/// `Clock` returns `Date` and KVS reconciliation only cares about
/// integer millis — the smaller surface is the right shape.
public let systemEpochMillisClock: EpochMillisClock = {
    Int64(Date().timeIntervalSince1970 * 1000)
}

// MARK: - FavoriteCoinsStore decorator

/// Wraps any `FavoriteCoinsStore` with iCloud KVS dual-write. The
/// wrapped store is the source of truth for reads; KVS is a backup
/// channel.
///
/// **Dual-write rule:** every `toggle(_:)` writes to the wrapped store
/// first (so the local UI is always consistent), then — if the toggle
/// is currently enabled — encodes the new set and the current
/// `updatedAt` epoch-ms into KVS. KVS write failures (no entitlement,
/// no iCloud account, quota exceeded) are silently swallowed: the
/// wrapped store still has the value, so the user's data is not lost.
///
/// **Reconciliation on init:** if the toggle is enabled, compare the
/// wrapped store's `updatedAt` (read from a parallel UserDefaults key)
/// against the KVS `updatedAt`. Whichever is newer wins; the loser is
/// overwritten. Ties prefer the local store (avoids spurious churn on
/// devices that wrote the same content concurrently). Missing values
/// on either side are treated as "infinitely old" and lose to any
/// timestamped peer.
///
/// **External changes:** subscribes to `kvs.didExternalChange` for the
/// lifetime of the decorator. On each event, re-runs the same
/// reconciliation logic. New favorites from device B land on device A
/// without the user having to relaunch.
///
/// **Toggle changes:** subscribes to `toggle.didChange`. On OFF→ON, runs
/// reconciliation once (so a previously-saved KVS state can flow down
/// to the local store). On ON→OFF, does nothing — the wrapped store
/// keeps serving reads and writes, KVS just stops receiving new writes.
///
/// **Sendable:** `@unchecked Sendable`. Internal mutable state (the
/// cached `isEnabled` flag and the last-known local `updatedAt`) is
/// guarded by `NSLock`. The decorator does not spawn its own background
/// tasks; observation loops are owned by the composition root and run
/// on detached tasks tied to the app's lifecycle (see §26.5).
public final class ICloudBackedFavoriteCoinsStore: FavoriteCoinsStore, @unchecked Sendable {
    /// UserDefaults key for the local `updatedAt` companion. Kept in
    /// UserDefaults (not KVS) so we have a stable local-side timestamp
    /// to compare against KVS during reconciliation.
    public static let localUpdatedAtKey: String = "openhl.favoriteCoins.updatedAt"

    private let wrapped: any FavoriteCoinsStore
    private let kvs: any UbiquitousKeyValueStore
    private let toggle: any ICloudBackupToggle
    private let defaults: UserDefaults
    private let clock: EpochMillisClock

    private let lock = NSLock()
    private var enabledCache: Bool

    public init(
        wrapping wrapped: any FavoriteCoinsStore,
        kvs: any UbiquitousKeyValueStore,
        toggle: any ICloudBackupToggle,
        defaults: UserDefaults = .standard,
        clock: @escaping EpochMillisClock = systemEpochMillisClock
    ) {
        self.wrapped = wrapped
        self.kvs = kvs
        self.toggle = toggle
        self.defaults = defaults
        self.clock = clock
        self.enabledCache = toggle.isEnabled
        if enabledCache {
            reconcile()
        }
    }

    // MARK: FavoriteCoinsStore

    public func isFavorite(_ coin: String) -> Bool {
        wrapped.isFavorite(coin)
    }

    public func toggle(_ coin: String) {
        wrapped.toggle(coin)
        let now = clock()
        defaults.set(now, forKey: Self.localUpdatedAtKey)
        let shouldMirror: Bool = lock.withLock { enabledCache }
        if shouldMirror {
            writeToKVS(now: now)
        }
    }

    public func all() -> Set<String> {
        wrapped.all()
    }

    public var didChange: AsyncStream<Set<String>> {
        wrapped.didChange
    }

    // MARK: Observation hooks (called by the composition root)

    /// Called by the composition root inside a long-running `Task` that
    /// awaits `toggle.didChange`. On every emission, updates the cached
    /// flag and, on OFF→ON, runs reconciliation once.
    public func applyToggle(_ enabled: Bool) {
        let prior: Bool = lock.withLock {
            let p = enabledCache
            enabledCache = enabled
            return p
        }
        if !prior, enabled {
            reconcile()
        }
    }

    /// Called by the composition root inside a long-running `Task` that
    /// awaits `kvs.didExternalChange`. Re-runs reconciliation if the
    /// toggle is enabled; no-op otherwise.
    public func applyExternalChange() {
        let enabled: Bool = lock.withLock { enabledCache }
        guard enabled else { return }
        reconcile()
    }

    // MARK: - Reconciliation

    private func reconcile() {
        let localUpdatedAt = defaults.object(forKey: Self.localUpdatedAtKey) as? Int64
        let remoteUpdatedAt = iCloudDecodeUpdatedAt(kvs.data(forKey: ICloudBackupKey.favoriteCoinsUpdatedAt))

        switch (localUpdatedAt, remoteUpdatedAt) {
        case (.some(let local), .some(let remote)) where remote > local:
            adoptRemote()
        case (.none, .some):
            adoptRemote()
        case (.some, .none):
            // Local has data and remote doesn't — push local up.
            writeToKVS(now: localUpdatedAt ?? clock())
        case (.some(let local), .some(let remote)) where local > remote:
            writeToKVS(now: local)
        default:
            // Equal timestamps or both nil: nothing to do.
            break
        }
    }

    private func adoptRemote() {
        guard let payload = kvs.data(forKey: ICloudBackupKey.favoriteCoins),
            let array = try? JSONDecoder().decode([String].self, from: payload)
        else {
            return
        }
        let remote = Set(array)
        let current = wrapped.all()
        // Toggle into the wrapped store. The wrapped store's `toggle`
        // is the only public mutator; we use symmetric difference so the
        // end-state matches `remote`.
        let toFlip = current.symmetricDifference(remote)
        for coin in toFlip {
            wrapped.toggle(coin)
        }
        if let remoteUpdatedAt = iCloudDecodeUpdatedAt(kvs.data(forKey: ICloudBackupKey.favoriteCoinsUpdatedAt)) {
            defaults.set(remoteUpdatedAt, forKey: Self.localUpdatedAtKey)
        }
    }

    private func writeToKVS(now: Int64) {
        let sorted = wrapped.all().sorted()
        guard let payload = try? JSONEncoder().encode(sorted),
            let stamp = iCloudEncodeUpdatedAt(now)
        else {
            return
        }
        kvs.set(payload, forKey: ICloudBackupKey.favoriteCoins)
        kvs.set(stamp, forKey: ICloudBackupKey.favoriteCoinsUpdatedAt)
    }
}

// MARK: - Continuations bookkeeping (Bool)

/// Multi-subscriber fan-out for `AsyncStream<Bool>`. Internal to the
/// module; mirrors `VoidContinuations` and the `Continuations` helper
/// in `FavoriteCoinsStore.swift`.
final class BoolContinuations: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ continuation: AsyncStream<Bool>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = continuation }
        return token
    }

    func unregister(_ token: UUID) {
        lock.withLock { _ = subscribers.removeValue(forKey: token) }
    }

    func yield(_ value: Bool) {
        let snapshot: [AsyncStream<Bool>.Continuation] = lock.withLock {
            Array(subscribers.values)
        }
        for continuation in snapshot {
            continuation.yield(value)
        }
    }
}
