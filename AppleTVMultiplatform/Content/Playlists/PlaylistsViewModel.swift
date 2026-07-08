
import SwiftUI
import FactoryKit
import SwiftData

@Observable
final class PlaylistsViewModel {

    @ObservationIgnored @Injected(\.databaseService) private var databaseService
    @ObservationIgnored @Injected(\.playlistAddService) private var playlistAddService
    @ObservationIgnored @Injected(\.playlistService) private var playlistService
    @ObservationIgnored @Injected(\.logger) private var logger
    var playlists: [PlaylistItem] = []
    var selectedPlaylist: PlaylistItem?

    func updatePlaylists() {
        do {
            logger.info("Update playlists")
            let fetch = FetchDescriptor<PlaylistItem>(
                sortBy: [.init(\.date, order: .reverse)]
            )
            let all = try databaseService.mainContext.fetch(fetch)
                .filter({ $0.date != nil && $0.name != nil })
            // PlaylistItem mirrors to CloudKit, which can't enforce uniqueness,
            // so importing the same playlist on two devices leaves duplicate
            // records with the same identity after sync. Show one row per
            // identity; every copy is removed together in deletePlaylist. We
            // collapse for display rather than delete duplicates here to avoid
            // two devices racing to delete each other's copy of an identical
            // record.
            var seen = Set<PlaylistItem.Identity>()
            self.playlists = all.filter { item in
                guard let identity = item.identity else { return false }
                return seen.insert(identity).inserted
            }
        } catch {
            logger.error(error)
            self.playlists = []
        }
    }

    func deletePlaylist(_ playlist: PlaylistItem) {
        if let identity = playlist.identity {
            logger.info("Delete playlist", private: identity)
        }
        let state = try? PlaylistSettingsItem.state(for: playlist, in: databaseService.mainContext, create: false)
        let preparedPlaylist = PreparedPlaylist(playlist, cachedData: state?.data)
        let reloadCurrent = playlist.identity == selectedPlaylist?.identity
        // Delete every record sharing this identity so CloudKit duplicates go
        // too; deletions converge across devices, unlike keep-one dedup.
        let itemsToDelete: [PlaylistItem]
        if let identity = playlist.identity {
            itemsToDelete = ((try? databaseService.mainContext.fetch(FetchDescriptor<PlaylistItem>())) ?? [])
                .filter { $0.identity == identity }
        } else {
            itemsToDelete = [playlist]
        }
        for item in itemsToDelete {
            databaseService.mainContext.delete(item)
        }
        if let state {
            databaseService.mainContext.delete(state)
        }
        try? databaseService.mainContext.save()
        if reloadCurrent {
            selectedPlaylist = nil
        }
        updatePlaylists()
        guard let preparedPlaylist else { return }
        // Restoring an encrypted playlist requires a pin we don't have at
        // delete time, so build the content directly from the identity.
        // clearCache still drops the in-memory entry and (for playlists
        // opened this session) the recorded guide/logo cache files.
        let content = PlaylistItem.Content(
            identity: .init(name: preparedPlaylist.name, date: preparedPlaylist.date),
            url: preparedPlaylist.url,
            data: preparedPlaylist.data,
            isStoredInMemoryOnly: false
        )
        Task.detached { [playlistService] in
            await playlistService.clearCache(for: content)
        }
    }

    func updateSelection(_ selection: PlaylistItem.Identity?) {
        guard let selection else {
            logger.info("Clear playlist selection")
            self.selectedPlaylist = nil
            return
        }
        logger.info("Select playlist", private: selection)
        let fetch = FetchDescriptor<PlaylistItem>()
        self.selectedPlaylist = try? databaseService.mainContext.fetch(fetch)
            .first(where: { $0.identity == selection })
    }

    func onPlaylistSelection() -> PlaylistItem.Identity? {
        let playlist = selectedPlaylist
        guard let name = playlist?.name,
              let date = playlist?.date else { return nil }
        return PlaylistItem.Identity(name: name, date: date)
    }

    isolated deinit {
        logger.info("deinit of \(self)")
    }
}
