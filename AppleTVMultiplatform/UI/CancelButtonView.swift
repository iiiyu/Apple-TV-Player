
import SwiftUI

struct CancelButtonView: View {

    let action: @MainActor () -> Void

    var body: some View {
#if !os(iOS)
        Button("Cancel", role: .cancel, action: action)
            .accessibilityIdentifier("cancel")
#else
        // iOS 26: the .close role renders the standard circular
        // glass close button in toolbars.
        Button("Cancel", role: .close, action: action)
            .accessibilityIdentifier("cancel")
#endif
    }
}
