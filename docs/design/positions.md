# Design spec: positions screen (account snapshot)

**Feature:** `positions`
**Phase:** 1
**Owner:** uxui-designer
**Last updated:** 2026-05-15

---

## 1. Goal

Show the user's current open positions and account-level summary from a single `clearinghouseState` API call, with pull-to-refresh to re-fetch.

---

## 2. User scenario

The user has entered a valid wallet address. The app has fetched or is fetching the account snapshot. The user wants to see, at a glance: how much capital is in the account, what positions are open, whether they are profitable or underwater, and the entry/mark/liquidation context for each position. They are likely checking quickly — on the train, between other tasks. The screen must be readable in under five seconds per visit.

---

## 3. Screen architecture

The positions screen is the root view after a valid address is stored. It contains:

1. A **navigation bar** with the app name and a settings affordance.
2. A **scrollable content area** that contains the account summary header followed by the positions list.
3. Pull-to-refresh on the scroll view.

No tab bar in Phase 1. Navigation to orders and fills (Phase 2) will introduce the tab/section shell; this spec does not design that shell. The positions screen is a standalone full-screen view in Phase 1.

---

## 4. States and wireframes

### 4a. Loading — initial fetch (cold start)

The address was just saved or the app just launched with a stored address. No data is cached.

```
┌──────────────────────────────────────┐
│  0x3f5C…833D         open-hl    ⚙   │  ← nav bar: truncated address left,
├──────────────────────────────────────┤     app name center, settings right
│                                      │
│                                      │
│                                      │
│                                      │
│            ◌                         │  ← ProgressView, centered
│            Fetching account…         │  ← subheadline, secondary label
│                                      │
│                                      │
│                                      │
│                                      │
└──────────────────────────────────────┘
```

Notes:
- Do not show the header skeleton. A fake layout with placeholder shapes is a pattern that can misrepresent the structure if the API shape differs from expectation. A centered spinner is honest and fast.
- The truncated address in the nav bar is a trust signal: the user can see which address is being fetched.
- Navigation bar uses `.navigationTitle` with display mode `.inline`. The centered "open-hl" label is a subtitle/logo — implement via `principal` toolbar item. The address goes in the leading toolbar slot.
- The settings gear (`⚙`, SF Symbol `gearshape`) is in the trailing toolbar slot. It is present even during loading so the user can navigate away if they fetched the wrong address.

---

### 4b. Loading — pull-to-refresh (data already on screen)

The user has pulled down. Existing data remains visible. The system-provided refresh control appears at the top.

```
┌──────────────────────────────────────┐
│  0x3f5C…833D         open-hl    ⚙   │
├──────────────────────────────────────┤
│  ↓  ◌  (system refresh control)     │  ← appears above content during pull
├─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┤
│  Account value                       │
│  $12,453.21                          │  ← stale data still visible
│  ─────────────────────────────────   │    opacity slightly reduced during refresh
│  Unrealized PnL        –$140.32      │    to signal staleness
│  Margin used           $4,201.10     │
│  Available margin      $8,252.11     │
├─────────────────────────────────────┤
│  BTC-USD    Long                     │
│  …                                   │
└──────────────────────────────────────┘
```

Notes:
- Use `.refreshable { await viewModel.refresh() }` on the `List` or `ScrollView`.
- The stale data remains at full layout during refresh. A subtle opacity reduction (`.opacity(0.6)`) on the content during refresh communicates "this is updating." Do not hide or replace the content.
- The last-updated timestamp updates after refresh completes. See the header spec in Section 4c.
- Pull-to-refresh is the only way to update data in Phase 1 (no WebSocket yet). Make it obvious by ensuring the scroll view's top content is not pinned such that the refresh control is unreachable.

---

### 4c. Success state — positions present

The fetch completed. Account has open positions.

```
┌──────────────────────────────────────┐
│  0x3f5C…833D         open-hl    ⚙   │
├──────────────────────────────────────┤
│                                      │
│  Account value                       │  ← label: footnote, secondary color
│  $12,453.21                          │  ← value: largeTitle, primary color
│                                      │
│  ────────────────────────────────    │  ← Divider
│                                      │
│  Unrealized PnL        –$140.32      │  ← label+value: subheadline, inline
│                                      │    value color: red tint + ▼ indicator
│  Margin used           $4,201.10     │  ← subheadline
│  Available margin      $8,252.11     │  ← subheadline
│                                      │
│  Updated 14:32:01                    │  ← caption, tertiary, trailing-aligned
│                                      │
├─────────────────────────────────────┤
│  OPEN POSITIONS  (3)                 │  ← section header, all caps, footnote
├─────────────────────────────────────┤
│  BTC-USD                    Long  ▲  │  ← asset name (headline) + side chip
│  Size  0.5000 BTC                    │  ← body, secondary
│  Entry $62,400.00                    │
│  Mark  $61,180.00                    │
│  Unr. PnL  –$610.00  –0.98%  ▼      │  ← value + percent, red + ▼
│  Liq.  $58,200.00                    │
├─────────────────────────────────────┤
│  ETH-USD                   Short  ▼  │
│  Size  2.0000 ETH                    │
│  Entry $3,210.00                     │
│  Mark  $3,194.50                     │
│  Unr. PnL  +$31.00   +0.48%  ▲      │  ← value + percent, green + ▲
│  Liq.  $3,480.00                     │
├─────────────────────────────────────┤
│  SOL-USD                    Long  ▲  │
│  Size  10.000 SOL                    │
│  Entry $142.80                       │
│  Mark  $144.30                       │
│  Unr. PnL  +$15.00   +1.05%  ▲      │
│  No liquidation price                │  ← only shown when liq. price absent
└─────────────────────────────────────┘
```

#### Account summary header details

| Field | Label text | Notes |
|---|---|---|
| Account value | "Account value" | Total equity. Large, prominent. |
| Unrealized PnL | "Unrealized PnL" | Sum of all position PnL. Can be negative. |
| Margin used | "Margin used" | Cross or isolated margin consumed. |
| Available margin | "Available margin" | Equity minus margin used, approximately. |
| Timestamp | "Updated [HH:mm:ss]" | Time of the last successful fetch, device local time. |

Wording rules:
- Do not use "profit," "gain," "return," or "earnings" anywhere. "Unrealized PnL" is the standard trading term and is factually neutral.
- Do not use "balance" for account value unless confirmed by the API schema — the Hyperliquid `clearinghouseState` response uses `marginSummary.accountValue`.
- "Available margin" may not map directly to a single API field. Flag in open questions.

#### Position row details

Each row is a `VStack(alignment: .leading, spacing: 4)` wrapped in a `List` row. The row does not use a `NavigationLink` in Phase 1 (no detail screen for positions yet).

Fields per row:

| Field | Display label | Notes |
|---|---|---|
| Asset | No label | Asset symbol in `.headline` weight. E.g. "BTC-USD". |
| Side | "Long" or "Short" | Trailing on the same line as asset. Color chip: blue for long, orange for short (not green/red — reserved for PnL). SF Symbol: `arrow.up` for long, `arrow.down` for short, placed next to the text. |
| Size | "Size" | Formatted with 4 decimal places for most assets. Do not hardcode decimal places — format according to the asset's tick size (open question: how is tick size available? see Section 9). |
| Entry price | "Entry" | Formatted as currency. |
| Mark price | "Mark" | Formatted as currency. This is the current price per the API snapshot, not a live feed in Phase 1. |
| Unrealized PnL | "Unr. PnL" | Absolute value with sign ("+$31.00" or "–$610.00") and percentage (" +0.48%" or " –0.98%"). See PnL color rules below. |
| Liquidation price | "Liq." | Omit row entirely if null or zero. If present: formatted as currency. |

PnL color and shape rules (color-blind safe):

- Positive PnL: system green tint on the value text + `▲` (SF Symbol `arrow.up`, small) trailing the percentage.
- Negative PnL: system red tint on the value text + `▼` (SF Symbol `arrow.down`, small) trailing the percentage.
- Zero PnL: primary label color, no arrow.
- When "Increase Contrast" is enabled in accessibility settings, use `.primary` label color for the text and rely only on the directional arrow for positive/negative signal. Use `.foregroundStyle(.red)` and `.foregroundStyle(.green)` only — these are system semantic colors that adapt to Increase Contrast mode automatically.
- Color-blind users: the arrows (`▲` / `▼`) are the primary indicator. Color is secondary. Verify with Deuteranopia simulation in Xcode Accessibility Inspector.

Side chip colors (not for PnL, for position direction):

- Long: system blue (`.systemBlue`) background tint on the text. Not green (green is for PnL).
- Short: system orange (`.systemOrange`) background tint. Not red (red is for PnL).
- Using distinct colors for direction vs. PnL avoids the conflation that makes many trading apps hard to read.

---

### 4d. Success state — no open positions

Valid address, fetch succeeded, account has zero positions.

```
┌──────────────────────────────────────┐
│  0x3f5C…833D         open-hl    ⚙   │
├──────────────────────────────────────┤
│                                      │
│  Account value                       │
│  $12,453.21                          │
│                                      │
│  ────────────────────────────────    │
│                                      │
│  Unrealized PnL         $0.00        │  ← no color, no arrow (zero)
│  Margin used            $0.00        │
│  Available margin      $12,453.21    │
│                                      │
│  Updated 14:32:01                    │
│                                      │
├─────────────────────────────────────┤
│                                      │
│                                      │
│       No open positions              │  ← title3, secondary label
│                                      │
│       Pull down to refresh.          │  ← subheadline, tertiary label
│                                      │
│                                      │
└──────────────────────────────────────┘
```

Notes:
- The account summary header is still shown. The user still has an account with a non-zero value; hiding the header would feel like the screen is broken.
- "No open positions" is factual. Not "You're all clear!" or any encouraging framing.
- "Pull down to refresh." is a functional affordance — the user may have just closed positions and wants to confirm. Pull-to-refresh still works in the empty state.

---

### 4e. Error state — offline

Device has no network connection. Either the initial fetch failed or a pull-to-refresh failed.

```
┌──────────────────────────────────────┐
│  0x3f5C…833D         open-hl    ⚙   │
├──────────────────────────────────────┤
│                                      │
│                                      │
│                                      │
│  wifi.slash                          │  ← SF Symbol, large, secondary color
│  (large symbol, centered)            │
│                                      │
│  No internet connection              │  ← title3
│                                      │
│  Connect and pull down to refresh.   │  ← subheadline, secondary
│                                      │
│                                      │
│  [ Try again ]                       │  ← .bordered button, centered
│                                      │
│                                      │
└──────────────────────────────────────┘
```

Notes:
- If this is a pull-to-refresh failure and data was previously loaded, the error replaces the content area but the nav bar still shows. Consider keeping the last-loaded content visible with a non-intrusive banner at the top instead of a full-page error. See open questions.
- `wifi.slash` is the system symbol for "no connection." Do not use a custom illustration.
- "Try again" calls the same fetch. Pull-to-refresh also works.

---

### 4f. Error state — server error (5xx)

API returned a non-success HTTP status.

```
┌──────────────────────────────────────┐
│  0x3f5C…833D         open-hl    ⚙   │
├──────────────────────────────────────┤
│                                      │
│                                      │
│  exclamationmark.circle              │  ← SF Symbol, large, secondary color
│  (large symbol, centered)            │
│                                      │
│  Hyperliquid is unavailable          │  ← title3
│                                      │
│  The server returned an error        │  ← subheadline, secondary
│  (HTTP 503). Try again in a moment.  │    inject the actual status code
│                                      │
│  [ Try again ]                       │
│                                      │
└──────────────────────────────────────┘
```

Notes:
- Include the HTTP status code. It is useful for users who want to check the Hyperliquid status page.
- Do not say "something went wrong." Say what went wrong.

---

### 4g. Error state — timeout

Request exceeded the networking layer's timeout.

```
┌──────────────────────────────────────┐
│  0x3f5C…833D         open-hl    ⚙   │
├──────────────────────────────────────┤
│                                      │
│                                      │
│  clock.badge.exclamationmark         │  ← SF Symbol
│  (large symbol, centered)            │
│                                      │
│  Request timed out                   │  ← title3
│                                      │
│  Hyperliquid may be slow.            │  ← subheadline, secondary
│  Pull down or tap to try again.      │
│                                      │
│  [ Try again ]                       │
│                                      │
└──────────────────────────────────────┘
```

---

### 4h. Error state — parse failure

Response arrived but the app could not decode it. This is rare in production but must be designed.

```
┌──────────────────────────────────────┐
│  0x3f5C…833D         open-hl    ⚙   │
├──────────────────────────────────────┤
│                                      │
│                                      │
│  xmark.circle                        │  ← SF Symbol
│                                      │
│  Could not read account data         │  ← title3
│                                      │
│  The API returned a response the     │  ← subheadline, secondary
│  app did not recognize. This may     │
│  be a temporary API change.          │
│                                      │
│  [ Try again ]                       │
│                                      │
│  If this persists, please file       │  ← footnote, tertiary, link style
│  an issue on GitHub.                 │    tappable: opens repo issues URL
│                                      │
└──────────────────────────────────────┘
```

Notes:
- The GitHub issues link serves two purposes: it tells the user this is not their fault, and it provides a feedback channel for the open-source project. Use `Link("file an issue on GitHub", destination: URL(string: "https://github.com/…/issues")!)` (URL TBD — open question).
- This error is distinct from network errors. Use a different symbol (`xmark.circle` not `wifi.slash`) and different message to help users report it accurately.

---

### 4i. Settings / change address affordance

The `⚙` button in the nav bar leads to a minimal settings sheet. In Phase 1 this sheet contains one action: change the wallet address.

```
┌──────────────────────────────────────┐
│  Done                 Settings       │  ← modal sheet nav bar
├──────────────────────────────────────┤
│                                      │
│  WALLET ADDRESS                      │  ← section header
├─────────────────────────────────────┤
│  0x3f5CE5FBFe3E9af3971dD833D26f…    │  ← truncated, body, monospace, read-only
│  Change address                      │  ← system link color, tappable
├─────────────────────────────────────┤
│                                      │
│  ABOUT                               │  ← section header
├─────────────────────────────────────┤
│  open-hl v1.0 (build 1)             │  ← no tappable affordance
│  MIT licensed, open source          │  ← tappable link → GitHub repo URL
└──────────────────────────────────────┘
```

Notes:
- "Change address" navigates to the address entry screen presented as a `.sheet` (described in `address-entry.md` section 3g).
- The settings sheet is itself a `.sheet`. Presenting a sheet from within a sheet on iOS requires `.presentationDetents` or a push; test on iOS 17 specifically since sheet-on-sheet behavior changed. Flag as open question.
- "Done" dismisses the settings sheet.
- No "delete address" or "log out" concept in v1 — "change address" replaces the stored one.
- Version string: read from `Bundle.main.infoDictionary` for `CFBundleShortVersionString` and `CFBundleVersion`. Do not hardcode.

---

## 5. Position row reflow for Dynamic Type

At default text sizes, each position uses a two-column layout on some fields (label left, value right). At large Dynamic Type sizes, this becomes unreadable because the values cannot fit on a single line.

### Default and Large text sizes (up to ~AX2)

```
BTC-USD                      Long  ▲
Size   0.5000 BTC
Entry  $62,400.00
Mark   $61,180.00
Unr. PnL  –$610.00  –0.98%  ▼
Liq.  $58,200.00
```

All on one card. Asset and side on the same line. Fields stacked below.

### AX3 and above

When Dynamic Type exceeds a threshold (check using `@Environment(\.dynamicTypeSize) >= .accessibility3`), switch to a fully vertical layout:

```
BTC-USD
Long  ▲
────────────
Size
0.5000 BTC
────────────
Entry
$62,400.00
────────────
Mark
$61,180.00
────────────
Unrealized PnL
–$610.00  –0.98%  ▼
────────────
Liquidation price
$58,200.00
```

Label on one line, value directly below it. Labels expand to full words ("Unrealized PnL" not "Unr. PnL", "Liquidation price" not "Liq."). This is readable in AX5 without horizontal scrolling.

Implementation: use `@Environment(\.dynamicTypeSize)` to branch the row layout. A `ViewBuilder` helper `func positionRow(_ position: Position, compact: Bool) -> some View` keeps the two layouts in one place.

---

## 6. iPhone SE vs. Pro Max layout notes

iPhone SE 3rd gen screen width: 375pt logical pixels.
iPhone 16 Pro Max screen width: 430pt.

| Element | SE behavior | Pro Max behavior |
|---|---|---|
| Nav bar address label | Truncates at ~120pt; shows "0x3f5C…833D" | More room; can show a few more chars |
| Account value ($largeTitle) | Fits at most 12 characters before wrapping; "$12,453.21" (10 chars) fits | Fits comfortably |
| Position row, single-line asset+side | "BTC-USD" (7 chars) + "Long ▲" (6 chars) = 13 chars, fits at default size | Ample space |
| Unrealized PnL line | "–$610.00  –0.98%  ▼" — 19 chars at body size fits in 335pt; verify | Fine |
| AX5 text sizes | Fields wrap; row height grows significantly; List row auto-sizes | Same, slightly more horizontal breathing room |

On SE, verify at AX5 that the account value (largeTitle) does not clip. Use `.minimumScaleFactor(0.7)` on the value label and `.lineLimit(1)` — if the formatted value is still too long, allow it to break to two lines without a minimum scale factor. Do not truncate currency values.

On Pro Max, no special layout changes needed. The `.listStyle(.insetGrouped)` (or equivalent) provides symmetric margins.

---

## 7. Interactions

| Trigger | Response |
|---|---|
| Initial navigation to positions | Fetch begins via `.task`; loading state shown |
| Pull down on scroll view | System refresh control activates; `viewModel.refresh()` called |
| Refresh succeeds | Content updates; timestamp updates; haptic: `.success` |
| Refresh fails | Error state shown (or inline banner if data was already loaded); haptic: `.error` |
| Tap `⚙` settings button | Settings sheet presents |
| Tap "Change address" in settings | Settings sheet presents address entry sheet on top |
| Tap "Try again" on error | Re-triggers fetch |
| Tap "file an issue on GitHub" | Opens Safari with the GitHub issues URL |
| Scroll up past top | System pull-to-refresh activates if user continues |

Position rows are not tappable in Phase 1. No detail screen. Rows should not have a disclosure indicator or chevron. Use `.listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))` to suppress the tappable highlight.

Haptics summary:
- Successful data load/refresh: `.success` (one gentle tap)
- Failed refresh: `.error` (double tap, indicates something went wrong)
- Do not haptic on the initial cold-start load.

---

## 8. Accessibility

### VoiceOver

Every numeric value requires a meaningful VoiceOver label. The default label for a `Text("–$610.00")` is the literal string "minus dollar 610.00", which is not useful. Use `.accessibilityLabel` on each numeric value.

Required VoiceOver overrides:

| Displayed text | `.accessibilityLabel` string |
|---|---|
| "$12,453.21" (account value) | "Account value, 12,453 dollars and 21 cents" |
| "–$140.32" (unrealized PnL) | "Unrealized PnL, minus 140 dollars and 32 cents" |
| "$4,201.10" (margin used) | "Margin used, 4,201 dollars and 10 cents" |
| "$8,252.11" (available margin) | "Available margin, 8,252 dollars and 11 cents" |
| "Updated 14:32:01" | "Last updated at 2:32 PM" (spell out, use relative time format) |
| Position row | Combine all fields into one `.accessibilityElement(children: .combine)` label on the row container. Format: "[Asset] [side], size [size], entry [entry], mark [mark], unrealized PnL [PnL absolute and percent], [liq price or 'no liquidation price']." Example: "BTC-USD long, size 0.5 bitcoin, entry 62,400 dollars, mark 61,180 dollars, unrealized PnL minus 610 dollars, minus 0.98 percent, liquidation price 58,200 dollars." |
| "Long" chip | "Long position" |
| "Short" chip | "Short position" |
| PnL `▲` or `▼` | Included in the combined row label; do not separately announce the arrow symbol |
| Settings gear button | "Settings" |
| "Change address" | "Change wallet address" |

Grouping: each position row should be an `accessibilityElement(children: .combine)` so VoiceOver swipes to the whole row, not each label individually.

### Rotor and navigation

The positions list should be navigable by heading. Add `.accessibilityAddTraits(.isHeader)` to the "OPEN POSITIONS (3)" section header and to each position's asset label so VoiceOver users can jump between positions using the Headings rotor.

### Reduce Motion

The only animation candidate in Phase 1 is the optional fade/opacity change when data refreshes. Wrap it in `withAnimation(reduceMotion ? nil : .default)` using `@Environment(\.accessibilityReduceMotion)`.

### Contrast

Same rules as address-entry.md: system semantic colors are used throughout, which adapt to Increase Contrast automatically. The only custom color usage is the blue/orange side chips — verify at maximum contrast that these remain distinguishable from background.

---

## 9. SwiftUI implementation hints

- Use `List` with `.listStyle(.insetGrouped)` for the positions list. This gives the correct iOS 17+ visual appearance and handles row separators, swipe actions, and accessibility automatically. Alternative: `LazyVStack` inside `ScrollView` if more layout control is needed; but then you must manage separators and pull-to-refresh manually.
- The account summary header is a non-list section at the top of the `List`, implemented as a `Section` with no header text, or as a `.listRowBackground(.clear)` section above the positions section.
- Pull-to-refresh: `.refreshable { await viewModel.refresh() }` on the `List`.
- Data fetch: `.task { await viewModel.loadInitial() }` on the view. The task is cancelled automatically when the view disappears.
- `PositionsViewModel` (`@MainActor @Observable final class`) state enum:

  ```swift
  enum ViewState {
      case idle
      case loading
      case loaded(AccountSnapshot)
      case refreshing(AccountSnapshot)  // has data, refreshing in background
      case error(HyperliquidError, AccountSnapshot?)  // error, optional stale data
  }
  ```

  The `refreshing` and `error(_, stale)` cases allow the view to keep showing existing data during a refresh attempt or after a failed refresh.

- `AccountSnapshot` is a domain model in `OpenHLCore` (or `HyperliquidAPI`). It holds `Decimal`-typed fields. The view model converts it to view-facing structs (`PositionRowItem`, etc.) with pre-formatted strings using `NumberFormatter` / `Decimal.FormatStyle`.
- Number formatting: do not format in the view. Pass pre-formatted strings from the view model. This keeps `Decimal` out of the view layer and makes tests trivial.
- Timestamp: store the `Date` of the last successful fetch in the view model. Format it with `Date.FormatStyle` using `.time(.standard)` for display, and a full description for VoiceOver.
- For the "no internet" state, use `NWPathMonitor` (Network.framework) in the view model to detect offline state before attempting a fetch. This is not required in Phase 1 if the networking layer's `HyperliquidError.offline` handles it — but showing the `wifi.slash` state immediately on launch without waiting for a timeout is a significantly better experience. Flag as open question.
- The settings sheet and change-address sheet: `@State private var showingSettings = false` and `@State private var showingAddressEntry = false` on the positions view, presented via `.sheet(isPresented:)`. On iOS 17+, sheets can be stacked; test this interaction.

---

## 10. Open questions

1. **API field mapping for account summary.** The `clearinghouseState` response schema needs to be confirmed so labels map to the right fields. Specifically: what field represents "account value" (total equity)? What is "margin used" (cross margin consumed, isolated margin, or sum)? What is "available margin"? Document the mapping in `HyperliquidAPI` DTOs so it is not guessed.

2. **Stale-data behavior on failed refresh.** The spec calls for keeping existing data visible with an error state during a failed pull-to-refresh. This is a UX judgment call (vs. replacing all content with the error screen). PM to confirm the desired behavior for Phase 1. The `ViewState.error(_, AccountSnapshot?)` design above supports both modes; the view just needs to know which to render.

3. **Asset decimal places.** The spec notes "format according to the asset's tick size" for position sizes and prices. Does the `clearinghouseState` response include tick size metadata per asset, or must the app infer it? If it must be hardcoded or fetched from a separate endpoint, that is a Phase 1 scope item that needs engineering input.

4. **Liquidation price availability.** Is liquidation price always present in the API response for a position, or is it null/absent for some position types (e.g. isolated vs. cross margin)? The spec handles the null case with "No liquidation price" text — confirm this is the right fallback.

5. **"Available margin" field.** The architecture doc notes `UserDefaults` for address persistence but does not describe the API schema in detail. Confirm which API field corresponds to "available margin" and whether it is directly available or must be computed (equity - margin used). A computed value that doesn't match the exchange's own display number is a trust problem.

6. **Offline detection.** The spec recommends `NWPathMonitor` for proactive offline detection. This requires the `Network` framework. Confirm with swift-expert whether `Network.framework` import is acceptable in the view model layer or whether it belongs in `HyperliquidAPI` / `OpenHLCore`, and whether the scope is in Phase 1 or deferred.

7. **GitHub issues URL.** The parse-failure error state links to the GitHub issues page. Confirm the repo URL so the developer can hardcode it as a constant (it should not change after launch, unlike API endpoints).

8. **Settings sheet stacking on iOS 17.** Presenting an address entry sheet from within the settings sheet (sheet-on-sheet) has changed behavior across iOS versions. Confirm that `.sheet(isPresented:)` from inside a `.sheet` works as expected on iOS 17.0 specifically, or whether a navigation push within the settings sheet is more reliable.

9. **Position sort order.** The spec does not specify how positions are ordered in the list. Options: as returned by the API, by asset name alphabetically, by unrealized PnL (largest loss first, largest gain first), by size. PM to decide the default sort order for Phase 1.

10. **PnL sign convention.** Confirm whether the API returns PnL as a signed decimal (positive = profit, negative = loss) or always positive with a separate direction field. The display spec assumes signed decimal.
