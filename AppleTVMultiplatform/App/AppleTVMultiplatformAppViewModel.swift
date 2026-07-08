
import SwiftUI
import SwiftData
import FactoryKit

@Observable
final class AppleTVMultiplatformAppViewModel {

    @ObservationIgnored @Injected(\.databaseService) private var databaseService
    @ObservationIgnored @Injected(\.logger) private var logger
    private(set) var error: LocalizableError? {
        didSet {
            isErrorPresented = error != nil
        }
    }
    var isErrorPresented = false

    func handleIncomingFile(url: URL) -> Bool {
        let isSecureScoped = url.startAccessingSecurityScopedResource()
        var didImport = false
        defer {
            if isSecureScoped {
                url.stopAccessingSecurityScopedResource()
            } else if didImport {
                // Only clean up the inbox copy after a successful import; on
                // failure keep the file so the user can retry.
                try? FileManager.default.removeItem(at: url)
            }
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(PlaylistItem.self, from: data)
            guard decoded.name != nil, decoded.date != nil else {
                error = "Invalid playlist"
                return false
            }
            let fetch = FetchDescriptor<PlaylistItem>()
            guard try databaseService.mainContext.fetch(fetch)
                .first(where: { $0.identity == decoded.identity }) == nil else {
                error = "Playlist already exists"
                return false
            }
            databaseService.mainContext.insert(decoded)
            if let identity = decoded.identity {
                databaseService.mainContext.insert(
                    PlaylistSettingsItem(
                        playlistName: identity.name,
                        playlistDate: identity.date,
                        data: decoded.data,
                        order: decoded.settings?.order
                    )
                )
            }
            try databaseService.mainContext.save()
            logger.info("Playlist added")
            didImport = true
            return true
        } catch {
            logger.error(error)
            self.error = .init(error: error)
            return false
        }
    }
}
