
import Foundation

nonisolated extension URLSession {

    /// User-Agent sent for playlist/EPG/logo downloads. Pinned to one value so
    /// every platform fetches identically: the default URLSession User-Agent
    /// differs by OS (CFNetwork/Darwin versions), and many IPTV hosts serve
    /// different content — or block — based on it, which otherwise makes the
    /// same playlist load a different channel list on iOS vs macOS vs tvOS.
    static let downloadUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Shared session for playlist/EPG/logo downloads. Unlike `shared` it
    /// fails instead of hanging forever on slow or dead IPTV servers.
    static let download: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        configuration.httpAdditionalHeaders = ["User-Agent": downloadUserAgent]
        return URLSession(configuration: configuration)
    }()
}
