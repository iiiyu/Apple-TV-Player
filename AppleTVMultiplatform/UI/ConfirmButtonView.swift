
import SwiftUI

struct ConfirmButtonView: View {

    let action: @MainActor () -> Void

    var body: some View {
        #if os(iOS)
        Button("Done", systemImage: "checkmark", role: nil, action: action)
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("confirm")
        #else
        Button("Done", action: action)
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("confirm")
        #endif
    }
}
