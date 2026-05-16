// SPDX-License-Identifier: MIT

import Foundation
import OSLog
import OpenHLCore

private let logger = Logger(subsystem: "xyz.hyperliquid.openhl", category: "HyperliquidClient")

/// Production `HyperliquidClient`. One instance per app, constructed in
/// the composition root.
///
/// Concurrency: a `struct` with `Sendable` dependencies. No shared mutable
/// state. The underlying `URLSession` is itself thread-safe and `Sendable`.
///
/// Configuration:
/// - `timeoutIntervalForRequest`: 15 seconds (per-request).
/// - `timeoutIntervalForResource`: 30 seconds (whole-resource ceiling).
/// - `waitsForConnectivity`: `true`.
/// - `httpAdditionalHeaders`: `Content-Type: application/json`,
///   `Accept: application/json`.
/// - Cache policy: `.reloadIgnoringLocalCacheData` (snapshot endpoints,
///   no caching).
///
/// Retry / backoff: **none in Phase 1.** Pull-to-refresh is the user's
/// retry control. Phase 3's WebSocket has its own reconnect machine.
public struct URLSessionHyperliquidClient: HyperliquidClient {

    public let baseURL: URL
    public let session: URLSession
    public let clock: any Clock

    public init(
        baseURL: URL = URL(string: "https://api.hyperliquid.xyz")!,
        clock: any Clock = SystemClock()
    ) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil

        self.baseURL = baseURL
        self.session = URLSession(configuration: config)
        self.clock = clock
    }

    /// Test/seam initializer.
    public init(
        baseURL: URL,
        session: URLSession,
        clock: any Clock
    ) {
        self.baseURL = baseURL
        self.session = session
        self.clock = clock
    }

    /// Hard cap on `userFills(for:)` results.
    public static let userFillsCap: Int = 200

    // MARK: - Public API

    public func clearinghouseState(for user: Address) async throws -> ClearinghouseState {
        let fetchedAt = clock.now()
        let dto: ClearinghouseStateDTO = try await perform(.clearinghouseState(user: user))
        return try Self.mapDTOtoDomain(dto, fetchedAt: fetchedAt)
    }

    public func openOrders(for user: Address) async throws -> [OpenOrder] {
        let dtos: [OpenOrderDTO] = try await perform(.openOrders(user: user))
        return try dtos.map { try Self.mapOpenOrderDTO($0) }
    }

    public func userFills(for user: Address) async throws -> [Fill] {
        let dtos: [UserFillDTO] = try await perform(.userFills(user: user))
        let fills = try dtos.map { try Self.mapUserFillDTO($0) }
        return Array(fills.prefix(URLSessionHyperliquidClient.userFillsCap))
    }

    public func markets() async throws -> [Market] {
        let dto: MetaAndAssetCtxsDTO = try await perform(.metaAndAssetCtxs)
        return dto.toMarkets()
    }

    public func candles(
        coin: String,
        interval: CandleInterval,
        startTime: Date,
        endTime: Date
    ) async throws -> [Candle] {
        let dtos: [CandleDTO] = try await perform(
            .candleSnapshot(
                coin: coin,
                interval: interval,
                startTime: startTime,
                endTime: endTime
            )
        )
        return dtos.toCandles()
    }

    public func portfolio(for user: Address) async throws -> Portfolio {
        let dto: PortfolioDTO = try await perform(.portfolio(user: user))
        return dto.toDomain()
    }

    // MARK: - Shared transport / decode pipeline

    /// One pipeline for every `POST /info` call. Builds the request,
    /// performs it, validates status, decodes the typed response.
    /// `HyperliquidError` is the only thing this ever throws (other than
    /// `CancellationError`, which propagates untouched so structured
    /// concurrency can clean up).
    private func perform<Response: Decodable>(
        _ infoRequest: InfoRequest
    ) async throws -> Response {
        let urlRequest = try buildRequest(body: infoRequest)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            throw Self.mapURLError(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HyperliquidError.transport(underlying: error)
        }

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HyperliquidError.unexpectedResponse(reason: "Non-HTTP response received")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HyperliquidError.httpStatus(httpResponse.statusCode)
        }

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            logger.error(
                "\(String(describing: Response.self), privacy: .public) decode error: \(error, privacy: .public)")
            throw HyperliquidError.decoding(underlying: error)
        }

        try Task.checkCancellation()
        return decoded
    }

    private func buildRequest(body: some Encodable) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("info")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw HyperliquidError.unexpectedResponse(reason: "Failed to encode request: \(error)")
        }
        return request
    }

    private static func mapURLError(_ error: URLError) -> HyperliquidError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timeout
        case .cancelled:
            return .transport(underlying: error)
        default:
            return .transport(underlying: error)
        }
    }

    // MARK: - DTO → domain mappers (pure, hence `static`)

    private static func mapOpenOrderDTO(_ dto: OpenOrderDTO) throws -> OpenOrder {
        let side: OpenOrder.Side
        switch dto.side {
        case "B": side = .buy
        case "A": side = .sell
        default:
            throw HyperliquidError.unexpectedResponse(
                reason: "openOrders: unknown side '\(dto.side)'"
            )
        }

        let orderType: OpenOrder.OrderType
        // orderType is absent for plain limit orders; default to .limit when nil.
        switch dto.orderType {
        case nil, "Limit": orderType = .limit
        case "Trigger": orderType = .trigger
        case "Stop Limit": orderType = .stopLimit
        case "Stop Market": orderType = .stopMarket
        case "Take Profit Limit": orderType = .takeProfitLimit
        case "Take Profit Market": orderType = .takeProfitMarket
        default:
            let raw = dto.orderType!
            logger.info(
                "openOrders: unrecognized orderType '\(raw, privacy: .public)' — using .unknown fallback"
            )
            orderType = .unknown(raw)
        }

        let placedAt = Date(timeIntervalSince1970: TimeInterval(dto.timestamp) / 1000.0)

        return OpenOrder(
            oid: dto.oid,
            coin: dto.coin,
            side: side,
            limitPrice: dto.limitPx,
            size: dto.sz,
            origSize: dto.origSz,
            orderType: orderType,
            reduceOnly: dto.reduceOnly ?? false,
            triggerPrice: dto.triggerPx,
            placedAt: placedAt
        )
    }

    private static func mapUserFillDTO(_ dto: UserFillDTO) throws -> Fill {
        let side: Fill.Side
        switch dto.side {
        case "B": side = .buy
        case "A": side = .sell
        default:
            throw HyperliquidError.unexpectedResponse(
                reason: "userFills: unknown side '\(dto.side)'"
            )
        }

        let executedAt = Date(timeIntervalSince1970: TimeInterval(dto.time) / 1000.0)

        return Fill(
            tid: dto.tid,
            oid: dto.oid,
            coin: dto.coin,
            side: side,
            direction: dto.dir,
            price: dto.px,
            size: dto.sz,
            fee: dto.fee,
            feeToken: dto.feeToken,
            closedPnL: dto.closedPnl,
            crossed: dto.crossed,
            hash: dto.hash,
            executedAt: executedAt
        )
    }

    private static func mapDTOtoDomain(
        _ dto: ClearinghouseStateDTO,
        fetchedAt: Date
    ) throws -> ClearinghouseState {
        let summary = ClearinghouseState.AccountSummary(
            accountValue: dto.marginSummary.accountValue,
            totalNotionalPosition: dto.marginSummary.totalNtlPos,
            totalRawUSD: dto.marginSummary.totalRawUsd,
            totalMarginUsed: dto.marginSummary.totalMarginUsed,
            withdrawable: dto.withdrawable
        )

        let positions = try dto.assetPositions.map { assetPos -> ClearinghouseState.Position in
            guard assetPos.type == "oneWay" else {
                throw HyperliquidError.unexpectedResponse(
                    reason: "Unknown assetPosition type: '\(assetPos.type)'"
                )
            }
            let pos = assetPos.position

            let leverageMode: ClearinghouseState.Position.LeverageMode
            switch pos.leverage.type {
            case "cross": leverageMode = .cross(pos.leverage.value)
            case "isolated": leverageMode = .isolated(pos.leverage.value)
            default:
                throw HyperliquidError.unexpectedResponse(
                    reason: "Unknown leverage type: '\(pos.leverage.type)'"
                )
            }

            let side: ClearinghouseState.Position.Side = pos.szi >= 0 ? .long : .short

            return ClearinghouseState.Position(
                coin: pos.coin,
                size: pos.szi,
                side: side,
                entryPrice: pos.entryPx,
                positionValue: pos.positionValue,
                unrealizedPnL: pos.unrealizedPnl,
                returnOnEquity: pos.returnOnEquity,
                liquidationPrice: pos.liquidationPx,
                marginUsed: pos.marginUsed,
                leverage: leverageMode
            )
        }

        let serverTime = Date(timeIntervalSince1970: TimeInterval(dto.time) / 1000.0)

        return ClearinghouseState(
            summary: summary,
            positions: positions,
            serverTime: serverTime,
            fetchedAt: fetchedAt
        )
    }
}
