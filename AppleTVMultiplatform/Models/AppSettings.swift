
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

extension AppSettings {

    static func lastWatchedSettings(in context: ModelContext) throws -> AppSettings {
        if let settings = try mergedLastWatchedSettings(in: context) {
            return settings
        }

        let settings = AppSettings()
        context.insert(settings)
        return settings
    }

    static func mergedLastWatchedSettings(in context: ModelContext) throws -> AppSettings? {
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        guard let appSettings = settings.first(where: { $0.lastPlaylistName != nil && $0.lastPlaylistDate != nil })
                ?? settings.first else {
            return nil
        }

        for duplicate in settings where duplicate !== appSettings {
            if appSettings.lastPlaylistName == nil {
                appSettings.lastPlaylistName = duplicate.lastPlaylistName
            }
            if appSettings.lastPlaylistDate == nil {
                appSettings.lastPlaylistDate = duplicate.lastPlaylistDate
            }
            if appSettings.lastStreamHmac == nil {
                appSettings.lastStreamHmac = duplicate.lastStreamHmac
            }
            context.delete(duplicate)
        }

        return appSettings
    }
}

