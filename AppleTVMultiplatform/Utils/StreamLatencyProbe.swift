import Foundation

struct StreamLatencyMeasurement: Equatable, Sendable {
    let milliseconds: Int

    var displayText: String {
        "\(milliseconds) ms"
    }
}

actor StreamLatencyProbe {

    static let shared = StreamLatencyProbe()

    private var cache: [String: StreamLatencyMeasurement] = [:]

    func measurement(for urlString: String) async -> StreamLatencyMeasurement? {
        if let cached = cache[urlString] {
            return cached
        }
        guard let url = URL(string: urlString), Self.isProbeable(url) else {
            return nil
        }
        guard let measurement = await Self.probe(url: url) else {
            return nil
        }
        cache[urlString] = measurement
        return measurement
    }

    static func isProbeable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private static func probe(url: URL) async -> StreamLatencyMeasurement? {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 3
        )
        request.httpMethod = "HEAD"

        let startedAt = Date()
        do {
            _ = try await URLSession.shared.data(for: request)
            let milliseconds = max(Int(Date().timeIntervalSince(startedAt) * 1000), 1)
            return StreamLatencyMeasurement(milliseconds: milliseconds)
        } catch {
            return nil
        }
    }
}
