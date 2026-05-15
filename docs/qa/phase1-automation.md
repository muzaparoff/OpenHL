# Phase 1 QA Automation Test Plan

**Owner:** qa-automation
**Phase:** 1 — Address entry and account snapshot
**Status:** Tests written; execution gated on ios-developer Phase 1 implementation.

---

## What is covered

### OpenHLCoreTests (Swift Testing, no `.disabled`)

| Area | Test file | Count | Notes |
|---|---|---|---|
| `Address` validation — valid inputs | `AddressTests.swift` | 9 | Parameterized over 5 valid addresses; property-style generator (10 trials each) |
| `Address` validation — invalid inputs | `AddressTests.swift` | 9 | Parameterized over 6 invalid inputs; `ValidationError` cases by exact case |
| `Address` Codable | `AddressTests.swift` | 2 | Round-trip; lowercase normalization |
| `DecimalParsing.parse` | `DecimalParsingTests.swift` | 15 | Zero, positive, negative, high-precision, whitespace, scientific notation rejection, grouping separator, leading plus, multiple dots, bare dot |
| `@DecimalString` Codable round-trip | `DecimalParsingTests.swift` | 8 | Decode valid, optional present/absent/null, encode-as-string, numeric-token rejection, malformed, comma separator, leading plus |
| `MoneyFormatter.usd` | `MoneyFormatterTests.swift` | 6 | Positive, zero, negative, 2 fraction digits, optional overloads |
| `MoneyFormatter.signedUSD` | `MoneyFormatterTests.swift` | 4 | Plus/minus/zero/optional |
| `MoneyFormatter.signedPercent` | `MoneyFormatterTests.swift` | 4 | Ratio × 100, signed, zero, optional |
| `MoneyFormatter.decimal` | `MoneyFormatterTests.swift` | 4 | Fraction digits, padding, rounding, zero |
| Locale leakage guard | `MoneyFormatterTests.swift` | 3 | Asserts `en_US` and `fr_FR` produce different output for `usd`, `signedUSD`, `decimal` |

### HyperliquidAPITests (Swift Testing, all Phase-1-impl-dependent tests `.disabled`)

| Area | Test file | Fixtures | Notes |
|---|---|---|---|
| Fixture decoding — `ClearinghouseState` | `DTODecodingTests.swift` | 7 | `empty`, `single_long`, `single_short_negative_pnl`, `multiple_mixed`, `large_decimals`, `with_liquidation_price`, `without_liquidation_price` |
| Error mapping | `DTODecodingTests.swift` | — | 500 → `httpStatus`; malformed JSON → `decoding`; `notConnectedToInternet` → `offline`; `timedOut` → `timeout` |
| Request shape | `DTODecodingTests.swift` | — | POST to `/info`, Content-Type header, body shape with lowercase address |
| `UserDefaultsAddressStore` | `AddressStoreTests.swift` | — | Write/read/clear; pre-seeding via public key; invalid stored value → nil |
| `InMemoryAddressStore` | `AddressStoreTests.swift` | — | Write/read/clear; seed; clear-on-empty no-op |

### OpenHLTests (Swift Testing, all `.disabled`)

| Area | Test file | Notes |
|---|---|---|
| `PositionsViewModel` state machine | `ViewModelStateTests.swift` | idle→loading→loaded; idle→error (offline, timeout, decoding, 5xx, 4xx); refresh preserves `lastLoaded` on failure |
| Position sort order | `ViewModelStateTests.swift` | Descending absolute notional; stable by coin name for ties; short positions use absolute value |

### OpenHLUITests (XCTest)

| Area | Status | Blocker |
|---|---|---|
| Phase-0 regression: app launches, title visible | **passes** | — |
| Entry → loaded happy path | `XCTSkip` | `OPENHL_UI_TEST_STUB` launch-env injection point in `OpenHLApp.swift` |
| Address entry: inline validation error | `XCTSkip` | `AddressEntryView` with accessibility IDs |
| Pull-to-refresh | `XCTSkip` | Both above |
| Offline error state | `XCTSkip` | `OPENHL_UI_TEST_STUB=error_offline` mode |

---

## Implementation bugs found by tests

The following are real bugs in the current partial ios-developer implementation, surfaced when running `swift test` on `OpenHLCore`:

| Bug | Test | Observed | Expected |
|---|---|---|---|
| `Address.init` accepts `0X` prefix | `AddressTests/0X uppercase prefix throws .missingPrefix` | No error thrown, returns address | `.missingPrefix` thrown (spec: prefix check is case-sensitive) |
| `DecimalParsing.parse` accepts scientific notation | `DecimalParsingTests/Rejects scientific notation` | Returns `100000` for `"1e5"` | Returns `nil` (spec: reject; Hyperliquid never uses it) |
| `DecimalParsing.parse` accepts multiple decimal points | `DecimalParsingTests/Returns nil for multiple decimal points` | Returns `1.2` for `"1.2.3"` | Returns `nil` |
| `DecimalParsing.parse` accepts bare `.` | `DecimalParsingTests/Returns nil for bare decimal point` | Returns `0` for `"."` | Returns `nil` |
| `DecimalParsing.parse` loses precision on high-precision input | `DecimalParsingTests/Parses a high-precision decimal` | `123456789.1234568` (truncated) | `123456789.123456789` |
| `@OptionalDecimalString` decode loses precision | `DecimalStringWrapperTests/Decodes optional field when present` | `99.98999...` for `"99.99"` | `99.99` (exact) |
| `MoneyFormatter.signedPercent` multiplier wrong | `MoneyFormatterTests/Positive ratio multiplies by 100` | `+0.12%` for `0.1234` | `+12.34%` (spec: input is a raw ratio) |
| `MoneyFormatter.signedPercent` multiplier wrong (negative) | `MoneyFormatterTests/Negative ratio shows minus` | `-0.01%` for `-0.012` | `-1.20%` |

These are **not test defects** — the tests are correct per the architecture spec. ios-developer needs to fix the implementation.

---

## What is NOT covered by automation (hand to qa-manual)

- VoiceOver labels on every interactive element and numeric value (Phase 1 acceptance criterion).
- Dynamic Type rendering at AX5 scale for the positions list and account header.
- Pull-to-refresh spinner visual behavior.
- Error state copy: is "Try again" discoverable? Does it clearly name the error type?
- Device-matrix: iPhone SE (narrow), Pro Max (wide), various iOS 17.x runtime variants.
- App cold-start to populated positions screen on real network (live API response, not fixture).

---

## Fixture inventory

All fixtures live in `Packages/HyperliquidAPI/Tests/HyperliquidAPITests/Fixtures/`. Wallet addresses are sanitized to `0xabcdef1234567890abcdef1234567890abcdef12` (test-only, no real funds).

| Fixture | Covers |
|---|---|
| `clearinghouseState_empty.json` | No positions; non-zero account value from sanitized real-looking response |
| `clearinghouseState_single_long.json` | One long BTC position, positive PnL, cross leverage, liquidation price present |
| `clearinghouseState_single_short_negative_pnl.json` | One short ETH position, negative PnL, isolated leverage |
| `clearinghouseState_multiple_mixed.json` | Long BTC, short ETH, long SOL (null liquidation price) |
| `clearinghouseState_large_decimals.json` | `123456789.123456789` scale values — precision regression guard |
| `clearinghouseState_with_liquidation_price.json` | Liquidation price present (isolated leverage) |
| `clearinghouseState_without_liquidation_price.json` | `liquidationPx: null` — optional field nil path |
| `clearinghouseState_malformed_decimal.json` | `"not_a_number"` in `accountValue` — decoder failure path |

Pre-existing fixtures (from architecture.md spec, added by ios-developer):
`clearinghouseState_typical.json`, `clearinghouseState_largeNegativePnL.json`,
`clearinghouseState_isolatedLeverage.json`, `clearinghouseState_missingLiquidationPx.json`
(overlap with qa-automation fixtures; both are valid; a consolidation pass is acceptable post-Phase 1).

---

## CI state

`.github/workflows/ci.yml` already runs `swift test --package-path Packages/HyperliquidAPI` and `swift test --package-path Packages/OpenHLCore` on every PR and push to main. The `xcodebuild test` step runs `OpenHLTests` and `OpenHLUITests` via the full Xcode scheme. No CI changes are needed for Phase 1 test coverage.

Disabled tests (`.disabled` trait) compile and appear in the test run as "skipped" — they do not fail CI. When ios-developer removes `fatalError` and implementations are complete, the `.disabled` traits must be removed and the tests must pass before the Phase 1 PR merges.

---

## How to enable tests incrementally

When ios-developer lands a piece of the implementation:

1. Remove the `.disabled("...")` trait from the relevant `@Suite`.
2. Run `swift test --package-path Packages/<PackageName>` locally.
3. Fix any new failures (they will either be implementation bugs or test-assumption mismatches; document which).
4. Ensure no previously-passing tests regress.
5. Remove this note from the suite once it consistently passes.
