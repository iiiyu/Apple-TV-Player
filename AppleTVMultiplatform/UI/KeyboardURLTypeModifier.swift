
import SwiftUI

struct KeyboardURLTypeModifier: ViewModifier {

    func body(content: Content) -> some View {
        content
#if os(iOS)
            .keyboardType(.URL)
#endif
    }
}
