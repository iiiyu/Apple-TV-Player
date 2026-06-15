import AVKit
import FactoryKit
import SwiftUI
import Combine

// Some members of my family used to old layout on Apple TV.
private let homeTvOSStreamLayout = false

struct StreamView: View {

    @InjectedObservable(\.logger) var logger
    @State private var viewModel: StreamViewModel
    @Binding private var reloadCurrentProgram: UUID
    @State private var showMediaInfo = false
    @State private var playbackErrorMessage: String?
    @State private var playbackReloadID = UUID()
#if os(tvOS)
    @State private var showFullScreen = false
    @State private var tvOSPlayer: TvOSPlayer
    @State private var reloadProgramGuide = UUID()
    @Binding private var reselectStream: Bool
    @Binding var focusedStream: PlaylistParser.Stream?

    init(
        content: PlaylistItem.Content,
        stream: PlaylistParser.Stream,
        reselectStream: Binding<Bool>,
        focusedStream: Binding<PlaylistParser.Stream?>,
        reloadCurrentProgram: Binding<UUID>
    ) {
        _viewModel = State(wrappedValue: StreamViewModel(content: content, stream: stream))
        _tvOSPlayer = State(wrappedValue: TvOSPlayer(urlString: stream.url))
        _reselectStream = reselectStream
        _focusedStream = focusedStream
        _reloadCurrentProgram = reloadCurrentProgram
    }
#else
    init(
        content: PlaylistItem.Content,
        stream: PlaylistParser.Stream,
        reloadCurrentProgram: Binding<UUID>
    ) {
        _viewModel = State(wrappedValue: StreamViewModel(content: content, stream: stream))
        _reloadCurrentProgram = reloadCurrentProgram
    }
#endif

    var body: some View {
        ZStack {
            TimelineView(.periodic(from: Date(), by: 60)) { context in
#if os(tvOS)
                let _ = viewModel.displayedPrograms(at: context.date, stream: focusedStream ?? viewModel.stream)
#else
                let _ = viewModel.displayedPrograms(at: context.date, stream: viewModel.stream)
#endif

                VStack(alignment: .leading, spacing: 16) {
#if os(tvOS)
                    if !homeTvOSStreamLayout {
                        headerView(now: context.date)
                            .padding(.trailing, 22)
                        videoPlayer()
                        programList()
                            .id(reloadProgramGuide)
                    } else {
                        ZStack {
                            VStack {
                                headerView(now: context.date)
                                    .padding(.trailing, 22)
                                programList()
                                    .id(reloadProgramGuide)
                                    .padding(.bottom, 24)
                            }
                            VStack {
                                Spacer()
                                HStack {
                                    videoPlayer()
                                    Spacer()
                                }
                            }
                        }
                    }
#else
                    videoPlayer()
                    programList()
#endif
                }
                .padding([.leading, .trailing, .bottom])
            }
        }
#if os(iOS)
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
#if !os(tvOS)
            ToolbarItem {
                Button("Stream Info", systemImage: "info.circle") {
                    presentMediaInfo()
                }
                .accessibilityIdentifier("stream-info")
            }
#endif
        }
        .sheet(isPresented: $showMediaInfo) {
            mediaInfoView()
        }
        .task(id: reloadCurrentProgram) {
            await viewModel.loadPrograms()
        }
#if os(tvOS)
        .fullScreenCover(isPresented: $showFullScreen, onDismiss: {
            reloadCurrentProgram = .init()
        }) {
            let _ = logger.info("Presenting full screen from floating player", private: viewModel.stream.title)
            ZStack {
                tvOSPlayer.fullScreenView(onPlaybackError: handlePlaybackError)
                if let playbackErrorMessage {
                    playbackErrorView(playbackErrorMessage)
                }
            }
        }
        .fullScreenCover(isPresented: $reselectStream, onDismiss: {
            reloadCurrentProgram = .init()
        }) {
            let _ = logger.info("Presenting full screen from double select", private: viewModel.stream.title)
            ZStack {
                tvOSPlayer.fullScreenView(onPlaybackError: handlePlaybackError)
                if let playbackErrorMessage {
                    playbackErrorView(playbackErrorMessage)
                }
            }
        }
        .onChange(of: focusedStream) {
            if let focusedStream {
                Task {
                    if await viewModel.loadPrograms(focusedStream) {
                        reloadProgramGuide = UUID()
                    }
                }
            }
        }
#endif
    }
#if os(tvOS)
    private func headerView(now: Date) -> some View {
        HStack {
            if !homeTvOSStreamLayout,
               focusedStream != viewModel.stream,
               let currentProgram = viewModel.originStreamCurrentProgram {
                Text(currentProgram.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            } else {
                Spacer()
            }

            HStack(spacing: 10) {
                Text(viewModel.title)
                Text(viewModel.currentTimeText(at: now))
                Button("", systemImage: "info.circle") {
                    presentMediaInfo()
                }
                .accessibilityIdentifier("stream-info")
            }
            .font(.headline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
#endif
    private func presentMediaInfo() {
        showMediaInfo = true
        Task {
            await viewModel.loadMediaInfo()
        }
    }

    private func mediaInfoView() -> some View {
        NavigationStack {
            StreamMediaInfoView(viewModel: viewModel)
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
#endif
    }

    private func videoPlayer() -> some View {
        ZStack {
            platformVideoPlayer()
            if let playbackErrorMessage {
                playbackErrorView(playbackErrorMessage)
            }
        }
    }

    @ViewBuilder
    private func platformVideoPlayer() -> some View {
#if os(macOS)
        MacOsPlayerView(
            urlString: viewModel.stream.url,
            onPlaybackError: handlePlaybackError
        ) {
            reloadCurrentProgram = .init()
        }
        .id(playbackReloadID)
#elseif os(tvOS)
        HStack(spacing: 0) {
            Button {
                showFullScreen = true
            } label: {
                tvOSPlayer.compactView(onPlaybackError: handlePlaybackError)
            }
            .buttonStyle(.card)
        }
        .ignoresSafeArea()
#else
        iOSPlayerView(
            urlString: viewModel.stream.url,
            onPlaybackError: handlePlaybackError
        )
        .id(playbackReloadID)
#endif
    }

    private func playbackErrorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Unable to Play Channel", systemImage: "lock.slash")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                retryPlayback()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func handlePlaybackError(_ message: String?) {
        playbackErrorMessage = message
    }

    private func retryPlayback() {
        playbackErrorMessage = nil
#if os(tvOS)
        tvOSPlayer.retry()
#else
        playbackReloadID = UUID()
#endif
    }

    private func programList() -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if viewModel.didLoadPrograms, viewModel.displayProgram.isEmpty {
                    ContentUnavailableView(
                        "No Program Guide",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No guide information is available for this channel.")
                    )
                } else {
                    ForEach(viewModel.displayProgram) { displayedProgram in
#if os(tvOS)
                        Button {
                        } label: {
                            program(displayedProgram)
                        }
                        .buttonStyle(.borderless)
#else
                        program(displayedProgram)
#endif
                    }
                }
            }
        }
        .accessibilityIdentifier("program-list")
    }

    private func program(_ displayedProgram: StreamViewModel.DisplayProgram) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayedProgram.text)
                .foregroundStyle(color(for: displayedProgram.state))
#if os(tvOS)
                .font(.system(size: 31, weight: .regular))
#endif
            if let progress = displayedProgram.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.green)
            }
        }
    }

    private func color(for state: StreamViewModel.ProgramState) -> Color {
        switch state {
        case .past:
            .secondary
        case .now:
            .green
        case .future:
            .primary
        }
    }
}

private struct StreamMediaInfoView: View {

    @Bindable var viewModel: StreamViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoadingMediaInfo {
                    ProgressView("Reading Stream Info")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let mediaInfo = viewModel.mediaInfo {
                    badgeList(mediaInfo.badges)
                    MediaInfoSectionView(title: "Video Info 1", items: mediaInfo.videoItems)
                    MediaInfoSectionView(title: "Audio Info 1", items: mediaInfo.audioItems)
                } else if let errorMessage = viewModel.mediaInfoErrorMessage {
                    ContentUnavailableView {
                        Label("Stream Info Unavailable", systemImage: "info.circle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            Task {
                                await viewModel.loadMediaInfo()
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Stream Info")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .task {
            await viewModel.loadMediaInfo()
        }
    }

    private func badgeList(_ badges: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }
}

private struct MediaInfoSectionView: View {

    let title: LocalizedStringKey
    let items: [StreamMediaInfo.Item]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(LocalizedStringKey(item.name))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 16)
                            Text(item.value)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 10)
                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

#if os(macOS)
private struct MacOsPlayerView: NSViewRepresentable {

    let urlString: String
    let onPlaybackError: (String?) -> Void
    let onExitFullScreen: () -> Void

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = context.coordinator.controller.player
        view.showsFullScreenToggleButton = true
        // The inline controls instantiate AVKit's embedded volume slider, which
        // can emit unsatisfiable constraints on current macOS SDKs.
        view.controlsStyle = .minimal
        view.allowsPictureInPicturePlayback = true
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player?.play()
    }

    func makeCoordinator() -> PlayerDelegate {
        return PlayerDelegate(
            controller: StreamPlayerController(
                urlString: urlString,
                onPlaybackError: onPlaybackError
            ),
            onExitFullScreen: onExitFullScreen
        )
    }

    static func dismantleNSView(_ nsView: Self.NSViewType, coordinator: Self.Coordinator) {
        nsView.player?.pause()
        nsView.player = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Self.NSViewType, context: Self.Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return .init(width: width, height: width * (9.0 / 16.0))
    }

    class PlayerDelegate: NSObject, AVPlayerViewDelegate {

        let controller: StreamPlayerController
        let onExitFullScreen: () -> Void

        init(controller: StreamPlayerController, onExitFullScreen: @escaping () -> Void) {
            self.controller = controller
            self.onExitFullScreen = onExitFullScreen
            super.init()
        }

        func playerViewWillExitFullScreen(_ playerView: AVPlayerView) {
            onExitFullScreen()
        }
    }
}
#elseif os(tvOS)
private struct TvOSPlayerView: UIViewControllerRepresentable {

    let player: AVPlayer
    let compact: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player?.play()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: Self.UIViewControllerType, context: Self.Context) -> CGSize? {
        let multiplier: CGFloat = homeTvOSStreamLayout ? 1 : 2.8 / 3.0
        guard compact, let width = proposal.width.map({ $0 * multiplier }) else { return nil }
        return .init(width: width, height: width * (9.0 / 16.0))
    }
}

private final class TvOSPlayer {

    private let controller: StreamPlayerController

    init(urlString: String) {
        controller = StreamPlayerController(urlString: urlString)
    }

    func compactView(onPlaybackError: @escaping (String?) -> Void) -> some View {
        controller.setPlaybackErrorHandler(onPlaybackError)
        return TvOSPlayerView(player: controller.player, compact: true)
    }

    func fullScreenView(onPlaybackError: @escaping (String?) -> Void) -> some View {
        controller.setPlaybackErrorHandler(onPlaybackError)
        return TvOSPlayerView(player: controller.player, compact: false)
            .ignoresSafeArea()
    }

    func retry() {
        controller.retry()
    }
}
#else
private struct iOSPlayerView: UIViewControllerRepresentable {

    let urlString: String
    let onPlaybackError: (String?) -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothHFP, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            Container.shared.logger().error(error)
        }
        let controller = AVPlayerViewController()
        controller.player = context.coordinator.controller.player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            controller: StreamPlayerController(
                urlString: urlString,
                onPlaybackError: onPlaybackError
            )
        )
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player?.play()
    }

    final class Coordinator {

        let controller: StreamPlayerController

        init(controller: StreamPlayerController) {
            self.controller = controller
        }
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Self.Coordinator) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: Self.UIViewControllerType, context: Self.Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return .init(width: width, height: width * (9.0 / 16.0))
    }
}
#endif

#if DEBUG

struct StreamViewPreviews: PreviewProvider {
    
    static var previews: some View {
        Container.preview { container in
            container.playlistService.register {
                ProgramGuidePlaylistServicePreviewMock()
            }
        }
        let content = PlaylistItem.Content(
           identity: .init(
               name: "Preview",
               date: Date(timeIntervalSince1970: 100)
           ),
           url: Data("https://example.com/playlist.m3u".utf8),
           data: Data("#EXTM3U".utf8),
           isStoredInMemoryOnly: true
       )
        let stream = PlaylistParser.Stream(
           title: "Channel",
           url: "https://example.com/master.m3u8",
           tvgLogo: nil,
           tvgID: nil,
           tvgName: "Channel HD",
           groupTitle: nil
       )

#if os(iOS)
        NavigationStack {
            StreamView(
                content: content, stream: stream,
                reloadCurrentProgram: .constant(.init())
            )
        }
#elseif os(macOS)
        StreamView(
            content: content, stream: stream,
            reloadCurrentProgram: .constant(.init())
        )
        .frame(width: 600, height: 460)
#else
        HStack {
            Rectangle()
                .fill(.clear)
                .frame(width: UIScreen.main.bounds.width / 4)
                
            StreamView(
                content: content,
                stream: stream,
                reselectStream: .constant(false),
                focusedStream: .constant(nil),
                reloadCurrentProgram: .constant(.init())
            )
            .background(Color(uiColor: .darkGray))
        }
#endif
    }
}

private final class ProgramGuidePlaylistServicePreviewMock: PlaylistServiceInterface {

    func playlists(
        for content: PlaylistItem.Content,
        reloadProgramGuide: Bool,
        progress: @escaping ProgressHandler
    ) async throws -> [PlaylistParser.Playlist] {
        []
    }

    func playlists(
        for content: PlaylistItem.Content,
        reloadPlaylist: Bool,
        progress: @escaping ProgressHandler
    ) async throws -> [PlaylistParser.Playlist] {
        []
    }

    func programGuide(
        for content: PlaylistItem.Content,
        stream: PlaylistParser.Stream
    ) async -> ProgramGuide? {
        let now = Date()

        return ProgramGuide(
            channel: .init(
                id: "preview",
                displayName: "Preview Channel HD",
                iconURL: nil
            ),
            programs: [
                .init(
                    title: "Pre-Late Show",
                    start: now.addingTimeInterval(-6000),
                    stop: now.addingTimeInterval(-3600)
                ),
                .init(
                    title: "Late Show",
                    start: now.addingTimeInterval(-3600),
                    stop: now.addingTimeInterval(-1800)
                ),
                .init(
                    title: "News",
                    start: now.addingTimeInterval(-1800),
                    stop: now.addingTimeInterval(1800)
                ),
                .init(
                    title: "Movie",
                    start: now.addingTimeInterval(1800),
                    stop: now.addingTimeInterval(5400)
                ),
                .init(
                    title: "Night Show",
                    start: now.addingTimeInterval(5400),
                    stop: now.addingTimeInterval(8400)
                )
            ]
        )
    }

    func clearCache(for content: PlaylistItem.Content) async {
    }

    func programGuides(for content: PlaylistItem.Content, since: Date) async -> [ProgramGuide] {
        []
    }
}

#endif
