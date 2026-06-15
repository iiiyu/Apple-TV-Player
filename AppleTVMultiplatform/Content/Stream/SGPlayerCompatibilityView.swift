@preconcurrency import Foundation
import SwiftUI

#if os(macOS)
import AppKit
fileprivate typealias SGHostView = NSView
#else
import UIKit
fileprivate typealias SGHostView = UIView
#endif

enum SGPlayerCompatibility {
    static var isAvailable: Bool {
        SGPlayerRuntime.playerClass != nil
    }
}

final class SGPlayerCompatibilitySession {

    private let player: NSObject
    private var loadedURL: URL?
    private var onPlaybackError: ((String?) -> Void)?
    private var onPlaybackStateChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?

    init?(urlString: String, onPlaybackError: ((String?) -> Void)? = nil) {
        guard let playerClass = SGPlayerRuntime.playerClass as? NSObject.Type else {
            return nil
        }

        self.player = playerClass.init()
        self.onPlaybackError = onPlaybackError
        observePlayerInfo()
        replace(with: urlString)
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setPlaybackErrorHandler(_ handler: @escaping (String?) -> Void) {
        onPlaybackError = handler
    }

    func setPlaybackStateHandler(_ handler: @escaping (Bool) -> Void) {
        onPlaybackStateChange = handler
        reportPlaybackState()
    }

    func replace(with urlString: String) {
        guard let url = URL(string: urlString) else {
            reportPlaybackError(String(localized: "The channel URL is invalid."))
            return
        }

        guard loadedURL != url else { return }
        loadedURL = url
        reportPlaybackError(nil)

        let selector = NSSelectorFromString("replaceWithURL:")
        guard player.responds(to: selector) else {
            reportPlaybackError(String(localized: "SGPlayer is not compatible with this build."))
            return
        }

        let implementation = player.method(for: selector)
        typealias ReplaceMessage = @convention(c) (AnyObject, Selector, NSURL) -> Bool
        let replace = unsafeBitCast(implementation, to: ReplaceMessage.self)
        if !replace(player, selector, url as NSURL) {
            reportPlaybackError(String(localized: "SGPlayer could not open this channel."))
        }
    }

    fileprivate func attach(to view: SGHostView) {
        configureHostView(view)
        renderer()?.setValue(view, forKey: "view")
        renderer()?.setValue(NSNumber(value: 1), forKey: "scalingMode")
        play()
    }

    func detach() {
        renderer()?.setValue(nil, forKey: "view")
    }

    func play() {
        reportPlaybackError(nil)
        sendBooleanMessage("play")
        reportPlaybackState()
    }

    func pause() {
        sendBooleanMessage("pause")
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
        reportPlaybackError(String(format: String(localized: "SGPlayer failed: %@"), error.localizedDescription))
    }

    private func reportPlaybackState() {
        let isPlaying = isPlaying
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackStateChange?(isPlaying)
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
        let selector = NSSelectorFromString(selectorName)
        guard player.responds(to: selector) else { return nil }

        let implementation = player.method(for: selector)
        typealias ObjectMessage = @convention(c) (AnyObject, Selector) -> AnyObject?
        let message = unsafeBitCast(implementation, to: ObjectMessage.self)
        return message(player, selector)
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
    let onPlaybackError: (String?) -> Void

    init(
        urlString: String,
        widthMultiplier: CGFloat = 1,
        sharedSession: SGPlayerCompatibilitySession? = nil,
        onPlaybackError: @escaping (String?) -> Void
    ) {
        self.urlString = urlString
        self.widthMultiplier = widthMultiplier
        self.sharedSession = sharedSession
        self.onPlaybackError = onPlaybackError
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view, urlString: urlString, onPlaybackError: onPlaybackError)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView, urlString: urlString, onPlaybackError: onPlaybackError)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: sharedSession ?? SGPlayerCompatibilitySession(urlString: urlString, onPlaybackError: onPlaybackError))
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
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

        func attach(to view: NSView, urlString: String, onPlaybackError: @escaping (String?) -> Void) {
            guard let session else {
                DispatchQueue.main.async {
                    onPlaybackError(String(localized: "SGPlayer is not available in this build."))
                }
                return
            }

            session.setPlaybackErrorHandler(onPlaybackError)
            session.replace(with: urlString)
            session.attach(to: view)
        }

        func detach() {
            session?.pause()
            session?.detach()
        }
    }
}
#else
struct SGPlayerCompatibilityView: UIViewRepresentable {

    let urlString: String
    let widthMultiplier: CGFloat
    let sharedSession: SGPlayerCompatibilitySession?
    let onPlaybackError: (String?) -> Void

    init(
        urlString: String,
        widthMultiplier: CGFloat = 1,
        sharedSession: SGPlayerCompatibilitySession? = nil,
        onPlaybackError: @escaping (String?) -> Void
    ) {
        self.urlString = urlString
        self.widthMultiplier = widthMultiplier
        self.sharedSession = sharedSession
        self.onPlaybackError = onPlaybackError
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        context.coordinator.attach(to: view, urlString: urlString, onPlaybackError: onPlaybackError)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attach(to: uiView, urlString: urlString, onPlaybackError: onPlaybackError)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: sharedSession ?? SGPlayerCompatibilitySession(urlString: urlString, onPlaybackError: onPlaybackError))
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
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

        func attach(to view: UIView, urlString: String, onPlaybackError: @escaping (String?) -> Void) {
            guard let session else {
                DispatchQueue.main.async {
                    onPlaybackError(String(localized: "SGPlayer is not available in this build."))
                }
                return
            }

            session.setPlaybackErrorHandler(onPlaybackError)
            session.replace(with: urlString)
            session.attach(to: view)
        }

        func detach() {
            session?.pause()
            session?.detach()
        }
    }
}
#endif
