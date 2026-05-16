# Real-Data Fixture Policy

## Summary

Every Hyperliquid REST endpoint we ship MUST have at least one fixture captured
from the live API, not just hand-authored JSON.  The purpose is to detect latent
DTO bugs — nullable fields the API returns as `null` in practice, fields the API
sometimes omits entirely, or extra top-level keys that would expose gaps in our
`Decodable` implementations.

This rule was put in place after a P0: `metaAndAssetCtxs` returns `null` for
`premium`/`oraclePx`/`midPx` on ~47 delisted perps, our DTO required them, and
first-launch decoding tanked with "Could not read data" for all users.

---

## Covered endpoints (as of 2026-05-16)

| Endpoint | Hand-authored fixtures | Real-data fixture | DTO bugs found |
|---|---|---|---|
| `clearinghouseState` | yes (Phase 1/2, many variants) | `clearinghouseState_real_subset.json` | none new |
| `openOrders` | yes (Phase 2) | `openOrders_real_subset.json` | **P0: `orderType` was required but is always absent in real responses** |
| `userFills` | yes (Phase 2) | `userFills_real_subset.json` | none (extra fields silently ignored) |
| `metaAndAssetCtxs` | yes | `metaAndAssetCtxs_real_subset.json` | P0 (the original incident — already fixed) |
| `candleSnapshot` | hand-authored only (3 bars) | `candleSnapshot_btc_1h_real.json`, `_4h_real`, `_1d_real`, `_1w_real` | none |

---

## DTO bug found: `openOrders` — `orderType` field

**Severity:** P0 (same class as the `metaAndAssetCtxs` incident).

**Root cause:** `OpenOrderDTO` declared `orderType: String` as a required field.
Real `openOrders` API responses **never include `orderType`** for plain limit
orders, which accounts for the overwhelming majority of all open orders.  A
`JSONDecoder` decode attempt on any real account would have thrown
`keyNotFound("orderType")`, causing `HyperliquidError.decoding` and surfacing
"Could not read data" to the user.

**Fix applied (minimal):**

1. `OpenOrdersDTO.swift`: changed `internal let orderType: String` to
   `internal let orderType: String?`.  Changed `orderType = try c.decode(…)`
   to `orderType = try c.decodeIfPresent(…)`.

2. `URLSessionHyperliquidClient.swift` mapper: added `case nil` alongside
   `case "Limit"` in the `switch dto.orderType` so a missing field defaults
   to `.limit` (consistent with Hyperliquid's implicit behavior — all
   market-maker/reduce-only orders without an `orderType` key are limit orders).

**Tests added:** see `openOrders — real subset fixture` suite in
`Phase3RealDataDecodingTests.swift`.

---

## Fields present in real responses but absent from DTOs (intentionally ignored)

These are all fine — Swift's `Decodable` ignores unknown keys by default.
Documented here so future engineers know we've seen them:

| Endpoint | Extra field | Type | Notes |
|---|---|---|---|
| `clearinghouseState` | `crossMaintenanceMarginUsed` | `String` | Maintenance margin at top level |
| `clearinghouseState` position | `maxLeverage` | `Int` | Per-position max leverage |
| `clearinghouseState` position | `cumFunding` | object | Funding fee history |
| `openOrders` | `cloid` | `String` | Client order ID, hex |
| `userFills` | `startPosition` | `String` | Position size before fill |
| `userFills` | `twapId` | `null` (nullable) | TWAP order reference |
| `userFills` | `liquidation` | object or `null` | Populated when fill was a liquidation |
| `userFills` | `cloid` | `String` | Client order ID, hex |

---

## Process rule: how to add a new endpoint

Before merging any PR that adds a new `HyperliquidClient` method:

1. `curl` the real endpoint with at least one address/parameter that produces
   representative data (non-empty arrays, mix of null and non-null optional fields
   where applicable).
2. Save the raw JSON as `Packages/HyperliquidAPI/Tests/HyperliquidAPITests/Fixtures/<endpoint>_real_subset.json`.
   Trim arrays to ≤15 entries to keep diff size sane; preserve full structural shape.
   Sanitize any wallet addresses in response bodies (replace with `0xdeadbeef...`).
3. Write a `@Suite` / `@Test` group in a `Phase*RealDataDecodingTests.swift` file that:
   - Decodes the fixture through the DTO.
   - Asserts on at least: array count, one `String` field, one `Decimal` field,
     and any optional that should be `nil` in the real data.
   - Runs `swift test --package-path Packages/HyperliquidAPI` green before the PR
     is opened.
4. If the real data exposes a nullable field that the DTO requires as non-optional,
   fix the DTO (make optional + add default in the mapper) and add a regression test.

---

## What automation cannot cover (hand to qa-manual)

- Accounts with zero balance / no fills / no orders (empty-array paths are covered
  by hand-authored fixtures but should be validated on-device once per release).
- Trigger / stop-loss orders: no real-data fixture for `orderType: "Trigger"` or
  `"Stop Limit"` yet because none appeared in the sampled live accounts.  Hand-authored
  fixtures exist; real-data gap should be filled when an address with such orders is
  identified.
- Spot fills (`"@142"` coin format, `feeToken: "UBTC"`) — the `feeToken` field can be
  non-USDC for spot dust conversions.  DTO handles it (`feeToken: String`), but no
  dedicated test.  Add a real fixture once the app begins displaying spot fills.
- `userFills` over-200-cap behavior on a real account with >200 fills — covered by a
  hand-authored fixture but not a real one (requires an account with exactly the right
  data shape).
