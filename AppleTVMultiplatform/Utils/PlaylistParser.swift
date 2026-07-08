import Foundation
import FactoryKit

actor PlaylistParser {

    struct Playlist: Equatable, Sendable {
        let tvgURL: String? // URL to an archive with program guide
        let imageURL: String? // URL to an archive with images (png, jpg) for stream logos
        let xTvgURL: String? // Backup url for `tvgURL`
        let tvgLogo: String? // URL to the playlist's main logo image
        let streams: [Stream]
    }

    struct Stream: Sendable, Identifiable, Hashable {
        let title: String
        let url: String
        let tvgLogo: String?
        let tvgID: String?
        let tvgName: String?
        let groupTitle: String?
        // Length-prefix the title so the id can't be forged by a colon inside
        // a title/url — e.g. ("HD:1","x") and ("HD","1:x") stay distinct.
        var id: String { "\(title.count):\(title)|\(url)" }

        static func == (lhs: Stream, rhs: Stream) -> Bool {
            lhs.title == rhs.title && lhs.url == rhs.url
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
            hasher.combine(url)
        }
    }

    enum ParserError: Error, Equatable {
        case invalidEncoding
        case invalidFormat
    }

    private struct PlaylistBuilder {
        var tvgURL: String?
        var imageURL: String?
        var xTvgURL: String?
        var tvgLogo: String?
        var streams: [Stream] = []

        var playlist: Playlist {
            Playlist(
                tvgURL: tvgURL,
                imageURL: imageURL,
                xTvgURL: xTvgURL,
                tvgLogo: tvgLogo,
                streams: streams
            )
        }
    }

    private struct PendingStream {
        let title: String
        let tvgLogo: String?
        let tvgID: String?
        let tvgName: String?
        let groupTitle: String?
        // HTTP headers from #EXTVLCOPT lines, folded into the URL so the
        // playback engines send them.
        var headers: [String: String] = [:]

        func resolve(url: String) -> Stream {
            Stream(
                title: title,
                url: Self.applyingHeaders(headers, to: url),
                tvgLogo: tvgLogo,
                tvgID: tvgID,
                tvgName: tvgName,
                groupTitle: groupTitle
            )
        }

        // Appends captured headers as pipe-options unless the URL already
        // carries an options suffix.
        private static func applyingHeaders(_ headers: [String: String], to url: String) -> String {
            guard !headers.isEmpty, !url.contains("|") else {
                return url
            }
            let options = headers
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
            return "\(url)|\(options)"
        }
    }

    private static let m3uHeader = "#EXTM3U"
    private static let streamInfoHeader = "#EXTINF:"
    private static let vlcOptionHeader = "#EXTVLCOPT:"
    private static let attributePattern = #"([A-Za-z0-9-]+)=("([^"]*)"|([^\s,]+))"#
    @ObservationIgnored @Injected(\.logger) private var logger

    private let content: String

    init(string: String) {
        content = Self.normalize(string)
    }

    init(data: Data, encoding: String.Encoding = .utf8) throws {
        guard let string = String(data: data, encoding: encoding) else {
            throw ParserError.invalidEncoding
        }

        content = Self.normalize(string)
    }

    func parse() throws -> [Playlist] {
        var playlists: [Playlist] = []
        var currentPlaylist: PlaylistBuilder?
        var pendingStream: PendingStream?
        var hasHeader = false
        let measure = measureTime {
            for rawLine in content.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

                if line.isEmpty {
                    continue
                }

                if line.hasPrefix(Self.m3uHeader) {
                    if let currentPlaylist {
                        playlists.append(currentPlaylist.playlist)
                    }

                    currentPlaylist = Self.buildPlaylist(from: line)
                    pendingStream = nil
                    hasHeader = true
                    continue
                }

                guard currentPlaylist != nil else {
                    continue
                }

                if line.hasPrefix(Self.streamInfoHeader) {
                    pendingStream = Self.buildStream(from: line)
                    continue
                }

                if line.hasPrefix(Self.vlcOptionHeader) {
                    if let (name, value) = Self.parseVLCOption(from: line) {
                        pendingStream?.headers[name] = value
                    }
                    continue
                }

                if line.hasPrefix("#") {
                    continue
                }

                guard let resolvedStream = pendingStream, var playlist = currentPlaylist else {
                    continue
                }

                playlist.streams.append(resolvedStream.resolve(url: line))
                currentPlaylist = playlist
                pendingStream = nil
            }
        }

        guard hasHeader else {
            throw ParserError.invalidFormat
        }

        if let currentPlaylist {
            playlists.append(currentPlaylist.playlist)
        }

        logger.info("Playlist parsing completed in \(measure.milliseconds) milliseconds")

        return playlists
    }

    private static func normalize(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func buildPlaylist(from line: String) -> PlaylistBuilder {
        let attributes = parseAttributes(in: String(line.dropFirst(m3uHeader.count)))

        return PlaylistBuilder(
            tvgURL: attributes["url-tvg"],
            imageURL: attributes["url-img"],
            xTvgURL: attributes["x-tvg-url"],
            tvgLogo: attributes["tvg-logo"]
        )
    }

    private static func buildStream(from line: String) -> PendingStream {
        let body = String(line.dropFirst(streamInfoHeader.count))
        let (metadata, title) = splitMetadataAndTitle(in: body)
        let attributes = parseAttributes(in: metadata)

        return PendingStream(
            title: title,
            tvgLogo: attributes["tvg-logo"],
            tvgID: attributes["tvg-id"],
            tvgName: attributes["tvg-name"],
            groupTitle: attributes["group-title"]
        )
    }

    private static func parseVLCOption(from line: String) -> (name: String, value: String)? {
        let body = String(line.dropFirst(vlcOptionHeader.count))
        let parts = body.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let value = parts[1].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        switch key {
        case "http-user-agent":
            return ("User-Agent", value)
        case "http-referrer", "http-referer":
            return ("Referer", value)
        case "http-origin":
            return ("Origin", value)
        default:
            return nil
        }
    }

    private static func splitMetadataAndTitle(in line: String) -> (metadata: String, title: String) {
        var isInsideQuotes = false

        // Commas inside quoted attributes are part of metadata, not the title separator.
        for index in line.indices {
            let character = line[index]

            if character == "\"" {
                isInsideQuotes.toggle()
                continue
            }

            if character == ",", !isInsideQuotes {
                let metadata = String(line[..<index]).trimmingCharacters(in: .whitespaces)
                let titleStart = line.index(after: index)
                let title = String(line[titleStart...]).trimmingCharacters(in: .whitespaces)

                return (metadata, title)
            }
        }

        return (line.trimmingCharacters(in: .whitespaces), "")
    }

    private static func parseAttributes(in line: String) -> [String: String] {
        let attributeRegex = try! NSRegularExpression(pattern: attributePattern)
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        var attributes: [String: String] = [:]

        for match in attributeRegex.matches(in: line, range: nsRange) {
            guard
                let keyRange = Range(match.range(at: 1), in: line)
            else {
                continue
            }

            let key = String(line[keyRange])
            let valueRange = Range(match.range(at: 3), in: line)
                ?? Range(match.range(at: 4), in: line)

            guard let valueRange else {
                continue
            }

            attributes[key] = String(line[valueRange])
        }

        return attributes
    }
}
