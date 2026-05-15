// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// DTOs mirror Hyperliquid's wire format 1:1, including their naming
/// (`marginSummary`, `assetPositions`, `unrealizedPnl`). Domain types
/// (in `DomainModels.swift`) use idiomatic Swift names and are what
/// view models consume. The mapping from DTO -> domain is done in
/// `URLSessionHyperliquidClient.clearinghouseState(for:)` so the rest of
/// the app never sees a DTO.
///
/// DTO convention:
/// - Suffix `DTO`.
/// - `Decodable, Sendable`. No `Encodable` unless we round-trip in tests.
/// - All money fields use `@DecimalString` (or `@OptionalDecimalString`).
/// - Coding keys match the wire field names exactly. If the wire name is
///   already valid Swift, no `CodingKeys` is needed.
/// - No computed properties, no derived state. DTOs are dumb.
internal struct ClearinghouseStateDTO: Decodable, Sendable {

    /// `marginSummary` block — aggregate USD figures for the account.
    internal struct MarginSummaryDTO: Decodable, Sendable {
        @DecimalString internal var accountValue: Decimal
        @DecimalString internal var totalNtlPos: Decimal
        @DecimalString internal var totalRawUsd: Decimal
        @DecimalString internal var totalMarginUsed: Decimal
    }

    /// One entry in `assetPositions`. Hyperliquid wraps each position in
    /// `{"type":"oneWay","position":{...}}`; we model the wrapper here.
    internal struct AssetPositionDTO: Decodable, Sendable {
        internal let type: String  // "oneWay" expected
        internal let position: PositionDTO
    }

    /// The inner `position` object.
    internal struct PositionDTO: Decodable, Sendable {
        internal let coin: String
        @DecimalString internal var szi: Decimal  // signed size
        @DecimalString internal var entryPx: Decimal
        @DecimalString internal var positionValue: Decimal
        @DecimalString internal var unrealizedPnl: Decimal
        @DecimalString internal var returnOnEquity: Decimal
        @OptionalDecimalString internal var liquidationPx: Decimal?
        @DecimalString internal var marginUsed: Decimal
        internal let leverage: LeverageDTO
        // Extra wire fields (maxLeverage, cumFunding) are intentionally
        // omitted from this DTO until Phase 2 needs them.
    }

    internal struct LeverageDTO: Decodable, Sendable {
        internal let type: String  // "cross" | "isolated"
        internal let value: Int
    }

    internal let marginSummary: MarginSummaryDTO
    internal let crossMarginSummary: MarginSummaryDTO
    @DecimalString internal var withdrawable: Decimal
    internal let assetPositions: [AssetPositionDTO]
    internal let time: Int64  // server timestamp, ms since epoch
}
