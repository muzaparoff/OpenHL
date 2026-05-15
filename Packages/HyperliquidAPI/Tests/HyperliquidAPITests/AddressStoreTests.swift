// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore
import Testing

@testable import HyperliquidAPI

// MARK: - UserDefaultsAddressStore

@Suite("UserDefaultsAddressStore — write / read / clear")
struct UserDefaultsAddressStoreTests {

    /// Each test gets a private suite so it cannot pollute `.standard` or
    /// any other test's suite. The suite name embeds a UUID to guarantee
    /// uniqueness even if tests run in parallel.
    private func makeSuite() -> UserDefaults {
        let suiteName = "com.openhl.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        // Start clean.
        suite.removePersistentDomain(forName: suiteName)
        return suite
    }

    private let address1 = try! Address("0xabcdef1234567890abcdef1234567890abcdef12")
    private let address2 = try! Address("0x1234567890abcdef1234567890abcdef12345678")

    @Test("load returns nil when nothing is stored")
    func loadReturnsNilWhenEmpty() {
        let store = UserDefaultsAddressStore(defaults: makeSuite())
        #expect(store.load() == nil)
    }

    @Test("save then load round-trips the address")
    func saveAndLoadRoundTrip() {
        let store = UserDefaultsAddressStore(defaults: makeSuite())
        store.save(address1)
        #expect(store.load() == address1)
    }

    @Test("save overwrites a previous address")
    func saveOverwritesPrevious() {
        let store = UserDefaultsAddressStore(defaults: makeSuite())
        store.save(address1)
        store.save(address2)
        #expect(store.load() == address2)
    }

    @Test("clear removes the stored address")
    func clearRemovesAddress() {
        let store = UserDefaultsAddressStore(defaults: makeSuite())
        store.save(address1)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test("storage key constant is openhl.address")
    func storageKeyIsCorrect() {
        #expect(UserDefaultsAddressStore.storageKey == "openhl.address")
    }

    @Test("pre-seeding via the public storage key and then loading succeeds")
    func preSeedingViaStorageKey() {
        let suite = makeSuite()
        // Pre-seed using the public key (the way a migration or test setup might)
        suite.set(address1.rawValue, forKey: UserDefaultsAddressStore.storageKey)
        let store = UserDefaultsAddressStore(defaults: suite)
        #expect(store.load() == address1)
    }

    @Test("load returns nil for a stored value that fails address validation")
    func loadReturnsNilForInvalidStoredValue() {
        let suite = makeSuite()
        // Manually plant a bad value (e.g. from an older build format).
        suite.set("not-a-valid-address", forKey: UserDefaultsAddressStore.storageKey)
        let store = UserDefaultsAddressStore(defaults: suite)
        // Defensive: bad stored value → nil, not a crash.
        #expect(store.load() == nil)
    }
}

// MARK: - InMemoryAddressStore

@Suite("InMemoryAddressStore — write / read / clear")
struct InMemoryAddressStoreTests {

    private let address1 = try! Address("0xabcdef1234567890abcdef1234567890abcdef12")
    private let address2 = try! Address("0x1234567890abcdef1234567890abcdef12345678")

    @Test("load returns nil when initialised without a seed")
    func loadReturnsNilWhenNoSeed() {
        let store = InMemoryAddressStore()
        #expect(store.load() == nil)
    }

    @Test("load returns the seed address when initialised with one")
    func loadReturnsSeedAddress() {
        let store = InMemoryAddressStore(initial: address1)
        #expect(store.load() == address1)
    }

    @Test("save then load round-trips the address")
    func saveAndLoadRoundTrip() {
        let store = InMemoryAddressStore()
        store.save(address1)
        #expect(store.load() == address1)
    }

    @Test("save overwrites a previous address")
    func saveOverwritesPrevious() {
        let store = InMemoryAddressStore(initial: address1)
        store.save(address2)
        #expect(store.load() == address2)
    }

    @Test("clear removes the stored address")
    func clearRemovesAddress() {
        let store = InMemoryAddressStore(initial: address1)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test("clear on an empty store is a no-op (does not crash)")
    func clearOnEmptyIsNoop() {
        let store = InMemoryAddressStore()
        store.clear()  // Must not crash.
        #expect(store.load() == nil)
    }
}
