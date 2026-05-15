# open-hl roadmap

Source of truth for what we are building, in what order, and why. Phases are sequential by default; effort is S/M/L (not hours). Solo developer assisted by the agent team in `.claude/agents/`.

**Target for v1.0:** a SwiftUI iOS 17+ app that lets a user paste a Hyperliquid wallet address and view positions, PnL, open orders, and recent fills — read-only, no backend, no tracking — submitted to the App Store.

---

# Phase 0 — Foundations: scaffold the repo, project, and CI so feature work can start

**Status:** planned
**Effort:** S
**Depends on:** —

## User outcome
No end-user-visible outcome. After this phase the project builds on a clean machine, runs in the simulator, and every push runs tests in CI.

## Acceptance criteria
- [ ] Xcode project (`OpenHL.xcodeproj` or SwiftPM-driven workspace) exists, opens cleanly, builds for iOS 17+ simulator and device.
- [ ] App target launches to a placeholder SwiftUI screen ("open-hl") on iPhone simulator.
- [ ] Swift 5.10+/Swift 6 language mode set; warnings-as-errors enabled in Release.
- [ ] Bundle identifier reserved, signing configured with the user's Apple Developer team.
- [ ] `.gitignore` covers Xcode/SPM/macOS noise; no DerivedData or user state checked in.
- [ ] GitHub Actions workflow builds the app and runs an empty unit-test target on every PR and on `main`.
- [ ] `README.md` "Building" section filled in with the actual checkout/build steps.
- [ ] MIT `LICENSE` header convention agreed and documented in `docs/architecture.md` stub.
- [ ] SwiftLint or built-in Swift formatter wired into the build (one of the two, not both).

## Out of scope
- Any Hyperliquid API calls.
- Any real UI beyond a placeholder screen.
- App icon, launch screen polish, marketing copy.
- TestFlight upload (deferred to the submission-prep phase).
- WebSocket client, persistence, settings.

## Specialist assignments
- **swift-expert:** propose project layout (single app target + feature modules vs. flat), Swift 6 concurrency posture, dependency policy (no third-party SDKs unless justified in `docs/decisions.md`); write `docs/architecture.md` v0.
- **ios-developer:** create the Xcode project per swift-expert's spec, add the placeholder SwiftUI root view, wire signing.
- **qa-automation:** add the unit-test target, write the GitHub Actions workflow, fail the build on test or lint failures.
- **uxui-designer:** not needed this phase (defer to Phase 1).
- **qa-manual:** not needed this phase.

---

# Phase 1 — Address entry and account snapshot: paste an address, see positions and PnL

**Status:** planned
**Effort:** M
**Depends on:** Phase 0

## User outcome
A user can paste or type a Hyperliquid wallet address, the app validates the address format, calls `clearinghouseState`, and displays current positions with size, entry price, mark price, and unrealized PnL. The address is remembered between launches.

## Acceptance criteria
- [ ] Address entry screen accepts a 0x-prefixed 40-hex address, validates format inline, rejects malformed input with a clear error.
- [ ] On valid address, app calls `POST https://api.hyperliquid.xyz/info` with `{"type":"clearinghouseState","user":"0x..."}` and parses the response.
- [ ] Positions list renders: asset, side (long/short), size, entry price, mark price, unrealized PnL (absolute and percent), liquidation price if present.
- [ ] Account summary header shows account value, total unrealized PnL, margin used.
- [ ] Pull-to-refresh re-fetches the snapshot.
- [ ] Address is persisted across app launches (UserDefaults or Keychain — decision logged).
- [ ] Network errors (offline, 5xx, timeout, parse failure) render an actionable error state, not a crash.
- [ ] All decimal values use `Decimal` end-to-end; no `Double` for money.
- [ ] Unit tests cover address validation, response decoding (with golden-file fixtures), and PnL formatting.
- [ ] VoiceOver labels are present on every interactive element and every numeric value.

## Out of scope
- Open orders, fills, trade history (next phase).
- Live updates over WebSocket (later phase).
- Multiple addresses / watchlist (post-v1).
- Charts, sparklines, historical PnL.
- Sub-account support if not in the v1 API surface.

## Specialist assignments
- **uxui-designer:** wireframes for empty/entry/loaded/error states; `docs/design/address-entry.md` and `docs/design/positions.md`; accessibility annotations; iPhone SE → Pro Max layout notes.
- **swift-expert:** networking layer design (URLSession + async/await, typed errors, retry/backoff policy), `Decimal` boundary rules, persistence choice for the address, fixture format for tests.
- **ios-developer:** implement address entry, networking client per swift-expert's spec, positions and summary views.
- **qa-automation:** fixture-driven unit tests for the decoder; UI test for the entry → loaded happy path; address-validation property tests.
- **qa-manual:** not yet — defer exploratory testing to Phase 4.

---

# Phase 2 — Open orders and recent fills: see what is working and what just happened

**Status:** planned
**Effort:** M
**Depends on:** Phase 1

## User outcome
Users can switch tabs/sections to see their current open orders (size, price, side, asset, time placed) and recent fills (asset, side, size, price, fee, timestamp). All values formatted consistently with Phase 1.

## Acceptance criteria
- [ ] Open orders screen calls `{"type":"openOrders","user":"0x..."}` and renders a list grouped or sorted sensibly (decision logged).
- [ ] Fills screen calls `{"type":"userFills","user":"0x..."}` and renders a paginated or scroll-capped list.
- [ ] Empty states ("no open orders", "no recent fills") are designed and shipped, not stubs.
- [ ] Tab/section navigation between Positions, Orders, Fills is keyboard- and VoiceOver-navigable.
- [ ] Timestamps render in the device's locale and time zone.
- [ ] Network client reuses Phase 1 infrastructure; no duplicated request code.
- [ ] Decoders covered by fixture-based unit tests.
- [ ] UI test for the tab navigation and one populated list per tab.

## Out of scope
- Order cancellation or any write action.
- Filtering, search, sorting controls beyond the chosen default.
- Export / share.
- Push notifications on fills.

## Specialist assignments
- **uxui-designer:** orders and fills list specs; empty/error states; tab/section IA decision in `docs/design/navigation.md`.
- **swift-expert:** extend networking with the two new request types, decide on list pagination strategy.
- **ios-developer:** implement the two screens and the navigation shell.
- **qa-automation:** decoder fixtures for orders and fills (including edge cases: zero fills, very long lists), UI tests for navigation.

---

# Phase 3 — Live updates: account view stays current without manual refresh

**Status:** planned
**Effort:** L
**Depends on:** Phase 2

## User outcome
While the app is foregrounded on the account view, positions, PnL, orders, and fills update live without the user touching the screen. When the app backgrounds, the connection is closed cleanly; on return, it reconnects and reconciles.

## Acceptance criteria
- [ ] WebSocket client connects to `wss://api.hyperliquid.xyz/ws`, subscribes to the relevant channels for the current address.
- [ ] PnL and mark prices update in-place at a rate that does not jank scrolling.
- [ ] Connection lifecycle is tied to scene phase: connect on `.active`, disconnect on `.background`, reconnect with exponential backoff on transport failure.
- [ ] Stale-data indicator appears within a defined threshold (e.g. 10s) of last update when the socket is down.
- [ ] No battery / CPU regression vs. Phase 2 idle baseline (measured once on device).
- [ ] Snapshot REST fetch still runs on cold start and on pull-to-refresh; WebSocket is an overlay, not a replacement.
- [ ] Concurrency model documented in `docs/architecture.md` (actor boundaries, main-thread guarantees for UI state).
- [ ] Unit tests for the reconnect/backoff state machine.
- [ ] UI test verifying that a simulated price update reaches the view.

## Out of scope
- Background updates / push notifications.
- Custom alerting on price or PnL thresholds.
- Multi-address concurrent subscriptions.

## Specialist assignments
- **swift-expert:** WebSocket client design (URLSessionWebSocketTask vs. Network.framework), reconnection state machine, actor model for the live store, conflict-resolution rules between REST snapshot and WS deltas.
- **ios-developer:** implement the client and wire it into the existing screens; ensure no view re-renders on unchanged values.
- **qa-automation:** reconnect/backoff unit tests with a fake transport; UI test with an injected mock socket.
- **uxui-designer:** stale-data and reconnecting UI affordances.

---

# Phase 4 — QA hardening and App Store submission prep: ship v1.0

**Status:** planned
**Effort:** M
**Depends on:** Phase 3

## User outcome
A submitted, in-review (or approved) build on App Store Connect. Externally: the app feels finished — icon, launch, empty states, error states, accessibility, and copy are all production quality.

## Acceptance criteria
- [ ] App icon and launch screen designed and added; all required icon sizes present.
- [ ] Accessibility audit pass: Dynamic Type up to AX5, VoiceOver, Reduce Motion, Increase Contrast, RTL spot-check.
- [ ] Device matrix smoke test on at least: iPhone SE (3rd gen), an iPhone with notch, an iPhone with Dynamic Island; iOS 17.x and current iOS.
- [ ] Performance: cold-launch under a target (set by swift-expert), scrolling at 60/120fps on a populated fills list.
- [ ] Privacy nutrition label filled in honestly: "Data Not Collected." App Privacy details in App Store Connect match.
- [ ] App review screening: no language about gains/returns; crypto wording factual; screenshots show realistic, non-promotional data.
- [ ] App Store metadata drafted: name, subtitle, description, keywords, support URL, marketing URL (repo), category.
- [ ] Screenshots produced for required device sizes.
- [ ] TestFlight build uploaded; at least one external tester round completed.
- [ ] Crash-free over a defined manual session length on real devices (Console / Xcode Organizer, no third-party reporter).
- [ ] `docs/qa/manual/release-checklist.md` complete and checked off.
- [ ] Final submission to App Store Review.

## Out of scope
- Trading / signing (post-v1 phase, not on this roadmap yet).
- Multi-address watchlist.
- Charts, historical analytics.
- Localization beyond English (English-only v1; copy structured to allow future localization).

## Specialist assignments
- **uxui-designer:** app icon, launch screen, App Store screenshots, final empty/error state polish.
- **qa-manual:** device-matrix exploratory testing, accessibility audit, release checklist in `docs/qa/manual/release-checklist.md`, bug triage notes.
- **qa-automation:** expand UI test coverage to cover regression-prone paths surfaced by qa-manual; ensure CI is green on the release branch.
- **ios-developer:** fix bugs surfaced by QA, implement icon/launch assets, ship final copy.
- **swift-expert:** code review of the release branch, performance review, sign-off on architecture doc as it stands at v1.0.
- **product-manager:** App Store Connect metadata, privacy nutrition label, submission, decision log entries for any scope cuts made under review pressure.

---

## Post-v1 (not scheduled)

Captured here only so we remember we deliberately deferred them:

- Trading via WalletConnect + EIP-712 signing (separate, larger initiative).
- Multi-address watchlist.
- Push notifications on fills / liquidation risk.
- Charts and historical PnL.
- iPad / Mac Catalyst layouts.
- Localization.

These are not commitments. They get scoped only after v1.0 ships and we have real usage feedback.
