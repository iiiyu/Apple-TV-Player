import Foundation
import SwiftData
import Testing
import FactoryKit
import FactoryTesting
#if canImport(UIKit)
import UIKit
#endif
@testable import HiPlayer

@Suite(.container)
struct ContentViewModelTests {

    @MainActor
    @Test func prepareForLaunchWithoutRestoreStartsAtHome() async throws {
        let date = Date(timeIntervalSince1970: 100)
        let playlist = try await makePlaylistItem(name: "Playlist", date: date, encrypted: false)
        let database = try makeDatabaseService(items: [playlist])
        let appSettings = AppSettings()
        appSettings.lastPlaylistName = "Playlist"
        appSettings.lastPlaylistDate = date
        appSettings.lastStreamHmac = "stream-hmac"
        database.mainContext.insert(appSettings)
        try database.mainContext.save()
        Container.shared.databaseService.register { database }

        let stream = PlaylistParser.Stream(
            title: "Existing",
            url: "https://example.com/existing.m3u8",
            tvgLogo: nil,
            tvgID: nil,
            tvgName: nil,
            groupTitle: nil
        )
        let viewModel = ContentViewModel()
        viewModel.selectedPlaylist = playlist.identity
        viewModel.selectedPlaylistContent = .init(
            identity: try #require(playlist.identity),
            url: try #require(playlist.url),
            data: Data("#EXTM3U".utf8),
            isStoredInMemoryOnly: false
        )
        viewModel.selectedPlaylistStream = stream

        viewModel.prepareForLaunch(restoringLastWatched: false)

        #expect(viewModel.selectedPlaylist == nil)
        #expect(viewModel.selectedPlaylistContent == nil)
        #expect(viewModel.selectedPlaylistStream == nil)
        #expect(viewModel.consumeRestoreStreamHmac() == nil)

        // If SwiftUI restarts the task later, don't erase navigation that the
        // user performed after the initial launch preparation completed.
        viewModel.selectedPlaylist = playlist.identity
        viewModel.selectedPlaylistStream = stream
        viewModel.prepareForLaunch(restoringLastWatched: false)
        #expect(viewModel.selectedPlaylist == playlist.identity)
        #expect(viewModel.selectedPlaylistStream == stream)
    }

    @MainActor
    @Test func clearSelectedStreamOnlyClearsCurrentPlayback() async throws {
        let selected = PlaylistParser.Stream(
            title: "Selected",
            url: "https://example.com/selected.m3u8",
            tvgLogo: nil,
            tvgID: nil,
            tvgName: nil,
            groupTitle: nil
        )
        let other = PlaylistParser.Stream(
            title: "Other",
            url: "https://example.com/other.m3u8",
            tvgLogo: nil,
            tvgID: nil,
            tvgName: nil,
            groupTitle: nil
        )
        let viewModel = ContentViewModel()
        viewModel.selectedPlaylistStream = selected

        viewModel.clearSelectedStream(ifMatching: other)
        #expect(viewModel.selectedPlaylistStream == selected)

        viewModel.clearSelectedStream(ifMatching: selected)
        #expect(viewModel.selectedPlaylistStream == nil)
    }

    @MainActor
    @Test func leavePlaylistClearsEveryNavigationSelection() async throws {
        let identity = PlaylistItem.Identity(name: "Playlist", date: Date(timeIntervalSince1970: 100))
        let stream = PlaylistParser.Stream(
            title: "Selected",
            url: "https://example.com/selected.m3u8",
            tvgLogo: nil,
            tvgID: nil,
            tvgName: nil,
            groupTitle: nil
        )
        let viewModel = ContentViewModel()
        viewModel.selectedPlaylist = identity
        viewModel.selectedPlaylistContent = .init(
            identity: identity,
            url: Data("https://example.com/playlist.m3u".utf8),
            data: Data("#EXTM3U".utf8),
            isStoredInMemoryOnly: false
        )
        viewModel.selectedPlaylistStream = stream

        viewModel.leavePlaylist()

        #expect(viewModel.selectedPlaylist == nil)
        #expect(viewModel.selectedPlaylistContent == nil)
        #expect(viewModel.selectedPlaylistStream == nil)
    }

    @MainActor
    @Test func restoreLastWatchedSelectsStoredPlaylistOnce() async throws {
        let date = Date(timeIntervalSince1970: 100)
        let playlist = try await makePlaylistItem(name: "Playlist", date: date, encrypted: false)
        let database = try makeDatabaseService(items: [playlist])
        let appSettings = AppSettings()
        appSettings.lastPlaylistName = "Playlist"
        appSettings.lastPlaylistDate = date
        appSettings.lastStreamHmac = "stream-hmac"
        database.mainContext.insert(appSettings)
        try database.mainContext.save()
        Container.shared.databaseService.register { database }

        let viewModel = ContentViewModel()
        viewModel.restoreLastWatched()

        #expect(viewModel.selectedPlaylist == .init(name: "Playlist", date: date))
        #expect(viewModel.consumeRestoreStreamHmac() == "stream-hmac")
        // Consumed once only.
        #expect(viewModel.consumeRestoreStreamHmac() == nil)

        // A second restore attempt must not override the user's navigation.
        viewModel.selectedPlaylist = nil
        viewModel.restoreLastWatched()
        #expect(viewModel.selectedPlaylist == nil)
    }

    @MainActor
    @Test func restoreLastWatchedSkipsDeletedPlaylist() async throws {
        let database = try makeDatabaseService(items: [])
        let appSettings = AppSettings()
        appSettings.lastPlaylistName = "Gone"
        appSettings.lastPlaylistDate = Date(timeIntervalSince1970: 100)
        appSettings.lastStreamHmac = "stream-hmac"
        database.mainContext.insert(appSettings)
        try database.mainContext.save()
        Container.shared.databaseService.register { database }

        let viewModel = ContentViewModel()
        viewModel.restoreLastWatched()

        #expect(viewModel.selectedPlaylist == nil)
        #expect(viewModel.consumeRestoreStreamHmac() == nil)
    }

    @MainActor
    @Test func onPlaylistSelectedStoresRestoredContentAndClearsSelectedStream() async throws {
        let date = Date(timeIntervalSince1970: 100)
        let playlist = try await makePlaylistItem(
            name: "Playlist",
            date: date,
            encrypted: false
        )
        let database = try makeDatabaseService(items: [playlist])
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { PlaylistAddService() }
        let viewModel = ContentViewModel()
        viewModel.selectedPlaylistContent = .init(
            identity: .init(name: "Old", date: .distantPast),
            url: Data("https://example.com/old.m3u".utf8),
            data: Data("#EXTM3U".utf8),
            isStoredInMemoryOnly: false
        )
        viewModel.selectedPlaylistStream = .init(
            title: "Existing",
            url: "https://example.com/existing.m3u8",
            tvgLogo: nil,
            tvgID: nil,
            tvgName: nil,
            groupTitle: nil
        )
        viewModel.selectedPlaylist = .init(name: "Playlist", date: date)

        await viewModel.onPlaylistSelected()

        let selectedContent = try #require(viewModel.selectedPlaylistContent)

        #expect(selectedContent.identity == .init(name: "Playlist", date: date))
        #expect(selectedContent.url == Data("https://example.com/Playlist.m3u".utf8))
        #expect(selectedContent.data == Data("#EXTM3U".utf8))
        #expect(selectedContent.isStoredInMemoryOnly == false)
        #expect(viewModel.selectedPlaylistStream == nil)
        #expect(viewModel.isShowingPlaylistDecryptPin == nil)
    }

    @MainActor
    @Test func onPlaylistSelectedShowsDecryptPinForEncryptedPlaylist() async throws {
        let date = Date(timeIntervalSince1970: 200)
        let playlist = try await makePlaylistItem(
            name: "Encrypted",
            date: date,
            encrypted: true
        )
        let database = try makeDatabaseService(items: [playlist])
        Container.shared.databaseService.register { database }
        Container.shared.playlistAddService.register { PlaylistAddService() }
        let viewModel = ContentViewModel()
        viewModel.selectedPlaylistContent = .init(
            identity: .init(name: "Old", date: .distantPast),
            url: Data("https://example.com/old.m3u".utf8),
            data: Data("#EXTM3U".utf8),
            isStoredInMemoryOnly: false
        )
        viewModel.selectedPlaylistStream = .init(
            title: "Existing",
            url: "https://example.com/existing.m3u8",
            tvgLogo: nil,
            tvgID: nil,
            tvgName: nil,
            groupTitle: nil
        )
        
        viewModel.selectedPlaylist = .init(name: "Encrypted", date: date)

        await viewModel.onPlaylistSelected()

        #expect(viewModel.selectedPlaylistContent == nil)
        #expect(viewModel.selectedPlaylistStream == nil)
        #expect(viewModel.isShowingPlaylistDecryptPin == playlist.identity)
    }
}

private extension ContentViewModelTests {

    func makeDatabaseService(items: [PlaylistItem]) throws -> DatabaseService {
        let database = DatabaseService(isStoredInMemoryOnly: true)

        for item in items {
            database.mainContext.insert(item)
            if let identity = item.identity {
                database.mainContext.insert(
                    PlaylistSettingsItem(
                        playlistName: identity.name,
                        playlistDate: identity.date,
                        data: item.data,
                        order: nil
                    )
                )
            }
        }

        try database.mainContext.save()

        return database
    }

    func makePlaylistItem(
        name: String,
        date: Date,
        encrypted: Bool
    ) async throws -> PlaylistItem {
        let playlistData = Data("#EXTM3U".utf8)
        let storedData = encrypted
            ? Data("encrypted-playlist".utf8)
            : try await DataCompressor().compress(playlistData)

        return PlaylistItem(
            name: name,
            date: date,
            icon: nil,
            url: Data("https://example.com/\(name).m3u".utf8),
            data: storedData,
            salt: encrypted ? Data("salt".utf8) : nil,
            encrypted: encrypted
        )
    }
}
