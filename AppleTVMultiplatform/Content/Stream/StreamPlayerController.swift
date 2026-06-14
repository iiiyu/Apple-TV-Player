import AVKit
import Combine
import FactoryKit
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Owns an AVPlayer for a live stream and automatically restarts playback
/// when the stream fails or stalls without recovering on its own.
final class StreamPlayerController {

    let player = AVPlayer()

    private let originalURL: URL?
    private var activeURL: URL?
    private let logger = Container.shared.logger()
    private var playerObservers: Set<AnyCancellable> = []
    private var itemObservers: Set<AnyCancellable> = []
    private var recoveryTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var didAttemptHLSFallback = false

    init(urlString: String) {
        originalURL = URL(string: urlString)
        activeURL = originalURL
        load()

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .playing {
                    self?.consecutiveFailures = 0
                }
            }
            .store(in: &playerObservers)

        NotificationCenter.default.publisher(for: Self.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recoverIfFailed()
            }
            .store(in: &playerObservers)
    }

    deinit {
        recoveryTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Private

    private func load() {
        guard let activeURL else {
            logger.error("Cannot play stream, invalid URL")
            return
        }
        itemObservers = []
        let item = Self.playerItem(for: activeURL)

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                if status == .failed {
                    self?.scheduleRecovery(after: item?.error)
                }
            }
            .store(in: &itemObservers)

        NotificationCenter.default
            .publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self?.scheduleRecovery(after: error)
            }
            .store(in: &itemObservers)

        NotificationCenter.default
            .publisher(for: .AVPlayerItemPlaybackStalled, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recoverAfterStall()
            }
            .store(in: &itemObservers)

        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func scheduleRecovery(after error: Error?) {
        guard recoveryTask == nil else { return }
        if let error {
            logger.error(error, private: activeURL?.absoluteString ?? originalURL?.absoluteString ?? "")
            if Self.isRangeWithoutContentLengthError(error), switchToHLSFallback() {
                return
            }
        }
        consecutiveFailures += 1
        let delay = min(pow(2, Double(consecutiveFailures - 1)), 30)
        logger.info("Stream failed, reloading in \(Int(delay))s, attempt \(consecutiveFailures)", private: activeURL?.absoluteString ?? "")
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            recoveryTask = nil
            load()
        }
    }

    private func recoverAfterStall() {
        guard recoveryTask == nil else { return }
        logger.info("Stream stalled", private: activeURL?.absoluteString ?? "")
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            recoveryTask = nil
            // Still stuck buffering after the grace period. A user initiated
            // pause is .paused and is left alone.
            if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                logger.info("Stream did not recover from stall, reloading", private: activeURL?.absoluteString ?? "")
                consecutiveFailures += 1
                load()
            }
        }
    }

    private func recoverIfFailed() {
        guard recoveryTask == nil else { return }
        guard let item = player.currentItem, item.status != .failed else {
            logger.info("Reloading failed stream on activation", private: activeURL?.absoluteString ?? "")
            consecutiveFailures = 0
            load()
            return
        }
    }

    private func switchToHLSFallback() -> Bool {
        guard !didAttemptHLSFallback,
              let originalURL,
              let fallbackURL = Self.hlsFallbackURL(for: originalURL),
              fallbackURL != activeURL else {
            return false
        }
        didAttemptHLSFallback = true
        activeURL = fallbackURL
        consecutiveFailures = 0
        logger.info("Stream server rejected byte ranges, switching to HLS fallback", private: fallbackURL.absoluteString)
        load()
        return true
    }

    private static func playerItem(for url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let item = AVPlayerItem(asset: asset)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.preferredForwardBufferDuration = 5
        return item
    }

    static func isRangeWithoutContentLengthError(_ error: Error) -> Bool {
        var pending = [error as NSError]
        var seen = Set<String>()
        while let current = pending.popLast() {
            let key = "\(current.domain):\(current.code)"
            guard seen.insert(key).inserted else { continue }
            if current.domain == "CoreMediaErrorDomain", current.code == -12939 {
                return true
            }
            if current.localizedDescription.localizedCaseInsensitiveContains("byte range and no content length") {
                return true
            }
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                pending.append(underlying)
            }
        }
        return false
    }

    static func hlsFallbackURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let credentialsAndStreamID: ArraySlice<String>
        if pathComponents.count == 3 {
            credentialsAndStreamID = pathComponents[0...2]
        } else if pathComponents.count == 4, pathComponents[0].lowercased() == "live" {
            credentialsAndStreamID = pathComponents[1...3]
        } else {
            return nil
        }

        let user = credentialsAndStreamID[credentialsAndStreamID.startIndex]
        let password = credentialsAndStreamID[credentialsAndStreamID.index(after: credentialsAndStreamID.startIndex)]
        let streamComponent = credentialsAndStreamID[credentialsAndStreamID.index(credentialsAndStreamID.startIndex, offsetBy: 2)]
        let streamIDPath = streamComponent as NSString
        let streamExtension = streamIDPath.pathExtension.lowercased()
        guard streamExtension != "m3u8" else { return nil }

        let streamID = streamExtension.isEmpty
            ? streamComponent
            : streamIDPath.deletingPathExtension
        guard !streamID.isEmpty,
              streamID.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) else {
            return nil
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/live/\(user)/\(password)/\(streamID).m3u8"
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }

#if os(macOS)
    private static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
#else
    private static let didBecomeActiveNotification = UIApplication.didBecomeActiveNotification
#endif
}
