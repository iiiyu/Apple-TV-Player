
import Foundation
import SwiftData

@Model
final class AppSettings {

    // Last watched channel, restored on app launch. The stream is referenced
    // by the same HMAC used for the view/recent statistics, so no plain
    // channel title is persisted.
    var lastPlaylistName: String?
    var lastPlaylistDate: Date?
    var lastStreamHmac: String?

    init() {

    }
}


