
import SwiftUI
import SwiftData
import FactoryKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@main
struct AppleTVMultiplatformApp: App {

    @State private var viewModel = AppleTVMultiplatformAppViewModel()
    @State private var playlistListUpdate: UUID = .init()
    @InjectedObservable(\.logger) var logger
#if os(iOS)
    @UIApplicationDelegateAdaptor(HiPlayerAppDelegate.self) private var appDelegate
#elseif os(macOS)
    @NSApplicationDelegateAdaptor(HiPlayerMacAppDelegate.self) private var appDelegate
#endif

    var body: some Scene {
        WindowGroup {
            ContentView(playlistListUpdate: $playlistListUpdate)
#if os(macOS)
                // Keep the detail pane wide enough for the SGPlayer control row
                // (sidebar + channel list + player). Below this the controls
                // overflow their bar.
                .frame(minWidth: 1000, minHeight: 560)
#endif
#if os(macOS) && DEBUG
                .modifier(SnapshotTestScreenSizeRatioViewModifier())
#endif
                .onAppear {
                    logger.info("App started")
                }
                .onOpenURL { url in
                    logger.info("App Open URL", private: url)
                    if viewModel.handleIncomingFile(url: url) {
                        playlistListUpdate = .init()
                    }
                }
                .alert(isPresented: $viewModel.isErrorPresented, error: viewModel.error, actions: {
                    Button("OK", role: .cancel) { }
                })
        }
#if os(macOS)
        .defaultSize(width: 1200, height: 720)
#endif
    }
}

#if os(iOS)
final class HiPlayerAppDelegate: NSObject, UIApplicationDelegate {

    static var orientationLock: UIInterfaceOrientationMask?

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if let orientationLock = Self.orientationLock {
            return orientationLock
        }
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }
}
#endif

#if os(macOS)
final class HiPlayerMacAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            self.showMainWindow(in: NSApp)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showMainWindow(in: sender)
        }
        return true
    }

    private func showMainWindow(in application: NSApplication) {
        application.activate()
        application.windows
            .first(where: { $0.canBecomeMain })?
            .makeKeyAndOrderFront(nil)
    }
}
#endif

#if os(macOS) && DEBUG
private struct SnapshotTestScreenSizeRatioViewModifier: ViewModifier {

    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.arguments.contains("--window-fixed-size") {
            content
                .frame(
                    minWidth: 1280,
                    maxWidth: 1280,
                    minHeight: 748,
                    maxHeight: 748
                )
        } else {
            content
        }
    }
}
#endif
