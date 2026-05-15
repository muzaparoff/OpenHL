// SPDX-License-Identifier: MIT

import Foundation

/// The only error type `HyperliquidClient` throws. View models pattern-
/// match on these to choose a user-facing state; they never see a raw
/// `URLError` or `DecodingError`.
///
/// Cases are stable. New cases get added (with a decision log entry); we
/// do not silently re-map.
///
/// Mapping rules used by `URLSessionHyperliquidClient`:
/// - `URLError.notConnectedToInternet`, `.networkConnectionLost`,
///   `.dataNotAllowed` -> `.offline`.
/// - `URLError.timedOut` -> `.timeout`.
/// - HTTP status outside `200..<300` -> `.httpStatus(code)`. The body is
///   discarded (Hyperliquid does not return structured error bodies for
///   the endpoints we use in Phase 1).
/// - Any `DecodingError` thrown by `JSONDecoder` -> `.decoding(underlying:)`.
///   The underlying error is preserved for logging via `OSLog`; it is
///   not surfaced to the user.
/// - Anything else from the transport (`URLError` cases not in the
///   above list, including `.cancelled`) -> `.transport(underlying:)`.
///   `.cancelled` is allowed to propagate as `CancellationError` from
///   the surrounding `async` machinery; we only wrap if the URL session
///   reports cancellation through `URLError`.
/// - Response shape valid as JSON but semantically wrong (missing required
///   keys handled by `Decodable`, but post-decode invariants violated —
///   e.g. an enum case the API documents but we have not yet implemented)
///   -> `.unexpectedResponse(reason:)`.
public enum HyperliquidError: Error, Sendable {
    /// Device has no network. View model state: `.error(.offline)`.
    case offline

    /// Request exceeded `URLSessionConfiguration.timeoutIntervalForRequest`.
    /// View model state: `.error(.timeout)`.
    case timeout

    /// Non-2xx HTTP response. View model state: `.error(.serverError)` for
    /// 5xx; `.error(.badRequest)` for 4xx. View models translate, not the
    /// client.
    case httpStatus(Int)

    /// Response body did not decode. Underlying `DecodingError` preserved
    /// for log diagnostics only — never shown to the user. View model
    /// state: `.error(.unexpectedResponse)`.
    case decoding(underlying: any Error)

    /// JSON decoded but contents violated a documented invariant the
    /// client enforces post-decode. View model state:
    /// `.error(.unexpectedResponse)`.
    case unexpectedResponse(reason: String)

    /// Any other transport failure (DNS, TLS, etc.). View model state:
    /// `.error(.unknown)`.
    case transport(underlying: any Error)
}
