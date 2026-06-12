
import SwiftUI

struct BlurProgressView: View {
    
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        ProgressView(text)
            .controlSize(.large)
            .padding(44)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}
