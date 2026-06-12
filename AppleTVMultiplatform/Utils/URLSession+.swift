
import Foundation

nonisolated extension URLSession {

    /// Shared session for playlist/EPG/logo downloads. Unlike `shared` it
    /// fails instead of hanging forever on slow or dead IPTV servers.
    static let download: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()
}
