
import SwiftUI

struct AddButtonView: View {

    /// When placed in a toolbar the container already provides a glass
    /// background, so the button must not add a second (prominent) glass layer
    /// on top — otherwise two rounded shapes visibly overlap on macOS.
    var isToolbar: Bool = false
    let action: @MainActor () -> Void

    var body: some View {
#if os(tvOS)
        Button(isToolbar ? "" : String(localized: "Add"), systemImage: "plus", role: .none, action: action)
            .accessibilityIdentifier("add")
#elseif os(macOS)
        if isToolbar {
            Button("Add", systemImage: "plus", role: .none, action: action)
                .accessibilityIdentifier("add")
        } else {
            Button("Add", systemImage: "plus", role: .none, action: action)
                .accessibilityIdentifier("add")
                .buttonStyle(.glassProminent)
        }
#else
        Button("Add", systemImage: "plus", role: .none, action: action)
            .accessibilityIdentifier("add")
#endif
    }
}
