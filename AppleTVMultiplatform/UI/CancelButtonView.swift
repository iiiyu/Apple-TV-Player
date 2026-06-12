
import SwiftUI

struct CancelButtonView: View {

    let action: @MainActor () -> Void

    var body: some View {
#if !os(iOS)
        Button("Cancel", role: .cancel, action: action)
            .accessibilityIdentifier("cancel")
#else
        Button("Cancel", systemImage: "xmark", role: nil, action: action)
            .accessibilityIdentifier("cancel")
#endif
    }
}
