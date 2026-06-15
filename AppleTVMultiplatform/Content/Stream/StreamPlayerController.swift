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
    var onPlaybackError: (String?) -> Void

    private let originalURL: URL?
    private var activeURL: URL?
    private let logger = Container.shared.logger()
    private var playerObservers: Set<AnyCancellable> = []
    private var itemObservers: Set<AnyCancellable> = []
    private var recoveryTask: Task<Void, Never>?
    private var videoStartupTask: Task<Void, Never>?
    private var playbackTimeObserver: PlaybackTimeObserver?
    private var consecutiveFailures = 0
    private var didAttemptHLSFallback = false
    private var terminalPlaybackError: String?
    private var lastObservedPlaybackTime: CMTime?
    private var lastPlaybackProgressDate = Date()
    private var shouldPlayWhenReady: Bool

    init(
        urlString: String,
        autoplays: Bool = true,
        onPlaybackError: @escaping (String?) -> Void = { _ in }
    ) {
        self.onPlaybackError = onPlaybackError
        originalURL = URL(string: urlString)
        activeURL = originalURL
        shouldPlayWhenReady = autoplays
        load()

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                guard shouldPlayWhenReady else {
                    if status == .playing {
                        player.pause()
                    }
                    return
                }
                if status == .playing {
                    consecutiveFailures = 0
                    clearPlaybackError()
                    markPlaybackProgress(at: player.currentTime())
                } else if status == .waitingToPlayAtSpecifiedRate {
                    scheduleStallRecovery(
                        trigger: "player waiting \(player.reasonForWaitingToPlay?.rawValue ?? "unknown")",
                        delay: Self.waitingRecoveryDelay
                    )
                }
            }
            .store(in: &playerObservers)

        NotificationCenter.default.publisher(for: Self.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recoverIfFailed()
            }
            .store(in: &playerObservers)

        playbackTimeObserver = PlaybackTimeObserver(player.addPeriodicTimeObserver(
            forInterval: Self.playbackProgressObservationInterval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.handlePeriodicPlaybackTime(time)
            }
        })
    }

    deinit {
        recoveryTask?.cancel()
        videoStartupTask?.cancel()
        let playbackTimeObserver = playbackTimeObserver
        let player = player
        Task { @MainActor in
            playbackTimeObserver?.remove(from: player)
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Private

    private func load() {
        guard terminalPlaybackError == nil else { return }
        guard let activeURL else {
            logger.error("Cannot play stream, invalid URL")
            presentTerminalPlaybackError(String(localized: "This stream URL is not valid."))
            return
        }
        itemObservers = []
        cancelCurrentItemLoading()
        resetPlaybackProgress()
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
            .publisher(for: .AVPlayerItemNewErrorLogEntry, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                self?.handleNewErrorLogEntry(from: item)
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
        if shouldPlayWhenReady {
            player.play()
            scheduleVideoStartupCheck(for: item, sourceURL: activeURL)
        } else {
            player.pause()
        }
    }

    private func scheduleRecovery(after error: Error?) {
        guard shouldPlayWhenReady, terminalPlaybackError == nil else { return }
        recoveryTask?.cancel()
        recoveryTask = nil
        if let error {
            logger.error(error, private: activeURL?.absoluteString ?? originalURL?.absoluteString ?? "")
            if Self.isForbiddenResourceError(error) {
                presentTerminalPlaybackError(Self.forbiddenResourceMessage)
                return
            }
            if Self.isUnsupportedMediaFormatError(error) {
                presentTerminalPlaybackError(Self.unsupportedStreamFormatMessage)
                return
            }
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
        guard shouldPlayWhenReady else { return }
        logger.info("Stream stalled", private: activeURL?.absoluteString ?? "")
        scheduleStallRecovery(trigger: "playback stalled notification", delay: Self.stallRecoveryDelay)
    }

    private func scheduleStallRecovery(trigger: String, delay: TimeInterval) {
        guard shouldPlayWhenReady, recoveryTask == nil, terminalPlaybackError == nil else { return }
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            recoveryTask = nil
            recoverIfStillStuck(trigger: trigger)
        }
    }

    private func recoverIfStillStuck(trigger: String) {
        guard shouldPlayWhenReady, terminalPlaybackError == nil else { return }
        guard let item = player.currentItem else { return }

        if let error = item.error {
            logger.error(error, private: activeURL?.absoluteString ?? originalURL?.absoluteString ?? "")
            if Self.isForbiddenResourceError(error) {
                presentTerminalPlaybackError(Self.forbiddenResourceMessage)
                return
            }
            if Self.isUnsupportedMediaFormatError(error) {
                presentTerminalPlaybackError(Self.unsupportedStreamFormatMessage)
                return
            }
            if Self.isRangeWithoutContentLengthError(error), switchToHLSFallback() {
                return
            }
        }

        guard item.status == .failed
                || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                || playbackHasStoppedProgressing() else {
            return
        }

        consecutiveFailures += 1
        logger.info("Stream did not recover from \(trigger), reloading attempt \(consecutiveFailures)", private: activeURL?.absoluteString ?? "")
        load()
    }

    private func recoverIfFailed() {
        guard shouldPlayWhenReady, recoveryTask == nil, terminalPlaybackError == nil else { return }
        guard let item = player.currentItem, item.status != .failed else {
            logger.info("Reloading failed stream on activation", private: activeURL?.absoluteString ?? "")
            consecutiveFailures = 0
            load()
            return
        }
    }

    func retry() {
        shouldPlayWhenReady = true
        recoveryTask?.cancel()
        recoveryTask = nil
        videoStartupTask?.cancel()
        videoStartupTask = nil
        consecutiveFailures = 0
        didAttemptHLSFallback = false
        activeURL = originalURL
        terminalPlaybackError = nil
        updatePlaybackError(nil)
        load()
    }

    func play() {
        shouldPlayWhenReady = true
        resetPlaybackProgress()

        guard terminalPlaybackError == nil else { return }
        guard let item = player.currentItem else {
            load()
            return
        }

        if item.status == .failed {
            consecutiveFailures = 0
            load()
            return
        }

        player.play()
        if let activeURL {
            scheduleVideoStartupCheck(for: item, sourceURL: activeURL)
        }
    }

    func pause() {
        shouldPlayWhenReady = false
        recoveryTask?.cancel()
        recoveryTask = nil
        videoStartupTask?.cancel()
        videoStartupTask = nil
        player.pause()
    }

    func setPlaybackErrorHandler(_ handler: @escaping (String?) -> Void) {
        onPlaybackError = handler
        if let terminalPlaybackError {
            updatePlaybackError(terminalPlaybackError)
        }
    }

    private func switchToHLSFallback() -> Bool {
        guard shouldPlayWhenReady,
              !didAttemptHLSFallback,
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

    private func scheduleVideoStartupCheck(for item: AVPlayerItem, sourceURL: URL) {
        videoStartupTask?.cancel()
        videoStartupTask = Task { [weak self, weak item] in
            try? await Task.sleep(for: .seconds(Self.videoStartupGracePeriod))
            guard let self, let item, !Task.isCancelled else { return }
            await inspectVideoStartup(for: item, sourceURL: sourceURL)
        }
    }

    private func inspectVideoStartup(for item: AVPlayerItem, sourceURL: URL) async {
        guard shouldPlayWhenReady,
              terminalPlaybackError == nil,
              player.currentItem === item,
              player.timeControlStatus != .paused else {
            return
        }

        let tracks = (try? await item.asset.load(.tracks)) ?? []
        let videoTracks = tracks.filter { $0.mediaType == .video }
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        guard !audioTracks.isEmpty else { return }

        let presentationSize = item.presentationSize
        let hasVisibleVideo = presentationSize.width > 0 && presentationSize.height > 0
        guard !hasVisibleVideo else { return }

        let codec = await Self.codecText(for: videoTracks.first)
        logger.info(
            "Stream audio is playing but no visible video track is available",
            private: "\(sourceURL.absoluteString) codec=\(codec ?? "unknown")"
        )

        if switchToHLSFallback() {
            return
        }

        presentTerminalPlaybackError(Self.unsupportedVideoMessage(codec: codec))
    }

    private func handleNewErrorLogEntry(from item: AVPlayerItem?) {
        guard shouldPlayWhenReady else { return }
        guard let event = item?.errorLog()?.events.last else { return }
        let comment = event.errorComment ?? ""
        let domain = event.errorDomain
        let url = event.uri ?? activeURL?.absoluteString ?? originalURL?.absoluteString ?? ""
        logger.error(
            "Stream error log entry \(event.errorStatusCode) \(domain) \(comment)",
            private: url
        )

        if Self.isForbiddenResourceLog(statusCode: event.errorStatusCode, comment: comment) {
            presentTerminalPlaybackError(Self.forbiddenResourceMessage)
            return
        }

        guard Self.shouldRecoverFromErrorLog(
            statusCode: event.errorStatusCode,
            domain: event.errorDomain,
            comment: event.errorComment
        ) else {
            return
        }

        scheduleStallRecovery(
            trigger: "player error log \(event.errorStatusCode)",
            delay: Self.errorLogRecoveryDelay
        )
    }

    private func handlePeriodicPlaybackTime(_ time: CMTime) {
        guard shouldPlayWhenReady, terminalPlaybackError == nil else { return }
        guard player.currentItem != nil else {
            resetPlaybackProgress()
            return
        }
        guard player.timeControlStatus != .paused else { return }

        if markPlaybackProgressIfAdvanced(to: time) {
            if player.timeControlStatus == .playing {
                consecutiveFailures = 0
                clearPlaybackError()
            }
            return
        }

        guard player.timeControlStatus == .playing, playbackHasStoppedProgressing() else { return }
        scheduleStallRecovery(trigger: "playback progress watchdog", delay: 0)
    }

    static func isRangeWithoutContentLengthError(_ error: Error) -> Bool {
        for current in errorChain(for: error) {
            if current.domain == "CoreMediaErrorDomain", current.code == -12939 {
                return true
            }
            if current.localizedDescription.localizedCaseInsensitiveContains("byte range and no content length") {
                return true
            }
        }
        return false
    }

    static func isForbiddenResourceError(_ error: Error) -> Bool {
        errorChain(for: error).contains { current in
            if current.domain == NSURLErrorDomain, current.code == -1102 {
                return true
            }
            if current.code == 403 {
                return true
            }
            let description = current.localizedDescription
            return description.localizedCaseInsensitiveContains("HTTP 403")
                || description.localizedCaseInsensitiveContains("403: Forbidden")
                || description.localizedCaseInsensitiveContains("Forbidden")
        }
    }

    static func isUnsupportedMediaFormatError(_ error: Error) -> Bool {
        errorChain(for: error).contains { current in
            if current.domain == AVFoundationErrorDomain, current.code == AVError.Code.decoderNotFound.rawValue {
                return true
            }
            if current.domain == AVFoundationErrorDomain, current.code == -11828 {
                return true
            }
            if current.domain == NSOSStatusErrorDomain, current.code == -12847 {
                return true
            }
            let description = current.localizedDescription
            return description.localizedCaseInsensitiveContains("media format is not supported")
                || description.localizedCaseInsensitiveContains("Cannot Open")
        }
    }

    static func isForbiddenResourceLog(statusCode: Int, comment: String?) -> Bool {
        statusCode == 403
            || comment?.localizedCaseInsensitiveContains("HTTP 403") == true
            || comment?.localizedCaseInsensitiveContains("403: Forbidden") == true
            || comment?.localizedCaseInsensitiveContains("Forbidden") == true
    }

    static func shouldRecoverFromErrorLog(statusCode: Int, domain: String?, comment: String?) -> Bool {
        if isForbiddenResourceLog(statusCode: statusCode, comment: comment) {
            return false
        }
        if statusCode != 0 {
            return true
        }
        return domain?.isEmpty == false || comment?.isEmpty == false
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

    private static func codecText(for track: AVAssetTrack?) async -> String? {
        guard
            let track,
            let formatDescription = (try? await track.load(.formatDescriptions))?.first
        else {
            return nil
        }

        return CMFormatDescriptionGetMediaSubType(formatDescription).fourCCString
    }

#if os(macOS)
    private static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
#else
    private static let didBecomeActiveNotification = UIApplication.didBecomeActiveNotification
#endif
}

private final class PlaybackTimeObserver: @unchecked Sendable {

    private let token: Any

    init(_ token: Any) {
        self.token = token
    }

    func remove(from player: AVPlayer) {
        player.removeTimeObserver(token)
    }
}

private extension StreamPlayerController {

    static let errorLogRecoveryDelay: TimeInterval = 3
    static let stallRecoveryDelay: TimeInterval = 8
    static let waitingRecoveryDelay: TimeInterval = 12
    static let playbackProgressTimeout: TimeInterval = 20
    static let playbackProgressObservationInterval = CMTime(seconds: 2, preferredTimescale: 1)
    static let videoStartupGracePeriod: TimeInterval = 15

    static var forbiddenResourceMessage: String {
        String(localized: "You do not have permission to access this channel. Check your playlist, subscription, or server access.")
    }

    static var unsupportedStreamFormatMessage: String {
        String(localized: "This stream format is not supported by AVPlayer on this device. Try another source or a lower-quality stream.")
    }

    static func unsupportedVideoMessage(codec: String?) -> String {
        guard let codec, !codec.isEmpty else {
            return String(localized: "This channel's video format is not supported by AVPlayer on this device. Try another source or a lower-quality stream.")
        }
        return String(format: String(localized: "This channel uses %@ video, which AVPlayer cannot display on this device. Try another source or a lower-quality stream."), codec)
    }

    func presentTerminalPlaybackError(_ message: String) {
        recoveryTask?.cancel()
        recoveryTask = nil
        videoStartupTask?.cancel()
        videoStartupTask = nil
        terminalPlaybackError = message
        player.pause()
        updatePlaybackError(message)
    }

    func clearPlaybackError() {
        guard terminalPlaybackError == nil else { return }
        updatePlaybackError(nil)
    }

    func updatePlaybackError(_ message: String?) {
        DispatchQueue.main.async { [onPlaybackError] in
            onPlaybackError(message)
        }
    }

    func cancelCurrentItemLoading() {
        guard let item = player.currentItem else { return }
        item.cancelPendingSeeks()
        item.asset.cancelLoading()
    }

    func resetPlaybackProgress() {
        lastObservedPlaybackTime = nil
        lastPlaybackProgressDate = Date()
    }

    func markPlaybackProgress(at time: CMTime) {
        guard time.isNumeric else { return }
        lastObservedPlaybackTime = time
        lastPlaybackProgressDate = Date()
    }

    func markPlaybackProgressIfAdvanced(to time: CMTime) -> Bool {
        guard time.isNumeric else { return false }
        guard let lastObservedPlaybackTime, lastObservedPlaybackTime.isNumeric else {
            markPlaybackProgress(at: time)
            return true
        }

        let delta = CMTimeGetSeconds(CMTimeSubtract(time, lastObservedPlaybackTime))
        guard delta.isFinite, abs(delta) >= 0.5 else { return false }
        markPlaybackProgress(at: time)
        return true
    }

    func playbackHasStoppedProgressing() -> Bool {
        Date().timeIntervalSince(lastPlaybackProgressDate) >= Self.playbackProgressTimeout
    }

    static func errorChain(for error: Error) -> [NSError] {
        var pending = [error as NSError]
        var seen = Set<String>()
        var chain: [NSError] = []

        while let current = pending.popLast() {
            let key = "\(current.domain):\(current.code):\(current.localizedDescription)"
            guard seen.insert(key).inserted else { continue }
            chain.append(current)

            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                pending.append(underlying)
            }
            if let underlyingErrors = current.userInfo["NSDetailedErrors"] as? [NSError] {
                pending.append(contentsOf: underlyingErrors)
            }
        }

        return chain
    }
}

private extension FourCharCode {

    var fourCCString: String {
        let bytes: [UInt8] = [
            UInt8((self >> 24) & 0xff),
            UInt8((self >> 16) & 0xff),
            UInt8((self >> 8) & 0xff),
            UInt8(self & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(self)"
    }
}
