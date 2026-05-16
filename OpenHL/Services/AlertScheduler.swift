// SPDX-License-Identifier: MIT

import BackgroundTasks
import Foundation
import HyperliquidAPI
import OSLog
import OpenHLCore
import UserNotifications

// MARK: - AlertScheduler

/// Coordinates background evaluation of alert rules and posting of local
/// notifications.
///
/// **Two trigger paths:**
/// 1. **Foreground hook** — `evaluate(markets:accountValue:now:)` is called
///    by view models after every successful fetch. Runs on `@MainActor`;
///    the notification post runs on a detached `Task` so the caller is not
///    blocked by I/O.
/// 2. **Background refresh** — `registerBackgroundTask()` registers a
///    `BGAppRefreshTask` handler with `BGTaskScheduler`. The handler fetches
///    fresh market data, evaluates, and posts any notifications.
///    `scheduleNextRefresh()` schedules the next wake roughly 1 hour out.
///
/// **Singleton rationale:** `BGTaskScheduler` requires registration before
/// the app finishes launching. The composition root calls
/// `configure(...)`, `registerBackgroundTask()`, and
/// `scheduleNextRefresh()` from `OpenHLApp.init`. This is intentionally
/// not `@Observable` — it is a service, not a view model.
final class AlertScheduler: Sendable {

    static let shared = AlertScheduler()

    /// Must match the `BGTaskSchedulerPermittedIdentifiers` entry in Info.plist.
    /// Identifier shape: `<bundle-id-reversed>.refresh`. We deliberately do
    /// not name this `*.alertRefresh` — the same BG slot may grow to cover
    /// other refresh duties later (e.g. positions snapshot for a future
    /// widget). A single permitted identifier in Info.plist keeps the
    /// system-side surface minimal.
    static let backgroundTaskIdentifier = "xyz.hyperliquid.openhl.refresh"

    private let logger = Logger(subsystem: "xyz.hyperliquid.openhl", category: "AlertScheduler")
    private let state = SchedulerState()

    private init() {}

    // MARK: - Configuration

    /// Call once from `OpenHLApp.init` before `body`. Injects production
    /// dependencies. UI-test stubs call this too, so evaluation still runs
    /// against in-memory data.
    func configure(
        rulesStore: any AlertRulesStore,
        client: any HyperliquidClient,
        addressStore: any AddressStore,
        clock: any Clock
    ) {
        state.configure(
            rulesStore: rulesStore,
            client: client,
            addressStore: addressStore,
            clock: clock
        )
    }

    // MARK: - Background task registration

    /// Register the BG refresh handler with `BGTaskScheduler`. Must be called
    /// before the end of the app delegate's launch callback (or from `@main`
    /// struct `init`).
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundRefresh(task: bgTask)
        }
        logger.debug("BG refresh task registered: \(Self.backgroundTaskIdentifier, privacy: .public)")
    }

    /// Submit a BG refresh request ~1 hour from now. Safe to call repeatedly;
    /// an existing pending request is silently replaced.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("BG refresh scheduled ~1h from now")
        } catch {
            logger.error("BG refresh schedule failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Foreground evaluation

    /// Evaluate all enabled alert rules against the freshly fetched market
    /// data and optional account value.
    ///
    /// Call this on the `@MainActor` after a successful `markets()` fetch.
    /// The evaluation itself is synchronous (pure logic); the notification
    /// post runs in a detached task so the caller is not stalled.
    func evaluate(
        markets: [Market],
        accountValue: Decimal?,
        now: Date
    ) {
        guard let rulesStore = state.rulesStore else { return }
        let rules = rulesStore.all()
        guard !rules.isEmpty else { return }

        let snapshots = markets.map {
            AlertMarketSnapshot(
                coin: $0.coin,
                markPrice: $0.markPrice,
                dayChangeRatio: $0.dayChangeRatio
            )
        }

        let (firings, updates) = AlertEvaluator.evaluate(
            rules: rules,
            markets: snapshots,
            walletAccountValue: accountValue,
            now: now
        )

        guard !firings.isEmpty else { return }

        // Persist the stamped rules synchronously (store is thread-safe).
        for updatedRule in updates {
            rulesStore.upsert(updatedRule)
        }

        // Post notifications off the main actor.
        Task.detached { [weak self, firings] in
            await self?.postNotifications(for: firings)
        }
    }

    // MARK: - Private: BG handler

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleNextRefresh()

        guard
            let rulesStore = state.rulesStore,
            let client = state.client,
            let clock = state.clock
        else {
            task.setTaskCompleted(success: false)
            return
        }

        // BGAppRefreshTask is not `Sendable`. Wrap the completion in a
        // nonisolated-safe closure via a Sendable flag cell so we can
        // hand the success/failure outcome back from a detached task
        // without directly capturing `task` across an isolation boundary.
        let completion = BGTaskCompletion(task: task)
        let addressStore = state.addressStore
        let scheduler = self
        let fetchTask = Task.detached { [completion] in
            do {
                let markets = try await client.markets()

                var accountValue: Decimal? = nil
                if let addressStore,
                    let address = addressStore.load()
                {
                    let snapshot = try await client.clearinghouseState(for: address)
                    accountValue = snapshot.summary.accountValue
                }

                let snapshots = markets.map {
                    AlertMarketSnapshot(
                        coin: $0.coin,
                        markPrice: $0.markPrice,
                        dayChangeRatio: $0.dayChangeRatio
                    )
                }
                let now = clock.now()
                let (firings, updates) = AlertEvaluator.evaluate(
                    rules: rulesStore.all(),
                    markets: snapshots,
                    walletAccountValue: accountValue,
                    now: now
                )
                for updatedRule in updates {
                    rulesStore.upsert(updatedRule)
                }
                await scheduler.postNotifications(for: firings)
                completion.complete(success: true)
                scheduler.logger.debug("BG refresh done: \(firings.count, privacy: .public) firings")
            } catch {
                scheduler.logger.error("BG refresh error: \(error, privacy: .public)")
                completion.complete(success: false)
            }
        }

        task.expirationHandler = {
            fetchTask.cancel()
            completion.complete(success: false)
        }
    }

    // MARK: - Private: notifications

    private func postNotifications(for firings: [AlertFiring]) async {
        for firing in firings {
            let content = UNMutableNotificationContent()
            content.title = notificationTitle(for: firing.rule.subject)
            content.body = firing.displayBody
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: firing.rule.id.uuidString,
                content: content,
                trigger: nil
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                logger.error(
                    "Notification failed for rule \(firing.rule.id, privacy: .public): \(error, privacy: .public)"
                )
            }
        }
    }

    private func notificationTitle(for subject: AlertSubject) -> String {
        switch subject {
        case .coin(let symbol): return "\(symbol) Alert"
        case .walletAccountValue: return "Wallet Alert"
        }
    }
}

// MARK: - BGTaskCompletion

/// Wraps a `BGAppRefreshTask` so that its `setTaskCompleted` can be called
/// from a `Task.detached` closure without directly capturing the non-`Sendable`
/// `BGAppRefreshTask`. `@unchecked Sendable` is safe here because:
/// - `complete(success:)` is called at most once (guarded by `NSLock`).
/// - `BGAppRefreshTask.setTaskCompleted(success:)` is documented thread-safe.
private final class BGTaskCompletion: @unchecked Sendable {
    private let task: BGAppRefreshTask
    private let lock = NSLock()
    private var completed = false

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.withLock {
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: success)
        }
    }
}

// MARK: - SchedulerState

/// Mutable shared dependency bag. Mutation only happens once at startup
/// before any concurrent access.
private final class SchedulerState: @unchecked Sendable {
    private let lock = NSLock()

    private var _rulesStore: (any AlertRulesStore)?
    private var _client: (any HyperliquidClient)?
    private var _addressStore: (any AddressStore)?
    private var _clock: (any Clock)?

    var rulesStore: (any AlertRulesStore)? { lock.withLock { _rulesStore } }
    var client: (any HyperliquidClient)? { lock.withLock { _client } }
    var addressStore: (any AddressStore)? { lock.withLock { _addressStore } }
    var clock: (any Clock)? { lock.withLock { _clock } }

    func configure(
        rulesStore: any AlertRulesStore,
        client: any HyperliquidClient,
        addressStore: any AddressStore,
        clock: any Clock
    ) {
        lock.withLock {
            _rulesStore = rulesStore
            _client = client
            _addressStore = addressStore
            _clock = clock
        }
    }
}
