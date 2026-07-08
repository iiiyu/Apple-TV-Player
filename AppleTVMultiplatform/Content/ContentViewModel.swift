
import SwiftUI
import FactoryKit
import SwiftData

@Observable
final class ContentViewModel {

    @ObservationIgnored @Injected(\.databaseService) private var databaseService
    @ObservationIgnored @Injected(\.playlistAddService) private var playlistAddService
    @ObservationIgnored @Injected(\.logger) private var logger

    var selectedPlaylist: PlaylistItem.Identity?
    var selectedPlaylistContent: PlaylistItem.Content?
    var selectedPlaylistStream: PlaylistParser.Stream?
    var isShowingPlaylistAdd = false
    var isShowingPlaylistDecryptPin: PlaylistItem.Identity?
    var errorMessage: String?
    var isShowingError = false
#if os(tvOS)
    var path: [PlaylistItem.Content] = []
#endif
    private(set) var playlistListUpdate = UUID()
    @ObservationIgnored private var selectionTask: Task<Void, Never>?

    /// Starts loading the newly selected playlist, cancelling any in-flight
    /// selection so a slow earlier tap can't overwrite a later one.
    func onPlaylistSelectionChanged() {
        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            await self?.onPlaylistSelected()
        }
    }

    func onPlaylistSelected() async {
        selectedPlaylistContent = nil
        selectedPlaylistStream = nil
        isShowingPlaylistDecryptPin = nil

        guard let identity = selectedPlaylist else {
            return
        }
        logger.info("Playlist selected", private: identity)
        do {
            let fetch = FetchDescriptor<PlaylistItem>()
            guard let playlist = (try databaseService.mainContext.fetch(fetch))
                .first(where: { $0.identity == identity }) else {
                return
            }

            if playlist.encrypted {
                selectedPlaylistContent = nil
#if os(tvOS)
                path = []
#endif
                logger.info("Show enter pin to decrypt", private: identity)
                isShowingPlaylistDecryptPin = identity
            } else {
                guard let preparedPlaylist = try await preparedPlaylist(for: playlist, pin: nil) else {
                    return
                }
                let restoredPlaylist = try await playlistAddService.restorePlaylist(preparedPlaylist, pin: nil)
                // The selection may have changed (or been cancelled) while the
                // playlist was downloading; don't clobber a newer selection.
                guard !Task.isCancelled, selectedPlaylist == identity else {
                    return
                }
                logger.info("Show Playlist", private: identity)
                selectedPlaylistContent = restoredPlaylist.content
#if os(tvOS)
                path = [restoredPlaylist.content]
#endif
            }
        } catch is CancellationError {
            return
        } catch {
            logger.error(error)
            guard selectedPlaylist == identity else { return }
            errorMessage = errorText(for: error)
            isShowingError = true
        }
    }

    private func errorText(for error: Swift.Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        return String(localized: "This playlist could not be opened. Check your connection and try again.")
    }

    func onDecrypt() {
        if let selectedPlaylistContent {
            logger.info("Show Playlist", private: selectedPlaylistContent.identity)
#if os(tvOS)
            path = [selectedPlaylistContent]
#endif
        } else {
            selectedPlaylist = nil
        }
    }

    func updatePlaylists() {
        logger.info("Update Playlists")
        playlistListUpdate = .init()
    }

    @ObservationIgnored private var pendingRestoreStreamHmac: String?
    @ObservationIgnored private var didAttemptRestore = false

    func restoreLastWatched() {
        guard !didAttemptRestore else {
            return
        }
        didAttemptRestore = true
        guard selectedPlaylist == nil else {
            return
        }
        guard let appSettings = try? AppSettings.mergedLastWatchedSettings(in: databaseService.mainContext),
              let name = appSettings.lastPlaylistName,
              let date = appSettings.lastPlaylistDate else {
            return
        }
        try? databaseService.mainContext.save()
        let identity = PlaylistItem.Identity(name: name, date: date)
        let playlists = (try? databaseService.mainContext.fetch(FetchDescriptor<PlaylistItem>())) ?? []
        guard playlists.contains(where: { $0.identity == identity }) else {
            return
        }
        logger.info("Restore last watched playlist", private: identity)
        pendingRestoreStreamHmac = appSettings.lastStreamHmac
        selectedPlaylist = identity
    }

    func consumeRestoreStreamHmac() -> String? {
        defer {
            pendingRestoreStreamHmac = nil
        }
        return pendingRestoreStreamHmac
    }

    func onPlaylistRenamed(_ identity: PlaylistItem.Identity) {
        logger.info("Playlist renamed", private: identity)
        // Re-selecting by the new identity restores fresh content from the
        // database; the list refresh shows the new name in the sidebar.
        selectedPlaylist = identity
        updatePlaylists()
    }
    
    func onAddPlaylist() {
        logger.info("Show Add Playlist")
        isShowingPlaylistAdd = true
    }

    isolated deinit {
        logger.info("deinit of \(self)")
    }
}

private extension ContentViewModel {

    func preparedPlaylist(for playlist: PlaylistItem, pin: String?) async throws -> PreparedPlaylist? {
        guard let source = PlaylistSourceSnapshot(playlist),
              let state = try PlaylistSettingsItem.state(for: playlist, in: databaseService.mainContext) else {
            return nil
        }

        let prepared = try await playlistAddService.preparePlaylist(
            from: source,
            cachedData: state.data,
            pin: pin,
            progress: { _, _ in }
        )
        if state.data != prepared.data {
            state.data = prepared.data
            try databaseService.mainContext.save()
        }
        return prepared
    }
}
