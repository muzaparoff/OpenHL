// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore
import Testing

@testable import HyperliquidAPI

/// Locks in the `clearinghouseState` decoder against a real response from
/// a known Hyperliquid account (`0x99382723C90EcC72dad2A7DD375DE45b88E8fe72`).
/// Captured 2026-05-16.
///
/// The fixture stays frozen on disk; the test asserts on **structural
/// invariants** (shape, fields, types) rather than exact decimal values
/// because live PnL drifts whenever the fixture is re-captured.
@Suite("clearinghouseState — real account fixture (0x9938…fe72)")
struct ClearinghouseStateRealFixtureTests {

    @Test("Decodes real fixture into the expected shape")
    func decodesRealFixture() throws {
        let data = try FixtureLoader.load("clearinghouseState_real_btc_short")
        let dto = try JSONDecoder().decode(ClearinghouseStateDTO.self, from: data)

        // Account summary is populated (account isn't empty).
        #expect(dto.marginSummary.accountValue > 0)
        #expect(dto.marginSummary.totalNtlPos > 0)
        #expect(dto.marginSummary.totalRawUsd > 0)
        #expect(dto.marginSummary.totalMarginUsed >= 0)
        #expect(dto.withdrawable >= 0)
        #expect(dto.time > 0)

        // Exactly one position when captured: a BTC short on cross margin.
        #expect(dto.assetPositions.count == 1)
        let assetPos = try #require(dto.assetPositions.first)
        #expect(assetPos.type == "oneWay")
        let pos = assetPos.position
        #expect(pos.coin == "BTC")
        #expect(pos.szi < 0)  // short
        #expect(pos.leverage.type == "cross")
        #expect(pos.leverage.value == 1)
        // Entry price is in BTC's plausible range (smoke check against a
        // decoding bug that produced 0 or a multiplied value).
        #expect(pos.entryPx > 1000)
        #expect(pos.liquidationPx ?? 0 > 0)
    }
}
