
import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable
import FactoryKit

@Model
final class PlaylistItem {

    var name: String? // Not encrypted
    // Read-only: `identity` is derived from (name, date), edits must never touch the date.
    private(set) var date: Date? // Not encrypted
    var icon: String? // Not encrypted
    var url: Data? // date url plain or encrypted
    var salt: Data? // Not encrypted
    var encrypted: Bool = false
    var urlTvg: String?
    var urlImg: String?
    var tvgLogo: String?
    @Transient var data: Data?
    @Transient var settings: PlaylistSettingsItem?

    init(
        name: String?,
        date: Date?,
        icon: String?,
        url: Data?,
        data: Data? = nil,
        salt: Data?,
        encrypted: Bool,
        settings: PlaylistSettingsItem? = nil,
        urlTvg: String? = nil,
        urlImg: String? = nil,
        tvgLogo: String? = nil
    ) {
        self.name = name
        self.date = date
        self.icon = icon
        self.url = url
        self.data = data
        self.salt = salt
        self.encrypted = encrypted
        self.settings = settings
        self.urlTvg = urlTvg
        self.urlImg = urlImg
        self.tvgLogo = tvgLogo
    }
}

nonisolated extension PlaylistItem: Codable {

    enum CodingKeys: String, CodingKey {
        case name
        case date
        case icon
        case url
        case data
        case salt
        case encrypted
        case settings
        case urlTvg
        case urlImg
        case tvgLogo
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decodeIfPresent(String.self, forKey: .name),
            date: try container.decodeIfPresent(Date.self, forKey: .date),
            icon: try container.decodeIfPresent(String.self, forKey: .icon),
            url: try container.decodeIfPresent(Data.self, forKey: .url),
            data: try container.decodeIfPresent(Data.self, forKey: .data),
            salt: try container.decodeIfPresent(Data.self, forKey: .salt),
            encrypted: try container.decodeIfPresent(Bool.self, forKey: .encrypted) ?? false,
            settings: try container.decodeIfPresent(PlaylistSettingsItem.self, forKey: .settings),
            urlTvg: try container.decodeIfPresent(String.self, forKey: .urlTvg),
            urlImg: try container.decodeIfPresent(String.self, forKey: .urlImg),
            tvgLogo: try container.decodeIfPresent(String.self, forKey: .tvgLogo)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(salt, forKey: .salt)
        try container.encode(encrypted, forKey: .encrypted)
        try container.encodeIfPresent(settings, forKey: .settings)
        try container.encodeIfPresent(urlTvg, forKey: .urlTvg)
        try container.encodeIfPresent(urlImg, forKey: .urlImg)
        try container.encodeIfPresent(tvgLogo, forKey: .tvgLogo)
    }
}

extension PlaylistItem {

    static var UtType: UTType {
        // Read the exported type from the Info.plist so it follows the bundle
        // identifier, but never crash in hosts without the declaration
        // (unit tests, extensions).
        if let declarations = Bundle.main.infoDictionary?["UTExportedTypeDeclarations"] as? [[String: Any]],
           let identifier = declarations.first?["UTTypeIdentifier"] as? String,
           let type = UTType(identifier) {
            return type
        }
        if let identifier = Bundle.main.bundleIdentifier {
            return UTType(exportedAs: "\(identifier).playlist")
        }
        return .json
    }
}

extension PlaylistItem {

    var transfer: TransferIdentity? {
        identity.map({
            .init(identity: $0, icon: icon)
        })
    }

    struct TransferIdentity: Transferable {

        let identity: PlaylistItem.Identity
        let icon: String?

        static var transferRepresentation: some TransferRepresentation {            
            FileRepresentation(exportedContentType: PlaylistItem.UtType, shouldAllowToOpenInPlace: true, exporting: { @MainActor  identity in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(identity.title).playlist")
                let fetch = FetchDescriptor<PlaylistItem>()
                guard let playlist = try Container.shared.databaseService().mainContext.fetch(fetch)
                    .first(where: { $0.identity == identity.identity }) else {
                    throw NSError(domain: "com.app.playlist", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Playlist \(identity.title) not found"
                    ])
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(playlist)
                try data.write(to: url)
                return SentTransferredFile(url)
            })
        }

        var title: String {
            identity.name
        }
    }
}

extension PlaylistItem {

    @Transient var identity: Identity? {
        guard let name, let date else { return nil }
        return Identity(name: name, date: date)
    }

    nonisolated struct Identity: Identifiable, Hashable, CustomStringConvertible, Sendable {
        let name: String
        let date: Date
        var id: Identity { self }
        var description: String {
            "'\(name)' created at \(date.formatted(.dateTime.year().month().day().hour().minute().second()))"
        }
    }
}

extension PlaylistItem {

     struct Content: Identifiable, Hashable, CustomStringConvertible, Sendable {
        let identity: Identity
        let url: Data // plain url data ready to use (decrypted)
        let data: Data // plain data from url ready to use (decompressed and decrypted)
        let isStoredInMemoryOnly: Bool
        var id: Identity { identity }

        func hash(into hasher: inout Hasher) {
            hasher.combine(identity)
        }

        static func ==(lhs: Content, rhs: Content) -> Bool {
            lhs.identity == rhs.identity
        }

        var description: String {
            id.description
        }
    }
}
