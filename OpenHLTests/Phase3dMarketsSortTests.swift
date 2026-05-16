// SPDX-License-Identifier: MIT

// Tests for the Markets favourites sort/section logic introduced in Phase 3d.
//
// STATUS: swift-expert's `FavoriteCoinsStore` protocol and ios-developer's
// `MarketsViewModel` favourites integration are not yet landed.
//
// Strategy (mirrors `ViewModelStateTests.swift`):
//   - The pure sorting/grouping logic is extracted into a local function
//     `groupMarketsWithFavorites(_:favorites:)` whose shape matches the
//     contract agreed with swift-expert (§24, forthcoming). These tests run
//     today and exercise the algorithm in isolation.
//   - The ViewModel-level integration suite is `.disabled` until ios-developer
//     wires `FavoriteCoinsStore` into `MarketsViewModel`. Unlock steps are
//     documented per suite.
//
// NO new API endpoints are added by Phase 3d. The per-memory fixture-test
// rule is NOT triggered.
//
// UNLOCK CHECKLIST (remove .disabled when all items are done):
//   MarketsViewModelFavoritesIntegrationTests:
//     [ ] swift-expert: `FavoriteCoinsStore` protocol + impls in OpenHLCore
//     [ ] ios-developer: `MarketsViewModel` exposes `groupedMarkets` property
//         of type `[(section: String, markets: [Market])]` (or equivalent)
//     [ ] ios-developer: `MarketsViewModel.init` / factory accepts a
//         `FavoriteCoinsStore` dependency
//     [ ] Remove `@testable import OpenHL` guard comment below; add real import
//     [ ] Delete the local `groupMarketsWithFavorites` stub (replace with
//         calls to the real ViewModel's grouped output)

import Foundation
import HyperliquidAPI
import OpenHLCore
import Testing

// MARK: - Helpers

/// Section descriptor returned by the grouping function.
///
/// Mirrors the shape swift-expert is expected to define on `MarketsViewModel`.
/// When the real VM lands, delete this struct and use the VM's own type.
private struct MarketSection: Equatable {
    let title: String
    let markets: [Market]
}

/// Pure grouping function under test.
///
/// Contract (to be matched exactly by the real MarketsViewModel implementation):
///
///   - When `favorites` is non-empty:
///       • Section 0 — title "PINNED", contains markets whose `coin` is in
///         `favorites`, sorted ascending by coin name.
///       • Section 1 — title "MARKETS", contains the remaining markets in their
///         original (caller-supplied) order.
///
///   - When `favorites` is empty:
///       • A single section with title "MARKETS" containing all markets in their
///         original order.
///
///   - A coin in `favorites` that has no matching market row is ignored (no
///     phantom row is created in the PINNED section).
private func groupMarketsWithFavorites(
    _ markets: [Market],
    favorites: Set<String>
) -> [MarketSection] {
    guard !favorites.isEmpty else {
        return [MarketSection(title: "MARKETS", markets: markets)]
    }

    let pinned =
        markets
        .filter { favorites.contains($0.coin) }
        .sorted { $0.coin < $1.coin }

    let rest = markets.filter { !favorites.contains($0.coin) }

    var sections: [MarketSection] = []
    if !pinned.isEmpty {
        sections.append(MarketSection(title: "PINNED", markets: pinned))
    }
    sections.append(MarketSection(title: "MARKETS", markets: rest))
    return sections
}

// MARK: - Market test factory

extension Market {
    /// Minimal market stub. Volume drives natural sort order when the test
    /// passes a volume-desc sorted list.
    fileprivate static func stub(coin: String, volume: Double = 0) -> Market {
        Market(
            coin: coin,
            maxLeverage: 20,
            szDecimals: 3,
            onlyIsolated: false,
            markPrice: 1000,
            midPrice: 1001,
            prevDayPrice: 990,
            openInterest: 100,
            dayNotionalVolume: Money(volume),
            fundingRate: 0
        )
    }
}

// MARK: - Pure grouping logic tests (no disable — runs today)

@Suite("Markets grouping — pure sort/section logic")
struct MarketGroupingPureTests {

    // Input list ordered by volume desc (as the VM's postProcess delivers it).
    private let volumeSortedMarkets: [Market] = [
        .stub(coin: "BTC", volume: 900_000_000),
        .stub(coin: "ETH", volume: 500_000_000),
        .stub(coin: "SOL", volume: 200_000_000),
        .stub(coin: "DOGE", volume: 50_000_000),
    ]

    // MARK: No favorites

    @Test("Empty favorites → single MARKETS section with full list in input order")
    func emptyFavoritesSingleSection() {
        let sections = groupMarketsWithFavorites(volumeSortedMarkets, favorites: [])

        #expect(sections.count == 1)
        #expect(sections[0].title == "MARKETS")
        #expect(sections[0].markets.map(\.coin) == ["BTC", "ETH", "SOL", "DOGE"])
    }

    @Test("Empty favorites, empty markets list → single empty MARKETS section")
    func emptyFavoritesEmptyMarkets() {
        let sections = groupMarketsWithFavorites([], favorites: [])
        #expect(sections.count == 1)
        #expect(sections[0].title == "MARKETS")
        #expect(sections[0].markets.isEmpty)
    }

    // MARK: With favorites

    @Test("ETH + SOL favorited → PINNED=[ETH,SOL] alphabetical, MARKETS=[BTC,DOGE] volume order")
    func favoritedCoinsMoveToPinnedAlphabetically() {
        let sections = groupMarketsWithFavorites(
            volumeSortedMarkets,
            favorites: ["ETH", "SOL"]
        )

        #expect(sections.count == 2)

        let pinned = sections[0]
        #expect(pinned.title == "PINNED")
        // ETH < SOL alphabetically.
        #expect(pinned.markets.map(\.coin) == ["ETH", "SOL"])

        let markets = sections[1]
        #expect(markets.title == "MARKETS")
        // Remaining coins preserved in input (volume-desc) order.
        #expect(markets.markets.map(\.coin) == ["BTC", "DOGE"])
    }

    @Test("BTC favorited → PINNED=[BTC], MARKETS=[ETH,SOL,DOGE] (volume order preserved)")
    func singleFavoritePinnedCorrectly() {
        let sections = groupMarketsWithFavorites(
            volumeSortedMarkets,
            favorites: ["BTC"]
        )

        #expect(sections.count == 2)
        #expect(sections[0].markets.map(\.coin) == ["BTC"])
        #expect(sections[1].markets.map(\.coin) == ["ETH", "SOL", "DOGE"])
    }

    @Test("PINNED section is in ascending coin-name order regardless of volume order")
    func pinnedSectionIsAlphabeticNotVolumeOrder() {
        // SOL has higher volume than ETH but ETH < SOL alphabetically.
        let sections = groupMarketsWithFavorites(
            volumeSortedMarkets,
            favorites: ["SOL", "ETH"]
        )

        let pinnedCoins = sections[0].markets.map(\.coin)
        #expect(pinnedCoins == ["ETH", "SOL"])
    }

    @Test("MARKETS section preserves input (volume-desc) order after removing pinned coins")
    func marketsSectionPreservesInputOrder() {
        // Pin ETH. Remaining in volume order: BTC, SOL, DOGE.
        let sections = groupMarketsWithFavorites(
            volumeSortedMarkets,
            favorites: ["ETH"]
        )

        #expect(sections[1].markets.map(\.coin) == ["BTC", "SOL", "DOGE"])
    }

    @Test("All coins favorited → PINNED contains all (alpha), MARKETS is empty")
    func allCoinsFavorited() {
        let sections = groupMarketsWithFavorites(
            volumeSortedMarkets,
            favorites: ["BTC", "ETH", "SOL", "DOGE"]
        )

        #expect(sections.count == 2)
        #expect(sections[0].title == "PINNED")
        // Alphabetical: BTC, DOGE, ETH, SOL
        #expect(sections[0].markets.map(\.coin) == ["BTC", "DOGE", "ETH", "SOL"])
        #expect(sections[1].title == "MARKETS")
        #expect(sections[1].markets.isEmpty)
    }

    @Test("Favorite coin not present in markets list → ignored (no phantom row)")
    func favoritedCoinAbsentFromMarketsIsIgnored() {
        let sections = groupMarketsWithFavorites(
            volumeSortedMarkets,
            favorites: ["XYZ_DOES_NOT_EXIST"]
        )

        // No PINNED section (all favourites resolved to zero rows).
        // Implementation note: the real VM may choose to still emit an empty
        // PINNED section; if so, update this test to allow either shape.
        #expect(sections.first(where: { $0.title == "PINNED" })?.markets.isEmpty != false)
        // All markets land in MARKETS in input order.
        let marketSection = sections.first(where: { $0.title == "MARKETS" })!
        #expect(marketSection.markets.map(\.coin) == ["BTC", "ETH", "SOL", "DOGE"])
    }

    // MARK: - Toggle-then-regroup

    @Test("Toggling an unfavorited coin moves it to PINNED on next grouping call")
    func toggleMovesRowToPinned() {
        // Initially no favorites.
        var favorites: Set<String> = []
        let before = groupMarketsWithFavorites(volumeSortedMarkets, favorites: favorites)
        #expect(before.count == 1)
        #expect(before[0].title == "MARKETS")

        // Simulate toggling BTC.
        favorites.insert("BTC")
        let after = groupMarketsWithFavorites(volumeSortedMarkets, favorites: favorites)

        #expect(after[0].title == "PINNED")
        #expect(after[0].markets.map(\.coin) == ["BTC"])
        #expect(after[1].markets.map(\.coin) == ["ETH", "SOL", "DOGE"])
    }

    @Test("Toggling a favorited coin moves it back to MARKETS on next grouping call")
    func toggleMovesPinnedRowBackToMarkets() {
        var favorites: Set<String> = ["ETH", "SOL"]

        // Simulate un-toggling SOL.
        favorites.remove("SOL")
        let sections = groupMarketsWithFavorites(volumeSortedMarkets, favorites: favorites)

        #expect(sections[0].title == "PINNED")
        #expect(sections[0].markets.map(\.coin) == ["ETH"])
        // SOL is back in MARKETS at its original volume-sorted position (index 2).
        #expect(sections[1].markets.map(\.coin) == ["BTC", "SOL", "DOGE"])
    }
}

// MARK: - ViewModel integration tests (disabled — pending implementation)

// UNLOCK: Remove `.disabled` when the checklist at the top of this file is
// complete and replace the stub body with real MarketsViewModel calls.

@Suite(
    "MarketsViewModel — favorites integration",
    .disabled("Waiting for FavoriteCoinsStore + MarketsViewModel groupedMarkets to land. See unlock checklist.")
)
@MainActor
struct MarketsViewModelFavoritesIntegrationTests {

    // -----------------------------------------------------------------------
    // STUB BODY — replace with real ViewModel calls when unlocked.
    //
    // Expected MarketsViewModel API surface (per forthcoming §24):
    //
    //   @MainActor @Observable final class MarketsViewModel {
    //     init(client: any HyperliquidClient,
    //          favoriteCoinsStore: any FavoriteCoinsStore) { ... }
    //     var groupedMarkets: [(section: String, markets: [Market])] { get }
    //     func toggle(coin: String)
    //   }
    //
    // Stub tests below document the intended assertions.
    // -----------------------------------------------------------------------

    @Test("ETH+SOL pinned, volume-sorted input → PINNED=[ETH,SOL], MARKETS=[BTC,DOGE]")
    func pinnedSectionOrderedAlpha_MarketsSectionPreservesVolume() async {
        // STUB — does not run (suite is .disabled).
        //
        // let favorites = InMemoryFavoriteCoinsStore(initial: ["ETH", "SOL"])
        // let client = LocalFakeMarketsClient(markets: [
        //     .stub(coin: "BTC", volume: 900_000_000),
        //     .stub(coin: "ETH", volume: 500_000_000),
        //     .stub(coin: "SOL", volume: 200_000_000),
        //     .stub(coin: "DOGE", volume: 50_000_000),
        // ])
        // let vm = MarketsViewModel(client: client, favoriteCoinsStore: favorites)
        // await vm.load()
        //
        // let grouped = vm.groupedMarkets
        // #expect(grouped[0].section == "PINNED")
        // #expect(grouped[0].markets.map(\.coin) == ["ETH", "SOL"])
        // #expect(grouped[1].section == "MARKETS")
        // #expect(grouped[1].markets.map(\.coin) == ["BTC", "DOGE"])
    }

    @Test("No favorites → single MARKETS section, full list")
    func noFavoritesSingleSection() async {
        // STUB — see above.
    }

    @Test("toggle on unfavorited coin moves it to PINNED on next groupedMarkets access")
    func toggleMovesCoinToPinned() async {
        // STUB — see above.
    }
}

// MARK: - Composition / injection smoke tests (disabled — pending implementation)

@Suite(
    "OpenHLApp — FavoriteCoinsStore injection",
    .disabled(
        "Waiting for ios-developer to wire FavoriteCoinsStore into OpenHLApp.init. Remove .disabled when injection seam lands."
    )
)
struct OpenHLAppFavoriteCoinsStoreInjectionTests {

    // STUB: verify that production path creates UserDefaultsFavoriteCoinsStore
    // and UI-test env-var path creates InMemoryFavoriteCoinsStore.
    //
    // This cannot be meaningfully unit-tested without refactoring OpenHLApp to
    // expose its store type — flag to swift-expert if a dedicated inspection
    // seam (e.g. a `favoriteCoinsStoreType` property on the app in DEBUG) is
    // needed to make this testable without UI tests.

    @Test("Production init constructs UserDefaultsFavoriteCoinsStore")
    func productionPathUsesUserDefaults() {
        // STUB — waiting for injection seam.
    }

    @Test("UI-test env var OPENHL_UI_TEST_STUB → InMemoryFavoriteCoinsStore is used")
    func uiTestPathUsesInMemoryStore() {
        // STUB — waiting for injection seam.
    }
}
