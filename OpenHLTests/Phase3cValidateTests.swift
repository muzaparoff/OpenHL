// SPDX-License-Identifier: MIT

import Foundation
import HyperliquidAPI
import OpenHLCore
import Testing

@testable import OpenHL

// Tests for `CoinDetailViewModel.validate(start:end:now:)`.
//
// `CoinDetailViewModel` lives in the app target (OpenHL), which is the test
// host for OpenHLTests. Its types are therefore directly accessible here
// without an explicit import.

@Suite("CoinDetailViewModel.validate — custom range error cases")
@MainActor
struct CoinDetailValidateTests {

    // A fixed "now" used throughout — a known epoch so test values are readable.
    // 2026-05-16 00:00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_747_353_600)

    private var day: TimeInterval { 60 * 60 * 24 }
    private var threeYearsExact: TimeInterval {
        CoinDetailViewModel.maxCustomSpan  // 60 * 60 * 24 * 365 * 3
    }

    // MARK: - Error cases

    @Test("endBeforeStart: end = start - 1h → throws .endBeforeStart")
    func endBeforeStart() {
        let start = now.addingTimeInterval(-7 * day)
        let end = start.addingTimeInterval(-3600)  // one hour before start
        #expect {
            try CoinDetailViewModel.validate(start: start, end: end, now: now)
        } throws: { error in
            (error as? CoinDetailViewModel.CustomRangeError) == .endBeforeStart
        }
    }

    @Test("endInFuture: end = now + 1s → throws .endInFuture")
    func endInFuture() {
        let start = now.addingTimeInterval(-7 * day)
        let end = now.addingTimeInterval(1)
        #expect {
            try CoinDetailViewModel.validate(start: start, end: end, now: now)
        } throws: { error in
            (error as? CoinDetailViewModel.CustomRangeError) == .endInFuture
        }
    }

    @Test("spanTooLarge: 4-year span → throws .spanTooLarge")
    func spanTooLarge() {
        let fourYears: TimeInterval = 60 * 60 * 24 * 365 * 4
        let start = now.addingTimeInterval(-fourYears)
        #expect {
            try CoinDetailViewModel.validate(start: start, end: now, now: now)
        } throws: { error in
            (error as? CoinDetailViewModel.CustomRangeError) == .spanTooLarge
        }
    }

    // MARK: - Happy paths

    @Test("Happy path: end = now, start = now - 7d → no throw")
    func happyPath() {
        let start = now.addingTimeInterval(-7 * day)
        #expect(throws: Never.self) {
            try CoinDetailViewModel.validate(start: start, end: now, now: now)
        }
    }

    @Test("Happy path: end = now, start = now - 90d → no throw")
    func happyPathNinetyDays() {
        let start = now.addingTimeInterval(-90 * day)
        #expect(throws: Never.self) {
            try CoinDetailViewModel.validate(start: start, end: now, now: now)
        }
    }

    @Test("Zero-duration range (start == end) is valid")
    func zeroDuration() {
        let start = now.addingTimeInterval(-7 * day)
        #expect(throws: Never.self) {
            try CoinDetailViewModel.validate(start: start, end: start, now: now)
        }
    }

    // MARK: - Boundary: exactly 3 years

    @Test("Boundary: exactly 3-year span is accepted (≤ is inclusive)")
    func exactlyThreeYearsIsAccepted() {
        let start = now.addingTimeInterval(-threeYearsExact)
        #expect(throws: Never.self) {
            try CoinDetailViewModel.validate(start: start, end: now, now: now)
        }
    }

    @Test("Boundary: 3-year span + 1s is rejected (.spanTooLarge)")
    func threeYearsPlusOneSecondIsRejected() {
        let start = now.addingTimeInterval(-(threeYearsExact + 1))
        #expect {
            try CoinDetailViewModel.validate(start: start, end: now, now: now)
        } throws: { error in
            (error as? CoinDetailViewModel.CustomRangeError) == .spanTooLarge
        }
    }
}
