// SPDX-License-Identifier: MIT

import Foundation
import HyperliquidAPI

/// View-facing error vocabulary shared by every screen that fetches from
/// `HyperliquidClient`. Maps transport-level `HyperliquidError` values onto
/// the categories the UI actually distinguishes.
enum ViewErrorState: Sendable, Equatable {
    case offline
    case timeout
    case badRequest
    case serverError(Int)
    case unexpectedResponse
    case unknown

    init(_ error: HyperliquidError) {
        switch error {
        case .offline:
            self = .offline
        case .timeout:
            self = .timeout
        case .httpStatus(let code):
            self = code >= 500 ? .serverError(code) : .badRequest
        case .decoding, .unexpectedResponse:
            self = .unexpectedResponse
        case .transport:
            self = .unknown
        }
    }

    /// Maps any `Error` to a `ViewErrorState`. Cancellation must be handled
    /// by callers before this is reached; non-Hyperliquid errors fall through
    /// to `.unknown`.
    init(any error: any Error) {
        if let hyperliquid = error as? HyperliquidError {
            self.init(hyperliquid)
        } else {
            self = .unknown
        }
    }
}
