// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// Wraps any `AddressStore` with iCloud KVS dual-write.
///
/// **Where this lives (and why):** in `HyperliquidAPI`, not in
/// `OpenHLCore`, because `AddressStore` itself lives in `HyperliquidAPI`
/// (it trafficks in `Address` and is colocated with the API client per
/// the rationale in `AddressStore.swift`). Putting the decorator in
/// `OpenHLCore` would force `OpenHLCore` to import `HyperliquidAPI` to
/// see the `AddressStore` protocol, inverting the module-dependency
/// direction documented in §2 of `docs/architecture.md`.
///
/// The dual-write *infrastructure* (`UbiquitousKeyValueStore`,
/// `ICloudBackupToggle`, key constants, timestamp helpers) lives in
/// `OpenHLCore` and is consumed here. So this file is the only piece
/// of the iCloud-backup machinery that lives outside `OpenHLCore`, for
/// the reason above. (Logged as a decision.)
///
/// **Dual-write rule:** every `save(_:)` writes to the wrapped store
/// first, then — if the toggle is enabled — encodes the address as a
/// JSON string and writes it to KVS alongside the current `updatedAt`
/// epoch-ms. `clear()` does the symmetric thing: removes the local
/// value first, then — if enabled — removes both KVS keys. The
/// rationale is that "clear" is an explicit user action that should
/// propagate across devices the same way "save" does.
///
/// **Reconciliation on init:** identical shape to
/// `ICloudBackedFavoriteCoinsStore.reconcile()`. Compare a local
/// UserDefaults `updatedAt` against the KVS one; newer wins; ties
/// prefer local; missing-on-one-side prefers the timestamped peer.
///
/// **External-change hook:** `applyExternalChange()` re-runs
/// reconciliation. The composition root drives this from a long-running
/// `Task` that awaits `kvs.didExternalChange`. Same shape as the
/// favorites decorator — the composition root owns one task per
/// observer chain, not per decorator.
///
/// **Sendable:** `@unchecked Sendable`. Mutable state is the cached
/// toggle flag, guarded by `NSLock`. The wrapped store is `Sendable`
/// by protocol contract.
public final class ICloudBackedAddressStore: AddressStore, @unchecked Sendable {
    /// UserDefaults key for the local `updatedAt` companion. Lives in
    /// UserDefaults (not in KVS) so reconciliation has a stable
    /// local-side timestamp to compare against KVS.
    public static let localUpdatedAtKey: String = "openhl.address.updatedAt"

    private let wrapped: any AddressStore
    private let kvs: any UbiquitousKeyValueStore
    private let toggle: any ICloudBackupToggle
    private let defaults: UserDefaults
    private let clock: EpochMillisClock

    private let lock = NSLock()
    private var enabledCache: Bool

    public init(
        wrapping wrapped: any AddressStore,
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

    // MARK: AddressStore

    public func load() -> Address? {
        wrapped.load()
    }

    public func save(_ address: Address) {
        wrapped.save(address)
        let now = clock()
        defaults.set(now, forKey: Self.localUpdatedAtKey)
        let shouldMirror: Bool = lock.withLock { enabledCache }
        if shouldMirror {
            writeToKVS(address: address, now: now)
        }
    }

    public func clear() {
        wrapped.clear()
        let now = clock()
        defaults.set(now, forKey: Self.localUpdatedAtKey)
        let shouldMirror: Bool = lock.withLock { enabledCache }
        if shouldMirror {
            kvs.set(nil, forKey: ICloudBackupKey.address)
            if let stamp = iCloudEncodeUpdatedAt(now) {
                kvs.set(stamp, forKey: ICloudBackupKey.addressUpdatedAt)
            }
        }
    }

    // MARK: Observation hooks (driven by the composition root)

    /// Called when `toggle.didChange` emits. On OFF→ON, runs
    /// reconciliation so any previously-saved KVS state flows down.
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

    /// Called when `kvs.didExternalChange` emits. Re-runs reconciliation
    /// when the toggle is enabled; no-op otherwise.
    public func applyExternalChange() {
        let enabled: Bool = lock.withLock { enabledCache }
        guard enabled else { return }
        reconcile()
    }

    // MARK: - Reconciliation

    private func reconcile() {
        let localUpdatedAt = defaults.object(forKey: Self.localUpdatedAtKey) as? Int64
        let remoteUpdatedAt = iCloudDecodeUpdatedAt(kvs.data(forKey: ICloudBackupKey.addressUpdatedAt))

        switch (localUpdatedAt, remoteUpdatedAt) {
        case (.some(let local), .some(let remote)) where remote > local:
            adoptRemote()
        case (.none, .some):
            adoptRemote()
        case (.some, .none):
            if let existing = wrapped.load() {
                writeToKVS(address: existing, now: localUpdatedAt ?? clock())
            }
        case (.some(let local), .some(let remote)) where local > remote:
            if let existing = wrapped.load() {
                writeToKVS(address: existing, now: local)
            } else {
                // Local says "cleared at <local>" — propagate the clear.
                kvs.set(nil, forKey: ICloudBackupKey.address)
                if let stamp = iCloudEncodeUpdatedAt(local) {
                    kvs.set(stamp, forKey: ICloudBackupKey.addressUpdatedAt)
                }
            }
        default:
            break
        }
    }

    private func adoptRemote() {
        let raw = kvs.data(forKey: ICloudBackupKey.address)
            .flatMap { try? JSONDecoder().decode(String.self, from: $0) }
        if let raw, let address = Address(validating: raw) {
            wrapped.save(address)
        } else {
            // Remote slot present but payload is `null`/malformed →
            // treat as "remote cleared the address."
            wrapped.clear()
        }
        if let remoteUpdatedAt = iCloudDecodeUpdatedAt(kvs.data(forKey: ICloudBackupKey.addressUpdatedAt)) {
            defaults.set(remoteUpdatedAt, forKey: Self.localUpdatedAtKey)
        }
    }

    private func writeToKVS(address: Address, now: Int64) {
        guard let payload = try? JSONEncoder().encode(address.rawValue),
            let stamp = iCloudEncodeUpdatedAt(now)
        else {
            return
        }
        kvs.set(payload, forKey: ICloudBackupKey.address)
        kvs.set(stamp, forKey: ICloudBackupKey.addressUpdatedAt)
    }
}
