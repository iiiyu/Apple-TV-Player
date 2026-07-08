
import Foundation
import SwiftData
import FactoryKit

@Model
final class PlaylistSettingsItem {

    var playlistName: String?
    var playlistDate: Date?
    @Attribute(.externalStorage)
    var data: Data?
    var order: String?
    @Attribute(.externalStorage)
    var viewsData: Data?
    @Attribute(.externalStorage)
    var recentData: Data?
    @Attribute(.externalStorage)
    var encryptedData: Data?
    @Attribute(.externalStorage)
    var favoritesData: Data?

    init(
        playlistName: String? = nil,
        playlistDate: Date? = nil,
        data: Data? = nil,
        order: String?
    ) {
        self.playlistName = playlistName
        self.playlistDate = playlistDate
        self.data = data
        self.order = order
    }
}

extension PlaylistSettingsItem: Codable {

    enum CodingKeys: String, CodingKey {
        case order
        case views
        case recent
        case encrypted
        case favorites
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let order = try container.decodeIfPresent(String.self, forKey: .order)
        self.init(order: order)
        self.views = try container.decodeIfPresent([String: Int].self, forKey: .views) ?? [:]
        self.recent = try container.decodeIfPresent([String: Date].self, forKey: .recent) ?? [:]
        self.encrypted = try container.decodeIfPresent([String: String].self, forKey: .encrypted) ?? [:]
        self.favorites = try container.decodeIfPresent([String].self, forKey: .favorites) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(order, forKey: .order)
        try container.encode(views, forKey: .views)
        try container.encode(recent, forKey: .recent)
        try container.encode(encrypted, forKey: .encrypted)
        try container.encode(favorites, forKey: .favorites)
    }
}

extension PlaylistSettingsItem {

    @Transient var identity: PlaylistItem.Identity? {
        guard let playlistName, let playlistDate else { return nil }
        return .init(name: playlistName, date: playlistDate)
    }

    /// Key is HMAC(title), value is view count.
    @Transient var views: [String: Int] {
        get { Self.decode([String: Int].self, from: viewsData) ?? [:] }
        set { viewsData = Self.encode(newValue) }
    }

    /// Key is HMAC(title), value is last viewed date.
    @Transient var recent: [String: Date] {
        get { Self.decode([String: Date].self, from: recentData) ?? [:] }
        set { recentData = Self.encode(newValue) }
    }

    /// Key is HMAC(title), value is AES-GCM encrypted title.
    @Transient var encrypted: [String: String] {
        get { Self.decode([String: String].self, from: encryptedData) ?? [:] }
        set { encryptedData = Self.encode(newValue) }
    }

    /// HMAC(title) of favorite streams.
    @Transient var favorites: [String] {
        get { Self.decode([String].self, from: favoritesData) ?? [] }
        set { favoritesData = Self.encode(newValue) }
    }

    @Transient var orderType: StreamListOrder {
        get {
            guard let order = order else { return .none }
            return StreamListOrder(rawValue: order) ?? .none
        }
        set {
            order = newValue.rawValue
        }
    }

    enum StreamListOrder: String, Hashable, CaseIterable {
        case none
        case ascending
        case descending
        case mostViewed
        case recentViewed
        case favorites

        var title: String {
            switch self {
            case .none: return String(localized: "Default")
            case .ascending: return String(localized: "Alphabetical")
            case .descending: return String(localized: "Reverse Alphabetical")
            case .mostViewed: return String(localized: "Most Viewed")
            case .recentViewed: return String(localized: "Recently Viewed")
            case .favorites: return String(localized: "Favorites First")
            }
        }
    }
}

extension PlaylistSettingsItem {

    static func state(
        for playlist: PlaylistItem,
        in context: ModelContext,
        create: Bool = true
    ) throws -> PlaylistSettingsItem? {
        guard let identity = playlist.identity else {
            return nil
        }
        return try state(for: identity, in: context, create: create)
    }

    static func state(
        for identity: PlaylistItem.Identity,
        in context: ModelContext,
        create: Bool = true
    ) throws -> PlaylistSettingsItem? {
        let states = try context.fetch(FetchDescriptor<PlaylistSettingsItem>())
            .filter { $0.identity == identity }
        if let state = states.first {
            for duplicate in states.dropFirst() {
                state.mergeMissingValues(from: duplicate)
                context.delete(duplicate)
            }
            return state
        }

        guard create else {
            return nil
        }

        let state = PlaylistSettingsItem(
            playlistName: identity.name,
            playlistDate: identity.date,
            order: nil
        )
        context.insert(state)
        return state
    }

    func updateIdentity(_ identity: PlaylistItem.Identity) {
        playlistName = identity.name
        playlistDate = identity.date
    }

    private func mergeMissingValues(from duplicate: PlaylistSettingsItem) {
        if data == nil {
            data = duplicate.data
        }
        if order == nil {
            order = duplicate.order
        }
        if viewsData == nil {
            viewsData = duplicate.viewsData
        }
        if recentData == nil {
            recentData = duplicate.recentData
        }
        if encryptedData == nil {
            encryptedData = duplicate.encryptedData
        }
        if favoritesData == nil {
            favoritesData = duplicate.favoritesData
        }
    }
}

private extension PlaylistSettingsItem {

    static func encode<Value: Encodable>(_ value: Value) -> Data? {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            Container.shared.logger().error(error)
            return nil
        }
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // Surface corruption instead of silently returning an empty value
            // that a later write would persist over the stored statistics.
            Container.shared.logger().error(error, private: "Corrupt \(type) blob in PlaylistSettingsItem")
            return nil
        }
    }
}
