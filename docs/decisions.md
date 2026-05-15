# Decision log

Append-only. Newest entries at the bottom. Each entry: date, title, context, decision, rationale, alternatives considered.

---

## 2026-05-15 — Phasing rationale

**Context:** Fresh repo with README, LICENSE, CLAUDE.md, and the agent team in place. No Xcode project, no roadmap, no code. Constraints fixed by CLAUDE.md: iOS 17+ SwiftUI, no backend, no analytics, read-only v1, MIT, solo developer with agent assistance, Apple Developer account already owned.

**Decision:** Ship v1.0 in five sequential phases: (0) Foundations — Xcode project, CI, repo polish; (1) Address entry + account snapshot via REST `clearinghouseState`; (2) Open orders and recent fills via REST; (3) Live updates via WebSocket; (4) QA hardening and App Store submission prep.

**Rationale:** Phase 0 buys a green CI and a buildable project before any feature work, so every later phase has a working safety net and we never debug "is it my code or the project setup." Phases 1 and 2 are both REST-only and share a networking layer, so building them before WebSocket lets the live-updates phase reuse a battle-tested decoder and error model rather than inventing both data plane and transport at once. Phase 3 is intentionally last among feature phases because WebSocket lifecycle, reconnect logic, and concurrency are the highest-risk parts of the codebase and benefit from coming after the data shapes are settled. Phase 4 is a dedicated hardening and submission phase rather than a "we'll polish as we go" assumption, because Apple review, accessibility, and the privacy nutrition label all require focused, end-of-cycle attention and they have historically blown up timelines when treated as cross-cutting. Effort sizing (S, M, M, L, M) reflects that Phase 3 is the single largest risk and everything else is bounded by a clear API surface. The phasing also gives natural demo-able milestones for an open-source audience: each phase ends with something a contributor can run and see.

**Alternatives considered:**
- *Build WebSocket first, treat REST as fallback.* Rejected: doubles risk on day one, and a WS-first architecture is hard to retrofit with proper REST reconciliation later.
- *Combine Phases 1 and 2 into one "all read endpoints" phase.* Rejected: too large to land safely solo, and splitting them gives a meaningful intermediate release where positions+PnL alone are already useful.
- *Skip a dedicated hardening phase and submit when feature-complete.* Rejected: privacy nutrition label, accessibility audit, app icon, screenshots, and review-language sweeps consistently slip when bundled into a feature phase.
- *Include WalletConnect/trading inside v1 to launch with a stronger story.* Rejected by CLAUDE.md constraint (read-only v1); also dramatically expands Apple review risk and key-handling responsibility. Trading is captured as post-v1 only.
