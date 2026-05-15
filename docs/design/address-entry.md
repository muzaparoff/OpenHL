# Design spec: address entry screen

**Feature:** `address-entry`
**Phase:** 1
**Owner:** uxui-designer
**Last updated:** 2026-05-15

---

## 1. Goal

Let the user enter a Hyperliquid wallet address (0x + 40 hex characters) so the app can fetch their account data.

---

## 2. User scenario

First launch. The user opens the app for the first time. There is no stored address. They are handed the app by a friend or found it on GitHub. They have their wallet address copied from the Hyperliquid web app or another wallet app. They want to see their positions as quickly as possible — the address entry is a gate, not a feature.

Secondary scenario: the user wants to change the address they previously saved.

---

## 3. Screen states and wireframes

### 3a. Empty state — first launch, no address stored

This is the root view when no address is persisted. The user has not yet interacted.

```
┌──────────────────────────────────────┐
│                                      │
│                                      │
│                                      │
│           open-hl                    │  ← app name, title3, secondary label color
│                                      │
│  ┌────────────────────────────────┐  │
│  │  0x…                           │  │  ← TextField, monospace prompt, placeholder text
│  └────────────────────────────────┘  │
│                                      │
│  [ Paste from clipboard ]            │  ← tappable, visible only when clipboard
│                                      │    has a plausible 0x string; otherwise hidden
│  ─────────────────────────────────   │
│                                      │
│  [ View account →              ]     │  ← primary button, disabled (grayed)
│                                      │
│                                      │
│  Hyperliquid public address          │  ← footnote, tertiary label color
│  No data leaves your device.         │    two lines, centered
│                                      │
└──────────────────────────────────────┘
```

Notes:
- No navigation bar on first launch. This is the root of the navigation stack. No "back" affordance.
- The app name label is not a logo. SF Pro Display weight semibold, Dynamic Type `.title3`. Not large/display — this should not feel like a splash screen.
- The input field uses a monospace font segment for the address text to aid legibility of hex characters (`Font.system(.body, design: .monospaced)`). Placeholder text is `0x…` in secondary color.
- "Paste from clipboard" button: system `.tinted` button style, uses SF Symbol `doc.on.clipboard`. Appears only when `UIPasteboard.general.hasStrings` returns true and the clipboard string starts with `0x` (case-insensitive check only — full validation runs after paste). If clipboard is empty or has no 0x string, this button is hidden (not disabled — hidden, to avoid visual noise on first launch with a clean clipboard).
- "View account" button: `.borderedProminent` style, full width, disabled until the field contains a string that passes inline format validation.
- The footer text is a trust signal. It is small and unobtrusive. "No data leaves your device." is factually accurate (all calls go device → api.hyperliquid.xyz directly).

---

### 3b. Typing / partial-input state

User is typing. Address is not yet valid.

```
┌──────────────────────────────────────┐
│                                      │
│                                      │
│           open-hl                    │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  0x3f5CE5FBFe3E9af3971dD833D   │  │  ← partial hex, cursor blinking
│  └────────────────────────────────┘  │
│                                      │
│                                      │  ← paste button hidden (user typed, not pasted)
│                                      │
│  [ View account →              ]     │  ← still disabled
│                                      │
│  Hyperliquid public address          │
│  No data leaves your device.         │
│                                      │
└──────────────────────────────────────┘
```

Notes:
- No inline error shown while the user is actively typing. Errors appear only after the field loses focus or the user taps the submit button (described in 3c and 3d). Do not interrupt mid-type.
- Character count aid: the field shows nothing — no counter, no progress bar. The validation rule (42 chars: "0x" + 40 hex) is simple enough that users either paste a full address or see the error after submit.
- The keyboard type is `.asciiCapable`. Not `.URL` (that adds a "/" key and a "." shortcut row that is unhelpful). `.asciiCapable` gives a standard QWERTY with all alphanumeric characters accessible.
- `autocorrectionDisabled(true)`, `autocapitalization(.never)`, `textContentType(.none)`.

---

### 3c. Invalid-address state

User tapped "View account" or dismissed the keyboard after typing an address that fails format validation.

```
┌──────────────────────────────────────┐
│                                      │
│                                      │
│           open-hl                    │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  0x3f5CE5FBFe3E9af3971dD83     │  ← field border tinted system red
│  └────────────────────────────────┘  │
│  ⚠ Address must be 0x followed by    │  ← SF Symbol `exclamationmark.triangle`
│    40 hex characters (0–9, a–f).     │    system red, caption1, left-aligned
│                                      │
│  [ View account →              ]     │  ← still disabled (input still invalid)
│                                      │
│  Hyperliquid public address          │
│  No data leaves your device.         │
│                                      │
└──────────────────────────────────────┘
```

Notes:
- The error message is factual and precise. It tells the user exactly what the format requires. It does not say "invalid address" alone — that is unhelpful when the user does not know the format.
- The field border color change (red tint via `.overlay(RoundedRectangle…stroke(color:))`) provides a visual cue in addition to the text. Do not rely on color alone: the `⚠` icon is the shape-based indicator.
- The error text is present in the accessibility tree with role `.staticText` and a VoiceOver label (see Section 6).
- The error disappears as soon as the field content changes again (i.e. on the next `.onChange`). It is not sticky.
- The submit button remains disabled while the address is invalid.

---

### 3d. Valid-address state (ready to submit)

User has entered or pasted a fully valid address.

```
┌──────────────────────────────────────┐
│                                      │
│                                      │
│           open-hl                    │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  0x3f5CE5FBFe3E9af3971dD833D26│  │  ← full 42-char address, no error
│  └────────────────────────────────┘  │
│                                      │
│                                      │
│                                      │
│  [ View account →              ]     │  ← enabled, .borderedProminent
│                                      │
│  Hyperliquid public address          │
│  No data leaves your device.         │
│                                      │
└──────────────────────────────────────┘
```

Notes:
- No green "checkmark valid" indicator. That would add visual noise for a momentary state before the user taps submit. The button enabling itself is sufficient feedback.
- The submit button text stays "View account →". The right-arrow (`→`) uses `Image(systemName: "arrow.right")` as a `Label` trailing icon, not a unicode character, to inherit Dynamic Type scaling.

---

### 3e. Loading state (after submit, fetching account data)

User tapped "View account". App is calling the API.

```
┌──────────────────────────────────────┐
│                                      │
│                                      │
│           open-hl                    │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  0x3f5CE5FBFe3E9af3971dD833D26│  │  ← field disabled during fetch
│  └────────────────────────────────┘  │
│                                      │
│                                      │
│                                      │
│  [ ◌ Fetching…                  ]    │  ← ProgressView (circular, inline style)
│                                      │    button replaced by progress row
│  Hyperliquid public address          │
│  No data leaves your device.         │
│                                      │
└──────────────────────────────────────┘
```

Notes:
- The submit button is replaced (not just disabled) by a row containing an inline `ProgressView` and the label "Fetching…". This avoids a disabled-but-still-present button sitting next to a spinner, which creates visual ambiguity.
- The text field is disabled during the fetch (`disabled(viewModel.isLoading)`). Tapping it does nothing; it does not dismiss the spinner.
- There is no cancel affordance in v1. Timeouts are handled by the networking layer (see architecture.md Section 6). If the user needs to cancel, they can background the app; the `.task` modifier will cancel on view disappear.
- Duration: if the fetch resolves in under ~300ms, the loading state may flash. Accept this — do not add an artificial delay. The spinner is visible enough even briefly.

---

### 3f. Network-error state (API unreachable or error returned)

Fetch failed. User is still on the address entry screen.

```
┌──────────────────────────────────────┐
│                                      │
│                                      │
│           open-hl                    │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  0x3f5CE5FBFe3E9af3971dD833D26│  │
│  └────────────────────────────────┘  │
│                                      │
│  ⚠ Could not reach Hyperliquid.      │  ← error banner, system orange, caption1
│    Check your connection and         │    (orange rather than red: this is a
│    try again.                        │    connectivity issue, not user error)
│                                      │
│  [ Try again →                 ]     │  ← re-enabled, same primary button
│                                      │
│  Hyperliquid public address          │
│  No data leaves your device.         │
│                                      │
└──────────────────────────────────────┘
```

Notes:
- Three distinct error messages mapped from `HyperliquidError`:
  - `.offline` / `URLError.notConnectedToInternet`: "No internet connection. Connect and try again."
  - `.timeout`: "Request timed out. Hyperliquid may be slow — try again."
  - `.httpStatus(5xx)`: "Hyperliquid returned an error (HTTP [code]). Try again in a moment."
  - `.decoding` / `.unexpectedResponse`: "Could not read the account data. The API response was unexpected." (This is a developer error, but the user sees it rarely and it is honest.)
- Orange is used for connectivity/server errors (external, user can resolve) to distinguish from red (format validation errors, which are user-input errors). This distinction aids colorblind users only when combined with the `⚠` icon and the different message text — do not depend on color alone.
- The address field re-enables. The user can edit the address if they believe the address itself caused the problem (unlikely but possible with a server-side address lookup rejection).

---

### 3g. Returning user — address already saved

App launches with a previously saved address in `UserDefaults`. The address entry screen is skipped entirely. Navigation goes directly to the positions screen.

The address entry screen becomes accessible via a "Change address" affordance on the positions screen (see `docs/design/positions.md` section on the settings/change affordance). It is not reachable from the positions screen navigation bar via a "back" button — the entry screen is conditionally shown as root, not pushed.

When the user navigates to address entry from positions (to change their address), the screen appears modally (`.sheet` or `.fullScreenCover`). It is the same view with one difference: a cancel/dismiss button appears in the top-left to return to the positions screen without changing the address.

```
┌──────────────────────────────────────┐
│  Cancel          Address             │  ← modal nav bar
├──────────────────────────────────────┤
│                                      │
│  ┌────────────────────────────────┐  │
│  │  0x3f5CE5FBFe3E9af3971dD833D26│  │  ← pre-filled with current address
│  └────────────────────────────────┘  │
│                                      │
│  [ Paste from clipboard ]            │
│                                      │
│  [ View account →              ]     │  ← enabled (current address is valid)
│                                      │
│  Hyperliquid public address          │
│  No data leaves your device.         │
│                                      │
└──────────────────────────────────────┘
```

Notes:
- The field pre-fills with the current saved address. The user can see what is already stored.
- Tapping "View account" with the same address re-fetches and dismisses the modal. This is intentional — it doubles as a "refresh" from the change-address screen.
- "Cancel" dismisses the modal without changing the stored address.

---

## 4. Interactions

| Trigger | Response |
|---|---|
| Tap text field | Keyboard appears, cursor placed at tap position |
| Paste via clipboard button | Field fills with clipboard content; validation runs immediately; button hides |
| Paste via system gesture (long-press > Paste) | Same as above — `.onChange` on the binding fires |
| Tap "View account" with invalid input | Error message appears below the field; haptic: `.error` (`UINotificationFeedbackGenerator`) |
| Tap "View account" with valid input | Loading state shown; haptic: none (loading start should not have haptic feedback — reserve it for outcomes) |
| Fetch succeeds | Navigation push to positions screen; haptic: `.success` (`UINotificationFeedbackGenerator`) |
| Fetch fails | Error message shown below the field; haptic: `.error` |
| Tap "Try again" | Repeat fetch with same address |
| Paste in "change address" modal, tap "View account" | Fetch; on success dismiss modal and push/reload positions |
| Tap "Cancel" in modal | Modal dismisses; no change to stored address; no haptic |

Pull-to-refresh: not applicable on this screen.

Keyboard dismissal: tapping outside the text field dismisses the keyboard via `.scrollDismissesKeyboard(.immediately)` on the containing scroll view, or a background tap gesture. The submit button should be visible above the keyboard — use `.ignoresSafeArea(.keyboard, edges: .bottom)` with a sticky-footer layout for the button so it floats above the keyboard.

---

## 5. Layout and spacing

The screen uses a `VStack` centered vertically in a `ScrollView` (to handle Dynamic Type large sizes). Approximate spacing rhythm:

```
top spacer (flexible)
  app name label          — title3
  32pt gap
  text field              — .roundedBorder style, body monospace, min height 44pt
  8pt gap
  error / paste button    — conditionally shown, caption1
  24pt gap
  submit / loading row    — min 44pt height, full width
  24pt gap
  footer text             — footnote, secondary
bottom spacer (flexible)
```

On iPhone SE (375pt width): all elements fit. Text field will be narrower but still usable; 42-character hex addresses wrap to two lines in body size — consider `lineLimit(1)` with horizontal scroll or a smaller monospace font size for the field specifically. Flag as open question for implementation.

On Pro Max (430pt width): extra horizontal whitespace adds visual breathing room. Add horizontal padding of 20–24pt on each side rather than stretching the field edge to edge.

---

## 6. Accessibility

### VoiceOver labels

| Element | VoiceOver label | Hint |
|---|---|---|
| App name label | "open-hl" | — |
| Text field (empty) | "Hyperliquid wallet address" | "Enter your 0x wallet address" |
| Text field (filled) | "Hyperliquid wallet address, [current value]" | — |
| Paste from clipboard button | "Paste address from clipboard" | — |
| Submit button (disabled) | "View account, button, dimmed" | (system provides dimmed state) |
| Submit button (enabled) | "View account" | — |
| Inline validation error | "Error: [full error text]" | — (announced automatically when it appears via `.accessibilityAnnouncement` or by putting focus on it after it appears) |
| Loading indicator | "Fetching account data" | — |
| Network error message | "Error: [full error text]" | — |
| Try again button | "Try again" | — |
| Footer text | "Hyperliquid public address. No data leaves your device." | — |

VoiceOver reading order (top to bottom): app name, text field, paste button (if visible), error (if present), submit/loading, footer.

When the error message appears after a failed validation or fetch, call `AccessibilityFocusState` or `UIAccessibility.post(notification: .announcement, argument: errorText)` to announce the error to VoiceOver users who will not see the visual change.

### Dynamic Type

All text uses `.font(.xxx)` from the Dynamic Type scale. No hardcoded font sizes. Tested sizes:

- Default (body = 17pt): standard layout as wireframed above.
- Large (body ≈ 20pt): layout holds.
- Accessibility XL / AX3 (body ≈ 28pt): the text field and submit button grow. Verify that the submit button label does not clip; use `minimumScaleFactor(0.8)` as a floor but prefer full size.
- AX5 (body ≈ 36pt): the app name, field, and button stack taller. The footer text may need `.fixedSize(horizontal: false, vertical: true)` to wrap correctly. The screen should remain scrollable so nothing is cropped.
- Test with "Larger Text" enabled in Settings > Accessibility; also test with Bold Text enabled.

### Contrast

- Primary text on system background: system label colors meet WCAG AA (4.5:1) in both light and dark.
- Error text (system red): verify in light mode against white background. Apple's `.systemRed` at `.caption1` size is borderline at 4.5:1 on white. If it fails, use `.label` color for the error text and limit red to the border/icon, where size requirements are lower.
- "No data leaves your device." footer: this is secondary/tertiary color, below 4.5:1. Acceptable because it is supplementary information, not interactive or critical. Flag for Phase 4 accessibility audit.

---

## 7. SwiftUI implementation hints

- Root conditional: `OpenHLApp.swift` checks `addressStore.savedAddress != nil`. If nil, present `AddressEntryView` as root. If not nil, present `PositionsView` with the stored address.
- `AddressEntryView` is a `View` backed by `AddressEntryViewModel` (`@MainActor @Observable final class`).
- The view model exposes: `addressText: String`, `validationError: String?`, `isLoading: Bool`, `fetchError: String?`, and `func submitAddress() async`.
- Validation logic lives in `OpenHLCore` as `Address.validate(_ raw: String) -> Result<Address, AddressValidationError>`. The view model calls this; it does not do regex in the view.
- `.task(id: triggerID)` is the right way to kick off the fetch when the user taps submit — avoid `Task { }` directly in button actions. Or use a `Button` with `.buttonStyle(.plain)` and a coordinator method on the view model that the `.task` observes.
- The paste button: use `.onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification))` or check clipboard in `.onAppear` and `.onChange(of: scenePhase)` to keep the button visibility current.
- Modal presentation for "change address": the navigation to this screen from positions is a `.sheet`. Pass the current address as a binding or initializer argument to pre-fill the field. On successful fetch in the modal, dismiss via `@Environment(\.dismiss)` and update the parent's address state via a callback or shared `AddressStore`.
- Sticky footer pattern (button above keyboard):

  ```
  ZStack(alignment: .bottom) {
      ScrollView {
          VStack { /* field, errors */ }
      }
      .scrollDismissesKeyboard(.immediately)
      submitButton
          .padding()
          .background(.regularMaterial)
  }
  .ignoresSafeArea(.keyboard, edges: .bottom)
  ```

---

## 8. Open questions

1. **Address validation: case sensitivity.** The Ethereum address format is case-insensitive for hex digits. Does the API require lowercase? Uppercase? EIP-55 checksum mixed case? Confirm whether the app should normalize the address (e.g. lowercase) before sending it to the API and before storing it. This affects the `Address` value type in `OpenHLCore`.

2. **iPhone SE text field width.** A 42-character monospaced address at body size is approximately 350pt wide. On an SE (375pt device width with 20pt padding each side = 335pt usable), the address will overflow. Options: smaller monospace point size for this field, allow horizontal scrolling within the field, or allow wrapping. Needs a decision so the developer knows what to implement.

3. **Clipboard privacy prompt.** iOS 16+ shows a banner when an app reads the clipboard (`UIPasteboard.general.string`). This is expected behavior but may surprise users who see it while the app reads the clipboard in `.onAppear`. Consider using `UIPasteboard.general.detectPatterns(for:completionHandler:)` (which does not trigger the banner) to check whether the clipboard looks like a wallet address before actually reading it. Confirm this is the right approach with the iOS developer.

4. **"Change address" navigation pattern.** The spec proposes a `.sheet` modal from the positions screen. An alternative is a navigation push with a custom "Edit address" button. Modal is simpler for v1 but adds a visual context switch. PM to confirm preferred pattern.

5. **Error mapping completeness.** The spec maps four `HyperliquidError` cases to user messages. Confirm with swift-expert that these four cases cover all thrown error paths in the networking layer, or whether additional cases (e.g. a non-200 non-5xx status like 429 rate-limit) need their own message.

6. **Loading timeout UX.** If the API takes more than, say, 10 seconds, should there be any additional feedback beyond the spinner (e.g. "This is taking longer than expected...")? Or is the networking layer's timeout sufficient? The architecture doc says `waitsForConnectivity = true` — this means the request queues instead of failing fast on a slow connection. Confirm the timeout value so UX matches the expected wait time.
