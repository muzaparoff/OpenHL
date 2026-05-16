// SPDX-License-Identifier: MIT

import SwiftUI

/// Full-page error view shown when a cold-start fetch fails and there
/// is no stale data to display. Extracted from `PositionsView` so
/// `OrdersView` and `FillsView` can reuse identical chrome.
///
/// Usage:
/// ```swift
/// ErrorStateView(errorState: .offline) {
///     await viewModel.retry()
/// }
/// ```
///
/// The `errorTitle` and `errorMessage` parameters let each screen
/// customise the title for the `.unexpectedResponse` case (e.g.
/// "Could not read orders" vs "Could not read account data") while
/// keeping every other symbol, layout, and CTA identical.
struct ErrorStateView: View {
    let errorState: ViewErrorState
    /// Override the title string. When `nil`, the built-in title is used.
    var titleOverride: String? = nil
    /// Async closure called when the user taps "Try again".
    let onRetry: () async -> Void

    var body: some View {
        let (symbol, title, message) = errorContent(errorState)
        let displayTitle = titleOverride ?? title

        return VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(displayTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") {
                Task { await onRetry() }
            }
            .buttonStyle(.bordered)

            if case .unexpectedResponse = errorState {
                Link(
                    "If this persists, please file an issue on GitHub.",
                    destination: URL(string: "https://github.com/open-hl/open-hl/issues")!
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Content mapping

    /// Returns (sfSymbol, title, message) for each error state. This is
    /// the canonical mapping — all three screens use it verbatim.
    private func errorContent(
        _ state: ViewErrorState
    ) -> (String, String, String) {
        switch state {
        case .offline:
            return (
                "wifi.slash",
                "No internet connection",
                "Connect and pull down to refresh."
            )
        case .timeout:
            return (
                "clock.badge.exclamationmark",
                "Request timed out",
                "Hyperliquid may be slow.\nPull down or tap to try again."
            )
        case .serverError(let code):
            return (
                "exclamationmark.circle",
                "Hyperliquid is unavailable",
                "The server returned an error (HTTP \(code)). Try again in a moment."
            )
        case .badRequest:
            return (
                "exclamationmark.circle",
                "Request rejected",
                "The server rejected the request. Try again."
            )
        case .unexpectedResponse:
            return (
                "xmark.circle",
                "Could not read data",
                "The API returned a response the app did not recognize. This may be a temporary API change."
            )
        case .unknown:
            return (
                "exclamationmark.triangle",
                "Could not load data",
                "An unexpected error occurred. Check your connection and try again."
            )
        }
    }
}
