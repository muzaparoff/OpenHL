// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import HyperliquidAPI

/// Unit tests for `CandleInterval.bestFit(for:)`.
///
/// The ladder (from architecture §23.4 and the `Candle.swift` doc-comment):
///
///   ≤ 2 days   → .oneHour
///   ≤ 30 days  → .fourHour
///   ≤ 180 days → .oneDay
///   ≤ 730 days → .oneWeek
///   > 730 days → .oneDay   (caller must clamp; Phase 3c caps at 3y)
///
/// Boundaries are inclusive at the upper end (≤ not <).
/// `bestFit` is a pure function — no state, no clock — so we construct
/// `DateInterval(start:duration:)` directly.
@Suite("CandleInterval.bestFit — boundary coverage")
struct BestFitTests {

    // MARK: - Helpers

    private static let day: TimeInterval = 60 * 60 * 24

    private func interval(days: Double, extraSeconds: TimeInterval = 0) -> DateInterval {
        let anchor = Date(timeIntervalSince1970: 0)
        let duration = days * Self.day + extraSeconds
        return DateInterval(start: anchor, duration: duration)
    }

    // MARK: - ≤ 2 days → .oneHour

    @Test("1 day span → .oneHour")
    func oneDay() {
        #expect(CandleInterval.bestFit(for: interval(days: 1)) == .oneHour)
    }

    @Test("exactly 2 days span → .oneHour (inclusive upper boundary)")
    func exactlyTwoDays() {
        // span = 2 * 86400 = 172800 s; the switch is `.<(2*day + 1)`, i.e. < 172801
        // so 172800 falls inside the first case → .oneHour.
        #expect(CandleInterval.bestFit(for: interval(days: 2)) == .oneHour)
    }

    @Test("2 days + 1s span → .fourHour (first step past the ≤2d boundary)")
    func twoDaysPlusOneSecond() {
        #expect(CandleInterval.bestFit(for: interval(days: 2, extraSeconds: 1)) == .fourHour)
    }

    // MARK: - ≤ 30 days → .fourHour

    @Test("30 days span → .fourHour (inclusive upper boundary)")
    func exactlyThirtyDays() {
        #expect(CandleInterval.bestFit(for: interval(days: 30)) == .fourHour)
    }

    @Test("30 days + 1s span → .oneDay (first step past the ≤30d boundary)")
    func thirtyDaysPlusOneSecond() {
        #expect(CandleInterval.bestFit(for: interval(days: 30, extraSeconds: 1)) == .oneDay)
    }

    // MARK: - ≤ 180 days → .oneDay

    @Test("180 days span → .oneDay (inclusive upper boundary)")
    func exactlyOneEightyDays() {
        #expect(CandleInterval.bestFit(for: interval(days: 180)) == .oneDay)
    }

    @Test("180 days + 1s span → .oneWeek (first step past the ≤180d boundary)")
    func oneEightyDaysPlusOneSecond() {
        #expect(CandleInterval.bestFit(for: interval(days: 180, extraSeconds: 1)) == .oneWeek)
    }

    // MARK: - ≤ 730 days → .oneWeek

    @Test("730 days (2 years) span → .oneWeek (inclusive upper boundary)")
    func exactlySevenThirtyDays() {
        #expect(CandleInterval.bestFit(for: interval(days: 730)) == .oneWeek)
    }

    @Test("730 days + 1s span → .oneDay (> 2 years default branch)")
    func sevenThirtyDaysPlusOneSecond() {
        #expect(CandleInterval.bestFit(for: interval(days: 730, extraSeconds: 1)) == .oneDay)
    }

    // MARK: - > 730 days → .oneDay (the "over 2 years" default branch)

    @Test("5 years span → .oneDay (deep in the default branch)")
    func fiveYears() {
        #expect(CandleInterval.bestFit(for: interval(days: 5 * 365)) == .oneDay)
    }
}
