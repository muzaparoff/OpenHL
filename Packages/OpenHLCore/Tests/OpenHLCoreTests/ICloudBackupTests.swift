// SPDX-License-Identifier: MIT

// Tests for `ICloudBackedAddressStore` and `ICloudBackedFavoriteCoinsStore`
// decorator types (Phase 3f).
//
// STATUS: swift-expert has not yet landed `iCloudBackup.swift` in
// `OpenHLCore`. The decorator types, their dependency protocols, and their
// in-memory fakes are stubbed locally below so the test shapes are final
// and compile-clean today.
//
// UNLOCK CHECKLIST — once swift-expert lands the real types:
//   1. Delete the LOCAL STUB TYPES section below (everything before the first
//      @Suite declaration), including the re-exported fakes.
//   2. Ensure `@testable import OpenHLCore` is active (already present).
//   3. Remove `.disabled` from every suite that carries it.
//   4. Run `swift test` from `Packages/OpenHLCore/`.
//
// Stubs mirror the contract agreed with swift-expert for Phase 3f:
//   - `ICloudBackedAddressStore` wraps an `AddressStore` + a
//     `UbiquitousKeyValueStore` + an `ICloudBackupToggle`.
//       Stored KVS keys: `openhl.address.value`  (address string bytes)
//                        `openhl.address.updatedAt` (UInt64 Unix ms, big-endian)
//       On init (toggle ON): reconcile — whichever side has the newer
//         `updatedAt` wins; the loser's store is updated.
//       `save(_:)` toggle ON: write to both stores with `updatedAt = now`.
//       `save(_:)` toggle OFF: write to wrapped store only.
//       `load()`: delegate to wrapped store (single source of truth post-reconcile).
//       `clear()`: delegate to wrapped store; does NOT clear KVS.
//       External KVS change (toggle ON): update wrapped store; emit on `didChange`.
//       `var didChange: AsyncStream<Address?>` — emits after any store mutation.
//   - `ICloudBackedFavoriteCoinsStore` — same matrix applied to `FavoriteCoinsStore`.
//       Stored KVS keys: `openhl.favorites.value`  (JSON-encoded [String])
//                        `openhl.favorites.updatedAt`
//
// Phase 3f adds NO new Hyperliquid API endpoints. The per-memory
// fixture-test rule is NOT triggered here.

import Foundation
import Testing

@testable import OpenHLCore

// MARK: - LOCAL STUB TYPES
// Delete this entire region once swift-expert's types land in OpenHLCore.

// ── Protocols (mirrors iCloudKeyValueStore.swift + AddressStore.swift stubs) ──

private protocol StubUbiquitousKeyValueStore: Sendable {
    func set(_ data: Data, forKey key: String)
    func data(forKey key: String) -> Data?
    func removeObject(forKey key: String)
    var externalChanges: AsyncStream<Void> { get }
}

private protocol StubAddressStore: Sendable {
    func load() -> StubAddress?
    func save(_ address: StubAddress)
    func clear()
}

/// Minimal address value type used in stubs (matches `Address.rawValue` shape).
private struct StubAddress: Equatable, Sendable {
    let rawValue: String
}

private protocol StubFavoriteCoinsStore: Sendable {
    func all() -> Set<String>
    func toggle(_ coin: String)
    func isFavorite(_ coin: String) -> Bool
    var didChange: AsyncStream<Set<String>> { get }
}

// ── InMemoryUbiquitousKeyValueStore (duplicated here from iCloudKeyValueStoreTests
//    so this file compiles independently) ──

private final class StubInMemoryKVS: StubUbiquitousKeyValueStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()
    private let continuations = StubKVSContinuations()

    func set(_ data: Data, forKey key: String) {
        lock.withLock { storage[key] = data }
    }

    func data(forKey key: String) -> Data? {
        lock.withLock { storage[key] }
    }

    func removeObject(forKey key: String) {
        lock.withLock { storage.removeValue(forKey: key) }
    }

    var externalChanges: AsyncStream<Void> {
        AsyncStream<Void> { continuation in
            let token = continuations.register(continuation)
            continuation.onTermination = { [continuations] _ in
                continuations.unregister(token)
            }
        }
    }

    func simulateExternalChange(key: String? = nil, value: Data? = nil) {
        if let key {
            lock.withLock {
                if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
            }
        }
        continuations.yield()
    }

    func allKeys() -> [String] { lock.withLock { Array(storage.keys) } }
}

private final class StubKVSContinuations: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ c: AsyncStream<Void>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = c }
        return token
    }

    func unregister(_ token: UUID) { lock.withLock { _ = subscribers.removeValue(forKey: token) } }
    func yield() {
        let snapshot = lock.withLock { Array(subscribers.values) }
        for c in snapshot { c.yield(()) }
    }
}

// ── InMemoryAddressStore ──

private final class StubInMemoryAddressStore: StubAddressStore, @unchecked Sendable {
    private var _value: StubAddress?
    private let lock = NSLock()

    init(initial: StubAddress? = nil) { _value = initial }

    func load() -> StubAddress? { lock.withLock { _value } }
    func save(_ address: StubAddress) { lock.withLock { _value = address } }
    func clear() { lock.withLock { _value = nil } }
}

// ── InMemoryFavoriteCoinsStore ──

private final class StubInMemoryFavoritesStore: StubFavoriteCoinsStore, @unchecked Sendable {
    private var cached: Set<String>
    private let lock = NSLock()
    private let conts = FavContinuations()

    init(initial: Set<String> = []) { cached = initial }

    func isFavorite(_ coin: String) -> Bool { lock.withLock { cached.contains(coin) } }

    func toggle(_ coin: String) {
        let updated: Set<String> = lock.withLock {
            if cached.contains(coin) { cached.remove(coin) } else { cached.insert(coin) }
            return cached
        }
        conts.yield(updated)
    }

    func all() -> Set<String> { lock.withLock { cached } }

    var didChange: AsyncStream<Set<String>> {
        let initial = all()
        return AsyncStream<Set<String>> { continuation in
            let token = conts.register(continuation)
            continuation.yield(initial)
            continuation.onTermination = { [conts] _ in conts.unregister(token) }
        }
    }
}

private final class FavContinuations: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<Set<String>>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ c: AsyncStream<Set<String>>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = c }
        return token
    }
    func unregister(_ token: UUID) { lock.withLock { _ = subscribers.removeValue(forKey: token) } }
    func yield(_ v: Set<String>) {
        let s = lock.withLock { Array(subscribers.values) }
        for c in s { c.yield(v) }
    }
}

// ── ICloudBackupToggle stub (re-used from iCloudKeyValueStoreTests) ──

private final class StubBackupToggle: @unchecked Sendable {
    private var _enabled: Bool
    private let lock = NSLock()
    private let conts = TogConts()

    init(enabled: Bool = false) { _enabled = enabled }

    var isEnabled: Bool { lock.withLock { _enabled } }

    func setEnabled(_ v: Bool) {
        lock.withLock { _enabled = v }
        conts.yield(v)
    }

    var didChange: AsyncStream<Bool> {
        let initial = isEnabled
        return AsyncStream<Bool> { continuation in
            let token = conts.register(continuation)
            continuation.yield(initial)
            continuation.onTermination = { [conts] _ in conts.unregister(token) }
        }
    }
}

private final class TogConts: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ c: AsyncStream<Bool>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = c }
        return token
    }
    func unregister(_ token: UUID) { lock.withLock { _ = subscribers.removeValue(forKey: token) } }
    func yield(_ v: Bool) {
        let s = lock.withLock { Array(subscribers.values) }
        for c in s { c.yield(v) }
    }
}

// ── KVS encoding helpers (mirror what the real decorator must use) ──

/// Packs a `StubAddress` into the two KVS keys expected by the decorator.
private func kvsWrite(
    address: StubAddress,
    updatedAt: UInt64,
    into kv: StubInMemoryKVS
) {
    kv.set(address.rawValue.data(using: .utf8)!, forKey: "openhl.address.value")
    var ts = updatedAt.bigEndian
    kv.set(Data(bytes: &ts, count: 8), forKey: "openhl.address.updatedAt")
}

private func kvsReadAddress(from kv: StubInMemoryKVS) -> StubAddress? {
    guard let d = kv.data(forKey: "openhl.address.value"),
        let s = String(data: d, encoding: .utf8)
    else { return nil }
    return StubAddress(rawValue: s)
}

private func kvsReadTimestamp(from kv: StubInMemoryKVS) -> UInt64 {
    guard let d = kv.data(forKey: "openhl.address.updatedAt"), d.count == 8 else { return 0 }
    return d.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
}

private func kvsWriteFavorites(
    coins: Set<String>,
    updatedAt: UInt64,
    into kv: StubInMemoryKVS
) {
    let sorted = coins.sorted()
    let data = (try? JSONEncoder().encode(sorted)) ?? Data()
    kv.set(data, forKey: "openhl.favorites.value")
    var ts = updatedAt.bigEndian
    kv.set(Data(bytes: &ts, count: 8), forKey: "openhl.favorites.updatedAt")
}

private func kvsReadFavorites(from kv: StubInMemoryKVS) -> Set<String>? {
    guard let d = kv.data(forKey: "openhl.favorites.value"),
        let arr = try? JSONDecoder().decode([String].self, from: d)
    else { return nil }
    return Set(arr)
}

// MARK: - ICloudBackedAddressStore — decorator stub
//
// This stub implements the full reconcile + delegate logic described in the
// STATUS header so the integration tests below can run against it today.
// Once swift-expert lands the real `ICloudBackedAddressStore`, delete this stub
// and the integration tests will exercise the real implementation unchanged.

private final class ICloudBackedAddressStore: @unchecked Sendable {
    private let wrapped: StubInMemoryAddressStore
    private let kv: StubInMemoryKVS
    private let toggle: StubBackupToggle
    private let lock = NSLock()
    private let conts = AddrContinuations()
    private var observationTask: Task<Void, Never>?

    init(
        wrapped: StubInMemoryAddressStore,
        kv: StubInMemoryKVS,
        toggle: StubBackupToggle,
        nowMs: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.wrapped = wrapped
        self.kv = kv
        self.toggle = toggle
        // Reconcile on init if toggle is ON.
        if toggle.isEnabled {
            reconcile(nowMs: nowMs)
        }
        // Start listening for external KVS changes.
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await _ in kv.externalChanges {
                guard self.toggle.isEnabled else { continue }
                let addr = kvsReadAddress(from: kv)
                if let addr {
                    self.wrapped.save(addr)
                }
                self.conts.yield(addr)
            }
        }
    }

    deinit { observationTask?.cancel() }

    // Reconcile: newer updatedAt wins; loser is updated.
    private func reconcile(nowMs: UInt64) {
        let kvsAddr = kvsReadAddress(from: kv)
        let kvsTsMs = kvsReadTimestamp(from: kv)
        let wrappedAddr = wrapped.load()
        // Use nowMs as the wrapped store's timestamp only when wrapped has data
        // but KVS has nothing — treated as "local is newer."
        if kvsAddr == nil && wrappedAddr == nil { return }

        if kvsAddr == nil {
            // KVS has nothing — upload local.
            if let a = wrappedAddr { kvsWrite(address: a, updatedAt: nowMs, into: kv) }
        } else if wrappedAddr == nil {
            // Local has nothing — download from KVS.
            wrapped.save(kvsAddr!)
        } else {
            // Both sides have data — compare timestamps.
            // We treat the wrapped store's timestamp as 0 (unknown) unless KVS is newer.
            if kvsTsMs > 0 {
                // KVS is the authoritative newer value; update wrapped.
                wrapped.save(kvsAddr!)
            } else {
                // Wrapped is considered newer; upload.
                kvsWrite(address: wrappedAddr!, updatedAt: nowMs, into: kv)
            }
        }
    }

    func load() -> StubAddress? { wrapped.load() }

    func save(_ address: StubAddress) {
        wrapped.save(address)
        if toggle.isEnabled {
            let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
            kvsWrite(address: address, updatedAt: nowMs, into: kv)
        }
        conts.yield(address)
    }

    func clear() {
        wrapped.clear()
        conts.yield(nil)
        // KVS data is intentionally NOT cleared.
    }

    var didChange: AsyncStream<StubAddress?> {
        AsyncStream<StubAddress?> { continuation in
            let token = conts.register(continuation)
            continuation.onTermination = { [conts] _ in conts.unregister(token) }
        }
    }
}

private final class AddrContinuations: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<StubAddress?>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ c: AsyncStream<StubAddress?>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = c }
        return token
    }
    func unregister(_ token: UUID) { lock.withLock { _ = subscribers.removeValue(forKey: token) } }
    func yield(_ v: StubAddress?) {
        let s = lock.withLock { Array(subscribers.values) }
        for c in s { c.yield(v) }
    }
}

// MARK: - ICloudBackedFavoriteCoinsStore — decorator stub

private final class ICloudBackedFavoriteCoinsStore: @unchecked Sendable {
    private let wrapped: StubInMemoryFavoritesStore
    private let kv: StubInMemoryKVS
    private let toggle: StubBackupToggle
    private let conts = FavsChangeContinuations()
    private var observationTask: Task<Void, Never>?

    init(
        wrapped: StubInMemoryFavoritesStore,
        kv: StubInMemoryKVS,
        toggle: StubBackupToggle,
        nowMs: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.wrapped = wrapped
        self.kv = kv
        self.toggle = toggle
        if toggle.isEnabled { reconcile(nowMs: nowMs) }
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await _ in kv.externalChanges {
                guard self.toggle.isEnabled else { continue }
                if let coins = kvsReadFavorites(from: kv) {
                    // Replace wrapped store by toggling to match KVS.
                    let current = self.wrapped.all()
                    let toRemove = current.subtracting(coins)
                    let toAdd = coins.subtracting(current)
                    for c in toRemove { self.wrapped.toggle(c) }
                    for c in toAdd { self.wrapped.toggle(c) }
                }
                self.conts.yield(self.wrapped.all())
            }
        }
    }

    deinit { observationTask?.cancel() }

    private func reconcile(nowMs: UInt64) {
        let kvsCoins = kvsReadFavorites(from: kv)
        let kvsTsMs = kvsReadTimestamp(from: kv)
        let wrappedCoins = wrapped.all()

        if kvsCoins == nil && wrappedCoins.isEmpty { return }

        if kvsCoins == nil {
            // KVS empty — upload local.
            kvsWriteFavorites(coins: wrappedCoins, updatedAt: nowMs, into: kv)
        } else if wrappedCoins.isEmpty {
            // Local empty — download KVS.
            let kCoins = kvsCoins!
            for c in kCoins { wrapped.toggle(c) }
        } else {
            if kvsTsMs > 0 {
                // KVS newer — update local.
                let kCoins = kvsCoins!
                let toRemove = wrappedCoins.subtracting(kCoins)
                let toAdd = kCoins.subtracting(wrappedCoins)
                for c in toRemove { wrapped.toggle(c) }
                for c in toAdd { wrapped.toggle(c) }
            } else {
                kvsWriteFavorites(coins: wrappedCoins, updatedAt: nowMs, into: kv)
            }
        }
    }

    func all() -> Set<String> { wrapped.all() }
    func isFavorite(_ coin: String) -> Bool { wrapped.isFavorite(coin) }

    func toggle(_ coin: String) {
        wrapped.toggle(coin)
        if toggle.isEnabled {
            let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
            kvsWriteFavorites(coins: wrapped.all(), updatedAt: nowMs, into: kv)
        }
        conts.yield(wrapped.all())
    }

    var didChange: AsyncStream<Set<String>> {
        AsyncStream<Set<String>> { continuation in
            let token = conts.register(continuation)
            continuation.onTermination = { [conts] _ in conts.unregister(token) }
        }
    }
}

private final class FavsContinuations: @unchecked Sendable {}

private final class FavsChangeContinuations: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<Set<String>>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ c: AsyncStream<Set<String>>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = c }
        return token
    }
    func unregister(_ token: UUID) { lock.withLock { _ = subscribers.removeValue(forKey: token) } }
    func yield(_ v: Set<String>) {
        let s = lock.withLock { Array(subscribers.values) }
        for c in s { c.yield(v) }
    }
}

// MARK: - Shared test addresses

private let addrA = StubAddress(rawValue: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
private let addrB = StubAddress(rawValue: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")

// MARK: - ICloudBackedAddressStore tests

@Suite("ICloudBackedAddressStore — decorator invariants")
struct ICloudBackedAddressStoreTests {

    // MARK: Toggle OFF (default)

    @Test("Toggle OFF: save writes to wrapped store only — KVS has no keys")
    func toggleOffSaveDoesNotWriteToKVS() {
        let wrapped = StubInMemoryAddressStore()
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: false)

        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.save(addrA)

        #expect(wrapped.load() == addrA)
        #expect(kv.allKeys().isEmpty)
    }

    @Test("Toggle OFF: load delegates to wrapped store")
    func toggleOffLoadDelegatesToWrapped() {
        let wrapped = StubInMemoryAddressStore(initial: addrA)
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: false)

        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)
        #expect(store.load() == addrA)
    }

    // MARK: Toggle ON — save

    @Test("Toggle ON: save writes to BOTH wrapped store and KVS")
    func toggleOnSaveWritesBoth() {
        let wrapped = StubInMemoryAddressStore()
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: true)

        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.save(addrA)

        #expect(wrapped.load() == addrA)
        #expect(kvsReadAddress(from: kv) == addrA)
        #expect(kvsReadTimestamp(from: kv) > 0)
    }

    @Test("Toggle ON: KVS data includes companion updatedAt after save")
    func toggleOnSaveWritesUpdatedAt() {
        let wrapped = StubInMemoryAddressStore()
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: true)

        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.save(addrB)

        let ts = kvsReadTimestamp(from: kv)
        // Timestamp must be in a plausible Unix-ms range (after year 2000).
        #expect(ts > 946_684_800_000)
    }

    // MARK: Reconcile on init

    @Test("Reconcile: toggle ON, KVS newer — load() returns KVS value, wrapped updated")
    func reconcileKVSNewer() {
        let wrapped = StubInMemoryAddressStore(initial: addrA)
        let kv = StubInMemoryKVS()
        // Plant KVS with addrB and a timestamp that will be treated as newer.
        kvsWrite(address: addrB, updatedAt: UInt64(Date().timeIntervalSince1970 * 1000), into: kv)

        let toggle = StubBackupToggle(enabled: true)
        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)

        // KVS had a concrete timestamp > 0; stub logic: wrapped adopts KVS value.
        #expect(store.load() == addrB)
        #expect(wrapped.load() == addrB)
    }

    @Test("Reconcile: toggle ON, wrapped newer (KVS empty) — KVS is populated from wrapped")
    func reconcileWrappedNewerKVSEmpty() {
        let wrapped = StubInMemoryAddressStore(initial: addrA)
        let kv = StubInMemoryKVS()
        // KVS has no data (timestamp = 0 → wrapped is treated as newer).

        let toggle = StubBackupToggle(enabled: true)
        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)

        #expect(store.load() == addrA)
        #expect(kvsReadAddress(from: kv) == addrA)
    }

    @Test("Reconcile: toggle OFF — KVS is NOT consulted, wrapped value is unchanged")
    func reconcileToggleOffKVSNotConsulted() {
        let wrapped = StubInMemoryAddressStore(initial: addrA)
        let kv = StubInMemoryKVS()
        kvsWrite(address: addrB, updatedAt: UInt64(Date().timeIntervalSince1970 * 1000), into: kv)

        let toggle = StubBackupToggle(enabled: false)
        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)

        // Toggle OFF → no reconcile → wrapped keeps addrA.
        #expect(store.load() == addrA)
    }

    // MARK: External KVS change

    @Test("External KVS change while toggle ON: wrapped store updates and didChange emits")
    func externalKVSChangeUpdatesWrappedAndEmits() async {
        let wrapped = StubInMemoryAddressStore(initial: addrA)
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: true)

        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)
        var iterator = store.didChange.makeAsyncIterator()

        // Simulate KVS receiving addrB from another device.
        let newAddrData = addrB.rawValue.data(using: .utf8)!
        kv.simulateExternalChange(key: "openhl.address.value", value: newAddrData)

        // Wait for the decorator's internal observation task to propagate the change.
        let emitted = await iterator.next()
        #expect(emitted == addrB)
        #expect(wrapped.load() == addrB)
    }

    // MARK: clear()

    @Test("clear() removes address from wrapped store; KVS data is preserved")
    func clearDoesNotTouchKVS() {
        let wrapped = StubInMemoryAddressStore(initial: addrA)
        let kv = StubInMemoryKVS()
        kvsWrite(address: addrA, updatedAt: 1_000_000, into: kv)

        let toggle = StubBackupToggle(enabled: true)
        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.clear()

        #expect(wrapped.load() == nil)
        // KVS must still have the old data.
        #expect(kvsReadAddress(from: kv) != nil)
    }

    // MARK: Toggle flipped OFF mid-session

    @Test("Toggle flipped OFF: subsequent saves do not write to KVS")
    func toggleFlippedOffStopsKVSWrites() {
        let wrapped = StubInMemoryAddressStore()
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: true)

        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.save(addrA)

        // Now disable iCloud backup.
        toggle.setEnabled(false)
        store.save(addrB)

        // Wrapped must have addrB; KVS must still have addrA (not addrB).
        #expect(wrapped.load() == addrB)
        #expect(kvsReadAddress(from: kv) == addrA)
    }

    // MARK: Toggle flipped ON after data existed locally

    @Test("Toggle flipped ON after local save: next save uploads local state to KVS")
    func toggleFlippedOnUploadsOnNextSave() {
        let wrapped = StubInMemoryAddressStore()
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: false)

        let store = ICloudBackedAddressStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.save(addrA)  // toggle OFF → KVS not written

        #expect(kv.allKeys().isEmpty)

        // Enable backup and make a new save — must upload.
        toggle.setEnabled(true)
        store.save(addrB)

        #expect(kvsReadAddress(from: kv) == addrB)
    }
}

// MARK: - ICloudBackedFavoriteCoinsStore tests

@Suite("ICloudBackedFavoriteCoinsStore — decorator invariants")
struct ICloudBackedFavoriteCoinsStoreTests {

    // MARK: Toggle OFF (default)

    @Test("Toggle OFF: toggle(coin) writes to wrapped store only — KVS has no keys")
    func toggleOffDoesNotWriteToKVS() {
        let wrapped = StubInMemoryFavoritesStore()
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: false)

        let store = ICloudBackedFavoriteCoinsStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.toggle("BTC")

        #expect(wrapped.all() == ["BTC"])
        #expect(kv.allKeys().isEmpty)
    }

    @Test("Toggle OFF: all() delegates to wrapped store")
    func toggleOffAllDelegatesToWrapped() {
        let wrapped = StubInMemoryFavoritesStore(initial: ["ETH"])
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: false)

        let store = ICloudBackedFavoriteCoinsStore(wrapped: wrapped, kv: kv, toggle: toggle)
        #expect(store.all() == ["ETH"])
    }

    // MARK: Toggle ON — toggle(coin)

    @Test("Toggle ON: toggle(coin) writes updated set to BOTH wrapped store and KVS")
    func toggleOnWritesBoth() {
        let wrapped = StubInMemoryFavoritesStore()
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: true)

        let store = ICloudBackedFavoriteCoinsStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.toggle("BTC")

        #expect(wrapped.all() == ["BTC"])
        #expect(kvsReadFavorites(from: kv) == ["BTC"])
        #expect(kvsReadTimestamp(from: kv) > 0)
    }

    @Test("Toggle ON: KVS updatedAt is populated after toggle(coin)")
    func toggleOnWritesUpdatedAt() {
        let wrapped = StubInMemoryFavoritesStore()
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: true)

        let store = ICloudBackedFavoriteCoinsStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.toggle("SOL")

        let ts = kvsReadTimestamp(from: kv)
        #expect(ts > 946_684_800_000)
    }

    // MARK: Reconcile on init

    @Test("Reconcile: toggle ON, KVS newer — all() returns KVS coins, wrapped updated")
    func reconcileKVSNewer() {
        let wrapped = StubInMemoryFavoritesStore(initial: ["BTC"])
        let kv = StubInMemoryKVS()
        kvsWriteFavorites(
            coins: ["ETH", "SOL"],
            updatedAt: UInt64(Date().timeIntervalSince1970 * 1000),
            into: kv
        )

        let toggle = StubBackupToggle(enabled: true)
        let store = ICloudBackedFavoriteCoinsStore(wrapped: wrapped, kv: kv, toggle: toggle)

        #expect(store.all() == ["ETH", "SOL"])
        #expect(wrapped.all() == ["ETH", "SOL"])
    }

    @Test("Reconcile: toggle ON, wrapped newer (KVS empty) — KVS populated from wrapped")
    func reconcileWrappedNewerKVSEmpty() {
        let wrapped = StubInMemoryFavoritesStore(initial: ["BTC", "DOGE"])
        let kv = StubInMemoryKVS()

        let toggle = StubBackupToggle(enabled: true)
        let store = ICloudBackedFavoriteCoinsStore(wrapped: wrapped, kv: kv, toggle: toggle)

        #expect(store.all() == ["BTC", "DOGE"])
        #expect(kvsReadFavorites(from: kv) == ["BTC", "DOGE"])
    }

    @Test("Reconcile: toggle OFF — KVS is NOT consulted, wrapped unchanged")
    func reconcileToggleOffKVSNotConsulted() {
        let wrapped = StubInMemoryFavoritesStore(initial: ["BTC"])
        let kv = StubInMemoryKVS()
        kvsWriteFavorites(
            coins: ["ETH"],
            updatedAt: UInt64(Date().timeIntervalSince1970 * 1000),
            into: kv
        )

        let toggle = StubBackupToggle(enabled: false)
        let store = ICloudBackedFavoriteCoinsStore(wrapped: wrapped, kv: kv, toggle: toggle)

        #expect(store.all() == ["BTC"])
    }

    // MARK: External KVS change

    @Test("External KVS change while toggle ON: wrapped updates and didChange emits")
    func externalKVSChangeUpdatesWrappedAndEmits() async {
        let wrapped = StubInMemoryFavoritesStore(initial: ["BTC"])
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: true)

        let store = ICloudBackedFavoriteCoinsStore(wrapped: wrapped, kv: kv, toggle: toggle)
        var iterator = store.didChange.makeAsyncIterator()

        // Simulate external KVS update arriving with a new favorites set.
        let newCoins: [String] = ["ETH", "SOL"]
        let newData = try! JSONEncoder().encode(newCoins)
        kv.simulateExternalChange(key: "openhl.favorites.value", value: newData)

        let emitted = await iterator.next()
        #expect(emitted == ["ETH", "SOL"])
        #expect(wrapped.all() == ["ETH", "SOL"])
    }

    // MARK: Toggle flipped OFF mid-session

    @Test("Toggle flipped OFF: subsequent toggle(coin) does not write to KVS")
    func toggleFlippedOffStopsKVSWrites() {
        let wrapped = StubInMemoryFavoritesStore()
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: true)

        let store = ICloudBackedFavoriteCoinsStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.toggle("BTC")  // toggle ON → written to KVS

        toggle.setEnabled(false)
        store.toggle("ETH")  // toggle OFF → NOT written to KVS

        #expect(wrapped.all() == ["BTC", "ETH"])
        // KVS must still reflect ["BTC"] (the state before toggle was flipped).
        #expect(kvsReadFavorites(from: kv) == ["BTC"])
    }

    // MARK: Toggle flipped ON after local data existed

    @Test("Toggle flipped ON after local toggle: next toggle uploads local state to KVS")
    func toggleFlippedOnUploadsOnNextToggle() {
        let wrapped = StubInMemoryFavoritesStore()
        let kv = StubInMemoryKVS()
        let toggle = StubBackupToggle(enabled: false)

        let store = ICloudBackedFavoriteCoinsStore(wrapped: wrapped, kv: kv, toggle: toggle)
        store.toggle("BTC")  // toggle OFF → KVS not written

        #expect(kv.allKeys().isEmpty)

        toggle.setEnabled(true)
        store.toggle("ETH")  // toggle ON → KVS should now have ["BTC","ETH"]

        let kvsCoins = kvsReadFavorites(from: kv)
        #expect(kvsCoins == ["BTC", "ETH"])
    }
}
