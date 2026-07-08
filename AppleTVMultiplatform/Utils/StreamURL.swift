import Foundation

/// Parses IPTV stream URLs of the form `url|Header1=value1&Header2=value2`,
/// the pipe-option syntax used by Kodi/VLC-style M3U playlists to attach HTTP
/// headers (User-Agent, Referer, …) to a channel.
///
/// `URL(string:)` cannot be used directly on these strings: on recent OSes the
/// lenient parser percent-encodes the `|` instead of failing, so the whole
/// `url|Header=…` string is sent to the server verbatim. Every playback engine
/// and the media-info loader must go through this type so AVPlayer, SGPlayer
/// and stream inspection all agree on the real URL and headers.
nonisolated struct StreamURL: Equatable, Sendable {

    let url: URL
    /// Header names normalized to their canonical casing (e.g. "User-Agent").
    let headers: [String: String]

    init?(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let urlPart: String
        let optionPart: String?
        if let separatorIndex = trimmed.firstIndex(of: "|") {
            urlPart = String(trimmed[..<separatorIndex])
            optionPart = String(trimmed[trimmed.index(after: separatorIndex)...])
        } else {
            urlPart = trimmed
            optionPart = nil
        }

        guard let url = Self.url(from: urlPart) else { return nil }
        self.url = url
        self.headers = optionPart.map(Self.headers(from:)) ?? [:]
    }

    private init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }

    func replacingURL(_ url: URL) -> Self {
        Self(url: url, headers: headers)
    }

    func headerValue(named name: String) -> String? {
        headers.first { key, _ in
            key.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }?.value
    }

    static func url(from string: String) -> URL? {
        if let url = URL(string: string) {
            return url
        }
        // Only escape spaces; re-encoding the whole string would turn an
        // already-escaped "%20" into "%2520".
        return URL(string: string.replacingOccurrences(of: " ", with: "%20"))
    }

    private static func headers(from optionPart: String) -> [String: String] {
        var headers: [String: String] = [:]

        for pair in optionPart.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let rawName = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let rawValue = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            guard let name = normalizedHeaderName(rawName) else { continue }

            let value = sanitizedHeaderValue(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
            if !value.isEmpty {
                headers[name] = value
            }
        }

        return headers
    }

    static func normalizedHeaderName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ scalar in
                  // Letters, digits, "-" (45) and "_" (95); playlists often
                  // write "User_Agent=…".
                  CharacterSet.alphanumerics.contains(scalar) || scalar.value == 45 || scalar.value == 95
              }) else {
            return nil
        }

        switch trimmed.replacingOccurrences(of: "_", with: "-").lowercased() {
        case "user-agent", "useragent":
            return "User-Agent"
        case "referer", "referrer":
            return "Referer"
        case "origin":
            return "Origin"
        case "cookie":
            return "Cookie"
        case "authorization":
            return "Authorization"
        default:
            return trimmed
        }
    }

    /// Strips CR/LF to prevent HTTP header injection through crafted playlists.
    static func sanitizedHeaderValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}
