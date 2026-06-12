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

    private let url: URL?
    private let logger = Container.shared.logger()
    private var playerObservers: Set<AnyCancellable> = []
    private var itemObservers: Set<AnyCancellable> = []
    private var recoveryTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    init(urlString: String) {
        url = URL(string: urlString)
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
        guard let url else {
            logger.error("Cannot play stream, invalid URL")
            return
        }
        itemObservers = []
        let item = AVPlayerItem(url: url)

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
            logger.error(error, private: url?.absoluteString ?? "")
        }
        consecutiveFailures += 1
        let delay = min(pow(2, Double(consecutiveFailures - 1)), 30)
        logger.info("Stream failed, reloading in \(Int(delay))s, attempt \(consecutiveFailures)", private: url?.absoluteString ?? "")
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            recoveryTask = nil
            load()
        }
    }

    private func recoverAfterStall() {
        guard recoveryTask == nil else { return }
        logger.info("Stream stalled", private: url?.absoluteString ?? "")
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            recoveryTask = nil
            // Still stuck buffering after the grace period. A user initiated
            // pause is .paused and is left alone.
            if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                logger.info("Stream did not recover from stall, reloading", private: url?.absoluteString ?? "")
                consecutiveFailures += 1
                load()
            }
        }
    }

    private func recoverIfFailed() {
        guard recoveryTask == nil else { return }
        guard let item = player.currentItem, item.status != .failed else {
            logger.info("Reloading failed stream on activation", private: url?.absoluteString ?? "")
            consecutiveFailures = 0
            load()
            return
        }
    }

#if os(macOS)
    private static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
#else
    private static let didBecomeActiveNotification = UIApplication.didBecomeActiveNotification
#endif
}
