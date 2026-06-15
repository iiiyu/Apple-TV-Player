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

    func replace(with urlString: String) {
        guard let url = URL(string: urlString) else {
            onPlaybackError?(String(localized: "The channel URL is invalid."))
            return
        }

        guard loadedURL != url else { return }
        loadedURL = url
        onPlaybackError?(nil)

        let selector = NSSelectorFromString("replaceWithURL:")
        guard player.responds(to: selector) else {
            onPlaybackError?(String(localized: "SGPlayer is not compatible with this build."))
            return
        }

        let implementation = player.method(for: selector)
        typealias ReplaceMessage = @convention(c) (AnyObject, Selector, NSURL) -> Bool
        let replace = unsafeBitCast(implementation, to: ReplaceMessage.self)
        if !replace(player, selector, url as NSURL) {
            onPlaybackError?(String(localized: "SGPlayer could not open this channel."))
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
        onPlaybackError?(nil)
        sendBooleanMessage("play")
    }

    func pause() {
        sendBooleanMessage("pause")
    }

    private func observePlayerInfo() {
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("SGPlayerDidChangeInfosNotification"),
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reportCurrentErrorIfNeeded()
            }
        }
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
        onPlaybackError?(String(format: String(localized: "SGPlayer failed: %@"), error.localizedDescription))
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

    private func objectMessage(_ selectorName: String) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard player.responds(to: selector) else { return nil }

        let implementation = player.method(for: selector)
        typealias ObjectMessage = @convention(c) (AnyObject, Selector) -> AnyObject?
        let message = unsafeBitCast(implementation, to: ObjectMessage.self)
        return message(player, selector)
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
                onPlaybackError(String(localized: "SGPlayer is not available in this build."))
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
                onPlaybackError(String(localized: "SGPlayer is not available in this build."))
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
