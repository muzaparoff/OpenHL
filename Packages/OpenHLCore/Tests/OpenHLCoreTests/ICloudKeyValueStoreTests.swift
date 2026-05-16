// SPDX-License-Identifier: MIT

// Tests for `UbiquitousKeyValueStore` protocol + `InMemoryUbiquitousKeyValueStore`
// and `ICloudBackupToggle` (Phase 3f).
//
// STATUS: swift-expert has not yet landed
// `iCloudKeyValueStore.swift` or `iCloudBackup.swift` in `OpenHLCore`.
// The protocol, `InMemoryUbiquitousKeyValueStore`, and `ICloudBackupToggle`
// are stubbed locally so the test shapes are final and compile-clean today.
//
// UNLOCK CHECKLIST — once swift-expert lands the real types:
//   1. Delete the LOCAL STUB TYPES section below.
//   2. Ensure `@testable import OpenHLCore` is active (already present).
//   3. Remove `.disabled` from every suite marked with it.
//   4. Run `swift test` from `Packages/OpenHLCore/`.
//
// Stubs below mirror the interface agreed with swift-expert for Phase 3f:
//   - Protocol `UbiquitousKeyValueStore: Sendable`
//       `set(_ data: Data, forKey key: String)`
//       `data(forKey key: String) -> Data?`
//       `removeObject(forKey key: String)`
//       `var externalChanges: AsyncStream<Void> { get }`
//   - `InMemoryUbiquitousKeyValueStore` — thread-safe via NSLock,
//     `@unchecked Sendable`. Exposes
//     `func simulateExternalChange(key: String, value: Data?)` for tests.
//   - `ICloudBackupToggle` — wraps a `UserDefaults` instance.
//       `var isEnabled: Bool { get }`
//       `func setEnabled(_ enabled: Bool)`
//       `var didChange: AsyncStream<Bool> { get }`
//     Default state is OFF. Stored under `openhl.iCloudBackupEnabled`.
//
// Phase 3f adds NO new Hyperliquid API endpoints. The per-memory
// fixture-test rule is NOT triggered here.

import Foundation
import Testing

@testable import OpenHLCore

// MARK: - LOCAL STUB TYPES
// Delete this entire section when swift-expert lands the real types.

/// Minimal protocol mirroring `UbiquitousKeyValueStore` from
/// `iCloudKeyValueStore.swift`.
private protocol UbiquitousKeyValueStore: Sendable {
    func set(_ data: Data, forKey key: String)
    func data(forKey key: String) -> Data?
    func removeObject(forKey key: String)
    var externalChanges: AsyncStream<Void> { get }
}

/// In-memory fake for the iCloud KVS. Thread-safe via NSLock.
/// Exposes `simulateExternalChange` so tests can drive the `externalChanges`
/// stream without a real NSUbiquitousKeyValueStore.
private final class InMemoryUbiquitousKeyValueStore: UbiquitousKeyValueStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()
    private let continuations = KVSContinuations()

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

    /// Call from test code to simulate an external iCloud change arriving.
    /// Optionally mutates storage at the same time.
    func simulateExternalChange(key: String? = nil, value: Data? = nil) {
        if let key {
            lock.withLock {
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

private final class KVSContinuations: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ c: AsyncStream<Void>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = c }
        return token
    }

    func unregister(_ token: UUID) {
        lock.withLock { _ = subscribers.removeValue(forKey: token) }
    }

    func yield() {
        let snapshot = lock.withLock { Array(subscribers.values) }
        for c in snapshot { c.yield(()) }
    }
}

/// Stub for `ICloudBackupToggle` from `iCloudBackup.swift`.
private final class ICloudBackupToggle: @unchecked Sendable {
    static let storageKey = "openhl.iCloudBackupEnabled"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let continuations = ToggleContinuations()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        lock.withLock { defaults.bool(forKey: Self.storageKey) }
    }

    func setEnabled(_ enabled: Bool) {
        lock.withLock { defaults.set(enabled, forKey: Self.storageKey) }
        continuations.yield(enabled)
    }

    var didChange: AsyncStream<Bool> {
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

private final class ToggleContinuations: @unchecked Sendable {
    private var subscribers: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private let lock = NSLock()

    func register(_ c: AsyncStream<Bool>.Continuation) -> UUID {
        let token = UUID()
        lock.withLock { subscribers[token] = c }
        return token
    }

    func unregister(_ token: UUID) {
        lock.withLock { _ = subscribers.removeValue(forKey: token) }
    }

    func yield(_ value: Bool) {
        let snapshot = lock.withLock { Array(subscribers.values) }
        for c in snapshot { c.yield(value) }
    }
}

// MARK: - Test helper

extension UserDefaults {
    fileprivate static func iCloudTestSuite() -> UserDefaults {
        let name = "com.openhl.tests.icloud.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }
}

// MARK: - InMemoryUbiquitousKeyValueStore tests
// These run today against the local stub; they remain valid once the real
// type lands (delete the stub, unlock this suite if it gains .disabled).

@Suite("InMemoryUbiquitousKeyValueStore — round-trip and external changes")
struct InMemoryUbiquitousKeyValueStoreTests {

    @Test("set + data(forKey:) round-trips raw Data")
    func setAndDataRoundTrips() {
        let kv = InMemoryUbiquitousKeyValueStore()
        let payload = "hello".data(using: .utf8)!
        kv.set(payload, forKey: "myKey")
        #expect(kv.data(forKey: "myKey") == payload)
    }

    @Test("data(forKey:) returns nil for an unset key")
    func dataReturnsNilForUnsetKey() {
        let kv = InMemoryUbiquitousKeyValueStore()
        #expect(kv.data(forKey: "absent") == nil)
    }

    @Test("set overwrites a previously set value")
    func setOverwritesPreviousValue() {
        let kv = InMemoryUbiquitousKeyValueStore()
        kv.set("first".data(using: .utf8)!, forKey: "k")
        kv.set("second".data(using: .utf8)!, forKey: "k")
        #expect(kv.data(forKey: "k") == "second".data(using: .utf8)!)
    }

    @Test("removeObject(forKey:) clears the key")
    func removeObjectClearsKey() {
        let kv = InMemoryUbiquitousKeyValueStore()
        kv.set("x".data(using: .utf8)!, forKey: "r")
        kv.removeObject(forKey: "r")
        #expect(kv.data(forKey: "r") == nil)
    }

    @Test("removeObject on absent key is a no-op")
    func removeObjectOnAbsentKeyIsNoop() {
        let kv = InMemoryUbiquitousKeyValueStore()
        kv.removeObject(forKey: "ghost")  // must not crash
        #expect(kv.data(forKey: "ghost") == nil)
    }

    @Test("externalChanges stream emits once after simulateExternalChange is called")
    func externalChangesStreamEmitsOnSimulate() async {
        let kv = InMemoryUbiquitousKeyValueStore()
        var iterator = kv.externalChanges.makeAsyncIterator()

        let newData = "remote".data(using: .utf8)!
        kv.simulateExternalChange(key: "addr", value: newData)

        let _ = await iterator.next()  // must not hang

        // After the emit the storage is updated.
        #expect(kv.data(forKey: "addr") == newData)
    }

    @Test("simulateExternalChange with nil value removes key from storage")
    func simulateExternalChangeWithNilRemovesKey() async {
        let kv = InMemoryUbiquitousKeyValueStore()
        kv.set("existing".data(using: .utf8)!, forKey: "addr")
        var iterator = kv.externalChanges.makeAsyncIterator()

        kv.simulateExternalChange(key: "addr", value: nil)
        let _ = await iterator.next()

        #expect(kv.data(forKey: "addr") == nil)
    }

    @Test("Two subscribers both receive the external-change emission")
    func twoSubscribersReceiveEmission() async {
        let kv = InMemoryUbiquitousKeyValueStore()
        var it1 = kv.externalChanges.makeAsyncIterator()
        var it2 = kv.externalChanges.makeAsyncIterator()

        kv.simulateExternalChange()

        let v1 = await it1.next()
        let v2 = await it2.next()

        #expect(v1 != nil)
        #expect(v2 != nil)
    }
}

// MARK: - ICloudBackupToggle tests

@Suite("ICloudBackupToggle — default state, persistence, and didChange stream")
struct ICloudBackupToggleTests {

    @Test("isEnabled is false by default (no key in UserDefaults)")
    func isEnabledFalseByDefault() {
        let toggle = ICloudBackupToggle(defaults: .iCloudTestSuite())
        #expect(toggle.isEnabled == false)
    }

    @Test("setEnabled(true) persists; subsequent isEnabled reads true")
    func setEnabledTrueRoundTrips() {
        let toggle = ICloudBackupToggle(defaults: .iCloudTestSuite())
        toggle.setEnabled(true)
        #expect(toggle.isEnabled == true)
    }

    @Test("setEnabled(false) after true persists false")
    func setEnabledFalseAfterTrueRoundTrips() {
        let toggle = ICloudBackupToggle(defaults: .iCloudTestSuite())
        toggle.setEnabled(true)
        toggle.setEnabled(false)
        #expect(toggle.isEnabled == false)
    }

    @Test("setEnabled persists across two toggle instances sharing the same suite")
    func persistsAcrossTwoInstances() {
        let suite = UserDefaults.iCloudTestSuite()
        let first = ICloudBackupToggle(defaults: suite)
        first.setEnabled(true)

        let second = ICloudBackupToggle(defaults: suite)
        #expect(second.isEnabled == true)
    }

    @Test("storageKey constant is openhl.iCloudBackupEnabled")
    func storageKeyIsCorrect() {
        #expect(ICloudBackupToggle.storageKey == "openhl.iCloudBackupEnabled")
    }

    @Test("didChange emits current (false) value immediately on subscription")
    func didChangeEmitsInitialFalse() async {
        let toggle = ICloudBackupToggle(defaults: .iCloudTestSuite())
        var iterator = toggle.didChange.makeAsyncIterator()

        let initial = await iterator.next()
        #expect(initial == false)
    }

    @Test("didChange emits true after setEnabled(true)")
    func didChangeEmitsTrueAfterEnable() async {
        let toggle = ICloudBackupToggle(defaults: .iCloudTestSuite())
        var iterator = toggle.didChange.makeAsyncIterator()
        _ = await iterator.next()  // consume initial

        toggle.setEnabled(true)
        let value = await iterator.next()
        #expect(value == true)
    }

    @Test("didChange emits on every flip: true then false")
    func didChangeEmitsOnEveryFlip() async {
        let toggle = ICloudBackupToggle(defaults: .iCloudTestSuite())
        var iterator = toggle.didChange.makeAsyncIterator()
        _ = await iterator.next()  // consume initial

        toggle.setEnabled(true)
        let first = await iterator.next()
        #expect(first == true)

        toggle.setEnabled(false)
        let second = await iterator.next()
        #expect(second == false)
    }

    @Test("didChange emits even for redundant same-value calls")
    func didChangeEmitsForRedundantCalls() async {
        let toggle = ICloudBackupToggle(defaults: .iCloudTestSuite())
        var iterator = toggle.didChange.makeAsyncIterator()
        _ = await iterator.next()  // consume initial

        toggle.setEnabled(false)  // same as default
        let value = await iterator.next()
        #expect(value == false)
    }
}
