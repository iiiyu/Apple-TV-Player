
import SwiftUI

/// Open source acknowledgements. Listing the copyright and permission
/// notices here fulfils the MIT license attribution requirement for the
/// original project and every bundled dependency.
struct AcknowledgementsView: View {

    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let name: String
        let copyright: String
        let url: String
        var id: String { name }
    }

    private static let entries: [Entry] = [
        .init(
            name: "Apple-TV-Player",
            copyright: "Copyright (c) 2026 Mikhail Demidov",
            url: "https://github.com/mikehouse/Apple-TV-Player"
        ),
        .init(
            name: "Factory",
            copyright: "Copyright (c) 2022 Michael Long",
            url: "https://github.com/hmlongco/Factory"
        ),
        .init(
            name: "Kanna",
            copyright: "Copyright (c) 2014 - 2015 Atsushi Kiwaki (@_tid_)",
            url: "https://github.com/tid-kijyun/Kanna"
        ),
        .init(
            name: "Nuke",
            copyright: "Copyright (c) 2015-2026 Alexander Grebenyuk",
            url: "https://github.com/kean/Nuke"
        ),
        .init(
            name: "SWCompression",
            copyright: "Copyright (c) 2024 Timofey Solomko",
            url: "https://github.com/tsolomko/SWCompression"
        ),
        .init(
            name: "BitByteData",
            copyright: "Copyright (c) 2024 Timofey Solomko",
            url: "https://github.com/tsolomko/BitByteData"
        )
    ]

    // Verbatim MIT permission notice, shown once for all entries above.
    private static let mitLicense = """
    Permission is hereby granted, free of charge, to any person obtaining a copy \
    of this software and associated documentation files (the "Software"), to deal \
    in the Software without restriction, including without limitation the rights \
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
    copies of the Software, and to permit persons to whom the Software is \
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all \
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
    SOFTWARE.
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("HiPlayer is based on the open source project Apple-TV-Player by Mikhail Demidov and uses the open source components below, all under the MIT License.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(Self.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: entry.name)
                            .font(.headline)
                        Text(verbatim: entry.copyright)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(verbatim: entry.url)
                            .font(.footnote)
                            .foregroundStyle(.tint)
#if !os(tvOS)
                            .textSelection(.enabled)
#endif
                    }
                }

                Text(verbatim: "MIT License")
                    .font(.headline)
                Text(verbatim: Self.mitLicense)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

#if !os(iOS)
                HStack {
                    Spacer()
                    ConfirmButtonView {
                        dismiss()
                    }
                }
#endif
            }
            .padding()
        }
        .navigationTitle(Text("Acknowledgements"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                ConfirmButtonView {
                    dismiss()
                }
            }
        }
#elseif os(macOS)
        .frame(minWidth: 460, minHeight: 420)
#elseif os(tvOS)
        .padding(44)
#endif
    }
}

#if DEBUG
struct AcknowledgementsViewPreviews: PreviewProvider {

    static var previews: some View {
#if os(iOS)
        NavigationStack {
            AcknowledgementsView()
        }
#else
        AcknowledgementsView()
#endif
    }
}
#endif
