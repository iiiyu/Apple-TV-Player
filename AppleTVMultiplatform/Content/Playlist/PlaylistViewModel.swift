import CryptoKit
import FactoryKit
import Foundation
import Observation
import SwiftData

@Observable
final class PlaylistViewModel {

    @ObservationIgnored @Injected(\.playlistService) private var playlistService
    @ObservationIgnored @Injected(\.databaseService) private var databaseService
    @ObservationIgnored @Injected(\.logger) private var logger

    let content: PlaylistItem.Content

    private(set) var streams: [[PlaylistParser.Stream]] = []
    private(set) var favoriteHmacs: Set<String> = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var progress: String?
    var searchText = ""

    // A projection over the sorted/grouped `streams`, so search keeps
    // the group order and the per-settings sort order intact.
    var filteredStreams: [[PlaylistParser.Stream]] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return streams }
        return streams.compactMap { group in
            let matches = group.filter { stream in
                title(for: stream).localizedCaseInsensitiveContains(query)
                    || stream.title.localizedCaseInsensitiveContains(query)
                    || (stream.groupTitle?.localizedCaseInsensitiveContains(query) ?? false)
            }
            return matches.isEmpty ? nil : matches
        }
    }
    private let crypto = Crypto()
    // Original iterations very slow when used for sorting.
    private let iterations: UInt32 = 50_000
    // Derived once: PBKDF2 per title would dominate the sorting cost for
    // large playlists (decode is called for every stream title).
    private let sortingKey: SymmetricKey?

    init(content: PlaylistItem.Content) {
        self.content = content
        let pin = String(data: content.url, encoding: .utf8) ?? ""
        sortingKey = try? Crypto.deriveKey(
            pin: pin,
            salt: Self.salt(for: content),
            iterations: iterations
        )
    }

    private func loadPlaylist(reloadProgramGuide: Bool) async throws -> [PlaylistParser.Playlist] {
        logger.info("Loading playlist", private: content.id)
        return try await playlistService.playlists(
            for: content,
            reloadProgramGuide: reloadProgramGuide
        ) { [weak self] _, step in
            Task { @MainActor in
                switch step {
                case .start, .complete:
                    break
                default:
                    self?.progress = step.title
                }
            }
        }
    }

    private(set) var isRefreshing = false

    func refresh() async {
        guard !isLoading, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            // Force a re-parse of the stored playlist plus a reload of the
            // program guide and logos. Unlike the settings update flow this
            // never re-downloads from the origin URL, so no pin is needed.
            _ = try await playlistService.playlists(for: content, reloadPlaylist: true) { _, _ in }
        } catch {
            logger.error(error, private: content.id)
            errorMessage = errorMessage(for: error)
            return
        }
        await loadStreams()
    }

    func loadStreams() async {
        isLoading = true
        errorMessage = nil
        progress = streams.isEmpty ? " " : nil
        defer { isLoading = false }

        do {
            var playlists = try await loadPlaylist(reloadProgramGuide: false)
            let programGuides = await playlistService.programGuides(for: content, since: Date())
            if programGuides.isEmpty {
                logger.info("Program guide seems outdated, reload it from scratch ...")
                playlists = try await loadPlaylist(reloadProgramGuide: true)
            }
            let streams = playlists.first?.streams ?? []
            let playlistItem = playlist
            guard let settings = playlistItem?.settings else {
                self.streams = [streams]
                return
            }
            let order = playlistItem?.settings?.orderType ?? .none
            favoriteHmacs = Set(settings.favorites)
            logger.info("Sorting streams with '\(order)'", private: content.id)
            let measure = await measureTime { @MainActor [self] in
                switch order {
                case .none:
                    self.streams = await Task<[[PlaylistParser.Stream]], Never>.detached(priority: .high) {
                        var streamsByGroup: [[PlaylistParser.Stream]] = []
                        let noGroupStreams: [PlaylistParser.Stream] = streams.filter { $0.groupTitle == nil }
                        let haveGroupStreams: [PlaylistParser.Stream] = streams.filter { $0.groupTitle != nil }
                        let groups: [String] = NSOrderedSet(array: haveGroupStreams.compactMap { $0.groupTitle }).array as! [String]
                        for group in groups {
                            streamsByGroup.append(haveGroupStreams.filter { $0.groupTitle == group })
                        }
                        if !noGroupStreams.isEmpty {
                            streamsByGroup.append(noGroupStreams)
                        }
                        return streamsByGroup
                    }.value
                case .ascending:
                    self.streams = await Task<[[PlaylistParser.Stream]], Never>.detached(priority: .high) {
                        [streams.sorted(by: { left, right in
                            return self.title(for: left) < self.title(for: right)
                        })]
                    }.value
                case .descending:
                    self.streams = await Task<[[PlaylistParser.Stream]], Never>.detached(priority: .high) {
                        [streams.sorted(by: { left, right in
                            return self.title(for: left) > self.title(for: right)
                        })]
                    }.value
                case .favorites:
                    self.streams = await Task<[[PlaylistParser.Stream]], Never>.detached(priority: .high) { [favoriteHmacs] in
                        let sorted = streams.sorted(by: { left, right in
                            self.title(for: left) < self.title(for: right)
                        })
                        var favorites: [PlaylistParser.Stream] = []
                        var others: [PlaylistParser.Stream] = []
                        for stream in sorted {
                            if favoriteHmacs.contains(self.hmacValue(for: stream)) {
                                favorites.append(stream)
                            } else {
                                others.append(stream)
                            }
                        }
                        return [favorites + others]
                    }.value
                case .recentViewed, .mostViewed:
                    let expectOrder: [String]
                    if order == .mostViewed {
                        expectOrder = await Task<[String], Never>.detached(priority: .high) { [views=settings.views, encrypted=settings.encrypted] in
                            views.sorted(by: { $0.value > $1.value }).compactMap({ encrypted[$0.key] }).map { self.decode(title: $0) }
                        }.value
                    } else if order == .recentViewed {
                        expectOrder = await Task<[String], Never>.detached(priority: .high) { [recent=settings.recent, encrypted=settings.encrypted] in
                            recent.sorted(by: { $0.value > $1.value }).compactMap({ encrypted[$0.key] }).map { self.decode(title: $0) }
                        }.value
                    } else {
                        fatalError()
                    }
                    var actualOrder: [PlaylistParser.Stream] = []
                    actualOrder.reserveCapacity(streams.count)
                    var indexes: Set<Int> = []
                    for expect in expectOrder {
                        guard let index = streams.firstIndex(where: { expect == title(for: $0) }) else { continue }
                        actualOrder.append(streams[index])
                        indexes.insert(index)
                    }
                    Set((0..<streams.count)).subtracting(indexes).sorted().forEach { index in
                        actualOrder.append(streams[index])
                    }
                    self.streams = [actualOrder]
                }
            }
            logger.info("Streams sorting completed in \(measure.milliseconds) milliseconds")
        } catch {
            logger.error(error, private: content.id)
            streams = []
            errorMessage = errorMessage(for: error)
        }
    }

    nonisolated func title(for stream: PlaylistParser.Stream) -> String {
        let tvgName = stream.tvgName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (tvgName?.isEmpty == false ? tvgName : nil) ?? stream.title
    }

    // HMAC-only variant of `encode` for lookups that never need the ciphertext.
    nonisolated func hmacValue(for stream: PlaylistParser.Stream) -> String {
        let title = title(for: stream)
        guard let sortingKey else {
            return title
        }
        return (try? crypto.hmac(title, key: sortingKey)) ?? title
    }

    func isFavorite(_ stream: PlaylistParser.Stream) -> Bool {
        favoriteHmacs.contains(hmacValue(for: stream))
    }

    func toggleFavorite(_ stream: PlaylistParser.Stream) {
        guard let playlist, let settings = playlist.settings else {
            return
        }
        let hmac = hmacValue(for: stream)
        if favoriteHmacs.contains(hmac) {
            favoriteHmacs.remove(hmac)
            settings.favorites.removeAll { $0 == hmac }
        } else {
            favoriteHmacs.insert(hmac)
            settings.favorites.append(hmac)
        }
        if settings.orderType == .favorites {
            Task {
                await loadStreams()
            }
        }
    }

    struct CurrentProgram: Equatable, Sendable {
        let title: String
        // How far the program has aired, clamped to 0...1.
        let progress: Double
    }

    func currentProgram(for stream: PlaylistParser.Stream, at now: Date = Date()) async -> CurrentProgram? {
        guard let guide = await playlistService.programGuide(for: content, stream: stream),
              let program = guide.programs.first(where: { $0.start <= now && now < $0.stop }) else {
            return nil
        }
        let total = program.stop.timeIntervalSince(program.start)
        let progress = total > 0 ? min(max(now.timeIntervalSince(program.start) / total, 0), 1) : 0
        return CurrentProgram(title: program.title, progress: progress)
    }

    func iconURL(for stream: PlaylistParser.Stream) async -> String? {
        if let icon = stream.tvgLogo {
            return icon
        }
        return await playlistService.programGuide(for: content, stream: stream)?.channel.iconURL
    }

    func selectedStream(_ stream: PlaylistParser.Stream) {
        if let playlist, let settings = playlist.settings {
            let (hmac, encrypted) = encode(title: title(for: stream))
            settings.views[hmac, default: 0] += 1
            settings.recent[hmac] = Date()
            settings.encrypted[hmac] = encrypted
            saveLastWatched(hmac: hmac)
        }
    }

    func stream(matchingLastWatched hmac: String) -> PlaylistParser.Stream? {
        for group in streams {
            for stream in group where hmacValue(for: stream) == hmac {
                return stream
            }
        }
        return nil
    }

    private func saveLastWatched(hmac: String) {
        let fetch = FetchDescriptor<AppSettings>()
        let appSettings: AppSettings
        if let existing = (try? databaseService.mainContext.fetch(fetch))?.first {
            appSettings = existing
        } else {
            appSettings = AppSettings()
            databaseService.mainContext.insert(appSettings)
        }
        appSettings.lastPlaylistName = content.identity.name
        appSettings.lastPlaylistDate = content.identity.date
        appSettings.lastStreamHmac = hmac
    }

    nonisolated private static func salt(for content: PlaylistItem.Content) -> Data {
        var salt: Data
        if content.url.count <= Crypto.keyLength {
          salt = Data(content.url)
        } else {
          salt = Data(content.url.dropLast(content.url.count - Crypto.keyLength))
        }
        while salt.count < Crypto.keyLength {
            salt.append(0x0)
        }
        return salt
    }

    // The key is derived from `content.url` as pin and salt because when
    // encrypted it is hidden under user passcode. It is enough to secure this
    // data that does not disclose a way to brute-force the passcode.
    func encode(title: String) -> (hmac: String, encrypted: String) {
        guard let sortingKey else {
            return (title, title)
        }
        let encrypted = (try? crypto.encrypt(title, key: sortingKey))?.base64EncodedString() ?? title
        let hmac = (try? crypto.hmac(title, key: sortingKey)) ?? title
        return (hmac, encrypted)
    }

    nonisolated func decode(title: String) -> String {
        guard let data = Data(base64Encoded: title), let sortingKey else {
            return title
        }
        return (try? crypto.decrypt(data, key: sortingKey)) ?? title
    }

    private var playlist: PlaylistItem? {
        let fetch = FetchDescriptor<PlaylistItem>()
        return try? databaseService.mainContext.fetch(fetch)
            .first(where: { $0.identity == content.identity })
    }

    isolated deinit {
        logger.info("deinit of \(self)")
    }
}

private extension PlaylistViewModel {

    func errorMessage(for error: Swift.Error) -> String? {
        if (error as NSError).code == NSURLErrorCancelled {
            return nil
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return "\(error)"
    }
}
