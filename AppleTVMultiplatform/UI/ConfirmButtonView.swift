
import SwiftUI

struct ConfirmButtonView: View {

    let action: @MainActor () -> Void

    var body: some View {
        #if os(iOS)
        Button("Done", systemImage: "checkmark", role: .confirm, action: action)
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("confirm")
        #else
        Button("Done", role: .confirm, action: action)
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("confirm")
        #endif
    }
}
