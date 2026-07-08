@preconcurrency import Foundation
import SwiftUI

#if os(macOS)
import AppKit
import IOKit.pwr_mgt
fileprivate typealias SGHostView = NSView
#else
import UIKit
fileprivate typealias SGHostView = UIView
#endif

struct PlaybackIdlePreventionToken: Hashable {
    fileprivate let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

@MainActor
enum PlaybackIdlePrevention {
    static let streamDetail = PlaybackIdlePreventionToken("stream-detail")

    private static var activeTokenCounts = [PlaybackIdlePreventionToken: Int]()
#if os(macOS)
    private static var assertionID = IOPMAssertionID(0)
#endif

    static func acquire(_ token: PlaybackIdlePreventionToken) {
        let wasInactive = activeTokenCounts.isEmpty
        activeTokenCounts[token, default: 0] += 1

        if wasInactive {
            enableSystemIdlePrevention()
        }
    }

    static func release(_ token: PlaybackIdlePreventionToken) {
        guard let count = activeTokenCounts[token] else { return }

        if count <= 1 {
            activeTokenCounts.removeValue(forKey: token)
        } else {
            activeTokenCounts[token] = count - 1
        }

        if activeTokenCounts.isEmpty {
            disableSystemIdlePrevention()
        }
    }

    private static func enableSystemIdlePrevention() {
#if os(iOS) || os(tvOS)
        UIApplication.shared.isIdleTimerDisabled = true
#elseif os(macOS)
        guard assertionID == 0 else { return }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "HiPlayer video playback" as CFString,
            &assertionID
        )

        if result != kIOReturnSuccess {
            assertionID = 0
        }
#endif
    }

    private static func disableSystemIdlePrevention() {
#if os(iOS) || os(tvOS)
        UIApplication.shared.isIdleTimerDisabled = false
#elseif os(macOS)
        guard assertionID != 0 else { return }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
#endif
    }
}

enum SGPlayerCompatibility {
    static var isAvailable: Bool {
        SGPlayerRuntime.playerClass != nil
    }
}

private struct SGPlayerSource: Equatable {

    let streamURL: StreamURL

    var url: URL { streamURL.url }
    var headers: [String: String] { streamURL.headers }

    init?(urlString: String) {
        guard let streamURL = StreamURL(urlString) else { return nil }
        self.streamURL = streamURL
    }

    private init(streamURL: StreamURL) {
        self.streamURL = streamURL
    }

    func replacingURL(_ url: URL) -> Self {
        Self(streamURL: streamURL.replacingURL(url))
    }

    var demuxerOptions: [String: Any] {
        let userAgent = streamURL.headerValue(named: "User-Agent") ?? Self.defaultUserAgent
        var options: [String: Any] = [
            "reconnect": 1,
            "reconnect_streamed": 1,
            "reconnect_delay_max": 5,
            "timeout": 20 * 1_000_000,
            "rw_timeout": 20 * 1_000_000,
            "user-agent": userAgent,
            "headers": httpHeaderString(userAgent: userAgent)
        ]

        if let referer = streamURL.headerValue(named: "Referer") {
            options["referer"] = referer
        }
        return options
    }

    private func httpHeaderString(userAgent: String) -> String {
        var headerLines: [(String, String)] = [
            ("User-Agent", userAgent),
            ("Accept", "*/*"),
            ("Connection", "keep-alive")
        ]

        for (key, value) in headers where key.compare("User-Agent", options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame {
            headerLines.append((key, value))
        }

        return headerLines
            .map { "\($0.0): \(StreamURL.sanitizedHeaderValue($0.1))" }
            .joined(separator: "\r\n") + "\r\n"
    }

    private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}

final class SGPlayerCompatibilitySession {

    private let player: NSObject
    private let idlePreventionToken = PlaybackIdlePreventionToken("sgplayer-\(UUID().uuidString)")
    private var requestedURLString: String?
    private var originalSource: SGPlayerSource?
    private var loadedSource: SGPlayerSource?
    private var onPlaybackError: ((String?) -> Void)?
    private var onPlaybackStateChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?
    private var isIdlePreventionActive = false
    private var didAttemptHLSFallback = false
    private weak var attachedView: SGHostView?
    private var attachedViewPriority = 0
    private weak var primaryView: SGHostView?
    private var isPlaybackRequested = true

    init?(urlString: String, onPlaybackError: ((String?) -> Void)? = nil) {
        guard let playerClass = SGPlayerRuntime.playerClass as? NSObject.Type else {
            return nil
        }

        self.player = playerClass.init()
        self.onPlaybackError = onPlaybackError
        observePlayerInfo()
        // Opening the stream is deferred to the first replace()/attach();
        // SwiftUI evaluates @State initial values on every view-struct
        // construction and discards the extras, so an eager open here would
        // spawn abandoned network connections on each parent re-render.
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        let token = idlePreventionToken
        Task { @MainActor in
            PlaybackIdlePrevention.release(token)
        }
    }

    func setPlaybackErrorHandler(_ handler: @escaping (String?) -> Void) {
        onPlaybackError = handler
    }

    func setPlaybackStateHandler(_ handler: @escaping (Bool) -> Void) {
        onPlaybackStateChange = handler
        reportPlaybackState()
    }

    func replace(with urlString: String, forceReload: Bool = false) {
        guard forceReload || requestedURLString != urlString else { return }
        guard let source = SGPlayerSource(urlString: urlString) else {
            reportPlaybackError(String(localized: "The channel URL is invalid."))
            return
        }

        requestedURLString = urlString
        originalSource = source
        didAttemptHLSFallback = false
        if forceReload {
            // A mid-stream failure leaves `loadedSource` set to the same
            // parsed source; without clearing it, open()'s dedupe guard
            // would turn a user-initiated retry into a no-op.
            loadedSource = nil
        }
        open(source, allowsFallback: true)
    }

    private func open(_ source: SGPlayerSource, allowsFallback: Bool) {
        guard loadedSource != source else { return }

        loadedSource = source
        reportPlaybackError(nil)
        configureDemuxerOptions(for: source)
        let selector = NSSelectorFromString("replaceWithURL:")
        guard player.responds(to: selector) else {
            loadedSource = nil
            reportPlaybackError(String(localized: "SGPlayer is not compatible with this build."))
            return
        }

        let implementation = player.method(for: selector)
        typealias ReplaceMessage = @convention(c) (AnyObject, Selector, NSURL) -> Bool
        let replace = unsafeBitCast(implementation, to: ReplaceMessage.self)
        if !replace(player, selector, source.url as NSURL) {
            loadedSource = nil
            if allowsFallback, switchToHLSFallback() {
                return
            }
            reportPlaybackError(String(localized: "SGPlayer could not open this channel."))
        }
    }

    fileprivate func attach(to view: SGHostView, priority: Int = 0) {
        configureHostView(view)
        // Remember the inline (priority 0) surface so the renderer can be
        // handed back to it when a higher-priority full-screen surface goes
        // away.
        if priority == 0 {
            primaryView = view
        }
        let renderer = renderer()
        if attachedView !== view {
            // While a full-screen surface holds the renderer, SwiftUI keeps
            // updating the covered inline surface; a lower-priority attach
            // must not steal the video back into the hidden view.
            if attachedView != nil, priority < attachedViewPriority {
                resumeIfPlaybackRequested()
                return
            }
            attachedView = view
            attachedViewPriority = priority
            renderer?.setValue(view, forKey: "view")
        } else {
            attachedViewPriority = priority
        }
        renderer?.setValue(NSNumber(value: 1), forKey: "scalingMode")
        resumeIfPlaybackRequested()
    }

    fileprivate func detach(from view: SGHostView? = nil) {
        if let view {
            if primaryView === view {
                primaryView = nil
            }
            if attachedView !== view {
                return
            }
        }
        attachedView = nil
        attachedViewPriority = 0
        renderer()?.setValue(nil, forKey: "view")
        // Hand the renderer back to the still-alive inline surface so leaving
        // a full-screen surface doesn't leave the video detached (audio-only).
        if let primaryView, primaryView !== view {
            attach(to: primaryView, priority: 0)
        }
    }

    func play() {
        isPlaybackRequested = true
        reportPlaybackError(nil)
        sendBooleanMessage("play")
        updateIdlePrevention(isPlaying: true)
        reportPlaybackState()
    }

    func pause() {
        isPlaybackRequested = false
        sendBooleanMessage("pause")
        updateIdlePrevention(isPlaying: false)
        reportPlaybackState()
    }

    // Called from SwiftUI view updates, which re-run on every render tick;
    // unlike play() this must not override a user-initiated pause or clear
    // a pending playback error.
    private func resumeIfPlaybackRequested() {
        guard isPlaybackRequested else { return }
        sendBooleanMessage("play")
        updateIdlePrevention(isPlaying: true)
        reportPlaybackState()
    }

    var isPlaying: Bool {
        boolMessage("wantsToPlay") ?? false
    }

    var volume: Double {
        get {
            doubleMessage("volume", on: audioRenderer()) ?? 1
        }
        set {
            guard let audioRenderer = audioRenderer() else { return }
            setDoubleMessage("setVolume:", value: min(max(newValue, 0), 1), on: audioRenderer)
        }
    }

    private func observePlayerInfo() {
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("SGPlayerDidChangeInfosNotification"),
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reportCurrentErrorIfNeeded()
                self?.reportPlaybackState()
            }
        }
    }

    private func audioRenderer() -> NSObject? {
        objectMessage("audioRenderer") as? NSObject
    }

    private func renderer() -> NSObject? {
        let selector = NSSelectorFromString("videoRenderer")
        guard player.responds(to: selector) else { return nil }

        let implementation = player.method(for: selector)
        typealias ObjectMessage = @convention(c) (AnyObject, Selector) -> AnyObject?
        let message = unsafeBitCast(implementation, to: ObjectMessage.self)
        return message(player, selector) as? NSObject
    }

    private func reportCurrentErrorIfNeeded() {
        guard let error = objectMessage("error") as? NSError else { return }
        if switchToHLSFallback() {
            return
        }
        reportPlaybackError(String(format: String(localized: "SGPlayer failed: %@"), error.localizedDescription))
    }

    @discardableResult
    private func switchToHLSFallback() -> Bool {
        guard !didAttemptHLSFallback,
              let originalSource,
              let fallbackURL = StreamPlayerController.hlsFallbackURL(for: originalSource.url) else {
            return false
        }

        didAttemptHLSFallback = true
        let shouldResume = isPlaying
        open(originalSource.replacingURL(fallbackURL), allowsFallback: false)
        if shouldResume {
            play()
        }
        return true
    }

    private func configureDemuxerOptions(for source: SGPlayerSource) {
        guard let options = objectMessage("options") as? NSObject,
              let demuxer = objectMessage("demuxer", on: options) as? NSObject else {
            return
        }

        var mergedOptions = objectMessage("options", on: demuxer) as? [String: Any] ?? [:]
        for (key, value) in source.demuxerOptions {
            mergedOptions[key] = value
        }
        setObjectMessage("setOptions:", value: mergedOptions as NSDictionary, on: demuxer)
    }

    private func reportPlaybackState() {
        let isPlaying = isPlaying
        updateIdlePrevention(isPlaying: isPlaying)
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackStateChange?(isPlaying)
        }
    }

    private func updateIdlePrevention(isPlaying: Bool) {
        guard isIdlePreventionActive != isPlaying else { return }
        isIdlePreventionActive = isPlaying

        let token = idlePreventionToken
        Task { @MainActor in
            if isPlaying {
                PlaybackIdlePrevention.acquire(token)
            } else {
                PlaybackIdlePrevention.release(token)
            }
        }
    }

    private func reportPlaybackError(_ message: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackError?(message)
        }
    }

    @discardableResult
    private func sendBooleanMessage(_ selectorName: String) -> Bool {
        let selector = NSSelectorFromString(selectorName)
        guard player.responds(to: selector) else { return false }

        let implementation = player.method(for: selector)
        typealias BooleanMessage = @convention(c) (AnyObject, Selector) -> Bool
        let message = unsafeBitCast(implementation, to: BooleanMessage.self)
        return message(player, selector)
    }

    private func boolMessage(_ selectorName: String) -> Bool? {
        let selector = NSSelectorFromString(selectorName)
        guard player.responds(to: selector) else { return nil }

        let implementation = player.method(for: selector)
        typealias BooleanMessage = @convention(c) (AnyObject, Selector) -> Bool
        let message = unsafeBitCast(implementation, to: BooleanMessage.self)
        return message(player, selector)
    }

    private func objectMessage(_ selectorName: String) -> AnyObject? {
        objectMessage(selectorName, on: player)
    }

    private func objectMessage(_ selectorName: String, on object: NSObject?) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard let object, object.responds(to: selector) else { return nil }

        let implementation = object.method(for: selector)
        typealias ObjectMessage = @convention(c) (AnyObject, Selector) -> AnyObject?
        let message = unsafeBitCast(implementation, to: ObjectMessage.self)
        return message(object, selector)
    }

    private func setObjectMessage(_ selectorName: String, value: AnyObject?, on object: NSObject) {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return }

        let implementation = object.method(for: selector)
        typealias SetObjectMessage = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let message = unsafeBitCast(implementation, to: SetObjectMessage.self)
        message(object, selector, value)
    }

    private func doubleMessage(_ selectorName: String, on object: NSObject?) -> Double? {
        let selector = NSSelectorFromString(selectorName)
        guard let object, object.responds(to: selector) else { return nil }

        let implementation = object.method(for: selector)
        typealias DoubleMessage = @convention(c) (AnyObject, Selector) -> Double
        let message = unsafeBitCast(implementation, to: DoubleMessage.self)
        return message(object, selector)
    }

    private func setDoubleMessage(_ selectorName: String, value: Double, on object: NSObject) {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return }

        let implementation = object.method(for: selector)
        typealias SetDoubleMessage = @convention(c) (AnyObject, Selector, Double) -> Void
        let message = unsafeBitCast(implementation, to: SetDoubleMessage.self)
        message(object, selector, value)
    }

    private func configureHostView(_ view: SGHostView) {
#if os(macOS)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
#else
        view.backgroundColor = .black
#endif
    }
}

private enum SGPlayerRuntime {

    static var playerClass: AnyClass? {
        return NSClassFromString("SGPlayer") ?? NSClassFromString("SGPlayer.SGPlayer")
    }
}

#if os(macOS)
struct SGPlayerCompatibilityView: NSViewRepresentable {

    let urlString: String
    let widthMultiplier: CGFloat
    let sharedSession: SGPlayerCompatibilitySession?
    let attachPriority: Int
    let onPlaybackError: (String?) -> Void

    init(
        urlString: String,
        widthMultiplier: CGFloat = 1,
        sharedSession: SGPlayerCompatibilitySession? = nil,
        attachPriority: Int = 0,
        onPlaybackError: @escaping (String?) -> Void
    ) {
        self.urlString = urlString
        self.widthMultiplier = widthMultiplier
        self.sharedSession = sharedSession
        self.attachPriority = attachPriority
        self.onPlaybackError = onPlaybackError
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view, urlString: urlString, priority: attachPriority, onPlaybackError: onPlaybackError)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView, urlString: urlString, priority: attachPriority, onPlaybackError: onPlaybackError)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: sharedSession ?? SGPlayerCompatibilitySession(urlString: urlString, onPlaybackError: onPlaybackError))
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach(from: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let adjustedWidth = width * widthMultiplier
        return .init(width: adjustedWidth, height: adjustedWidth * (9.0 / 16.0))
    }

    final class Coordinator {

        private let session: SGPlayerCompatibilitySession?

        init(session: SGPlayerCompatibilitySession?) {
            self.session = session
        }

        func attach(to view: NSView, urlString: String, priority: Int, onPlaybackError: @escaping (String?) -> Void) {
            guard let session else {
                DispatchQueue.main.async {
                    onPlaybackError(String(localized: "SGPlayer is not available in this build."))
                }
                return
            }

            session.setPlaybackErrorHandler(onPlaybackError)
            session.replace(with: urlString)
            session.attach(to: view, priority: priority)
        }

        func detach(from view: NSView) {
            session?.detach(from: view)
        }
    }
}
#else
struct SGPlayerCompatibilityView: UIViewRepresentable {

    let urlString: String
    let widthMultiplier: CGFloat
    let sharedSession: SGPlayerCompatibilitySession?
    let attachPriority: Int
    let onPlaybackError: (String?) -> Void

    init(
        urlString: String,
        widthMultiplier: CGFloat = 1,
        sharedSession: SGPlayerCompatibilitySession? = nil,
        attachPriority: Int = 0,
        onPlaybackError: @escaping (String?) -> Void
    ) {
        self.urlString = urlString
        self.widthMultiplier = widthMultiplier
        self.sharedSession = sharedSession
        self.attachPriority = attachPriority
        self.onPlaybackError = onPlaybackError
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        context.coordinator.attach(to: view, urlString: urlString, priority: attachPriority, onPlaybackError: onPlaybackError)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attach(to: uiView, urlString: urlString, priority: attachPriority, onPlaybackError: onPlaybackError)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: sharedSession ?? SGPlayerCompatibilitySession(urlString: urlString, onPlaybackError: onPlaybackError))
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach(from: uiView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let adjustedWidth = width * widthMultiplier
        return .init(width: adjustedWidth, height: adjustedWidth * (9.0 / 16.0))
    }

    final class Coordinator {

        private let session: SGPlayerCompatibilitySession?

        init(session: SGPlayerCompatibilitySession?) {
            self.session = session
        }

        func attach(to view: UIView, urlString: String, priority: Int, onPlaybackError: @escaping (String?) -> Void) {
            guard let session else {
                DispatchQueue.main.async {
                    onPlaybackError(String(localized: "SGPlayer is not available in this build."))
                }
                return
            }

            session.setPlaybackErrorHandler(onPlaybackError)
            session.replace(with: urlString)
            session.attach(to: view, priority: priority)
        }

        func detach(from view: UIView) {
            session?.detach(from: view)
        }
    }
}
#endif
