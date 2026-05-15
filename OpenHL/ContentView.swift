// SPDX-License-Identifier: MIT

import SwiftUI

struct ContentView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("open-hl")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("v\(appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ContentView()
}
