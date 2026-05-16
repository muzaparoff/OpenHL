// SPDX-License-Identifier: MIT

import OpenHLCore
import SwiftUI

/// Sheet that lets the user pick an arbitrary start/end date for the
/// coin-detail chart. Presented from `CoinDetailView` as a `.medium` detent
/// sheet; grows to `.large` if the user expands it or if Dynamic Type
/// forces the content taller.
///
/// Validation uses `CoinDetailViewModel.validate(customRange:now:)` (pure,
/// synchronous) and gates the Apply button accordingly. The validation
/// message only appears after the user has interacted with at least one
/// date picker to avoid surfacing errors on initial open.
struct CoinDetailCustomRangeSheet: View {

    // MARK: - Inputs

    /// The date to which the end picker is capped (`Date.now` at sheet open).
    let now: Date

    /// Called with the committed `DateInterval` when the user taps Apply.
    /// The callee is responsible for calling `viewModel.setMode(.customRange(...))`.
    let onApply: (DateInterval) -> Void

    /// Called when the user dismisses without applying (Cancel / drag-down).
    let onCancel: () -> Void

    // MARK: - Local state

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var hasInteracted = false
    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialiser

    /// - Parameters:
    ///   - initial: Pre-filled range, or `nil` to default to `[now−7d, now]`.
    ///   - now: Upper cap for the end date picker. Injected so the sheet is
    ///     testable with a fixed clock.
    init(
        initial: DateInterval?,
        now: Date,
        onApply: @escaping (DateInterval) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.now = now
        self.onApply = onApply
        self.onCancel = onCancel
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        _startDate = State(initialValue: initial?.start ?? sevenDaysAgo)
        _endDate = State(initialValue: initial?.end ?? now)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Start",
                        selection: $startDate,
                        in: ...endDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .accessibilityLabel("Start date")
                    .onChange(of: startDate) { _, _ in hasInteracted = true }

                    DatePicker(
                        "End",
                        selection: $endDate,
                        in: startDate...now,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .accessibilityLabel("End date")
                    .onChange(of: endDate) { _, _ in hasInteracted = true }
                }

                Section {
                    Button {
                        let range = DateInterval(start: startDate, end: endDate)
                        onApply(range)
                        dismiss()
                    } label: {
                        Text("Apply")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(validationError != nil)
                    .accessibilityLabel("Apply custom date range")
                    .accessibilityHint(
                        validationError != nil
                            ? "End date must be after start date and the range must not exceed three years."
                            : ""
                    )

                    if hasInteracted, let message = validationMessage {
                        Text(message)
                            .font(validationMessageFont)
                            .foregroundStyle(.secondary)
                        // Note: SwiftUI has no accessibilityLiveRegion modifier
                        // on iOS 17. VoiceOver users reach this text by
                        // swiping; a future UIKit bridge can post a
                        // UIAccessibility.post(.announcement) notification.
                    }
                }
            }
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel, dismiss without applying")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Validation

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var validationError: CoinDetailViewModel.CustomRangeError? {
        // Validate raw dates: `DateInterval(start:end:)` traps if end < start,
        // which can transiently happen while the user is dragging the pickers.
        do {
            try CoinDetailViewModel.validate(start: startDate, end: endDate, now: now)
            return nil
        } catch let error as CoinDetailViewModel.CustomRangeError {
            return error
        } catch {
            return nil
        }
    }

    private var validationMessage: String? {
        switch validationError {
        case nil:
            return nil
        case .endBeforeStart:
            return "End must be after start."
        case .endInFuture:
            return "End date cannot be in the future."
        case .spanTooLarge:
            return "Range cannot exceed 3 years."
        }
    }

    private var validationMessageFont: Font {
        dynamicTypeSize >= .accessibility3 ? .footnote : .caption
    }
}
