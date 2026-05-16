# Design spec: coin detail — interval picker and custom date range

**Feature:** `coin-detail-timelines`
**Phase:** 3c
**Owner:** uxui-designer
**Last updated:** 2026-05-16

---

## 1. Goal

Replace the existing 4-segment interval picker with a 6-segment picker that adds a "Custom" option, letting the user define an arbitrary date range and view the resulting candle chart without leaving the coin detail screen.

---

## 2. User scenario

A trader is on the BTC detail screen. They glance at the 1d chart, then want to compare the price action from a specific two-week window three months ago. They tap "Custom," pick a start and end date, tap Apply, and see the chart redrawn for that window. The selected range persists until they change interval or leave the screen. Pull-to-refresh re-fetches the same custom window without resetting the picker.

---

## 3. Wireframes

### 3a. Default state — picker at `1h`

```
┌──────────────────────────────────────┐
│  ← BTC         BTC             ⟳    │  ← nav bar, refresh trailing
├──────────────────────────────────────┤
│                                      │
│  BTC                                 │
│  $62,401.50                          │
│  ▲ +$760.50  +1.23%   24h           │
│                                      │
│  ┌──────────────────────────────┐    │
│  │ 1h · 1d · 1w · 1M · 1y · Custom │    │  ← segmented control
│  └──────────────────────────────┘    │
│                                      │
│  [  candlestick chart — 280pt tall ] │
│                                      │
│  ──────────────────────────────────  │
│  Open interest     1,234.50          │
│  24h volume        $830,000,000      │
│  Funding rate      +0.0100%          │
│  Max leverage      50×               │
└──────────────────────────────────────┘
```

The picker sits between the header and the chart, consistent with the current layout. No change to the nav bar or stats rows.

---

### 3b. Custom sheet — open (date pickers visible)

The sheet presents over the coin detail screen. The previously active segment (e.g. "1w") is still visually selected in the picker behind the sheet; the sheet has not yet committed a custom range.

```
┌──────────────────────────────────────┐
│  ← BTC         BTC             ⟳    │
├──────────────────────────────────────┤
│  [coin header — partially obscured]  │
│  [picker — partially obscured]       │
│  [chart — partially obscured]        │
│                                      │
│ ╔══════════════════════════════════╗ │
│ ║  Custom range              ✕     ║ │  ← sheet drag handle at top; ✕ = xmark
│ ╠══════════════════════════════════╣ │     button, dismisses without applying
│ ║                                  ║ │
│ ║  Start                           ║ │  ← label: subheadline, secondary
│ ║  ┌────────────────────────────┐  ║ │
│ ║  │  DatePicker — compact      │  ║ │  ← .datePickerStyle(.compact)
│ ║  │  May 1, 2026               │  ║ │    default: 7 days ago
│ ║  └────────────────────────────┘  ║ │
│ ║                                  ║ │
│ ║  End                             ║ │
│ ║  ┌────────────────────────────┐  ║ │
│ ║  │  DatePicker — compact      │  ║ │    default: today (now, rounded to day)
│ ║  │  May 8, 2026               │  ║ │
│ ║  └────────────────────────────┘  ║ │
│ ║                                  ║ │
│ ║  ┌────────────────────────────┐  ║ │
│ ║  │         Apply              │  ║ │  ← .buttonStyle(.borderedProminent)
│ ║  └────────────────────────────┘  ║ │    full-width, system blue
│ ║                                  ║ │
│ ║  [validation message area]       ║ │  ← see validation copy below
│ ║                                  ║ │
│ ╚══════════════════════════════════╝ │
└──────────────────────────────────────┘
```

**Sheet presentation:** `.presentationDetents([.medium])`. Medium detent is sufficient for two date pickers and a button. Full-height is not needed and would obscure the chart unnecessarily. If the keyboard or date wheel expands the content, the sheet should not grow to `.large` automatically — use `.presentationDragIndicator(.visible)` and allow the user to drag it up if needed.

**Dismiss without applying:** the `✕` button (SF Symbol `xmark`, leading-trailing placement in sheet nav bar using `.toolbar`) closes the sheet and reverts the picker selection to the previously active non-custom segment. Dragging the sheet down has the same effect.

**Validation rules and Apply button state:**

| Condition | Apply state | Message shown (below button, caption, secondary) |
|---|---|---|
| End >= Start + 1 day, range <= 3 years | Enabled | None |
| End == Start (same day) | Disabled | "Start and end must be different days." |
| End < Start | Disabled | "End must be after start." |
| Range > 3 years | Disabled | "Range cannot exceed 3 years." |

Validation messages appear only after the user has changed at least one date (not on initial open). Use a `@State var hasInteracted: Bool` to gate display.

---

### 3c. Custom active — label shows range

After Apply, the sheet dismisses and the chart re-fetches. The "Custom" segment label updates to show the compressed range.

```
┌──────────────────────────────────────┐
│  ← BTC         BTC             ⟳    │
├──────────────────────────────────────┤
│                                      │
│  BTC                                 │
│  $62,401.50                          │
│  ▲ +$760.50  +1.23%   24h           │
│                                      │
│  ┌─────────────────────────────────┐ │
│  │ 1h · 1d · 1w · 1M · 1y · May 1→Jun 14 │ │  ← selected segment, compressed label
│  └─────────────────────────────────┘ │
│                                      │
│  [  candlestick chart — custom window — 280pt ] │
│                                      │
│  ──────────────────────────────────  │
│  Open interest     1,234.50          │
│  …                                   │
└──────────────────────────────────────┘
```

**Active custom label format:**

- Same year as current year: "May 1 → Jun 14" (abbreviated month, day, arrow, no year)
- Cross-year range: "Dec 1 2024 → Jan 15 2025" (abbreviated month, day, 4-digit year)
- The arrow character is the Unicode rightwards arrow (→, U+2192), not an SF Symbol, to keep the segmented label a plain `String`.
- If the label exceeds the available segment width, it truncates with an ellipsis. Tapping it still selects it and re-opens the sheet (see interactions section).

**Tapping an active custom segment re-opens the custom sheet** pre-filled with the current custom dates, not reset to defaults. The user can adjust the range without starting over.

**Switching away from custom:** if the user taps any of 1h / 1d / 1w / 1M / 1y while a custom range is active, the chart fetches the standard interval and the custom range is retained in memory but deselected. Tapping "Custom" (or the compressed label) again restores the last custom range, not the defaults.

---

### 3d. Out-of-data empty state

The user picked a valid date range but the coin did not trade during that window (e.g. a coin listed in 2024; the user picked Jan–Feb 2022). The API returns an empty candle array. This is not a network error.

```
┌──────────────────────────────────────┐
│  ← BTC         BTC             ⟳    │
├──────────────────────────────────────┤
│                                      │
│  BTC                                 │
│  $62,401.50                          │
│  ▲ +$760.50  +1.23%   24h           │
│                                      │
│  ┌─────────────────────────────────┐ │
│  │ 1h · 1d · 1w · 1M · 1y · Jan 1→Feb 28 │ │
│  └─────────────────────────────────┘ │
│                                      │
│                                      │
│       calendar.badge.exclamationmark │  ← SF Symbol, .font(.system(size:48))
│                                      │     foregroundStyle(.secondary)
│       No data for this period        │  ← title3, primary
│                                      │
│       BTC may not have traded        │  ← subheadline, secondary
│       during Jan 1 → Feb 28, 2022.  │    inject the active range into copy
│                                      │
│       Try a different range.         │  ← subheadline, secondary, separate line
│                                      │
│  ──────────────────────────────────  │
│  Open interest     1,234.50          │
│  …                                   │
└──────────────────────────────────────┘
```

The stats row below the chart area remains visible. The empty state replaces only the chart frame (280pt height). The picker remains active so the user can select a different interval immediately without dismissing anything.

SF Symbol: `calendar.badge.exclamationmark`. This communicates "date-related issue" without implying a network failure. Do not use `wifi.slash`, `exclamationmark.circle`, or any error symbol from the network-error vocabulary established in `positions.md` and `orders.md` — those are reserved for infrastructure failures.

Pull-to-refresh in this state re-fetches the same custom window. If the result is still empty, the empty state persists.

---

## 4. Interactions

| Trigger | Response |
|---|---|
| Tap `1h`, `1d`, `1w`, `1M`, or `1y` | Chart fetches standard interval; any prior custom range is retained in memory but deselected |
| Tap `Custom` (no prior custom range) | Custom sheet opens; start defaults to 7 days ago, end defaults to today |
| Tap compressed custom label (range active) | Custom sheet opens pre-filled with the current custom dates |
| Drag sheet down or tap `✕` | Sheet dismisses; picker reverts to previously active non-custom segment |
| Tap Apply (enabled) | Sheet dismisses; chart re-fetches for the custom window; picker label updates |
| Pull-to-refresh (custom active) | Re-fetches the same custom window; does not reset interval |
| Pull-to-refresh (standard interval) | Re-fetches that standard interval |
| Tap `⟳` nav bar button | Same as pull-to-refresh for the current interval or custom window |
| Interval change during loading | Cancels the in-flight fetch via Swift structured concurrency task cancellation; starts new fetch |

**Haptics:**
- Chart data loads successfully after Apply or interval change: `.success` (UINotificationFeedbackGenerator)
- Chart load fails: `.error`
- Apply button tap when disabled: no haptic (do not use `.warning`; the validation message is sufficient)
- Sheet dismiss via `✕`: no haptic

---

## 5. Layout and Dynamic Type

### Picker overflow on iPhone SE (375pt) at large text sizes

Six segments at default text size on an SE (375pt wide) each get approximately 53pt. "Custom" (6 chars) fits; "1M" (2 chars) fits; all labels fit at default and Large Dynamic Type sizes because the segmented control clips label text to fit, not the control itself.

At `dynamicTypeSize >= .accessibility1` (AX1+), the segmented control labels begin to truncate. The approach chosen here is a **horizontally scrollable `ScrollView` wrapping a custom chip-style picker**, replacing the system `SegmentedPicker`. This is the only layout change needed.

**Rationale for scrollable chip picker over alternatives:**

- Two-row layout: requires hardcoded row breaks and is fragile across text sizes.
- Menu/pulldown: hides the 5 standard intervals behind a tap, which is a regression for the most common interactions.
- Scrollable chip row: all segments remain visible or reachable; the user scrolls horizontally within the picker area; it is a standard iOS pattern (Maps time-of-day picker, App Store category chips).

**Custom chip picker spec:**

```
┌──────────────────────────────────────┐
│  ← scroll view, horizontal, clips → │
│  [1h] [1d] [1w] [1M] [1y] [May 1→…]│  ← chips, single row
└──────────────────────────────────────┘
```

Each chip:
- Unselected: `RoundedRectangle(cornerRadius: 8)`, `Color(uiColor: .secondarySystemGroupedBackground)` fill, `.body` text, `.primary` foreground
- Selected: `Color.accentColor.opacity(0.15)` fill, `.accentColor` foreground text, 1pt `.accentColor` stroke
- Height: 36pt minimum (satisfies 44pt tap target with padding); padding: 10pt horizontal, 8pt vertical
- The scroll view does not page; it is free-scrolling. Show a fade-out gradient at the trailing edge when the content exceeds the frame to indicate scrollability.
- `showsIndicators: false` — the horizontal scroll indicator is not appropriate at this size.

**When to switch:** apply the custom chip picker at all Dynamic Type sizes, not only at AX1+. Reason: the system segmented control with 6 segments is already tight at default size on an SE. Keeping one picker implementation across all sizes simplifies the component and avoids a layout switch mid-session if the user changes text size in Settings.

**Scroll to selected on appear:** when the view appears or the selection changes to a chip that may be off-screen (the custom label chip), scroll it into view using `ScrollViewReader` and `.scrollTo(id:anchor:)`.

### Sheet height

`.medium` detent is sufficient for two compact date pickers, a label each, a button, and a validation message. Total content height is approximately 280–320pt, well within medium on all iPhone sizes. If either date picker expands to a wheel picker (which happens when the user taps the date field), the sheet should allow growth to `.large` via `.presentationDetents([.medium, .large])` with `.presentationDragIndicator(.visible)`.

---

## 6. Accessibility

### VoiceOver labels for picker chips

| Chip displayed | `.accessibilityLabel` |
|---|---|
| "1h" | "1 hour interval" |
| "1d" | "1 day interval" |
| "1w" | "1 week interval" |
| "1M" | "1 month interval" |
| "1y" | "1 year interval" |
| "Custom" (inactive) | "Custom date range, not set" |
| "May 1 → Jun 14" (active) | "Custom date range, May 1 to June 14" |

Each chip is an `.accessibilityElement(children: .ignore)` with `.accessibilityAddTraits(.isButton)` and `.accessibilityValue(isSelected ? "selected" : "")`. This lets VoiceOver read "1 day interval, button, selected" for the active chip.

The scrollable chip row as a whole has no container accessibility element — VoiceOver traverses each chip individually, which is correct.

### Custom sheet VoiceOver

- Sheet title "Custom range" is read on present via the sheet's navigation title.
- Start DatePicker: system `DatePicker` provides its own VoiceOver handling; the label "Start" is set via `.accessibilityLabel("Start date")`.
- End DatePicker: `.accessibilityLabel("End date")`.
- Apply button: `.accessibilityLabel("Apply custom date range")`. When disabled, `.accessibilityHint("End date must be after start date and the range must not exceed three years.")`.
- Dismiss button (`✕`): `.accessibilityLabel("Cancel, dismiss without applying")`.
- Validation message: `.accessibilityLiveRegion(.polite)` so VoiceOver announces it as it appears, without the user having to navigate to it.

### Out-of-data empty state VoiceOver

The empty state container: `.accessibilityElement(children: .combine)` with `.accessibilityLabel("No chart data for the selected period. \(coinName) may not have traded during \(startLabel) to \(endLabel). Try a different range.")`.

### Contrast and color blindness

- Selected chip: accent color fill plus a 1pt stroke. The stroke provides a shape-based selected indicator independent of color.
- Apply button uses `.buttonStyle(.borderedProminent)`, which is the system blue. It dims to its disabled appearance automatically; no custom color needed.
- Empty state uses `calendar.badge.exclamationmark` in secondary foreground — this glyph alone communicates the state without color dependency.

### Dynamic Type

- Chip text uses `.body` Dynamic Type style. At AX5 the chips grow; the horizontal scroll view accommodates this naturally.
- Sheet labels ("Start", "End") use `.subheadline`. At AX3+ consider whether the sheet needs more vertical breathing room — `.presentationDetents([.large])` only (dropping `.medium`) at AX3+ to ensure the content is not clipped.
- Validation messages use `.caption`. At AX3+, expand to `.footnote`.

---

## 7. SwiftUI hints

- The custom chip picker is a `ScrollView(.horizontal)` containing an `HStack` of `Button` views, each rendering a chip shape. Extract to `IntervalChipPickerView` accepting `Binding<CandleIntervalSelection>` where `CandleIntervalSelection` is an enum with cases `.preset(CandleInterval)` and `.custom(DateInterval)`.
- `CandleInterval.userFacing` will need updating: remove `.fourHour`, add the six new cases. The x-axis formatter in `CoinDetailView.xAxisFormat(date:)` also references `.fourHour` — flag for `ios-developer` to update the switch.
- The custom sheet is a separate `View` (`CustomRangePickerSheet`) presented via `.sheet(isPresented: $showingCustomSheet)`. It receives `@Binding<Date> startDate` and `@Binding<Date> endDate` plus an `onApply: () -> Void` closure.
- `ScrollViewReader` + `scrollTo` for scroll-to-selected behavior.
- Date picker constraints: `DatePicker("End", selection: $endDate, in: startDate...Date.now, displayedComponents: .date)`. Start picker: `DatePicker("Start", selection: $startDate, in: ...endDate, displayedComponents: .date)` — note the upper bound is `endDate` (not `Date.now`) to prevent start from exceeding end within the picker itself. The Apply button validation still catches edge cases.
- Empty state detection: in the view model, when `state == .loaded([])` after a fetch, expose a `.emptyData` case distinct from `.loaded([Candle])`. The view renders the empty chart placeholder instead of calling `candleChart([])` (which would render a blank chart frame with axes but no marks — confusing).
- Pull-to-refresh with custom active: `viewModel.refresh()` re-uses the stored `currentInterval` which, when custom is active, holds the `DateInterval`. No special handling needed in the view.
- Recall of previous standard interval: store `lastStandardInterval: CandleInterval` in the view model. Updated whenever a non-custom segment is selected. When the custom sheet is dismissed without applying, set `viewModel.interval = .preset(lastStandardInterval)`.

---

## 8. Open questions

1. **`CandleInterval` enum extension.** The existing `CandleInterval` type (in `HyperliquidAPI` or `OpenHLCore`) has a `.fourHour` case currently referenced in `xAxisFormat(date:)`. Removing it is a breaking change if other screens use it. Engineering to confirm whether `.fourHour` appears in any non-UI context (API request body) before the designer specifies removal.

2. **Maximum custom range and API behavior.** The spec caps the range at 3 years. Confirm with engineering whether the `candleSnapshot` endpoint has its own server-side limit on the time window or on the number of candles returned. If the API truncates silently (returns only the most recent N candles for a large window), the app needs to surface that truncation rather than show a misleadingly short chart.

3. **Candle resolution for custom ranges.** For a 2-week window, what candle interval should the app request from the API? The existing `CandleInterval` is used both as the picker selection and as the API `interval` parameter. For custom ranges, the resolution needs to be chosen automatically (e.g. daily candles for ranges > 7 days, hourly for < 7 days). Engineering to propose the mapping; this affects the API request construction and is not a pure UI decision.

4. **Cross-year compressed label length.** "Dec 1 2024 → Jan 15 2025" is 23 characters, which will truncate heavily in the chip. Engineering to confirm how truncation behaves in the custom chip — whether the label should fall back to a shorter format ("Dec '24 → Jan '25") or whether the chip simply truncates with an ellipsis and the full range is readable only from VoiceOver or by re-opening the sheet.

5. **DatePicker `.compact` behavior on AX text sizes.** The compact date picker on iOS 17 does not always respect Dynamic Type at larger sizes. Engineering to test `.datePickerStyle(.compact)` at AX5 on a real device and report whether it remains usable or whether `.datePickerStyle(.graphical)` (calendar view) is needed as a fallback, which would require a `.large` sheet detent.
