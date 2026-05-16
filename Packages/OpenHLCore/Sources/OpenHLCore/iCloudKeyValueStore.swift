// SPDX-License-Identifier: MIT

import Foundation

/// A thin protocol around `NSUbiquitousKeyValueStore` (iCloud Key-Value
/// Storage). Exists for one reason: production code talks to the real
/// system store; tests inject an in-memory fake.
///
/// **Why a wrapper at all?** `NSUbiquitousKeyValueStore.default` is a
/// process-singleton tied to the app's iCloud container entitlement. In
/// a unit-test bundle with no entitlement, every read returns `nil` and
/// every write is silently dropped — useless for verifying the decorator
/// logic in `iCloudBackup.swift`. A protocol seam lets the decorators
/// take any `UbiquitousKeyValueStore` and lets tests assert behavior
/// deterministically without entitlements.
///
/// **Surface kept tiny on purpose.** Just `data(forKey:)`, `set(_:forKey:)`,
/// `synchronize()` and an `AsyncStream` of external-change events. The
/// decorators don't need typed accessors (`bool(forKey:)`, etc.) — they
/// always traffic in JSON-encoded `Data` because the underlying values
/// (the saved address; the favorites set) are richer than a bool/string
/// and the JSON round-trip is the same code path the existing
/// `UserDefaultsFavoriteCoinsStore` already uses for `UserDefaults`.
///
/// **Sendable:** the protocol is `Sendable`. `NSUbiquitousKeyValueStore`
/// is documented thread-safe for concurrent reads and writes; the
/// production wrapper is `@unchecked Sendable` on that basis. The
/// in-memory fake serializes via `NSLock`.
public protocol UbiquitousKeyValueStore: Sendable {
    /// Returns the value at `key`, or `nil` if no value is stored.
    /// Tests rely on this being synchronous; the real KVS read is also
    /// synchronous (it consults an in-process cache, not iCloud).
    func data(forKey key: String) -> Data?

    /// Writes `data` at `key`. Passing `nil` removes the key. Writes are
    /// flushed to the cloud opportunistically by the system; callers do
    /// not need to call `synchronize()` for correctness, only for
    /// best-effort early-flush right before app suspension.
    func set(_ data: Data?, forKey key: String)

    /// Asks the system to push pending changes immediately. Returns
    /// `false` if the entitlement is missing or the store is otherwise
    /// unavailable. The decorators ignore the return value — KVS is a
    /// best-effort backup channel, not a strong-consistency store.
    @discardableResult
    func synchronize() -> Bool

    /// An async sequence that fires whenever the system reports that a
    /// remote device (or a server-driven reconciliation) wrote new
    /// values to the store. Subscribers receive a void event; they then
    /// re-read whichever keys they care about. Mirrors the
    /// `NSUbiquitousKeyValueStore.didChangeExternallyNotification` shape.
    ///
    /// The production wrapper synthesizes events from the notification
    /// center. The in-memory fake exposes a manual `simulateExternalChange()`
    /// hook so tests can drive the reconciliation path without touching
    /// `NotificationCenter`.
    var didExternalChange: AsyncStream<Void> { get }
}

// MARK: - Production: NSUbiquitousKeyValueStore-backed

/// Production wrapper over `NSUbiquitousKeyValueStore.default`.
///
/// **Entitlement requirement:** this type only works when the app target
/// has the `iCloud → Key-value storage` entitlement. Without it, reads
/// return `nil`, writes are dropped, and `synchronize()` returns `false`.
/// The composition root checks `FileManager.default.ubiquityIdentityToken`
/// before constructing the decorator chain; if the user is not signed
/// into iCloud, we still build the wrapper but the toggle UI surfaces
/// "Not signed into iCloud" copy (see §26.4).
///
/// **External-change observation:** the initializer registers for
/// `NSUbiquitousKeyValueStore.didChangeExternallyNotification` from the
/// underlying store (not from `default` — same object, but explicit
/// makes the data flow obvious). Each notification yields a `()` to the
/// shared continuation. Multiple subscribers fan out via the same
/// `Continuations` pattern used by `FavoriteCoinsStore`.
///
/// **Sendable:** `NSUbiquitousKeyValueStore` is documented as thread-safe
/// for property-list reads and writes. The wrapper holds the system store
/// and a `Continuations` helper guarded by `NSLock`. `@unchecked Sendable`
/// with those two as justification.
public final class SystemUbiquitousKeyValueStore: UbiquitousKeyValueStore, @unchecked Sendable {
    private let store: NSUbiquitousKeyValueStore
    private let continuations: VoidContinuations
    private let observerToken: NSObjectProtocol

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
        let continuations = VoidContinuations()
        self.continuations = continuations
        // Capture-by-reference: NotificationCenter retains the block until
        // we remove the observer in `deinit`. The wrapper is process-lived
        // (held by the composition root for the duration of the app), so
        // there is no realistic leak window.
        self.observerToken = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: nil
        ) { _ in
            continuations.yield()
        }
        // Ask the system to pull any pending remote changes on construction.
        // `synchronize()` is best-effort; the return value is informational.
        _ = store.synchronize()
    }

    deinit {
        NotificationCenter.default.removeObserver(observerToken)
        continuations.finishAll()
    }

    public func data(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            store.set(data, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    @discardableResult
    public func synchronize() -> Bool {
        store.synchronize()
    }

    public var didExternalChange: AsyncStream<Void> {
        AsyncStream<Void> { continuation in
            let token = continuations.register(continuation)
            continuation.onTermination = { [continuations] _ in
                continuations.unregister(token)
            }
        }
    }
}

// MARK: - Test/preview: In-memory

/// In-memory fake. Stores values in a dictionary behind an `NSLock`,
/// exposes a `simulateExternalChange()` hook so tests can drive the
/// reconciliation path deterministically.
///
/// `synchronize()` always returns `true` here — the fake has no remote
/// counterpart to fail on. Tests that want to assert "entitlement is
/// missing" should use a distinct fake variant; we do not over-model
/// failure modes that the production wrapper itself smooths over.
public final class InMemoryUbiquitousKeyValueStore: UbiquitousKeyValueStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()
    private let continuations: VoidContinuations

    public init(initial: [String: Data] = [:]) {
        self.storage = initial
        self.continuations = VoidContinuations()
    }

    public func data(forKey key: String) -> Data? {
        lock.withLock { storage[key] }
    }

    public func set(_ data: Data?, forKey key: String) {
        lock.withLock {
            if let data {
                storage[key] = data
            } else {
                storage.removeValue(forKey: key)
            }
        }
    }

    @discardableResult
    public func synchronize() -> Bool { true }

    public var didExternalChange: AsyncStream<Void> {
        AsyncStream<Void> { continuation in
            let token = continuations.register(continuation)
            continuation.onTermination = { [continuations] _ in
                continuations.unregister(token)
            }
        }
    }

    /// Test hook: simulate a remote write landing on this device. Mutates
    /// the storage dictionary (so subsequent `data(forKey:)` calls see
    /// the new value), then fires the external-change event.
    public func simulateExternalChange(setting values: [String: Data?]) {
        lock.withLock {
            for (key, value) in values {
                if let value {
                    storage[key] = value
                } else {
                    storage.removeValue(forKey: key)
                }
            }
        }
        continuations.yield()
    }
}

// MARK: - Continuations bookkeeping

/// Multi-subscriber fan-out for `AsyncStream<Void>` continuations.
/// Internal to this file; mirrors the `Continuations` helper in
/// `FavoriteCoinsStore.swift`, but parameterised over `Void` and exposed
/// as `internal` so `iCloudBackup.swift` (same module) can also reuse it.
///
/// `@unchecked Sendable` because the dictionary is guarded by `NSLock`.
final class VoidContinuations: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ continuation: AsyncStream<Void>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = continuation }
        return token
    }

    func unregister(_ token: UUID) {
        lock.withLock { _ = subscribers.removeValue(forKey: token) }
    }

    func yield() {
        let snapshot: [AsyncStream<Void>.Continuation] = lock.withLock {
            Array(subscribers.values)
        }
        for continuation in snapshot {
            continuation.yield(())
        }
    }

    func finishAll() {
        let snapshot: [AsyncStream<Void>.Continuation] = lock.withLock {
            let all = Array(subscribers.values)
            subscribers.removeAll()
            return all
        }
        for continuation in snapshot {
            continuation.finish()
        }
    }
}
