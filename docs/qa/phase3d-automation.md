# Phase 3d — Favorite coins pinned: automation test plan

## What is covered

### `FavoriteCoinsStore` protocol conformance (OpenHLCore, `swift test`)

Located in `Packages/OpenHLCore/Tests/OpenHLCoreTests/FavoriteCoinsStoreTests.swift`.

**InMemoryFavoriteCoinsStore** (15 tests, all active):
- Default init returns empty set.
- `init(initial:)` pre-seeds the set.
- `toggle` adds a coin (absent → present).
- `toggle` removes a coin (present → absent).
- Toggle round-trip (add + remove → empty).
- Toggle multiple distinct coins accumulates all.
- `isFavorite` returns correct bool before and after each toggle.
- `all()` and `isFavorite()` agree on the same state.
- Concurrency: 100 even toggles → deterministic absent state.
- Concurrency: 101 odd toggles → deterministic present state.
- Concurrency: 5 coins × 10 toggles concurrently → all absent.
- `AsyncStream.changes` emits the updated set after a toggle.
- `AsyncStream.changes` emits empty set after a round-trip toggle pair.

**UserDefaultsFavoriteCoinsStore** (10 tests, all active):
- `all()` returns empty when UserDefaults key is absent.
- `toggle` adds a coin; `all()` reflects it.
- Write/read round-trip across two store instances (simulates app restart).
- Persisted coin removed by toggle across two instances.
- `isFavorite` before and after toggle.
- `storageKey` constant is `openhl.favoriteCoins`.
- JSON corruption (garbage data) → `all()` returns empty (defensive).
- JSON wrong type (object not array) → `all()` returns empty.
- Wrong UserDefaults value type (String not Data) → `all()` returns empty.
- Multiple coins persist and reload correctly.
- Concurrency: 100 even toggles → deterministic absent state.

### Markets sort/section logic (`OpenHLTests`, xcodebuild)

Located in `OpenHLTests/Phase3dMarketsSortTests.swift`.

**Pure grouping function** (`MarketGroupingPureTests`, 11 tests, all active):
- Empty favorites → single MARKETS section, full list in input order.
- Empty favorites + empty markets → single empty MARKETS section.
- ETH + SOL favorited → PINNED=[ETH, SOL] (alpha), MARKETS=[BTC, DOGE] (volume order preserved).
- Single coin favorited → PINNED=[BTC], MARKETS=[ETH, SOL, DOGE].
- PINNED section is alphabetical regardless of volume order.
- MARKETS section preserves input (volume-desc) order after removing pinned coins.
- All coins favorited → PINNED contains all (alpha), MARKETS is empty.
- Favorited coin absent from markets list → ignored, no phantom row.
- Toggle an unfavorited coin → moves to PINNED on next grouping call.
- Toggle a pinned coin → moves back to MARKETS on next grouping call.

**MarketsViewModel integration** (3 tests, `.disabled`):
- ETH+SOL pinned, volume-sorted input → PINNED=[ETH,SOL], MARKETS=[BTC,DOGE].
- No favorites → single MARKETS section.
- Toggle on unfavorited coin moves it to PINNED on next `groupedMarkets` access.

**OpenHLApp injection smoke tests** (2 tests, `.disabled`):
- Production init constructs `UserDefaultsFavoriteCoinsStore`.
- UI-test env var → `InMemoryFavoriteCoinsStore` is used.

### XCUITest — star button tap (OpenHLUITests)

Located in `OpenHLUITests/Phase3dFavoriteCoinsUITests.swift`.

Both tests carry `XCTSkip` pending ios-developer prerequisites:
- Tap BTC star → BTC row appears under PINNED header.
- Un-star BTC → PINNED header disappears.

## What is NOT covered by automation

- Visual appearance of the filled vs. unfilled star button — hand to `qa-manual`.
- Star button tap target size (44×44 pt minimum) — hand to `qa-manual`.
- Persistence survives app force-quit and relaunch — covered by `UserDefaultsFavoriteCoinsStore` unit tests at the store level; end-to-end confirmation is `qa-manual`.
- VoiceOver: "Favorite BTC" / "Unfavorite BTC" label toggle is audible — hand to `qa-manual` with VoiceOver enabled.
- Scroll position is preserved when a coin is pinned (does the list jump?) — hand to `qa-manual`.
- Search + favorites interaction (favorited coins in PINNED still appear when search text matches) — hand to `qa-manual` until ViewModel integration is wired.

## API surface change

Phase 3d adds NO new Hyperliquid API endpoints. The per-memory rule (real-API fixture test for each new endpoint) is NOT triggered.

## Unlock checklist for disabled tests

**`MarketsViewModelFavoritesIntegrationTests`**:
- [ ] swift-expert: `FavoriteCoinsStore` protocol + impls land in `OpenHLCore`
- [ ] Delete local stub types from `FavoriteCoinsStoreTests.swift` and add `@testable import OpenHLCore`
- [ ] ios-developer: `MarketsViewModel` exposes `groupedMarkets: [(section: String, markets: [Market])]`
- [ ] ios-developer: `MarketsViewModel` factory/init accepts `FavoriteCoinsStore` dependency
- [ ] Remove `.disabled` from `MarketsViewModelFavoritesIntegrationTests`

**`OpenHLAppFavoriteCoinsStoreInjectionTests`**:
- [ ] ios-developer: expose store type in a DEBUG inspection seam (flag to swift-expert if refactor needed)
- [ ] Remove `.disabled` from `OpenHLAppFavoriteCoinsStoreInjectionTests`

**`Phase3dFavoriteCoinsUITests`**:
- [ ] ios-developer: star button with `accessibilityLabel` "Favorite \<coin\>" / "Unfavorite \<coin\>"
- [ ] ios-developer: PINNED header with `accessibilityIdentifier = "pinned-section-header"`
- [ ] ios-developer: `UITestStubClient` handles stub key `"markets_stub_no_favorites"`
- [ ] ios-developer: `OPENHL_UI_TEST_STUB` injection resets `FavoriteCoinsStore` to `InMemoryFavoriteCoinsStore`
- [ ] Remove `XCTSkip` from both test methods
