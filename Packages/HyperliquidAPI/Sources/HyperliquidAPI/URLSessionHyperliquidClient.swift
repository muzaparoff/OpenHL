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
/// - `waitsForConnectivity`: `true`. Foreground fetches that race a
///   transient network change get a chance to succeed instead of
///   immediately throwing `.offline`. The resource ceiling still bounds
///   it.
/// - `httpAdditionalHeaders`: `Content-Type: application/json`,
///   `Accept: application/json`. No `User-Agent` customization in v1
///   (the default URLSession UA carries no identifying info we control,
///   and Hyperliquid does not require one).
/// - Cache policy: `.reloadIgnoringLocalCacheData` for `/info` POST
///   requests. We always want fresh state; cached responses on a snapshot
///   endpoint are worse than no response.
///
/// Retry / backoff: **none in Phase 1.** The client makes one attempt;
/// transient failures throw and the view model surfaces an error state
/// with a "Try again" affordance. Rationale: retries inside the client
/// hide what is really happening from the view model and from the user,
/// double the time-to-error on real outages, and complicate cancellation.
/// Pull-to-refresh is the user's retry control. (Phase 3's WebSocket
/// will have its own reconnect/backoff machine — that is a different
/// problem with a different shape.)
public struct URLSessionHyperliquidClient: HyperliquidClient {

    /// The base URL. Default: `https://api.hyperliquid.xyz`. Override only
    /// in tests via the convenience initializer that takes a
    /// `URLProtocol` class array (or simply a different base URL).
    public let baseURL: URL

    /// The `URLSession` used for all requests. Injected so tests can pass
    /// a session with `URLProtocol` stubs registered.
    public let session: URLSession

    /// The clock, used to stamp `ClearinghouseState.fetchedAt`.
    public let clock: any Clock

    /// Production initializer. Constructs a session with the documented
    /// configuration.
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

    /// Test/seam initializer. Pass a pre-configured `URLSession` whose
    /// `URLSessionConfiguration.protocolClasses` includes a stub
    /// `URLProtocol` subclass that serves fixture JSON.
    public init(
        baseURL: URL,
        session: URLSession,
        clock: any Clock
    ) {
        self.baseURL = baseURL
        self.session = session
        self.clock = clock
    }

    public func clearinghouseState(for user: Address) async throws -> ClearinghouseState {
        let request = InfoRequest.clearinghouseState(user: user)
        let fetchedAt = clock.now()

        let urlRequest = try buildRequest(body: request)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            if error is CancellationError {
                throw error
            }
            throw HyperliquidError.transport(underlying: error)
        }

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HyperliquidError.unexpectedResponse(reason: "Non-HTTP response received")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HyperliquidError.httpStatus(httpResponse.statusCode)
        }

        let dto: ClearinghouseStateDTO
        do {
            dto = try JSONDecoder().decode(ClearinghouseStateDTO.self, from: data)
        } catch {
            logger.error("Decoding error: \(error, privacy: .public)")
            throw HyperliquidError.decoding(underlying: error)
        }

        try Task.checkCancellation()

        return try mapDTOtoDomain(dto, fetchedAt: fetchedAt)
    }

    // MARK: - Private helpers

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

    private func mapURLError(_ error: URLError) -> HyperliquidError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timeout
        case .cancelled:
            // Let the CancellationError propagate normally; if URLError.cancelled
            // arrives here, treat it as transport so the call site can handle it.
            return .transport(underlying: error)
        default:
            return .transport(underlying: error)
        }
    }

    private func mapDTOtoDomain(
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
            case "cross":
                leverageMode = .cross(pos.leverage.value)
            case "isolated":
                leverageMode = .isolated(pos.leverage.value)
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
