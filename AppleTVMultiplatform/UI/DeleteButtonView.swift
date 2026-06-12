
import SwiftUI

struct DeleteButtonView: View {

    let action: @MainActor () -> Void

    var body: some View {
        Button("Delete", systemImage: "trash", role: .destructive, action: action)
    }
}
