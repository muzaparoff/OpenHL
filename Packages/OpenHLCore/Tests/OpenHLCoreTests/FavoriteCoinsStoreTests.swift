// SPDX-License-Identifier: MIT

// Tests for `FavoriteCoinsStore` — the protocol and its two concrete
// implementations (`InMemoryFavoriteCoinsStore`, `UserDefaultsFavoriteCoinsStore`).
//
// STATUS (Phase 3d): swift-expert has not yet landed
// `FavoriteCoinsStore.swift` in `OpenHLCore`. The store protocol and both
// concrete implementations are stubbed locally here so the test *shapes* are
// final and compile-clean today. Once swift-expert lands the real types:
//
//   1. Delete the LOCAL STUB TYPES section below.
//   2. Add `@testable import OpenHLCore` (already present; remove the `// WHEN`
//      comment guard).
//   3. Remove `.disabled` from every suite that carries it.
//   4. Re-run `swift test` from `Packages/OpenHLCore/`.
//
// The stubs below mirror the interface agreed with swift-expert:
//   - Protocol `FavoriteCoinsStore: Sendable`
//   - `toggle(_ coin: String)` adds the coin if absent, removes it if present.
//   - `isFavorite(_ coin: String) -> Bool`
//   - `all() -> Set<String>` returns the current set.
//   - `AsyncStream<Set<String>>` property `changes` that emits on every mutation.
//   - `InMemoryFavoriteCoinsStore` — thread-safe via NSLock, `@unchecked Sendable`.
//   - `UserDefaultsFavoriteCoinsStore` — backed by a UserDefaults instance,
//     stores the set as a JSON-encoded `[String]` array under the key
//     `openhl.favoriteCoins`. `@unchecked Sendable`.
//
// NO new API endpoints are introduced in Phase 3d. The per-memory rule that
// requires a real-API fixture test for each new endpoint is NOT triggered here.

import Foundation
import Testing

@testable import OpenHLCore

// --------------------------------------------------------------------------
// Test helpers
// --------------------------------------------------------------------------

extension UserDefaults {
    /// Returns a fresh, empty UserDefaults suite with a UUID-stamped name so
    /// tests can run in parallel without polluting `.standard` or each other.
    fileprivate static func testSuite() -> UserDefaults {
        let name = "com.openhl.tests.favorites.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }
}

// --------------------------------------------------------------------------
// InMemoryFavoriteCoinsStore tests
// --------------------------------------------------------------------------

@Suite("InMemoryFavoriteCoinsStore — protocol conformance")
struct InMemoryFavoriteCoinsStoreTests {

    @Test("all() returns empty set on default init")
    func allIsEmptyByDefault() {
        let store = InMemoryFavoriteCoinsStore()
        #expect(store.all().isEmpty)
    }

    @Test("init(initial:) pre-seeds the favourites set")
    func initWithInitialPreSeeds() {
        let store = InMemoryFavoriteCoinsStore(initial: ["BTC", "ETH"])
        #expect(store.all() == ["BTC", "ETH"])
    }

    @Test("toggle adds a coin that was absent")
    func toggleAddsAbsentCoin() {
        let store = InMemoryFavoriteCoinsStore()
        store.toggle("BTC")
        #expect(store.all() == ["BTC"])
    }

    @Test("toggle removes a coin that was present")
    func toggleRemovesPresentCoin() {
        let store = InMemoryFavoriteCoinsStore(initial: ["BTC"])
        store.toggle("BTC")
        #expect(store.all().isEmpty)
    }

    @Test("toggle round-trip: add then remove leaves empty set")
    func toggleRoundTripLeavesEmptySet() {
        let store = InMemoryFavoriteCoinsStore()
        store.toggle("ETH")
        store.toggle("ETH")
        #expect(store.all().isEmpty)
    }

    @Test("toggle multiple distinct coins accumulates all of them")
    func toggleMultipleDistinctCoins() {
        let store = InMemoryFavoriteCoinsStore()
        store.toggle("BTC")
        store.toggle("ETH")
        store.toggle("SOL")
        #expect(store.all() == ["BTC", "ETH", "SOL"])
    }

    @Test("isFavorite returns false before toggle")
    func isFavoriteReturnsFalseBeforeToggle() {
        let store = InMemoryFavoriteCoinsStore()
        #expect(store.isFavorite("BTC") == false)
    }

    @Test("isFavorite returns true after first toggle")
    func isFavoriteReturnsTrueAfterToggle() {
        let store = InMemoryFavoriteCoinsStore()
        store.toggle("BTC")
        #expect(store.isFavorite("BTC") == true)
    }

    @Test("isFavorite returns false after second toggle (remove)")
    func isFavoriteReturnsFalseAfterSecondToggle() {
        let store = InMemoryFavoriteCoinsStore()
        store.toggle("BTC")
        store.toggle("BTC")
        #expect(store.isFavorite("BTC") == false)
    }

    @Test("all() is independent of isFavorite — both reflect same state")
    func allAndIsFavoriteAgree() {
        let store = InMemoryFavoriteCoinsStore(initial: ["ETH", "SOL"])
        for coin in store.all() {
            #expect(store.isFavorite(coin) == true)
        }
        #expect(store.isFavorite("BTC") == false)
    }

    // MARK: - Concurrency

    @Test("100 concurrent toggles of the same coin produce deterministic final state")
    func concurrentTogglesAreDeterministic() async {
        let store = InMemoryFavoriteCoinsStore()

        // 100 tasks each toggle "BTC". 100 is even, so the net effect is zero
        // toggles and the coin must NOT be in the final set.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { store.toggle("BTC") }
            }
        }

        // 100 even number of toggles → absent.
        #expect(store.isFavorite("BTC") == false)
        #expect(store.all() == [])
    }

    @Test("101 concurrent toggles of same coin produce deterministic final state (present)")
    func concurrentTogglesOddCountIsPresentDeterministic() async {
        let store = InMemoryFavoriteCoinsStore()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<101 {
                group.addTask { store.toggle("ETH") }
            }
        }

        // 101 (odd) toggles → present.
        #expect(store.isFavorite("ETH") == true)
        #expect(store.all() == ["ETH"])
    }

    @Test("Concurrent toggles across different coins leave the set internally consistent")
    func concurrentTogglesMultipleCoinsConsistent() async {
        let coins = ["BTC", "ETH", "SOL", "DOGE", "ARB"]
        let store = InMemoryFavoriteCoinsStore()

        // Each coin gets 10 toggles (even → absent) from 5 concurrent tasks.
        await withTaskGroup(of: Void.self) { group in
            for coin in coins {
                for _ in 0..<10 {
                    group.addTask { store.toggle(coin) }
                }
            }
        }

        let result = store.all()
        // All coins had an even number of toggles → none should be present.
        #expect(result.isEmpty)
        for coin in coins {
            #expect(store.isFavorite(coin) == false)
        }
    }

    // MARK: - AsyncStream

    @Test("didChange stream emits the updated set after a toggle")
    func changesStreamEmitsAfterToggle() async {
        let store = InMemoryFavoriteCoinsStore()
        var iterator = store.didChange.makeAsyncIterator()

        // First emission is the current state on subscribe (empty).
        let initial = await iterator.next()
        #expect(initial == [])

        store.toggle("BTC")
        let emitted = await iterator.next()
        #expect(emitted == ["BTC"])
    }

    @Test("didChange stream emits empty set after add-then-remove toggle pair")
    func changesStreamEmitsEmptyAfterRoundTrip() async {
        let store = InMemoryFavoriteCoinsStore()
        var iterator = store.didChange.makeAsyncIterator()

        // First emission is the initial empty set on subscribe.
        _ = await iterator.next()

        store.toggle("SOL")
        let first = await iterator.next()
        #expect(first == ["SOL"])

        store.toggle("SOL")
        let second = await iterator.next()
        #expect(second == [])
    }
}

// --------------------------------------------------------------------------
// UserDefaultsFavoriteCoinsStore tests
// --------------------------------------------------------------------------

@Suite("UserDefaultsFavoriteCoinsStore — protocol conformance")
struct UserDefaultsFavoriteCoinsStoreTests {

    @Test("all() returns empty set when UserDefaults key is absent")
    func allIsEmptyWhenKeyAbsent() {
        let store = UserDefaultsFavoriteCoinsStore(defaults: .testSuite())
        #expect(store.all().isEmpty)
    }

    @Test("toggle adds and all() reflects the coin")
    func toggleAddsAndAllReflects() {
        let store = UserDefaultsFavoriteCoinsStore(defaults: .testSuite())
        store.toggle("BTC")
        #expect(store.all() == ["BTC"])
    }

    @Test("toggle round-trip write/read persists via UserDefaults")
    func writeReadRoundTrip() {
        let suite = UserDefaults.testSuite()
        let writer = UserDefaultsFavoriteCoinsStore(defaults: suite)
        writer.toggle("ETH")

        // Simulate a fresh store instance reading the same suite (app restart).
        let reader = UserDefaultsFavoriteCoinsStore(defaults: suite)
        #expect(reader.all() == ["ETH"])
    }

    @Test("toggle removes a coin that was persisted across two store instances")
    func persistedCoinRemovedByToggle() {
        let suite = UserDefaults.testSuite()
        let first = UserDefaultsFavoriteCoinsStore(defaults: suite)
        first.toggle("SOL")

        let second = UserDefaultsFavoriteCoinsStore(defaults: suite)
        second.toggle("SOL")

        let third = UserDefaultsFavoriteCoinsStore(defaults: suite)
        #expect(third.all().isEmpty)
    }

    @Test("isFavorite returns correct bool before and after toggle")
    func isFavoriteBeforeAndAfterToggle() {
        let store = UserDefaultsFavoriteCoinsStore(defaults: .testSuite())
        #expect(store.isFavorite("DOGE") == false)
        store.toggle("DOGE")
        #expect(store.isFavorite("DOGE") == true)
        store.toggle("DOGE")
        #expect(store.isFavorite("DOGE") == false)
    }

    @Test("storageKey constant is openhl.favoriteCoins")
    func storageKeyIsCorrect() {
        #expect(UserDefaultsFavoriteCoinsStore.storageKey == "openhl.favoriteCoins")
    }

    @Test("JSON corruption: garbage stored under the key → all() returns empty (defensive)")
    func jsonCorruptionReturnsEmpty() {
        let suite = UserDefaults.testSuite()
        // Plant a value that is not a valid JSON-encoded [String].
        let garbage = "not-json-at-all".data(using: .utf8)!
        suite.set(garbage, forKey: UserDefaultsFavoriteCoinsStore.storageKey)

        let store = UserDefaultsFavoriteCoinsStore(defaults: suite)
        // Must not crash; must return empty rather than propagating a decode error.
        #expect(store.all().isEmpty)
    }

    @Test("JSON corruption: wrong JSON type stored (object not array) → all() returns empty")
    func jsonWrongTypeReturnsEmpty() {
        let suite = UserDefaults.testSuite()
        // A JSON object `{}` is not decodable as `[String]`.
        let wrongType = "{}".data(using: .utf8)!
        suite.set(wrongType, forKey: UserDefaultsFavoriteCoinsStore.storageKey)

        let store = UserDefaultsFavoriteCoinsStore(defaults: suite)
        #expect(store.all().isEmpty)
    }

    @Test("JSON corruption: wrong UserDefaults type (String not Data) → all() returns empty")
    func wrongDefaultsTypeReturnsEmpty() {
        let suite = UserDefaults.testSuite()
        // Store a plain String (not Data) — simulates an older build format.
        suite.set("[\"BTC\",\"ETH\"]", forKey: UserDefaultsFavoriteCoinsStore.storageKey)

        let store = UserDefaultsFavoriteCoinsStore(defaults: suite)
        // The store reads `.data(forKey:)` which returns nil for a String value.
        #expect(store.all().isEmpty)
    }

    @Test("Multiple coins persist and reload correctly")
    func multipleCoinsPersistedAndReloaded() {
        let suite = UserDefaults.testSuite()
        let writer = UserDefaultsFavoriteCoinsStore(defaults: suite)
        writer.toggle("BTC")
        writer.toggle("ETH")
        writer.toggle("SOL")

        let reader = UserDefaultsFavoriteCoinsStore(defaults: suite)
        #expect(reader.all() == ["BTC", "ETH", "SOL"])
    }

    // MARK: - Concurrency

    @Test("100 concurrent toggles of the same coin produce deterministic final state")
    func concurrentTogglesAreDeterministic() async {
        let store = UserDefaultsFavoriteCoinsStore(defaults: .testSuite())

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { store.toggle("BTC") }
            }
        }

        // 100 (even) toggles → absent.
        #expect(store.isFavorite("BTC") == false)
        #expect(store.all() == [])
    }
}
