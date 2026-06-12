
import Foundation
import FactoryKit
import SwiftUI
import SwiftData

@Observable
final class PlaylistSettingsViewModel {

    @ObservationIgnored @Injected(\.databaseService) private var databaseService
    @ObservationIgnored @Injected(\.playlistService) private var playlistService
    @ObservationIgnored @Injected(\.playlistAddService) private var playlistAddService
    @ObservationIgnored @Injected(\.logger) private var logger

    let identity: PlaylistItem.Identity
    private var playlist: PlaylistItem?

    var order: PlaylistSettingsItem.StreamListOrder = .none
    var pinEnabled = false
    var snapshot: (PlaylistSettingsItem.StreamListOrder, Bool, Bool, Bool, Bool)?
    var dataChanged = false
    var showPinCodeDecryptView = false
    var showPinCodeEncryptView = false
    var showPinCodeDecryptProgramGuideView = false
    var showPinCodeDecryptPlaylistView = false
    var playlistDecryptedContent: PlaylistItem.Content?
    var pin: String = ""
    var progressText: StringIdentifiable?
    var error: LocalizableError?

    // Editable add-time playlist info.
    var editedName = ""
    var editedURL = ""
    var editedTvgLogo = ""
    var editedUrlTvg = ""
    var editedUrlImg = ""
    var showPinCodeDecryptInfoView = false
    var infoDecryptedContent: PlaylistItem.Content?
    var infoPin = ""
    private(set) var infoLocked = false
    private(set) var infoLoaded = false
    private(set) var changedIdentity: PlaylistItem.Identity?
    private(set) var didRefreshPlaylist = false
    @ObservationIgnored private var retainedPin: String?
    @ObservationIgnored private var unlockedContent: PlaylistItem.Content?
    @ObservationIgnored private var infoSnapshot: InfoSnapshot?

    private(set) var progress = false
    private var pinChangesProgrammatically = false
    private var didUpdateProgramGuide = false
    private var didUpdatePlaylist = false

    init(identity: PlaylistItem.Identity) {
        self.identity = identity
        let fetch = FetchDescriptor<PlaylistItem>()
        playlist = (try? databaseService.mainContext.fetch(fetch))?
            .first(where: { $0.identity == identity })
        order = playlist?.settings?.orderType ?? .none
        pinEnabled = playlist?.encrypted ?? false
        infoLocked = playlist?.encrypted ?? false
        if playlist?.settings == nil {
            playlist?.settings = PlaylistSettingsItem(order: nil)
        }
        snapshot = makeSnapshot()
    }

    private func updateDataChanged() {
        guard let snapshot else {
            return
        }
        dataChanged = snapshot != makeSnapshot()
    }

    private func makeSnapshot() -> (PlaylistSettingsItem.StreamListOrder, Bool, Bool, Bool, Bool) {
        (order, pinEnabled, snapshot?.2 ?? false, didUpdateProgramGuide, didUpdatePlaylist)
    }

    isolated deinit {
        logger.info("deinit of \(self)")
    }
}

// MARK: - Playlist order update
extension PlaylistSettingsViewModel {

    func onOrderChange() -> Bool {
        logger.info("Change order", private: identity)
        playlist?.settings?.orderType = order
        updateDataChanged()
        return true
    }
}

// MARK: - Playlist program guide update
extension PlaylistSettingsViewModel {
    func updateProgramGuide() async -> Bool {
        progress = true
        defer {
            progress = false
            updateDataChanged()
        }
        guard let playlist else {
            return false
        }
        logger.info("Update program guide for encrypted=\(playlist.encrypted)", private: identity)
        if playlist.encrypted {
            // Ask a user to enter pin to recover playlist raw data.
            logger.info("Show enter pin to decrypt playlist", private: identity)
            showPinCodeDecryptProgramGuideView = true
            return false
        } else {
            guard let preparedPlaylist = PreparedPlaylist(playlist) else {
                return false
            }
            do {
                // Recover playlist raw data without pin.
                let content = try await playlistAddService.restorePlaylist(preparedPlaylist, pin: nil).content
                didUpdateProgramGuide = try await updateProgramGuide(content)
                return didUpdateProgramGuide
            } catch {
                logger.error(error)
                self.error = .init(error: error)
                return false
            }
        }
    }

    func updateProgramGuideDecrypted() async -> Bool {
        progress = true
        defer {
            progress = false
            playlistDecryptedContent = nil
            updateDataChanged()
        }
        guard let playlist, playlist.encrypted, let content = playlistDecryptedContent else {
            return false
        }
        do {
            didUpdateProgramGuide = try await updateProgramGuide(content)
            return didUpdateProgramGuide
        } catch {
            self.error = .init(error: error)
            logger.error(error)
            return false
        }
    }

    private func updateProgramGuide(_ content: PlaylistItem.Content) async throws -> Bool {
        defer {
            progressText = nil
        }
        logger.info("Updating program guide", private: identity)
        _ = try await playlistService.playlists(for: content, reloadProgramGuide: true, progress: { [weak self] _, step in
            Task { @MainActor in
                switch step {
                case .start, .complete:
                    break
                default:
                    self?.progressText = .init(string: step.title)
                }
            }
        })
        return true
    }
}

// MARK: - Playlist update
extension PlaylistSettingsViewModel {

    func updatePlaylist() async -> Bool {
        progress = true
        defer {
            progress = false
            updateDataChanged()
        }
        guard let playlist else {
            return false
        }
        logger.info("Update playlist for encrypted=\(playlist.encrypted)", private: identity)
        if playlist.encrypted {
            // Ask a user to enter pin to recover playlist raw data.
            logger.info("Show enter pin to decrypt playlist", private: identity)
            showPinCodeDecryptPlaylistView = true
            return false
        } else {
            guard let preparedCachedPlaylist = PreparedPlaylist(playlist) else {
                return false
            }
            do {
                // Recover playlist raw data without pin.
                let content = try await playlistAddService.restorePlaylist(preparedCachedPlaylist, pin: nil).content
                didUpdatePlaylist = try await updatePlaylist(playlist: playlist, content: content)
                return didUpdatePlaylist
            } catch {
                logger.error(error)
                self.error = .init(error: error)
                return false
            }
        }
    }

    func updatePlaylistDecrypted() async -> Bool {
        progress = true
        defer {
            progress = false
            playlistDecryptedContent = nil
            updateDataChanged()
        }
        guard let playlist, let content = playlistDecryptedContent else {
            return false
        }
        do {
            didUpdatePlaylist = try await updatePlaylist(playlist: playlist, content: content)
            return didUpdatePlaylist
        } catch {
            self.error = .init(error: error)
            logger.error(error)
            return false
        }
    }

    private func updatePlaylist(playlist: PlaylistItem, content: PlaylistItem.Content) async throws -> Bool {
        defer {
            progressText = nil
        }
        logger.info("Updating playlist", private: identity)
        // Read cached playlist.
        let playlistsCache = try await playlistService.playlists(
            for: content, reloadPlaylist: false, progress: { _, _ in }
        )
        guard let mainPlaylist = playlistsCache.first else {
            return false
        }
        // Create new playlist from cached playlist url and merge `EXTM3U` with cached one
        // as `urlTvg`, `urlImg` and `tvgLogo` might be absent in source url, at the same time
        // might be presented in cached version via `Add Playlist` flow.
        let preparedUpdatedPlaylist = try await playlistAddService.preparePlaylist(
            name: content.identity.name,
            urlString: String(data: content.url, encoding: .utf8)!,
            pin: nil,
            urlTvg: mainPlaylist.tvgURL ?? mainPlaylist.xTvgURL,
            urlImg: mainPlaylist.imageURL,
            tvgLogo: mainPlaylist.tvgLogo
        ){ [weak self]  _, step in
            switch step {
            case .start, .complete:
                break
            default:
                Task { @MainActor in
                    self?.progressText = .init(string: step.title)
                }
            }
        }
        let newContent = try await playlistAddService.restorePlaylist(preparedUpdatedPlaylist, pin: nil).content
        // Update cache with new playlist + update program guide + update images.
        let playlists = try await playlistService.playlists(for: newContent, reloadPlaylist: true, progress: { [weak self] _, step in
            Task { @MainActor in
                switch step {
                case .start, .complete:
                    break
                default:
                    self?.progressText = .init(string: step.title)
                }
            }
        })
        guard !playlists.filter({ !$0.streams.isEmpty }).isEmpty else {
            // In case updated playlist is empty, return back to old one.
            logger.info("Recover playlist back as updated is empty or broken", private: identity)
            _ = try await playlistService.playlists(
                for: content, reloadPlaylist: true, progress: { _, _ in }
            )
            return false
        }
        playlist.data = preparedUpdatedPlaylist.data
        return true
    }
}

// MARK: - Playlist pin update
extension PlaylistSettingsViewModel {

    func onPinChange() {
        guard !pinChangesProgrammatically else {
            pinChangesProgrammatically = false
            return
        }
        progress = true
        defer {
            progress = false
        }
        if pinEnabled {
            logger.info("Show enter pin to encrypt", private: identity)
            showPinCodeEncryptView = true
        } else {
            logger.info("Show enter pin to decrypt", private: identity)
            showPinCodeDecryptView = true
        }
        pinChangesProgrammatically = false
    }

    func onEncrypt() async -> Bool {
        logger.info("Start encryption", private: identity)
        progress = true
        var didEncrypt = false
        defer {
            if !didEncrypt {
                pinChangesProgrammatically = true
                pin = ""
                pinEnabled = false
            }
            progress = false
            updateDataChanged()
        }
        guard !pin.isEmpty else {
            return false
        }
        guard let playlist,
              let date = playlist.date,
              let name = playlist.name,
              let url = playlist.url,
              let data = playlist.data else {
            return false
        }
        assert(!playlist.encrypted)
        do {
            let preparedPlaylist = PreparedPlaylist(
                name: name,
                date: date,
                icon: playlist.icon,
                url: url,
                data: data,
                salt: nil,
                encrypted: playlist.encrypted
            )
            let encryptedPlaylist = try await playlistAddService.encryptPlaylist(preparedPlaylist, pin: pin)
            playlist.url = encryptedPlaylist.url
            playlist.data = encryptedPlaylist.data
            playlist.salt = encryptedPlaylist.salt
            playlist.encrypted = encryptedPlaylist.encrypted
            didEncrypt = true
            logger.info("Complete encryption", private: identity)
        } catch {
            logger.error(error)
            return false
        }
        return true
    }

    func onDecrypt() async -> Bool {
        logger.info("Start decryption", private: identity)
        progress = true
        defer {
            progress = false
            playlistDecryptedContent = nil
            updateDataChanged()
        }
        guard let playlistDecryptedContent, let playlist else {
            pinChangesProgrammatically = true
            pinEnabled = true
            return false
        }
        do {
            playlist.data = try await DataCompressor().compress(playlistDecryptedContent.data)
            playlist.url = playlistDecryptedContent.url
            playlist.salt = nil
            playlist.encrypted = false
            logger.info("Complete decryption", private: identity)
        } catch {
            logger.error(error)
            return false
        }
        return true
    }
}

// MARK: - Playlist info view/edit
extension PlaylistSettingsViewModel {

    struct InfoSnapshot: Equatable {
        let name: String
        let url: String
        let tvgLogo: String
        let urlTvg: String
        let urlImg: String
    }

    var infoChanged: Bool {
        guard infoLoaded, let infoSnapshot else {
            return false
        }
        return infoSnapshot != makeInfoSnapshot()
    }

    func loadInfo() async {
        guard !infoLoaded, !infoLocked, let playlist,
              let prepared = PreparedPlaylist(playlist) else {
            return
        }
        do {
            let content = try await playlistAddService.restorePlaylist(prepared, pin: nil).content
            await populateInfo(from: content)
        } catch {
            logger.error(error)
            self.error = .init(error: error)
        }
    }

    func onShowInfoUnlock() {
        logger.info("Show enter pin to view playlist info", private: identity)
        showPinCodeDecryptInfoView = true
    }

    func onInfoUnlock() async {
        defer {
            infoDecryptedContent = nil
        }
        guard let content = infoDecryptedContent else {
            // The pin sheet was cancelled.
            infoPin = ""
            return
        }
        retainedPin = infoPin
        unlockedContent = content
        infoLocked = false
        await populateInfo(from: content)
    }

    func saveInfo() async -> Bool {
        guard infoChanged else {
            return true
        }
        guard let playlist else {
            return false
        }
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = editedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return fail(String(localized: "The playlist name cannot be empty."))
        }
        guard !urlString.isEmpty else {
            return fail(String(localized: "The playlist URL cannot be empty."))
        }
        let current = makeInfoSnapshot()
        let nameOnly = current.url == infoSnapshot?.url
            && current.tvgLogo == infoSnapshot?.tvgLogo
            && current.urlTvg == infoSnapshot?.urlTvg
            && current.urlImg == infoSnapshot?.urlImg
        if nameOnly {
            return rename(playlist, to: name)
        }
        return await redownload(playlist, name: name, urlString: urlString)
    }

    // MARK: - Private

    private func populateInfo(from content: PlaylistItem.Content) async {
        editedName = identity.name
        editedURL = String(data: content.url, encoding: .utf8) ?? ""
        let mainPlaylist = try? await PlaylistParser(data: content.data).parse().first
        if let mainPlaylist {
            editedUrlTvg = mainPlaylist.tvgURL ?? mainPlaylist.xTvgURL ?? ""
            editedUrlImg = mainPlaylist.imageURL ?? ""
            editedTvgLogo = mainPlaylist.tvgLogo ?? ""
        }
        infoSnapshot = makeInfoSnapshot()
        infoLoaded = true
    }

    private func rename(_ playlist: PlaylistItem, to name: String) -> Bool {
        logger.info("Rename playlist", private: identity)
        playlist.name = name
        do {
            try databaseService.mainContext.save()
        } catch {
            databaseService.mainContext.rollback()
            logger.error(error)
            self.error = .init(error: error)
            return false
        }
        if name != identity.name {
            changedIdentity = .init(name: name, date: identity.date)
        }
        infoSnapshot = makeInfoSnapshot()
        return true
    }

    private func redownload(_ playlist: PlaylistItem, name: String, urlString: String) async -> Bool {
        progress = true
        defer {
            progress = false
            progressText = nil
        }
        var pin: String?
        if playlist.encrypted {
            pin = retainedPin ?? normalizedInfo(self.pin)
            guard pin != nil else {
                return fail(String(localized: "Enter the passcode to change an encrypted playlist."))
            }
        }
        logger.info("Rebuild playlist from edited info", private: identity)
        do {
            let prepared = try await playlistAddService.preparePlaylist(
                name: name,
                urlString: urlString,
                pin: pin,
                urlTvg: normalizedInfo(editedUrlTvg),
                urlImg: normalizedInfo(editedUrlImg),
                tvgLogo: normalizedInfo(editedTvgLogo)
            ) { [weak self] _, step in
                Task { @MainActor in
                    switch step {
                    case .start, .complete:
                        break
                    default:
                        self?.progressText = .init(string: step.title)
                    }
                }
            }
            let restored = try await playlistAddService.restorePlaylist(prepared, pin: pin)
            // Refresh the service cache under the stored identity: `prepared.date`
            // is a fresh Date() and a cache entry keyed by it would never be read.
            let refreshContent = PlaylistItem.Content(
                identity: identity,
                url: restored.url,
                data: restored.data,
                isStoredInMemoryOnly: restored.isStoredInMemoryOnly
            )
            let playlists = try await playlistService.playlists(for: refreshContent, reloadPlaylist: true, progress: { [weak self] _, step in
                Task { @MainActor in
                    switch step {
                    case .start, .complete:
                        break
                    default:
                        self?.progressText = .init(string: step.title)
                    }
                }
            })
            guard !playlists.filter({ !$0.streams.isEmpty }).isEmpty else {
                logger.info("Recover playlist back as edited one is empty or broken", private: identity)
                if let old = await oldContent(of: playlist) {
                    _ = try? await playlistService.playlists(for: old, reloadPlaylist: true, progress: { _, _ in })
                }
                return fail(String(localized: "The URL does not contain a valid playlist."))
            }
            playlist.url = prepared.url
            playlist.data = prepared.data
            playlist.icon = prepared.icon
            playlist.salt = prepared.salt
            playlist.encrypted = prepared.encrypted
            if name != identity.name {
                playlist.name = name
            }
            try databaseService.mainContext.save()
            if name != identity.name {
                changedIdentity = .init(name: name, date: identity.date)
            }
            didRefreshPlaylist = true
            infoSnapshot = makeInfoSnapshot()
            return true
        } catch {
            databaseService.mainContext.rollback()
            logger.error(error)
            self.error = .init(error: error)
            return false
        }
    }

    private func oldContent(of playlist: PlaylistItem) async -> PlaylistItem.Content? {
        if let unlockedContent {
            return unlockedContent
        }
        guard !playlist.encrypted, let prepared = PreparedPlaylist(playlist) else {
            return nil
        }
        return try? await playlistAddService.restorePlaylist(prepared, pin: nil).content
    }

    private func makeInfoSnapshot() -> InfoSnapshot {
        InfoSnapshot(
            name: editedName.trimmingCharacters(in: .whitespacesAndNewlines),
            url: editedURL.trimmingCharacters(in: .whitespacesAndNewlines),
            tvgLogo: editedTvgLogo.trimmingCharacters(in: .whitespacesAndNewlines),
            urlTvg: editedUrlTvg.trimmingCharacters(in: .whitespacesAndNewlines),
            urlImg: editedUrlImg.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func normalizedInfo(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fail(_ message: String) -> Bool {
        self.error = .init(error: message)
        return false
    }
}
