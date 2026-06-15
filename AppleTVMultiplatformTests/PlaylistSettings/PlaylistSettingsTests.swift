import Foundation
import SwiftData
import Testing
import FactoryKit
import FactoryTesting
@testable import HiPlayer

@Suite(.container)
struct PlaylistSettingsTests {

    @Test func settingsPersistCloudKitSafePayloadsAndInverseRelationship() throws {
        let identity = makeIdentity()
        let settings = PlaylistSettingsItem(order: PlaylistSettingsItem.StreamListOrder.none.rawValue)
        let viewedAt = Date(timeIntervalSince1970: 1_234)
        settings.views = ["stream-hmac": 3]
        settings.recent = ["stream-hmac": viewedAt]
        settings.encrypted = ["stream-hmac": "encrypted-title"]
        settings.favorites = ["stream-hmac"]
        let playlist = makePlaylistItem(identity: identity, encrypted: true, settings: settings)
        let database = try makeDatabaseService(items: [playlist])

        let storedPlaylist = try fetchPlaylist(from: database, identity: identity)
        let storedSettings = try #require(storedPlaylist.settings)

        #expect(storedSettings.identity == storedPlaylist.identity)
        #expect(storedSettings.viewsData != nil)
        #expect(storedSettings.recentData != nil)
        #expect(storedSettings.encryptedData != nil)
        #expect(storedSettings.favoritesData != nil)
        #expect(storedSettings.views == ["stream-hmac": 3])
        #expect(storedSettings.recent == ["stream-hmac": viewedAt])
        #expect(storedSettings.encrypted == ["stream-hmac": "encrypted-title"])
        #expect(storedSettings.favorites == ["stream-hmac"])

        let exported = try JSONEncoder().encode(storedSettings)
        let imported = try JSONDecoder().decode(PlaylistSettingsItem.self, from: exported)

        #expect(imported.views == storedSettings.views)
        #expect(imported.recent == storedSettings.recent)
        #expect(imported.encrypted == storedSettings.encrypted)
        #expect(imported.favorites == storedSettings.favorites)
    }

    @Test func initCreatesMissingSettingsAndUsesStoredEncryptionState() throws {
        let identity = makeIdentity()
        let playlist = makePlaylistItem(
            identity: identity,
            encrypted: true,
            settings: nil
        )
        let database = try makeDatabaseService(items: [playlist])
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        let storedPlaylist = try fetchPlaylist(from: database, identity: identity)

        #expect(viewModel.order == .none)
        #expect(viewModel.pinEnabled == true)
        #expect(viewModel.dataChanged == false)
        #expect(viewModel.snapshot != nil)
        #expect(storedPlaylist.settings != nil)
        #expect(storedPlaylist.settings?.order == nil)
    }

    @Test func onOrderChangeUpdatesStoredSettingsAndDataChanged() throws {
        let identity = makeIdentity()
        let playlist = makePlaylistItem(
            identity: identity,
            encrypted: false,
            settings: PlaylistSettingsItem(order: PlaylistSettingsItem.StreamListOrder.none.rawValue)
        )
        let database = try makeDatabaseService(items: [playlist])
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.order = .descending

        #expect(viewModel.onOrderChange() == true)
        #expect(try fetchPlaylist(from: database, identity: identity).settings?.orderType == .descending)
        #expect(viewModel.dataChanged == true)

        viewModel.order = .none

        #expect(viewModel.onOrderChange() == true)
        #expect(
            try fetchPlaylist(from: database, identity: identity).settings?.orderType
                == PlaylistSettingsItem.StreamListOrder.none
        )
        #expect(viewModel.dataChanged == false)
    }

    @Test func updateProgramGuideShowsDecryptPromptForEncryptedPlaylist() async throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: true)
        ])
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)

        #expect(viewModel.showPinCodeDecryptProgramGuideView == false)
        
        let didUpdate = await viewModel.updateProgramGuide()

        #expect(didUpdate == false)
        #expect(viewModel.showPinCodeDecryptProgramGuideView == true)
        #expect(viewModel.progress == false)
        #expect(viewModel.dataChanged == false)
    }

    @Test func updateProgramGuideRestoresPlaylistAndReloadsGuide() async throws {
        let identity = makeIdentity()
        let playlist = makePlaylistItem(identity: identity, encrypted: false)
        let database = try makeDatabaseService(items: [playlist])
        let initialPreparedPlaylist = try #require(PreparedPlaylist(playlist))
        let restoredPlaylist = makeRestoredPlaylist(
            identity: identity,
            urlString: "https://example.com/restored.m3u",
            data: Data("#EXTM3U restored".utf8)
        )
        let playlistAddService = MockPlaylistAddService()
        playlistAddService.restoreHandler = { preparedPlaylist, pin in
            #expect(preparedPlaylist == initialPreparedPlaylist)
            #expect(pin == nil)
            return restoredPlaylist
        }
        let playlistService = MockPlaylistService()
        playlistService.reloadProgramGuideHandler = { content, reloadProgramGuide in
            self.expectContent(content, equals: restoredPlaylist.content)
            #expect(reloadProgramGuide == true)
            return []
        }
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { playlistAddService }
        Container.shared.playlistService.register { playlistService }

        let viewModel = PlaylistSettingsViewModel(identity: identity)

        let didUpdate = await viewModel.updateProgramGuide()

        #expect(didUpdate == true)
        #expect(viewModel.progress == false)
        #expect(viewModel.progressText == nil)
        #expect(viewModel.error == nil)
        #expect(viewModel.dataChanged == true)
        #expect(playlistAddService.restoreCalls.count == 1)
        #expect(playlistService.reloadProgramGuideCalls.count == 1)
    }

    @Test func updateProgramGuideDecryptedUsesTemporaryContentAndClearsIt() async throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: true)
        ])
        let decryptedContent = makeContent(
            identity: identity,
            urlString: "https://example.com/decrypted.m3u",
            data: Data("#EXTM3U decrypted".utf8),
            isStoredInMemoryOnly: true
        )
        let playlistService = MockPlaylistService()
        playlistService.reloadProgramGuideHandler = { content, reloadProgramGuide in
            self.expectContent(content, equals: decryptedContent)
            #expect(reloadProgramGuide == true)
            return []
        }
        Container.shared.databaseService.register { database }
        Container.shared.playlistService.register { playlistService }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.playlistDecryptedContent = decryptedContent

        let didUpdate = await viewModel.updateProgramGuideDecrypted()

        #expect(didUpdate == true)
        #expect(viewModel.playlistDecryptedContent == nil)
        #expect(viewModel.progress == false)
        #expect(viewModel.dataChanged == true)
        #expect(viewModel.error == nil)
        #expect(playlistService.reloadProgramGuideCalls.count == 1)
    }

    @Test func updatePlaylistShowsDecryptPromptForEncryptedPlaylist() async throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: true)
        ])
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        
        #expect(viewModel.showPinCodeDecryptPlaylistView == false)

        let didUpdate = await viewModel.updatePlaylist()

        #expect(didUpdate == false)
        #expect(viewModel.showPinCodeDecryptPlaylistView == true)
        #expect(viewModel.progress == false)
        #expect(viewModel.dataChanged == false)
    }

    @Test func updatePlaylistRefreshesStoredDataUsingMergedHeaderValues() async throws {
        let identity = makeIdentity()
        let playlist = makePlaylistItem(identity: identity, encrypted: false)
        let originalData = try #require(playlist.data)
        let database = try makeDatabaseService(items: [playlist])
        let initialPreparedPlaylist = try #require(PreparedPlaylist(playlist))
        let restoredCachedPlaylist = makeRestoredPlaylist(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: Data("#EXTM3U cached".utf8)
        )
        let cachedPlaylist = makePlaylist(
            tvgURL: "https://example.com/program-guide.xml",
            imageURL: "https://example.com/images",
            xTvgURL: "https://example.com/fallback-guide.xml",
            tvgLogo: "https://example.com/logo.png",
            streams: [makeStream(title: "Cached")]
        )
        let preparedUpdatedPlaylist = makePreparedPlaylist(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: Data("updated-prepared-data".utf8),
            encrypted: false
        )
        let restoredUpdatedPlaylist = makeRestoredPlaylist(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: Data("#EXTM3U refreshed".utf8)
        )
        let playlistAddService = MockPlaylistAddService()
        playlistAddService.prepareHandler = { name, urlString, pin, urlTvg, urlImg, tvgLogo in
            #expect(name == identity.name)
            #expect(urlString == "https://example.com/original.m3u")
            #expect(pin == nil)
            #expect(urlTvg == cachedPlaylist.tvgURL)
            #expect(urlImg == cachedPlaylist.imageURL)
            #expect(tvgLogo == cachedPlaylist.tvgLogo)
            return preparedUpdatedPlaylist
        }
        playlistAddService.restoreHandler = { preparedPlaylist, pin in
            #expect(pin == nil)
            if preparedPlaylist == initialPreparedPlaylist {
                return restoredCachedPlaylist
            }
            if preparedPlaylist == preparedUpdatedPlaylist {
                return restoredUpdatedPlaylist
            }
            Issue.record("Unexpected prepared playlist in restoreHandler.")
            throw MockFailure.unexpectedCall
        }
        let playlistService = MockPlaylistService()
        playlistService.reloadPlaylistHandler = { content, reloadPlaylist in
            if playlistService.reloadPlaylistCalls.count == 1 {
                self.expectContent(content, equals: restoredCachedPlaylist.content)
                #expect(reloadPlaylist == false)
                return [cachedPlaylist]
            }

            self.expectContent(content, equals: restoredUpdatedPlaylist.content)
            #expect(reloadPlaylist == true)
            return [self.makePlaylist(streams: [self.makeStream(title: "Updated")])]
        }
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { playlistAddService }
        Container.shared.playlistService.register { playlistService }

        let viewModel = PlaylistSettingsViewModel(identity: identity)

        let didUpdate = await viewModel.updatePlaylist()
        let storedPlaylist = try fetchPlaylist(from: database, identity: identity)
        let storedState = try fetchState(from: database, identity: identity)

        #expect(didUpdate == true)
        #expect(storedState.data == preparedUpdatedPlaylist.data)
        #expect(storedState.data != originalData)
        #expect(viewModel.progress == false)
        #expect(viewModel.progressText == nil)
        #expect(viewModel.dataChanged == true)
        #expect(playlistAddService.prepareCalls.count == 1)
        #expect(playlistAddService.restoreCalls.count == 2)
        #expect(playlistService.reloadPlaylistCalls.count == 2)
    }

    @Test func updatePlaylistRecoversOriginalPlaylistWhenRefreshIsEmpty() async throws {
        let identity = makeIdentity()
        let playlist = makePlaylistItem(identity: identity, encrypted: false)
        let originalData = try #require(playlist.data)
        let database = try makeDatabaseService(items: [playlist])
        let initialPreparedPlaylist = try #require(PreparedPlaylist(playlist))
        let restoredCachedPlaylist = makeRestoredPlaylist(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: Data("#EXTM3U cached".utf8)
        )
        let preparedUpdatedPlaylist = makePreparedPlaylist(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: Data("broken-update".utf8),
            encrypted: false
        )
        let restoredUpdatedPlaylist = makeRestoredPlaylist(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: Data("#EXTM3U broken".utf8)
        )
        let playlistAddService = MockPlaylistAddService()
        playlistAddService.prepareHandler = { _, _, _, _, _, _ in
            preparedUpdatedPlaylist
        }
        playlistAddService.restoreHandler = { preparedPlaylist, pin in
            #expect(pin == nil)
            if preparedPlaylist == initialPreparedPlaylist {
                return restoredCachedPlaylist
            }
            if preparedPlaylist == preparedUpdatedPlaylist {
                return restoredUpdatedPlaylist
            }
            Issue.record("Unexpected prepared playlist in restoreHandler.")
            throw MockFailure.unexpectedCall
        }
        let playlistService = MockPlaylistService()
        playlistService.reloadPlaylistHandler = { content, reloadPlaylist in
            switch playlistService.reloadPlaylistCalls.count {
            case 1:
                self.expectContent(content, equals: restoredCachedPlaylist.content)
                #expect(reloadPlaylist == false)
                return [self.makePlaylist(streams: [self.makeStream(title: "Cached")])]
            case 2:
                self.expectContent(content, equals: restoredUpdatedPlaylist.content)
                #expect(reloadPlaylist == true)
                return [self.makePlaylist(streams: [])]
            case 3:
                self.expectContent(content, equals: restoredCachedPlaylist.content)
                #expect(reloadPlaylist == true)
                return [self.makePlaylist(streams: [self.makeStream(title: "Recovered")])]
            default:
                Issue.record("Unexpected playlist reload call count.")
                throw MockFailure.unexpectedCall
            }
        }
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { playlistAddService }
        Container.shared.playlistService.register { playlistService }

        let viewModel = PlaylistSettingsViewModel(identity: identity)

        let didUpdate = await viewModel.updatePlaylist()
        let storedPlaylist = try fetchPlaylist(from: database, identity: identity)

        #expect(didUpdate == false)
        #expect(storedPlaylist.data == originalData)
        #expect(viewModel.progress == false)
        #expect(viewModel.dataChanged == false)
        #expect(playlistService.reloadPlaylistCalls.count == 3)
    }

    @Test func onPinChangeShowsEncryptPromptWhenEnablingPin() throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: false)
        ])
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.pinEnabled = true

        viewModel.onPinChange()

        #expect(viewModel.showPinCodeEncryptView == true)
        #expect(viewModel.showPinCodeDecryptView == false)
        #expect(viewModel.progress == false)
    }

    @Test func onPinChangeShowsDecryptPromptWhenDisablingPin() throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: true)
        ])
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.pinEnabled = false

        viewModel.onPinChange()

        #expect(viewModel.showPinCodeEncryptView == false)
        #expect(viewModel.showPinCodeDecryptView == true)
        #expect(viewModel.progress == false)
    }

    @Test func onEncryptStoresEncryptedPlaylist() async throws {
        let identity = makeIdentity()
        let playlist = makePlaylistItem(identity: identity, encrypted: false)
        let database = try makeDatabaseService(items: [playlist])
        let initialPreparedPlaylist = try #require(PreparedPlaylist(playlist))
        let encryptedPlaylist = makePreparedPlaylist(
            identity: identity,
            urlString: "encrypted-url",
            data: Data("encrypted-data".utf8),
            encrypted: true,
            salt: Data("salt".utf8)
        )
        let playlistAddService = MockPlaylistAddService()
        playlistAddService.encryptHandler = { preparedPlaylist, pin in
            #expect(preparedPlaylist == initialPreparedPlaylist)
            #expect(pin == "1234")
            return encryptedPlaylist
        }
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { playlistAddService }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.pinEnabled = true
        viewModel.pin = "1234"

        let didEncrypt = await viewModel.onEncrypt()
        let storedPlaylist = try fetchPlaylist(from: database, identity: identity)
        let storedState = try fetchState(from: database, identity: identity)

        #expect(didEncrypt == true)
        #expect(storedPlaylist.url == encryptedPlaylist.url)
        #expect(storedState.data == encryptedPlaylist.data)
        #expect(storedPlaylist.salt == encryptedPlaylist.salt)
        #expect(storedPlaylist.encrypted == true)
        #expect(viewModel.progress == false)
        #expect(viewModel.dataChanged == true)
        #expect(playlistAddService.encryptCalls.count == 1)
    }

    @Test func onEncryptRollsBackPinStateWhenPinIsMissing() async throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: false)
        ])
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.pinEnabled = true
        viewModel.pin = ""

        let didEncrypt = await viewModel.onEncrypt()

        #expect(didEncrypt == false)
        #expect(viewModel.pin == "")
        #expect(viewModel.pinEnabled == false)
        #expect(viewModel.progress == false)
        #expect(viewModel.dataChanged == false)
    }

    @Test func onDecryptStoresDecryptedPlaylistData() async throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: true)
        ])
        let decryptedContent = makeContent(
            identity: identity,
            urlString: "https://example.com/decrypted.m3u",
            data: Data("#EXTM3U plain".utf8),
            isStoredInMemoryOnly: false
        )
        let expectedCompressedData = try await DataCompressor().compress(decryptedContent.data)
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.pinEnabled = false
        viewModel.playlistDecryptedContent = decryptedContent

        let didDecrypt = await viewModel.onDecrypt()
        let storedPlaylist = try fetchPlaylist(from: database, identity: identity)
        let storedState = try fetchState(from: database, identity: identity)

        #expect(didDecrypt == true)
        #expect(storedPlaylist.url == decryptedContent.url)
        #expect(storedState.data == expectedCompressedData)
        #expect(storedPlaylist.salt == nil)
        #expect(storedPlaylist.encrypted == false)
        #expect(viewModel.playlistDecryptedContent == nil)
        #expect(viewModel.progress == false)
        #expect(viewModel.dataChanged == true)
    }

    @Test func onDecryptReenablesPinWhenDecryptedContentIsMissing() async throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: true)
        ])
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.pinEnabled = false

        let didDecrypt = await viewModel.onDecrypt()

        #expect(didDecrypt == false)
        #expect(viewModel.pinEnabled == true)
        #expect(viewModel.progress == false)
        #expect(viewModel.playlistDecryptedContent == nil)
        #expect(viewModel.dataChanged == false)
    }

    @Test func updatePlaylistReencryptsEncryptedPlaylistAndRefreshesUnderStoredIdentity() async throws {
        let identity = makeIdentity()
        let playlist = makePlaylistItem(identity: identity, encrypted: true)
        let database = try makeDatabaseService(items: [playlist])
        let decryptedContent = makeContent(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: taggedPlaylistData,
            isStoredInMemoryOnly: true
        )
        let preparedUpdatedPlaylist = makePreparedPlaylist(
            identity: identity,
            urlString: "encrypted-url",
            data: Data("encrypted-updated".utf8),
            encrypted: true,
            salt: Data("fresh-salt".utf8)
        )
        // preparePlaylist stamps a fresh date in production: model that here to
        // prove the cache refresh still happens under the stored identity.
        let restoredUpdatedPlaylist = RestoredPlaylist(
            name: identity.name,
            date: Date(timeIntervalSince1970: 99_999),
            icon: "https://example.com/icon.png",
            url: Data("https://example.com/original.m3u".utf8),
            data: Data("#EXTM3U refreshed".utf8),
            isStoredInMemoryOnly: false
        )
        let playlistAddService = MockPlaylistAddService()
        playlistAddService.prepareHandler = { _, urlString, pin, _, _, _ in
            #expect(urlString == "https://example.com/original.m3u")
            #expect(pin == "1234")
            return preparedUpdatedPlaylist
        }
        playlistAddService.restoreHandler = { preparedPlaylist, pin in
            #expect(preparedPlaylist == preparedUpdatedPlaylist)
            #expect(pin == "1234")
            return restoredUpdatedPlaylist
        }
        let playlistService = MockPlaylistService()
        playlistService.reloadPlaylistHandler = { content, reloadPlaylist in
            if playlistService.reloadPlaylistCalls.count == 1 {
                #expect(reloadPlaylist == false)
                return [self.makePlaylist(
                    tvgURL: "https://example.com/guide.xml",
                    streams: [self.makeStream(title: "Cached")]
                )]
            }
            // The refresh must be keyed by the stored identity, not the fresh
            // date stamped by preparePlaylist.
            #expect(content.identity == identity)
            #expect(content.data == restoredUpdatedPlaylist.data)
            #expect(reloadPlaylist == true)
            return [self.makePlaylist(streams: [self.makeStream(title: "Updated")])]
        }
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { playlistAddService }
        Container.shared.playlistService.register { playlistService }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.playlistDecryptedContent = decryptedContent
        viewModel.decryptPin = "1234"

        let didUpdate = await viewModel.updatePlaylistDecrypted()
        let storedPlaylist = try fetchPlaylist(from: database, identity: identity)
        let storedState = try fetchState(from: database, identity: identity)

        #expect(didUpdate == true)
        #expect(storedPlaylist.url == preparedUpdatedPlaylist.url)
        #expect(storedState.data == preparedUpdatedPlaylist.data)
        #expect(storedPlaylist.salt == preparedUpdatedPlaylist.salt)
        #expect(storedPlaylist.encrypted == true)
        #expect(viewModel.decryptPin == "")
        #expect(playlistService.reloadPlaylistCalls.count == 2)
    }

    @Test func updatePlaylistDecryptedFailsWithoutPin() async throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: true)
        ])
        let decryptedContent = makeContent(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: taggedPlaylistData,
            isStoredInMemoryOnly: true
        )
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { MockPlaylistAddService() }
        Container.shared.playlistService.register { MockPlaylistService() }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.playlistDecryptedContent = decryptedContent
        viewModel.decryptPin = ""

        let didUpdate = await viewModel.updatePlaylistDecrypted()

        #expect(didUpdate == false)
        #expect(viewModel.error != nil)
    }

    @Test func loadInfoPopulatesFieldsForPlainPlaylist() async throws {
        let identity = makeIdentity()
        let playlist = makePlaylistItem(identity: identity, encrypted: false)
        let database = try makeDatabaseService(items: [playlist])
        let initialPreparedPlaylist = try #require(PreparedPlaylist(playlist))
        let restoredPlaylist = makeRestoredPlaylist(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: taggedPlaylistData
        )
        let playlistAddService = MockPlaylistAddService()
        playlistAddService.restoreHandler = { preparedPlaylist, pin in
            #expect(preparedPlaylist == initialPreparedPlaylist)
            #expect(pin == nil)
            return restoredPlaylist
        }
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { playlistAddService }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        await viewModel.loadInfo()

        #expect(viewModel.editedName == identity.name)
        #expect(viewModel.editedURL == "https://example.com/original.m3u")
        #expect(viewModel.editedUrlTvg == "https://example.com/guide.xml")
        #expect(viewModel.editedUrlImg == "https://example.com/images")
        #expect(viewModel.editedTvgLogo == "https://example.com/logo.png")
        #expect(viewModel.infoLoaded == true)
        #expect(viewModel.infoLocked == false)
        #expect(viewModel.infoChanged == false)
        #expect(viewModel.dataChanged == false)
        #expect(playlistAddService.restoreCalls.count == 1)
    }

    @Test func loadInfoSkipsEncryptedPlaylist() async throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: true)
        ])
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { MockPlaylistAddService() }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        await viewModel.loadInfo()

        #expect(viewModel.infoLocked == true)
        #expect(viewModel.infoLoaded == false)
        #expect(viewModel.infoChanged == false)
    }

    @Test func onInfoUnlockPopulatesFieldsAndUnlocks() async throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: true)
        ])
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.infoDecryptedContent = makeContent(
            identity: identity,
            urlString: "https://example.com/secret.m3u",
            data: taggedPlaylistData,
            isStoredInMemoryOnly: true
        )
        viewModel.infoPin = "1234"
        await viewModel.onInfoUnlock()

        #expect(viewModel.infoLocked == false)
        #expect(viewModel.infoLoaded == true)
        #expect(viewModel.editedURL == "https://example.com/secret.m3u")
        #expect(viewModel.editedUrlTvg == "https://example.com/guide.xml")
        #expect(viewModel.infoDecryptedContent == nil)
        #expect(viewModel.infoChanged == false)
    }

    @Test func onInfoUnlockCancelledKeepsLockedState() async throws {
        let identity = makeIdentity()
        let database = try makeDatabaseService(items: [
            makePlaylistItem(identity: identity, encrypted: true)
        ])
        Container.shared.databaseService.register { database }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.infoPin = "1234"
        await viewModel.onInfoUnlock()

        #expect(viewModel.infoLocked == true)
        #expect(viewModel.infoLoaded == false)
        #expect(viewModel.infoPin == "")
    }

    @Test func infoChangedTracksEditsAgainstLoadedSnapshot() async throws {
        let identity = makeIdentity()
        let viewModel = try await makeLoadedViewModel(identity: identity).viewModel

        #expect(viewModel.infoChanged == false)

        viewModel.editedName = identity.name + "  "
        #expect(viewModel.infoChanged == false)

        viewModel.editedName = "Other Name"
        #expect(viewModel.infoChanged == true)

        viewModel.editedName = identity.name
        #expect(viewModel.infoChanged == false)
    }

    @Test func saveInfoRenamesWithoutRedownload() async throws {
        let identity = makeIdentity()
        let loaded = try await makeLoadedViewModel(identity: identity)
        let viewModel = loaded.viewModel
        let originalData = try fetchPlaylist(from: loaded.database, identity: identity).data

        viewModel.editedName = "Renamed"
        let saved = await viewModel.saveInfo()
        let storedPlaylist = try #require(
            loaded.database.mainContext.fetch(FetchDescriptor<PlaylistItem>()).first
        )

        #expect(saved == true)
        #expect(storedPlaylist.name == "Renamed")
        #expect(storedPlaylist.date == identity.date)
        #expect(storedPlaylist.data == originalData)
        #expect(viewModel.changedIdentity == .init(name: "Renamed", date: identity.date))
        #expect(viewModel.didRefreshPlaylist == false)
        #expect(viewModel.infoChanged == false)
        #expect(loaded.playlistAddService.prepareCalls.isEmpty)
    }

    @Test func saveInfoRejectsEmptyNameOrURL() async throws {
        let identity = makeIdentity()
        let loaded = try await makeLoadedViewModel(identity: identity)
        let viewModel = loaded.viewModel

        viewModel.editedName = "   "
        #expect(await viewModel.saveInfo() == false)
        #expect(viewModel.error != nil)

        viewModel.error = nil
        viewModel.editedName = identity.name
        viewModel.editedURL = "   "
        #expect(await viewModel.saveInfo() == false)
        #expect(viewModel.error != nil)
        #expect(loaded.playlistAddService.prepareCalls.isEmpty)
    }

    @Test func saveInfoRedownloadsWhenURLOrTagsChange() async throws {
        let identity = makeIdentity()
        let loaded = try await makeLoadedViewModel(identity: identity)
        let viewModel = loaded.viewModel
        let preparedUpdatedPlaylist = makePreparedPlaylist(
            identity: identity,
            urlString: "https://example.com/new.m3u",
            data: Data("updated-prepared-data".utf8),
            encrypted: false
        )
        let restoredUpdatedPlaylist = makeRestoredPlaylist(
            identity: identity,
            urlString: "https://example.com/new.m3u",
            data: Data("#EXTM3U refreshed".utf8)
        )
        loaded.playlistAddService.prepareHandler = { name, urlString, pin, urlTvg, urlImg, tvgLogo in
            #expect(name == identity.name)
            #expect(urlString == "https://example.com/new.m3u")
            #expect(pin == nil)
            #expect(urlTvg == "https://example.com/new-guide.xml")
            #expect(urlImg == "https://example.com/images")
            #expect(tvgLogo == "https://example.com/logo.png")
            return preparedUpdatedPlaylist
        }
        loaded.playlistAddService.restoreHandler = { preparedPlaylist, pin in
            #expect(preparedPlaylist == preparedUpdatedPlaylist)
            #expect(pin == nil)
            return restoredUpdatedPlaylist
        }
        loaded.playlistService.reloadPlaylistHandler = { content, reloadPlaylist in
            // The cache must be refreshed under the stored identity, not the
            // freshly dated one from preparePlaylist.
            #expect(content.identity == identity)
            #expect(content.data == restoredUpdatedPlaylist.data)
            #expect(reloadPlaylist == true)
            return [self.makePlaylist(streams: [self.makeStream(title: "Updated")])]
        }

        viewModel.editedURL = "https://example.com/new.m3u"
        viewModel.editedUrlTvg = "https://example.com/new-guide.xml"
        let saved = await viewModel.saveInfo()
        let storedPlaylist = try fetchPlaylist(from: loaded.database, identity: identity)
        let storedState = try fetchState(from: loaded.database, identity: identity)

        #expect(saved == true)
        #expect(storedPlaylist.url == preparedUpdatedPlaylist.url)
        #expect(storedState.data == preparedUpdatedPlaylist.data)
        #expect(storedPlaylist.icon == preparedUpdatedPlaylist.icon)
        #expect(storedPlaylist.date == identity.date)
        #expect(viewModel.didRefreshPlaylist == true)
        #expect(viewModel.progress == false)
        #expect(loaded.playlistService.reloadPlaylistCalls.count == 1)
    }

    @Test func saveInfoReencryptsWithRetainedPin() async throws {
        let identity = makeIdentity()
        let playlist = makePlaylistItem(identity: identity, encrypted: true)
        let database = try makeDatabaseService(items: [playlist])
        let preparedEncryptedPlaylist = makePreparedPlaylist(
            identity: identity,
            urlString: "https://example.com/new.m3u",
            data: Data("encrypted-updated".utf8),
            encrypted: true,
            salt: Data("new-salt".utf8)
        )
        let restoredUpdatedPlaylist = makeRestoredPlaylist(
            identity: identity,
            urlString: "https://example.com/new.m3u",
            data: Data("#EXTM3U refreshed".utf8)
        )
        let playlistAddService = MockPlaylistAddService()
        playlistAddService.prepareHandler = { _, urlString, pin, _, _, _ in
            #expect(urlString == "https://example.com/new.m3u")
            #expect(pin == "1234")
            return preparedEncryptedPlaylist
        }
        playlistAddService.restoreHandler = { preparedPlaylist, pin in
            #expect(preparedPlaylist == preparedEncryptedPlaylist)
            #expect(pin == "1234")
            return restoredUpdatedPlaylist
        }
        let playlistService = MockPlaylistService()
        playlistService.reloadPlaylistHandler = { content, reloadPlaylist in
            #expect(content.identity == identity)
            #expect(reloadPlaylist == true)
            return [self.makePlaylist(streams: [self.makeStream(title: "Updated")])]
        }
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { playlistAddService }
        Container.shared.playlistService.register { playlistService }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        viewModel.infoDecryptedContent = makeContent(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: taggedPlaylistData,
            isStoredInMemoryOnly: true
        )
        viewModel.infoPin = "1234"
        await viewModel.onInfoUnlock()

        viewModel.editedURL = "https://example.com/new.m3u"
        let saved = await viewModel.saveInfo()
        let storedPlaylist = try fetchPlaylist(from: database, identity: identity)
        let storedState = try fetchState(from: database, identity: identity)

        #expect(saved == true)
        #expect(storedPlaylist.salt == preparedEncryptedPlaylist.salt)
        #expect(storedPlaylist.encrypted == true)
        #expect(storedState.data == preparedEncryptedPlaylist.data)
    }

    @Test func saveInfoKeepsOldDataWhenDownloadFails() async throws {
        let identity = makeIdentity()
        let loaded = try await makeLoadedViewModel(identity: identity)
        let viewModel = loaded.viewModel
        let originalData = try fetchPlaylist(from: loaded.database, identity: identity).data
        loaded.playlistAddService.prepareHandler = { _, _, _, _, _, _ in
            throw MockFailure.unexpectedCall
        }

        viewModel.editedURL = "https://example.com/broken.m3u"
        let saved = await viewModel.saveInfo()
        let storedPlaylist = try fetchPlaylist(from: loaded.database, identity: identity)

        #expect(saved == false)
        #expect(storedPlaylist.data == originalData)
        #expect(storedPlaylist.name == identity.name)
        #expect(viewModel.error != nil)
        #expect(viewModel.progress == false)
        #expect(viewModel.didRefreshPlaylist == false)
    }

    @Test func saveInfoRecoversCacheWhenRefreshedPlaylistIsEmpty() async throws {
        let identity = makeIdentity()
        let loaded = try await makeLoadedViewModel(identity: identity)
        let viewModel = loaded.viewModel
        let originalData = try fetchPlaylist(from: loaded.database, identity: identity).data
        let preparedUpdatedPlaylist = makePreparedPlaylist(
            identity: identity,
            urlString: "https://example.com/new.m3u",
            data: Data("broken-update".utf8),
            encrypted: false
        )
        let restoredUpdatedPlaylist = makeRestoredPlaylist(
            identity: identity,
            urlString: "https://example.com/new.m3u",
            data: Data("#EXTM3U broken".utf8)
        )
        loaded.playlistAddService.prepareHandler = { _, _, _, _, _, _ in
            preparedUpdatedPlaylist
        }
        loaded.playlistAddService.restoreHandler = { preparedPlaylist, pin in
            #expect(pin == nil)
            if preparedPlaylist == preparedUpdatedPlaylist {
                return restoredUpdatedPlaylist
            }
            // Recovery path restores the stored playlist.
            return self.makeRestoredPlaylist(
                identity: identity,
                urlString: "https://example.com/original.m3u",
                data: self.taggedPlaylistData
            )
        }
        let playlistService = loaded.playlistService
        playlistService.reloadPlaylistHandler = { content, reloadPlaylist in
            #expect(reloadPlaylist == true)
            if playlistService.reloadPlaylistCalls.count == 1 {
                #expect(content.identity == identity)
                #expect(content.data == restoredUpdatedPlaylist.data)
                return [self.makePlaylist(streams: [])]
            }
            #expect(content.data == self.taggedPlaylistData)
            return [self.makePlaylist(streams: [self.makeStream(title: "Recovered")])]
        }

        viewModel.editedURL = "https://example.com/new.m3u"
        let saved = await viewModel.saveInfo()
        let storedPlaylist = try fetchPlaylist(from: loaded.database, identity: identity)

        #expect(saved == false)
        #expect(storedPlaylist.data == originalData)
        #expect(viewModel.error != nil)
        #expect(viewModel.didRefreshPlaylist == false)
        #expect(playlistService.reloadPlaylistCalls.count == 2)
    }
}

private extension PlaylistSettingsTests {

    var taggedPlaylistData: Data {
        Data("""
        #EXTM3U url-tvg="https://example.com/guide.xml" url-img="https://example.com/images" tvg-logo="https://example.com/logo.png"
        #EXTINF:-1,Channel
        https://example.com/channel.m3u8
        """.utf8)
    }

    @MainActor
    func makeLoadedViewModel(
        identity: PlaylistItem.Identity
    ) async throws -> (
        viewModel: PlaylistSettingsViewModel,
        database: DatabaseService,
        playlistAddService: MockPlaylistAddService,
        playlistService: MockPlaylistService
    ) {
        let playlist = makePlaylistItem(identity: identity, encrypted: false)
        let database = try makeDatabaseService(items: [playlist])
        let restoredPlaylist = makeRestoredPlaylist(
            identity: identity,
            urlString: "https://example.com/original.m3u",
            data: taggedPlaylistData
        )
        let playlistAddService = MockPlaylistAddService()
        playlistAddService.restoreHandler = { _, _ in restoredPlaylist }
        let playlistService = MockPlaylistService()
        // All mocks must be registered before the view model is created,
        // @Injected resolves the services at init time.
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { playlistAddService }
        Container.shared.playlistService.register { playlistService }

        let viewModel = PlaylistSettingsViewModel(identity: identity)
        await viewModel.loadInfo()
        #expect(viewModel.infoLoaded == true)
        return (viewModel, database, playlistAddService, playlistService)
    }

    func makeIdentity(
        name: String = "Playlist",
        date: Date = Date(timeIntervalSince1970: 100)
    ) -> PlaylistItem.Identity {
        .init(name: name, date: date)
    }

    func makePlaylistItem(
        identity: PlaylistItem.Identity,
        encrypted: Bool,
        settings: PlaylistSettingsItem? = PlaylistSettingsItem(order: PlaylistSettingsItem.StreamListOrder.none.rawValue),
        urlString: String = "https://example.com/original.m3u",
        data: Data = Data("stored-playlist-data".utf8),
        salt: Data? = nil
    ) -> PlaylistItem {
        PlaylistItem(
            name: identity.name,
            date: identity.date,
            icon: "https://example.com/icon.png",
            url: Data(urlString.utf8),
            data: data,
            salt: salt ?? (encrypted ? Data("salt".utf8) : nil),
            encrypted: encrypted,
            settings: settings
        )
    }

    func makePreparedPlaylist(
        identity: PlaylistItem.Identity,
        urlString: String,
        data: Data,
        encrypted: Bool,
        salt: Data? = nil
    ) -> PreparedPlaylist {
        .init(
            name: identity.name,
            date: identity.date,
            icon: "https://example.com/icon.png",
            url: Data(urlString.utf8),
            data: data,
            salt: salt,
            encrypted: encrypted
        )
    }

    func makeRestoredPlaylist(
        identity: PlaylistItem.Identity,
        urlString: String,
        data: Data,
        isStoredInMemoryOnly: Bool = false
    ) -> RestoredPlaylist {
        .init(
            name: identity.name,
            date: identity.date,
            icon: "https://example.com/icon.png",
            url: Data(urlString.utf8),
            data: data,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
    }

    func makeContent(
        identity: PlaylistItem.Identity,
        urlString: String,
        data: Data,
        isStoredInMemoryOnly: Bool
    ) -> PlaylistItem.Content {
        .init(
            identity: identity,
            url: Data(urlString.utf8),
            data: data,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
    }

    func makePlaylist(
        tvgURL: String? = nil,
        imageURL: String? = nil,
        xTvgURL: String? = nil,
        tvgLogo: String? = nil,
        streams: [PlaylistParser.Stream] = []
    ) -> PlaylistParser.Playlist {
        .init(
            tvgURL: tvgURL,
            imageURL: imageURL,
            xTvgURL: xTvgURL,
            tvgLogo: tvgLogo,
            streams: streams
        )
    }

    func makeStream(title: String) -> PlaylistParser.Stream {
        .init(
            title: title,
            url: "https://example.com/\(title).m3u8",
            tvgLogo: nil,
            tvgID: nil,
            tvgName: nil,
            groupTitle: nil
        )
    }

    func makeDatabaseService(items: [PlaylistItem]) throws -> DatabaseService {
        let database = DatabaseService(isStoredInMemoryOnly: true)

        for item in items {
            database.mainContext.insert(item)
            if let identity = item.identity {
                let state = item.settings ?? PlaylistSettingsItem(order: nil)
                state.playlistName = identity.name
                state.playlistDate = identity.date
                state.data = item.data
                item.settings = state
                database.mainContext.insert(state)
            }
        }

        try database.mainContext.save()

        return database
    }

    func fetchPlaylist(
        from database: DatabaseService,
        identity: PlaylistItem.Identity
    ) throws -> PlaylistItem {
        try #require(
            database.mainContext.fetch(FetchDescriptor<PlaylistItem>())
                .first(where: { $0.identity == identity })
        )
    }

    func fetchState(
        from database: DatabaseService,
        identity: PlaylistItem.Identity
    ) throws -> PlaylistSettingsItem {
        let state = try PlaylistSettingsItem.state(
            for: identity,
            in: database.mainContext,
            create: false
        )
        return try #require(state)
    }

    func expectContent(_ actual: PlaylistItem.Content, equals expected: PlaylistItem.Content) {
        #expect(actual.identity == expected.identity)
        #expect(actual.url == expected.url)
        #expect(actual.data == expected.data)
        #expect(actual.isStoredInMemoryOnly == expected.isStoredInMemoryOnly)
    }
}

private enum MockFailure: LocalizedError {
    case unexpectedCall

    var errorDescription: String? {
        "Unexpected mock call."
    }
}

private final class MockPlaylistAddService: PlaylistAddServiceInterface, @unchecked Sendable {

    struct PrepareCall {
        let name: String?
        let urlString: String
        let pin: String?
        let urlTvg: String?
        let urlImg: String?
        let tvgLogo: String?
    }

    struct RestoreCall {
        let preparedPlaylist: PreparedPlaylist
        let pin: String?
    }

    struct EncryptCall {
        let preparedPlaylist: PreparedPlaylist
        let pin: String
    }

    var prepareHandler: (String?, String, String?, String?, String?, String?) async throws -> PreparedPlaylist = { _, _, _, _, _, _ in
        Issue.record("Unexpected preparePlaylist call.")
        throw MockFailure.unexpectedCall
    }
    var restoreHandler: (PreparedPlaylist, String?) async throws -> RestoredPlaylist = { _, _ in
        Issue.record("Unexpected restorePlaylist call.")
        throw MockFailure.unexpectedCall
    }
    var encryptHandler: (PreparedPlaylist, String) async throws -> PreparedPlaylist = { _, _ in
        Issue.record("Unexpected encryptPlaylist call.")
        throw MockFailure.unexpectedCall
    }

    private(set) var prepareCalls: [PrepareCall] = []
    private(set) var restoreCalls: [RestoreCall] = []
    private(set) var encryptCalls: [EncryptCall] = []

    func preparePlaylist(
        name: String?,
        urlString: String,
        pin: String?,
        urlTvg: String?,
        urlImg: String?,
        tvgLogo: String?,
        progress: ProgressHandler
    ) async throws -> PreparedPlaylist {
        prepareCalls.append(
            .init(
                name: name,
                urlString: urlString,
                pin: pin,
                urlTvg: urlTvg,
                urlImg: urlImg,
                tvgLogo: tvgLogo
            )
        )
        return try await prepareHandler(name, urlString, pin, urlTvg, urlImg, tvgLogo)
    }

    func preparePlaylist(
        from source: PlaylistSourceSnapshot,
        cachedData: Data?,
        pin: String?,
        progress: ProgressHandler
    ) async throws -> PreparedPlaylist {
        guard let cachedData else {
            return try await preparePlaylist(
                name: source.name,
                urlString: String(data: source.url, encoding: .utf8) ?? "",
                pin: pin,
                urlTvg: source.urlTvg,
                urlImg: source.urlImg,
                tvgLogo: source.tvgLogo,
                progress: progress
            )
        }
        return PreparedPlaylist(
            name: source.name,
            date: source.date,
            icon: source.icon,
            url: source.url,
            data: cachedData,
            salt: source.salt,
            encrypted: source.encrypted
        )
    }

    func encryptPlaylist(_ preparedPlaylist: PreparedPlaylist, pin: String) async throws -> PreparedPlaylist {
        encryptCalls.append(.init(preparedPlaylist: preparedPlaylist, pin: pin))
        return try await encryptHandler(preparedPlaylist, pin)
    }

    func restorePlaylist(_ preparedPlaylist: PreparedPlaylist, pin: String?) async throws -> RestoredPlaylist {
        restoreCalls.append(.init(preparedPlaylist: preparedPlaylist, pin: pin))
        return try await restoreHandler(preparedPlaylist, pin)
    }
}

private final class MockPlaylistService: PlaylistServiceInterface, @unchecked Sendable {

    struct ReloadProgramGuideCall {
        let content: PlaylistItem.Content
        let reloadProgramGuide: Bool
    }

    struct ReloadPlaylistCall {
        let content: PlaylistItem.Content
        let reloadPlaylist: Bool
    }

    var reloadProgramGuideHandler: (PlaylistItem.Content, Bool) async throws -> [PlaylistParser.Playlist] = { _, _ in
        Issue.record("Unexpected playlists(reloadProgramGuide:) call.")
        throw MockFailure.unexpectedCall
    }
    var reloadPlaylistHandler: (PlaylistItem.Content, Bool) async throws -> [PlaylistParser.Playlist] = { _, _ in
        Issue.record("Unexpected playlists(reloadPlaylist:) call.")
        throw MockFailure.unexpectedCall
    }

    private(set) var reloadProgramGuideCalls: [ReloadProgramGuideCall] = []
    private(set) var reloadPlaylistCalls: [ReloadPlaylistCall] = []

    func playlists(
        for content: PlaylistItem.Content,
        reloadProgramGuide: Bool,
        progress: @escaping ProgressHandler
    ) async throws -> [PlaylistParser.Playlist] {
        reloadProgramGuideCalls.append(
            .init(content: content, reloadProgramGuide: reloadProgramGuide)
        )
        return try await reloadProgramGuideHandler(content, reloadProgramGuide)
    }

    func playlists(
        for content: PlaylistItem.Content,
        reloadPlaylist: Bool,
        progress: @escaping ProgressHandler
    ) async throws -> [PlaylistParser.Playlist] {
        reloadPlaylistCalls.append(
            .init(content: content, reloadPlaylist: reloadPlaylist)
        )
        return try await reloadPlaylistHandler(content, reloadPlaylist)
    }

    func programGuide(
        for content: PlaylistItem.Content,
        stream: PlaylistParser.Stream
    ) async -> ProgramGuide? {
        Issue.record("Unexpected programGuide call.")
        return nil
    }

    func programGuides(for content: PlaylistItem.Content, since: Date) async -> [ProgramGuide] {
        Issue.record("Unexpected programGuides call.")
        return []
    }

    func clearCache(for content: PlaylistItem.Content) async {
        Issue.record("Unexpected clearCache call.")
    }
}
