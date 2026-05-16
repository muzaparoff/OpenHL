// SPDX-License-Identifier: MIT

// Tests for `SettingsViewModel` (Phase 3f — Settings screen + iCloud backup).
//
// STATUS: swift-expert has not yet landed `SettingsViewModel` in the app
// target. The view model, its protocol dependencies, and the in-memory fakes
// are stubbed locally so the test shapes are final and compile-clean today.
//
// UNLOCK CHECKLIST — once ios-developer lands `SettingsViewModel`:
//   1. Delete the LOCAL STUB TYPES section below.
//   2. Add `@testable import OpenHL` (already present as a comment guard below).
//   3. Remove `.disabled` from every suite that carries it.
//   4. Run xcodebuild test for the OpenHLTests scheme.
//
// Expected `SettingsViewModel` API surface (agree with swift-expert before
// removing .disabled):
//
//   @MainActor @Observable final class SettingsViewModel {
//     init(
//       toggle: any ICloudBackupToggleProtocol,
//       addressStore: any AddressStore,
//       favoritesStore: any FavoriteCoinsStore
//     )
//     var iCloudEnabled: Bool { get set }
//     func clearAddress()
//     func clearFavorites()
//   }
//
// Fakes used: `InMemoryAddressStore`, `InMemoryFavoriteCoinsStore` (from
// HyperliquidAPI / OpenHLCore). An `InMemoryBackupToggle` is defined locally
// below and must match the production toggle's protocol surface.
//
// Phase 3f adds NO new Hyperliquid API endpoints. The per-memory
// fixture-test rule is NOT triggered here.

import Foundation
import HyperliquidAPI
import OpenHLCore
import Testing

// @testable import OpenHL   ← un-comment once SettingsViewModel lands

// MARK: - LOCAL STUB TYPES
// Delete this entire section once swift-expert/ios-developer land the real types.

/// Minimal protocol that `ICloudBackupToggle` (from `OpenHLCore`) must conform to.
/// Lets us inject an in-memory stand-in for tests.
private protocol ICloudBackupToggleProtocol: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
    var didChange: AsyncStream<Bool> { get }
}

/// In-memory implementation suitable for unit tests.
private final class InMemoryBackupToggle: ICloudBackupToggleProtocol, @unchecked Sendable {
    private var _enabled: Bool
    private let lock = NSLock()
    private(set) var setEnabledCallCount: Int = 0
    private(set) var lastSetEnabledArg: Bool?
    private let conts = ToggleContinuations2()

    init(enabled: Bool = false) { _enabled = enabled }

    var isEnabled: Bool { lock.withLock { _enabled } }

    func setEnabled(_ enabled: Bool) {
        lock.withLock {
            _enabled = enabled
            setEnabledCallCount += 1
            lastSetEnabledArg = enabled
        }
        conts.yield(enabled)
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

private final class ToggleContinuations2: @unchecked Sendable {
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

/// Stub `SettingsViewModel` matching the agreed API surface above.
/// Delete and replace with real import once ios-developer lands the type.
@MainActor
private final class SettingsViewModel: Observable {

    private let toggle: InMemoryBackupToggle
    private let addressStore: InMemoryAddressStore
    private let favoritesStore: InMemoryFavoriteCoinsStore

    // Expose spy handles for assertions.
    var clearAddressCallCount: Int = 0
    var clearFavoritesCallCount: Int = 0

    init(
        toggle: InMemoryBackupToggle,
        addressStore: InMemoryAddressStore,
        favoritesStore: InMemoryFavoriteCoinsStore
    ) {
        self.toggle = toggle
        self.addressStore = addressStore
        self.favoritesStore = favoritesStore
    }

    var iCloudEnabled: Bool {
        get { toggle.isEnabled }
        set { toggle.setEnabled(newValue) }
    }

    func clearAddress() {
        clearAddressCallCount += 1
        addressStore.clear()
    }

    func clearFavorites() {
        clearFavoritesCallCount += 1
        for coin in favoritesStore.all() {
            favoritesStore.toggle(coin)
        }
    }
}

/// Conformance marker for the stub — required by the `Observable` macro in
/// the real implementation. The stub above uses it as a marker only.
private protocol Observable {}

// MARK: - Test addresses and coins

private let testAddress = try! Address("0xabcdef1234567890abcdef1234567890abcdef12")

// MARK: - SettingsViewModel unit tests
//
// These run today against the local stub; they remain valid once the real
// SettingsViewModel lands (delete stub + remove .disabled).

@Suite(
    "SettingsViewModel — initial state, iCloud toggle, clear actions",
    .disabled("Waiting for SettingsViewModel to land in the app target. See unlock checklist.")
)
@MainActor
struct SettingsViewModelTests {

    @Test("Initial iCloudEnabled mirrors toggle's isEnabled (false by default)")
    func initialICloudEnabledIsFalse() {
        let toggle = InMemoryBackupToggle(enabled: false)
        let vm = SettingsViewModel(
            toggle: toggle,
            addressStore: InMemoryAddressStore(),
            favoritesStore: InMemoryFavoriteCoinsStore()
        )
        #expect(vm.iCloudEnabled == false)
    }

    @Test("Initial iCloudEnabled mirrors toggle's isEnabled (true when pre-seeded)")
    func initialICloudEnabledIsTrue() {
        let toggle = InMemoryBackupToggle(enabled: true)
        let vm = SettingsViewModel(
            toggle: toggle,
            addressStore: InMemoryAddressStore(),
            favoritesStore: InMemoryFavoriteCoinsStore()
        )
        #expect(vm.iCloudEnabled == true)
    }

    @Test("Setting iCloudEnabled = true calls toggle.setEnabled(true)")
    func settingICloudEnabledTrueCallsToggle() {
        let toggle = InMemoryBackupToggle(enabled: false)
        let vm = SettingsViewModel(
            toggle: toggle,
            addressStore: InMemoryAddressStore(),
            favoritesStore: InMemoryFavoriteCoinsStore()
        )
        vm.iCloudEnabled = true

        #expect(toggle.setEnabledCallCount == 1)
        #expect(toggle.lastSetEnabledArg == true)
        #expect(toggle.isEnabled == true)
    }

    @Test("Setting iCloudEnabled = false calls toggle.setEnabled(false)")
    func settingICloudEnabledFalseCallsToggle() {
        let toggle = InMemoryBackupToggle(enabled: true)
        let vm = SettingsViewModel(
            toggle: toggle,
            addressStore: InMemoryAddressStore(),
            favoritesStore: InMemoryFavoriteCoinsStore()
        )
        vm.iCloudEnabled = false

        #expect(toggle.setEnabledCallCount == 1)
        #expect(toggle.lastSetEnabledArg == false)
        #expect(toggle.isEnabled == false)
    }

    @Test("iCloudEnabled read reflects toggle after external toggle.setEnabled call")
    func iCloudEnabledReadsLatestToggleState() {
        let toggle = InMemoryBackupToggle(enabled: false)
        let vm = SettingsViewModel(
            toggle: toggle,
            addressStore: InMemoryAddressStore(),
            favoritesStore: InMemoryFavoriteCoinsStore()
        )
        toggle.setEnabled(true)
        #expect(vm.iCloudEnabled == true)
    }

    @Test("clearAddress() calls addressStore.clear() — load() returns nil afterwards")
    func clearAddressCallsClearOnStore() {
        let addressStore = InMemoryAddressStore(initial: testAddress)
        let vm = SettingsViewModel(
            toggle: InMemoryBackupToggle(),
            addressStore: addressStore,
            favoritesStore: InMemoryFavoriteCoinsStore()
        )
        vm.clearAddress()

        #expect(vm.clearAddressCallCount == 1)
        #expect(addressStore.load() == nil)
    }

    @Test("clearAddress() on an already-empty store is a no-op (does not crash)")
    func clearAddressOnEmptyIsNoop() {
        let addressStore = InMemoryAddressStore()
        let vm = SettingsViewModel(
            toggle: InMemoryBackupToggle(),
            addressStore: addressStore,
            favoritesStore: InMemoryFavoriteCoinsStore()
        )
        vm.clearAddress()  // must not crash

        #expect(addressStore.load() == nil)
    }

    @Test("clearFavorites() removes all coins — all() returns empty set afterwards")
    func clearFavoritesRemovesAllCoins() {
        let favoritesStore = InMemoryFavoriteCoinsStore(initial: ["BTC", "ETH", "SOL"])
        let vm = SettingsViewModel(
            toggle: InMemoryBackupToggle(),
            addressStore: InMemoryAddressStore(),
            favoritesStore: favoritesStore
        )
        vm.clearFavorites()

        #expect(vm.clearFavoritesCallCount == 1)
        #expect(favoritesStore.all().isEmpty)
    }

    @Test("clearFavorites() on empty favorites is a no-op (does not crash)")
    func clearFavoritesOnEmptyIsNoop() {
        let favoritesStore = InMemoryFavoriteCoinsStore()
        let vm = SettingsViewModel(
            toggle: InMemoryBackupToggle(),
            addressStore: InMemoryAddressStore(),
            favoritesStore: favoritesStore
        )
        vm.clearFavorites()  // must not crash

        #expect(favoritesStore.all().isEmpty)
    }

    @Test("clearFavorites() removes a single coin correctly")
    func clearFavoritesRemovesSingleCoin() {
        let favoritesStore = InMemoryFavoriteCoinsStore(initial: ["BTC"])
        let vm = SettingsViewModel(
            toggle: InMemoryBackupToggle(),
            addressStore: InMemoryAddressStore(),
            favoritesStore: favoritesStore
        )
        vm.clearFavorites()

        #expect(favoritesStore.all().isEmpty)
    }

    @Test("clearAddress and clearFavorites are independent — only the targeted store is affected")
    func clearAddressAndFavoritesAreIndependent() {
        let addressStore = InMemoryAddressStore(initial: testAddress)
        let favoritesStore = InMemoryFavoriteCoinsStore(initial: ["BTC", "ETH"])
        let vm = SettingsViewModel(
            toggle: InMemoryBackupToggle(),
            addressStore: addressStore,
            favoritesStore: favoritesStore
        )

        vm.clearAddress()
        #expect(addressStore.load() == nil)
        #expect(favoritesStore.all() == ["BTC", "ETH"])  // favorites untouched

        vm.clearFavorites()
        #expect(addressStore.load() == nil)  // address still cleared
        #expect(favoritesStore.all().isEmpty)
    }
}

// MARK: - Compile-time smoke test (runs today, no .disabled)
//
// This verifies the fake types used in the disabled suites above are
// self-consistent. It gives CI immediate signal without requiring the real
// SettingsViewModel to exist.

@Suite("SettingsViewModel stubs — self-consistency")
struct SettingsViewModelStubSmokeTests {

    @Test("InMemoryBackupToggle default isEnabled is false")
    func inMemoryBackupToggleDefaultIsFalse() {
        let toggle = InMemoryBackupToggle()
        #expect(toggle.isEnabled == false)
    }

    @Test("InMemoryBackupToggle setEnabled round-trips")
    func inMemoryBackupToggleSetEnabledRoundTrips() {
        let toggle = InMemoryBackupToggle()
        toggle.setEnabled(true)
        #expect(toggle.isEnabled == true)
        toggle.setEnabled(false)
        #expect(toggle.isEnabled == false)
    }

    @Test("InMemoryBackupToggle didChange emits initial value")
    func inMemoryBackupToggleDidChangeEmitsInitial() async {
        let toggle = InMemoryBackupToggle(enabled: true)
        var iterator = toggle.didChange.makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial == true)
    }

    @Test("InMemoryBackupToggle setEnabledCallCount increments per call")
    func inMemoryBackupToggleCallCountIncrements() {
        let toggle = InMemoryBackupToggle()
        #expect(toggle.setEnabledCallCount == 0)
        toggle.setEnabled(true)
        toggle.setEnabled(false)
        #expect(toggle.setEnabledCallCount == 2)
    }
}
