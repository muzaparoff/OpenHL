// SPDX-License-Identifier: MIT

import Foundation
import OpenHLCore

/// Wire shape of `POST /info` with `{"type":"metaAndAssetCtxs"}`.
///
/// Hyperliquid returns a heterogeneous JSON array of exactly two elements:
///
///   `[ { "universe": [PerpInfoDTO, …] },  [AssetContextDTO, …] ]`
///
/// We hand-roll an unkeyed-container decoder so the response shape is
/// type-safe at the boundary. The two inner arrays are in the same order
/// — `universe[i]` and `assetCtxs[i]` describe the same perp.
internal struct MetaAndAssetCtxsDTO: Decodable, Sendable {
    let meta: MetaUniverseDTO
    let assetCtxs: [AssetContextDTO]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        meta = try container.decode(MetaUniverseDTO.self)
        assetCtxs = try container.decode([AssetContextDTO].self)
    }
}

internal struct MetaUniverseDTO: Decodable, Sendable {
    let universe: [PerpInfoDTO]
}

internal struct PerpInfoDTO: Decodable, Sendable {
    let name: String
    let szDecimals: Int
    let maxLeverage: Int
    let onlyIsolated: Bool?
}

/// Per-asset live context. Field order matches `meta.universe`.
///
/// `oraclePx`, `premium`, and `midPx` are nullable in the wire response
/// — delisted/inactive perps report `null` for them. The UI never reads
/// these directly; they're decoded as optional purely so a stale perp
/// doesn't tank the whole response.
internal struct AssetContextDTO: Decodable, Sendable {
    @DecimalString var funding: Decimal
    @DecimalString var openInterest: Decimal
    @DecimalString var prevDayPx: Decimal
    @DecimalString var markPx: Decimal
    @OptionalDecimalString var midPx: Decimal?
    @OptionalDecimalString var oraclePx: Decimal?
    @OptionalDecimalString var premium: Decimal?
    @DecimalString var dayNtlVlm: Decimal
}

extension MetaAndAssetCtxsDTO {
    /// Map the parallel arrays into the public `Market` domain type.
    /// Drops any pair where universe.count != assetCtxs.count (defensive —
    /// in practice Hyperliquid keeps these in lock-step).
    func toMarkets() -> [Market] {
        let count = min(meta.universe.count, assetCtxs.count)
        return (0..<count).map { i in
            let p = meta.universe[i]
            let c = assetCtxs[i]
            return Market(
                coin: p.name,
                maxLeverage: p.maxLeverage,
                szDecimals: p.szDecimals,
                onlyIsolated: p.onlyIsolated ?? false,
                markPrice: c.markPx,
                midPrice: c.midPx,
                prevDayPrice: c.prevDayPx,
                openInterest: c.openInterest,
                dayNotionalVolume: c.dayNtlVlm,
                fundingRate: c.funding
            )
        }
    }
}
