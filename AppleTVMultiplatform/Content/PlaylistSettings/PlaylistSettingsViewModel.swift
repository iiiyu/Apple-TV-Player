
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
    private var state: PlaylistSettingsItem?

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
    // Pin entered in the shared decrypt sheets (pin disable / guide / playlist
    // update), needed to re-encrypt after updating an encrypted playlist.
    var decryptPin = ""
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
        state = try? PlaylistSettingsItem.state(for: identity, in: databaseService.mainContext)
        order = state?.orderType ?? .none
        pinEnabled = playlist?.encrypted ?? false
        infoLocked = playlist?.encrypted ?? false
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
        state?.orderType = order
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
            do {
                guard let preparedPlaylist = try await preparedPlaylist(for: playlist, pin: nil) else {
                    return false
                }
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
            do {
                guard let preparedCachedPlaylist = try await preparedPlaylist(for: playlist, pin: nil) else {
                    return false
                }
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
            decryptPin = ""
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
        // An encrypted playlist must be re-encrypted on write, otherwise the
        // stored data would be plaintext while the encrypted flag stays true
        // and the next decryption would fail forever.
        var pin: String?
        if playlist.encrypted {
            pin = normalizedInfo(decryptPin)
            guard pin != nil else {
                self.error = .init(error: String(localized: "Enter the passcode to update an encrypted playlist."))
                return false
            }
        }
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
            pin: pin,
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
        let restoredUpdatedPlaylist = try await playlistAddService.restorePlaylist(preparedUpdatedPlaylist, pin: pin)
        // Refresh the cache under the stored identity: `preparePlaylist` stamps
        // a fresh date and a cache entry keyed by it would never be read again,
        // leaving the channel list stale after the update.
        let refreshContent = PlaylistItem.Content(
            identity: content.identity,
            url: restoredUpdatedPlaylist.url,
            data: restoredUpdatedPlaylist.data,
            isStoredInMemoryOnly: restoredUpdatedPlaylist.isStoredInMemoryOnly
        )
        // Update cache with new playlist + update program guide + update images.
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
            // In case updated playlist is empty, return back to old one.
            logger.info("Recover playlist back as updated is empty or broken", private: identity)
            _ = try await playlistService.playlists(
                for: content, reloadPlaylist: true, progress: { _, _ in }
            )
            return false
        }
        // The url and salt must be written together with the data: with a pin
        // the prepared playlist is encrypted under a fresh salt.
        playlist.url = preparedUpdatedPlaylist.url
        playlist.icon = preparedUpdatedPlaylist.icon
        playlist.salt = preparedUpdatedPlaylist.salt
        playlist.encrypted = preparedUpdatedPlaylist.encrypted
        state?.data = preparedUpdatedPlaylist.data
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
              let data = state?.data else {
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
            state?.data = encryptedPlaylist.data
            playlist.salt = encryptedPlaylist.salt
            playlist.encrypted = encryptedPlaylist.encrypted
            // Keep the info-edit pin in sync so a later save re-encrypts
            // with the pin that is actually in effect.
            retainedPin = pin
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
            state?.data = try await DataCompressor().compress(playlistDecryptedContent.data)
            playlist.url = playlistDecryptedContent.url
            playlist.salt = nil
            playlist.encrypted = false
            retainedPin = nil
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
              let prepared = try? await preparedPlaylist(for: playlist, pin: nil) else {
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
            return savePendingChanges()
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

    private func savePendingChanges() -> Bool {
        guard dataChanged else {
            return true
        }

        do {
            try databaseService.mainContext.save()
            snapshot = makeSnapshot()
            dataChanged = false
            return true
        } catch {
            databaseService.mainContext.rollback()
            logger.error(error)
            self.error = .init(error: error)
            return false
        }
    }

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
        if name != identity.name {
            let updatedIdentity = PlaylistItem.Identity(name: name, date: identity.date)
            changedIdentity = updatedIdentity
            state?.updateIdentity(updatedIdentity)
        }
        do {
            try databaseService.mainContext.save()
        } catch {
            databaseService.mainContext.rollback()
            logger.error(error)
            self.error = .init(error: error)
            return false
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
            playlist.icon = prepared.icon
            playlist.salt = prepared.salt
            playlist.encrypted = prepared.encrypted
            playlist.urlTvg = normalizedInfo(editedUrlTvg)
            playlist.urlImg = normalizedInfo(editedUrlImg)
            playlist.tvgLogo = normalizedInfo(editedTvgLogo)
            state?.data = prepared.data
            if name != identity.name {
                playlist.name = name
                let updatedIdentity = PlaylistItem.Identity(name: name, date: identity.date)
                changedIdentity = updatedIdentity
                state?.updateIdentity(updatedIdentity)
            }
            try databaseService.mainContext.save()
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
        guard !playlist.encrypted,
              let prepared = try? await preparedPlaylist(for: playlist, pin: nil) else {
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

    private func preparedPlaylist(for playlist: PlaylistItem, pin: String?) async throws -> PreparedPlaylist? {
        guard let source = PlaylistSourceSnapshot(playlist),
              let state else {
            return nil
        }

        let prepared = try await playlistAddService.preparePlaylist(
            from: source,
            cachedData: state.data,
            pin: pin,
            progress: { [weak self] _, step in
                Task { @MainActor in
                    switch step {
                    case .start, .complete:
                        break
                    default:
                        self?.progressText = .init(string: step.title)
                    }
                }
            }
        )
        if state.data != prepared.data {
            state.data = prepared.data
            try databaseService.mainContext.save()
        }
        return prepared
    }
}
