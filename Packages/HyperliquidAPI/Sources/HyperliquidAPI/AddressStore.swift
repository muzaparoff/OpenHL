// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// Persists the user's saved wallet address across launches.
///
/// **Where this lives:** `HyperliquidAPI`, not `OpenHLCore`. Rationale:
/// `OpenHLCore` is a pure-value-types leaf with no I/O. A protocol whose
/// concrete implementation does `UserDefaults` I/O (and may later do
/// Keychain I/O) is not pure. Phase 1 has exactly one consumer of
/// `AddressStore` (the address-entry view model) which already imports
/// `HyperliquidAPI` for the client, so co-locating the protocol there
/// adds no new import edges and keeps `OpenHLCore` clean. (Logged as a
/// decision.)
///
/// All methods are synchronous. `UserDefaults` reads and writes are fast
/// and lock-free at this scale; making the protocol `async` would buy us
/// nothing and force every caller into an `await`.
///
/// `Sendable`: the protocol itself is `Sendable`. The default
/// `UserDefaultsAddressStore` is a `struct` over the thread-safe
/// `UserDefaults` reference, and is therefore `Sendable`.
public protocol AddressStore: Sendable {
    /// Returns the saved address, or `nil` if nothing has been saved yet
    /// or the stored value fails `Address` validation (defensive: a
    /// malformed value in storage from an older build is treated as
    /// "nothing saved" and overwritten on next save).
    func load() -> Address?

    /// Persists the address. Overwrites any previous value.
    func save(_ address: Address)

    /// Removes the saved address. Used by a future "clear address" UI
    /// affordance and by tests.
    func clear()
}

/// Production implementation. Backed by a `UserDefaults` instance
/// (`standard` by default; tests inject a suite-backed instance).
///
/// `UserDefaults` is not formally `Sendable` in Swift 6, but `UserDefaults`
/// is documented to be thread-safe for read/write operations. We declare
/// `@unchecked Sendable` here with that documented thread-safety as
/// justification. The struct holds no other mutable state.
public struct UserDefaultsAddressStore: AddressStore, @unchecked Sendable {
    /// The key under which the address is stored. Public so tests can
    /// pre-seed a defaults instance without depending on this struct.
    public static let storageKey: String = "openhl.address"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Address? {
        guard let raw = defaults.string(forKey: Self.storageKey) else { return nil }
        return Address(validating: raw)
    }

    public func save(_ address: Address) {
        defaults.set(address.rawValue, forKey: Self.storageKey)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

/// In-memory fake for tests. Thread-safe via an internal lock; `Sendable`
/// via `@unchecked Sendable` with the lock as justification.
public final class InMemoryAddressStore: AddressStore, @unchecked Sendable {
    private var _address: Address?
    private let lock = NSLock()

    public init(initial: Address? = nil) {
        _address = initial
    }

    public func load() -> Address? {
        lock.withLock { _address }
    }

    public func save(_ address: Address) {
        lock.withLock { _address = address }
    }

    public func clear() {
        lock.withLock { _address = nil }
    }
}
