// SPDX-License-Identifier: MIT

import SwiftUI

/// Inline orange error banner shown when a pull-to-refresh fails but
/// stale data is still displayed underneath. Extracted from
/// `PositionsView` so all three tabs use identical banner chrome.
///
/// Usage:
/// ```swift
/// ErrorBannerView(errorState: refreshError) {
///     await viewModel.retry()
/// }
/// ```
struct ErrorBannerView: View {
    let errorState: ViewErrorState
    /// Async closure called when the user taps "Try again".
    let onRetry: () async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(bannerTitle(errorState))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Button("Try again") {
                    Task { await onRetry() }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(bannerTitle(errorState))")
    }

    // MARK: - Banner title mapping

    private func bannerTitle(_ state: ViewErrorState) -> String {
        switch state {
        case .offline: return "No internet connection."
        case .timeout: return "Request timed out."
        case .serverError(let code): return "Server error (HTTP \(code))."
        case .badRequest: return "Request rejected."
        case .unexpectedResponse: return "Unexpected API response."
        case .unknown: return "Could not refresh."
        }
    }
}
