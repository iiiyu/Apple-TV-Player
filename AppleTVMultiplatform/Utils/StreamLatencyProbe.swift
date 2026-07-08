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
    private var failures: [String: ContinuousClock.Instant] = [:]
    private var inFlight: [String: Task<StreamLatencyMeasurement?, Never>] = [:]
    private let clock = ContinuousClock()
    // Failed probes are remembered so list re-renders don't re-hit a dead
    // URL with a 3 s timeout each time, but they expire so a stream that
    // comes back up recovers its badge.
    private let failureRetryInterval: Duration = .seconds(60)

    func measurement(for urlString: String) async -> StreamLatencyMeasurement? {
        if let cached = cache[urlString] {
            return cached
        }
        if let failedAt = failures[urlString] {
            if clock.now - failedAt < failureRetryInterval {
                return nil
            }
            failures[urlString] = nil
        }
        // Resolve the real URL (dropping any `|Header=…` pipe-options) so
        // the probe hits the stream, not a percent-encoded options string.
        guard let url = StreamURL(urlString)?.url, Self.isProbeable(url) else {
            return nil
        }
        if let task = inFlight[urlString] {
            return await task.value
        }
        let task = Task { await Self.probe(url: url) }
        inFlight[urlString] = task
        let measurement = await task.value
        inFlight[urlString] = nil
        if let measurement {
            cache[urlString] = measurement
        } else {
            failures[urlString] = clock.now
        }
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

        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200 ... 399).contains(httpResponse.statusCode) {
                return nil
            }
            let milliseconds = max(Int((clock.now - startedAt) / .milliseconds(1)), 1)
            return StreamLatencyMeasurement(milliseconds: milliseconds)
        } catch {
            return nil
        }
    }
}
