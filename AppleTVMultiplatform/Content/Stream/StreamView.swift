import AVKit
import FactoryKit
import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// Some members of my family used to old layout on Apple TV.
private let homeTvOSStreamLayout = false

#if os(tvOS)
private enum TVOSPlaybackFocus: Hashable {
    case inlinePlayer
    case hiddenInteractionSurface
    case playPause
    case playbackEngine
    case streamInfo
    case exitFullScreen
}
#endif

struct StreamView: View {

    @InjectedObservable(\.logger) var logger
    @State private var viewModel: StreamViewModel
    @Binding private var reloadCurrentProgram: UUID
    private var onPlaybackPageDisappear: () -> Void = {}
    @State private var showMediaInfo = false
    @State private var playbackErrorMessage: String?
    @State private var playbackReloadID = UUID()
    @State private var useSGPlayerCompatibility = SGPlayerCompatibility.isAvailable
    @State private var sgPlayer: SGPlayerCompatibilitySession?
    @State private var isSGPlayerPlaying = true
    @State private var sgPlayerVolume = 1.0
#if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    @State private var iOSPlayer: StreamPlayerController
    @State private var iosFullScreen = IOSSGPlayerFullScreenController()
    @State private var isPlaybackPageVisible = false
    @State private var shouldResumeAfterForegrounding = true
#endif
#if os(macOS)
    @State private var macFullScreen = MacSGPlayerFullScreenController()
#endif
#if os(tvOS)
    @State private var showFullScreen = false
    @State private var showTvOSFullScreenControls = true
    @State private var tvOSFullScreenControlsAutoHideID = UUID()
    @FocusState private var tvOSPlaybackFocus: TVOSPlaybackFocus?
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
        let useSGPlayerCompatibility = SGPlayerCompatibility.isAvailable
        _useSGPlayerCompatibility = State(wrappedValue: useSGPlayerCompatibility)
        _viewModel = State(wrappedValue: StreamViewModel(content: content, stream: stream))
        _tvOSPlayer = State(wrappedValue: TvOSPlayer(urlString: stream.url, autoplays: !useSGPlayerCompatibility))
        _sgPlayer = State(wrappedValue: SGPlayerCompatibilitySession(urlString: stream.url))
        _reselectStream = reselectStream
        _focusedStream = focusedStream
        _reloadCurrentProgram = reloadCurrentProgram
    }
#else
    init(
        content: PlaylistItem.Content,
        stream: PlaylistParser.Stream,
        reloadCurrentProgram: Binding<UUID>,
        onPlaybackPageDisappear: @escaping () -> Void = {}
    ) {
        let useSGPlayerCompatibility = SGPlayerCompatibility.isAvailable
        _useSGPlayerCompatibility = State(wrappedValue: useSGPlayerCompatibility)
        _viewModel = State(wrappedValue: StreamViewModel(content: content, stream: stream))
        _sgPlayer = State(wrappedValue: SGPlayerCompatibilitySession(urlString: stream.url))
#if os(iOS)
        // The retained controller starts lazily from StreamView.onAppear.
        // This makes StreamView the single owner and prevents discarded
        // SwiftUI values from opening extra live connections.
        _iOSPlayer = State(wrappedValue: StreamPlayerController(urlString: stream.url, autoplays: false))
#endif
        _reloadCurrentProgram = reloadCurrentProgram
        self.onPlaybackPageDisappear = onPlaybackPageDisappear
    }
#endif

    var body: some View {
        ZStack {
            TimelineView(.periodic(from: Date(), by: 60)) { context in
#if os(tvOS)
                let snapshot = viewModel.displayedPrograms(at: context.date, stream: focusedStream ?? viewModel.stream)
#else
                let snapshot = viewModel.displayedPrograms(at: context.date, stream: viewModel.stream)
#endif

                VStack(alignment: .leading, spacing: 16) {
#if os(tvOS)
                    if !homeTvOSStreamLayout {
                        headerView(now: context.date, snapshot: snapshot)
                            .padding(.trailing, 22)
                        videoPlayer()
                        programList(snapshot: snapshot)
                            .id(reloadProgramGuide)
                    } else {
                        ZStack {
                            VStack {
                                headerView(now: context.date, snapshot: snapshot)
                                    .padding(.trailing, 22)
                                programList(snapshot: snapshot)
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
                    programList(snapshot: snapshot)
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
                Button(currentPlaybackEngineName, systemImage: currentPlaybackEngineSymbolName) {
                    togglePlaybackEngine()
                }
                .accessibilityIdentifier("stream-player-engine")
                .accessibilityLabel(Text("\(currentPlaybackEngineName) in use"))
                .accessibilityHint(Text("Switch to \(targetPlaybackEngineName)"))
                .help("Currently using \(currentPlaybackEngineName). Switch playback to \(targetPlaybackEngineName).")
            }
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
        .onAppear {
            playbackPageDidAppear()
        }
        .onDisappear {
            playbackPageDidDisappear()
        }
        .onChange(of: useSGPlayerCompatibility) {
            activateSelectedPlaybackEngine()
        }
#if os(iOS)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
#endif
#if os(tvOS)
        .fullScreenCover(isPresented: $showFullScreen, onDismiss: {
            tvOSFullScreenDidDismiss()
        }) {
            let _ = logger.info("Presenting full screen from floating player", private: viewModel.stream.title)
            tvOSFullScreenPlayer(isPresented: $showFullScreen)
        }
        .fullScreenCover(isPresented: $reselectStream, onDismiss: {
            tvOSFullScreenDidDismiss()
        }) {
            let _ = logger.info("Presenting full screen from double select", private: viewModel.stream.title)
            tvOSFullScreenPlayer(isPresented: $reselectStream)
        }
        .onPlayPauseCommand {
            guard !showFullScreen, !reselectStream else { return }
            toggleTVOSPlayback()
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

    private var currentPlaybackEngineName: String {
        useSGPlayerCompatibility ? "SGPlayer" : "AVPlayer"
    }

    private var targetPlaybackEngineName: String {
        useSGPlayerCompatibility ? "AVPlayer" : "SGPlayer"
    }

    private var currentPlaybackEngineSymbolName: String {
        useSGPlayerCompatibility ? "cpu.fill" : "play.rectangle.fill"
    }

#if os(tvOS)
    private func headerView(now: Date, snapshot: StreamViewModel.ProgramSnapshot) -> some View {
        HStack {
            if !homeTvOSStreamLayout,
               focusedStream != viewModel.stream,
               let currentProgram = snapshot.originCurrent {
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
                tvOSPlaybackEngineButton()
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

    private func tvOSPlaybackEngineButton(resetsFullScreenControls: Bool = false) -> some View {
        Button {
            if resetsFullScreenControls {
                revealTvOSFullScreenControls(focusing: .playbackEngine)
            }
            togglePlaybackEngine()
        } label: {
            Label {
                Text(targetPlaybackEngineName)
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .accessibilityIdentifier("stream-player-engine")
        .accessibilityLabel(Text("Use \(targetPlaybackEngineName)"))
    }

    @ViewBuilder
    private func tvOSFullScreenPlayer(isPresented: Binding<Bool>) -> some View {
        if useSGPlayerCompatibility, sgPlayer != nil {
            ZStack {
                sgPlayerSurface(
                    isFullScreen: true,
                    showsControls: false
                )
                .ignoresSafeArea()

                tvOSFullScreenInteractionLayer()

                if showTvOSFullScreenControls {
                    tvOSFullScreenControls(isPresented: isPresented)
                        .transition(.opacity)
                }

                if let playbackErrorMessage {
                    playbackErrorView(playbackErrorMessage)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .accessibilityIdentifier("stream-player-full-screen")
            .onAppear {
                revealTvOSFullScreenControls(focusing: .playPause)
            }
            .onPlayPauseCommand {
                toggleTVOSPlayback()
                revealTvOSFullScreenControls(focusing: .playPause)
            }
            .onExitCommand {
                isPresented.wrappedValue = false
            }
            .onChange(of: tvOSPlaybackFocus) { _, focus in
                guard showTvOSFullScreenControls,
                      focus != nil,
                      focus != .hiddenInteractionSurface else { return }
                tvOSFullScreenControlsAutoHideID = UUID()
            }
            .task(id: tvOSFullScreenControlsAutoHideID) {
                await autoHideTvOSFullScreenControls()
            }
        } else {
            ZStack {
                // AVPlayerViewController owns the complete tvOS transport UI.
                // Keeping custom SwiftUI gesture/focus layers out of this branch
                // preserves Siri Remote scrubbing, Play/Pause, voice commands,
                // subtitles, audio tracks, and future system-player behavior.
                tvOSPlayer.fullScreenView(onPlaybackError: handlePlaybackError)

                if let playbackErrorMessage {
                    playbackErrorView(playbackErrorMessage)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .accessibilityIdentifier("stream-player-full-screen")
            .onExitCommand {
                isPresented.wrappedValue = false
            }
        }
    }

    private func tvOSFullScreenControls(isPresented: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.title)
                        .font(.title2.bold())
                    Text(currentPlaybackEngineName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented.wrappedValue = false
                } label: {
                    Label("Exit Full Screen", systemImage: "xmark")
                }
                .focused($tvOSPlaybackFocus, equals: .exitFullScreen)
                .accessibilityIdentifier("stream-exit-full-screen")
            }

            Spacer()

            HStack(spacing: 20) {
                Button {
                    toggleTVOSPlayback()
                    revealTvOSFullScreenControls(focusing: .playPause)
                } label: {
                    Label(
                        isSGPlayerPlaying ? "Pause" : "Play",
                        systemImage: isSGPlayerPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.glassProminent)
                .focused($tvOSPlaybackFocus, equals: .playPause)
                .accessibilityIdentifier("stream-play-pause")

                Spacer()

                tvOSPlaybackEngineButton(resetsFullScreenControls: true)
                    .focused($tvOSPlaybackFocus, equals: .playbackEngine)

                Button {
                    revealTvOSFullScreenControls(focusing: .streamInfo)
                    presentMediaInfo()
                } label: {
                    Label("Stream Info", systemImage: "info.circle")
                }
                .focused($tvOSPlaybackFocus, equals: .streamInfo)
                .accessibilityIdentifier("stream-info")
            }
        }
        .font(.headline)
        .controlSize(.large)
        .buttonStyle(.glass)
        .padding(.horizontal, 72)
        .padding(.vertical, 56)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 340)
            .ignoresSafeArea()
        }
        .accessibilityIdentifier("stream-player-controls")
    }

    private func tvOSFullScreenInteractionLayer() -> some View {
        Color.clear
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .allowsHitTesting(!showTvOSFullScreenControls)
            .focusable(!showTvOSFullScreenControls)
            .focused($tvOSPlaybackFocus, equals: .hiddenInteractionSurface)
            .onTapGesture {
                revealTvOSFullScreenControls(focusing: .playPause)
            }
            .onMoveCommand { _ in
                revealTvOSFullScreenControls(focusing: .playPause)
            }
    }

    private func revealTvOSFullScreenControls(focusing focus: TVOSPlaybackFocus? = nil) {
        withAnimation(.easeIn(duration: 0.2)) {
            showTvOSFullScreenControls = true
        }
        tvOSFullScreenControlsAutoHideID = UUID()

        guard let focus else { return }
        Task { @MainActor in
            // Wait until the conditional controls have entered the focus tree.
            await Task.yield()
            tvOSPlaybackFocus = focus
        }
    }

    private func autoHideTvOSFullScreenControls() async {
        do {
            try await Task.sleep(for: .seconds(5))
        } catch {
            return
        }

        guard !Task.isCancelled, isSGPlayerPlaying else { return }
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.2)) {
                showTvOSFullScreenControls = false
            }
        }

        // Transfer focus only after the hidden interaction surface has become
        // focusable, otherwise the focus engine can briefly lose its target.
        await Task.yield()
        guard !Task.isCancelled else { return }
        await MainActor.run {
            tvOSPlaybackFocus = .hiddenInteractionSurface
        }
    }

    private func toggleTVOSPlayback() {
        if useSGPlayerCompatibility {
            if sgPlayer?.isPlaying ?? isSGPlayerPlaying {
                sgPlayer?.pause()
                isSGPlayerPlaying = false
            } else {
                sgPlayer?.play()
                isSGPlayerPlaying = true
            }
        } else {
            tvOSPlayer.togglePlayback()
        }
    }

    private func tvOSFullScreenDidDismiss() {
        reloadCurrentProgram = .init()
        showTvOSFullScreenControls = true
        tvOSPlaybackFocus = .inlinePlayer
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

#if os(macOS)
    private func enterMacSGPlayerFullScreen() {
        guard let sgPlayer else { return }
        // Present the video in its own full-screen window (the whole playback
        // picture, not the app window with its sidebar/list). The shared
        // SGPlayer session's renderer moves to that window via attach
        // priority, and returns to this inline surface when it closes.
        macFullScreen.present(
            session: sgPlayer,
            urlString: viewModel.stream.url,
            volume: sgPlayerVolume,
            onPlaybackError: handlePlaybackError,
            onClose: {
                isSGPlayerPlaying = true
                reloadCurrentProgram = .init()
                activateSelectedPlaybackEngine()
            }
        )
    }
#endif

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
        if useSGPlayerCompatibility {
            sgPlayerSurface {
                enterMacSGPlayerFullScreen()
            }
            .onDisappear {
                // Tear down the detached full-screen window if the stream view
                // goes away while it is open.
                macFullScreen.dismiss()
            }
        } else {
            MacOsPlayerView(
                urlString: viewModel.stream.url,
                onPlaybackError: handlePlaybackError,
                onExitFullScreen: { reloadCurrentProgram = .init() }
            )
            .id(playbackReloadID)
        }
#elseif os(tvOS)
        Button {
            showFullScreen = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if useSGPlayerCompatibility {
                    // The inline surface is a single tvOS content card. Tiny
                    // transport buttons inside the card created a nested focus
                    // hierarchy and made entering full screen unpredictable.
                    sgPlayerSurface(
                        widthMultiplier: homeTvOSStreamLayout ? 1 : 2.8 / 3.0,
                        showsControls: false
                    )
                } else {
                    // Compact AVKit playback is deliberately non-interactive;
                    // Select opens the native full-screen system player.
                    tvOSPlayer.compactView(onPlaybackError: handlePlaybackError)
                }

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.headline)
                    .padding(16)
                    .glassEffect(.regular, in: .circle)
                    .padding(22)
            }
        }
        .buttonStyle(.card)
        .focused($tvOSPlaybackFocus, equals: .inlinePlayer)
        .accessibilityIdentifier("stream-player-card")
        .accessibilityLabel(Text("Enter Full Screen"))
        .accessibilityHint(Text("Press Play/Pause to control playback without opening full screen."))
        .ignoresSafeArea()
#else
        if useSGPlayerCompatibility {
            sgPlayerSurface {
                presentIOSSGPlayerFullScreen()
            }
        } else {
            iOSPlayerView(
                controller: iOSPlayer,
                onPlaybackError: handlePlaybackError
            )
        }
#endif
    }

#if os(iOS)
    private func presentIOSSGPlayerFullScreen() {
        guard let sgPlayer else { return }
        iosFullScreen.present(
            session: sgPlayer,
            urlString: viewModel.stream.url,
            volume: sgPlayerVolume,
            onPlaybackError: handlePlaybackError,
            onClose: {
                guard isPlaybackPageVisible, scenePhase == .active else { return }
                isSGPlayerPlaying = true
                reloadCurrentProgram = .init()
                activateSelectedPlaybackEngine()
            }
        )
    }
#endif

    @ViewBuilder
    private func sgPlayerSurface(
        widthMultiplier: CGFloat = 1,
        isFullScreen: Bool = false,
        showsControls: Bool = true,
        fullScreenSystemImage: String = "arrow.up.left.and.arrow.down.right",
        fullScreenAccessibilityLabel: LocalizedStringKey = "Enter Full Screen",
        fullScreenAction: (() -> Void)? = nil
    ) -> some View {
        if let sgPlayer {
            let surface = SGPlayerSurface(
                urlString: viewModel.stream.url,
                widthMultiplier: widthMultiplier,
                session: sgPlayer,
                attachPriority: isFullScreen ? 1 : 0,
                onPlaybackError: handlePlaybackError,
                isPlaying: $isSGPlayerPlaying,
                volume: $sgPlayerVolume,
                isFullScreen: isFullScreen,
                showsControls: showsControls,
                fullScreenSystemImage: fullScreenSystemImage,
                fullScreenAccessibilityLabel: fullScreenAccessibilityLabel,
                fullScreenAction: fullScreenAction
            )
            .id(playbackReloadID)
#if os(iOS)
            // Inline, pin the player to a 16:9 box at the top; without this the
            // surface stretches to fill the detail area, leaving a tall black
            // box with the controls floating in it.
            if isFullScreen {
                surface
            } else {
                surface
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
#else
            surface
#endif
        } else {
            ContentUnavailableView {
                Label("Unable to Play Channel", systemImage: "play.slash")
            } description: {
                Text("SGPlayer is not available in this build.")
            }
        }
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
            .buttonStyle(.glassProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func handlePlaybackError(_ message: String?) {
        DispatchQueue.main.async {
            guard playbackErrorMessage != message else { return }
            playbackErrorMessage = message
        }
    }

    private func togglePlaybackEngine() {
        playbackErrorMessage = nil

        if useSGPlayerCompatibility {
            sgPlayer?.shutdown()
            sgPlayer = nil
            isSGPlayerPlaying = false
#if os(tvOS)
            tvOSPlayer.stop()
#elseif os(iOS)
            iOSPlayer.stop()
#endif
            useSGPlayerCompatibility = false
            playbackReloadID = UUID()
            return
        }

        guard SGPlayerCompatibility.isAvailable else {
            playbackErrorMessage = String(localized: "SGPlayer is not available in this build.")
            return
        }

#if os(tvOS)
        tvOSPlayer.stop()
#elseif os(iOS)
        iOSPlayer.stop()
#endif
        useSGPlayerCompatibility = true
        playbackReloadID = UUID()
    }

    private func retryPlayback() {
        playbackErrorMessage = nil
        if useSGPlayerCompatibility {
#if os(tvOS)
            tvOSPlayer.pause()
#endif
            playbackReloadID = UUID()
            sgPlayer?.replace(with: viewModel.stream.url, forceReload: true)
            sgPlayer?.volume = sgPlayerVolume
            sgPlayer?.play()
            isSGPlayerPlaying = true
        } else {
#if os(tvOS)
            tvOSPlayer.retry()
#elseif os(iOS)
            iOSPlayer.retry()
#else
            playbackReloadID = UUID()
#endif
        }
    }

    private func activateSelectedPlaybackEngine() {
#if os(iOS)
        guard isPlaybackPageVisible, scenePhase == .active else { return }
#endif
        if useSGPlayerCompatibility {
#if os(tvOS)
            tvOSPlayer.stop()
#elseif os(iOS)
            iOSPlayer.stop()
#endif
            if sgPlayer == nil {
                sgPlayer = SGPlayerCompatibilitySession(urlString: viewModel.stream.url)
            }
            sgPlayer?.replace(with: viewModel.stream.url)
            sgPlayer?.volume = sgPlayerVolume
            sgPlayer?.play()
            isSGPlayerPlaying = true
        } else {
            sgPlayer?.shutdown()
            sgPlayer = nil
            isSGPlayerPlaying = false
#if os(tvOS)
            tvOSPlayer.play()
#elseif os(iOS)
            iOSPlayer.play()
#endif
        }
    }

    private func pauseAllPlaybackEngines() {
        sgPlayer?.pause()
        isSGPlayerPlaying = false
#if os(tvOS)
        tvOSPlayer.pause()
#elseif os(iOS)
        iOSPlayer.pause()
#endif
    }

    private func playbackPageDidAppear() {
#if os(iOS)
        isPlaybackPageVisible = true
        shouldResumeAfterForegrounding = true
        guard scenePhase == .active else { return }
#endif
        activateSelectedPlaybackEngine()
    }

    private func playbackPageDidDisappear() {
#if os(iOS)
        // A popped NavigationSplitView detail may stay retained. Explicitly
        // unload its engines so returning to the same channel cannot leave an
        // old audio-only connection playing behind the new page.
        isPlaybackPageVisible = false
        shouldResumeAfterForegrounding = true
        iosFullScreen.dismiss(notifyOnClose: false)
        sgPlayer?.shutdown()
        sgPlayer = nil
        isSGPlayerPlaying = false
        iOSPlayer.stop()
        playbackErrorMessage = nil
        onPlaybackPageDisappear()
#else
        pauseAllPlaybackEngines()
#endif
    }

#if os(iOS)
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            guard isPlaybackPageVisible, shouldResumeAfterForegrounding else { return }
            activateSelectedPlaybackEngine()
        case .inactive, .background:
            if oldPhase == .active {
                shouldResumeAfterForegrounding = selectedEngineRequestsPlayback
            }
            pauseAllPlaybackEngines()
        @unknown default:
            pauseAllPlaybackEngines()
        }
    }

    private var selectedEngineRequestsPlayback: Bool {
        if useSGPlayerCompatibility {
            return sgPlayer?.isPlaying ?? isSGPlayerPlaying
        }
        return iOSPlayer.isPlaybackRequested
    }
#endif

    @ViewBuilder
    private func programList(snapshot: StreamViewModel.ProgramSnapshot) -> some View {
        if viewModel.didLoadPrograms, snapshot.displayed.isEmpty {
            ContentUnavailableView(
                "No Program Guide",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("No guide information is available for this channel.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityIdentifier("program-list")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(snapshot.displayed) { displayedProgram in
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("program-list")
        }
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        }
    }
}

private struct SGPlayerSurface: View {

    let urlString: String
    let widthMultiplier: CGFloat
    let session: SGPlayerCompatibilitySession
    let attachPriority: Int
    let onPlaybackError: (String?) -> Void
    @Binding var isPlaying: Bool
    @Binding var volume: Double
    let isFullScreen: Bool
    let showsControls: Bool
    let fullScreenSystemImage: String
    let fullScreenAccessibilityLabel: LocalizedStringKey
    let fullScreenAction: (() -> Void)?
#if !os(tvOS)
    @State private var controlsShown = true
    @State private var autoHideToken = UUID()
#endif

    var body: some View {
        SGPlayerCompatibilityView(
            urlString: urlString,
            widthMultiplier: widthMultiplier,
            sharedSession: session,
            attachPriority: attachPriority,
            fillsAvailableSpace: isFullScreen,
            onPlaybackError: onPlaybackError
        )
        .background(.black, ignoresSafeAreaEdges: playerBackgroundSafeAreaEdges)
        // Controls are presentation-only. Keeping them in an overlay prevents
        // the flexible tap target from participating in ZStack measurement and
        // stretching the inline player beyond its 16:9 video surface.
        .overlay(alignment: .bottom) {
#if os(tvOS)
            if controlsVisible {
                controlsBar.transition(.opacity)
            }
#else
            // The tap-to-toggle region sits ABOVE the control bar, not over it,
            // so its tap gesture never competes with the bar's buttons (which
            // otherwise lost taps while the slider — a drag — still worked).
            VStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }
                if controlsVisible {
                    controlsBar.transition(.opacity)
                }
            }
#endif
        }
        .background(.black, ignoresSafeAreaEdges: playerBackgroundSafeAreaEdges)
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
#if !os(tvOS)
        .task(id: autoHideToken) { await autoHideControls() }
#endif
        .onAppear {
            // The playback audio session is activated inside the session right
            // before playback starts (SGPlayerCompatibilitySession.play), so it
            // is ready before SGPlayer's audio unit initializes.
            session.volume = volume
            session.setPlaybackStateHandler { playing in
                guard isPlaying != playing else { return }
                isPlaying = playing
            }
        }
    }

    private var playerBackgroundSafeAreaEdges: Edge.Set {
#if os(iOS)
        // ShapeStyle backgrounds bleed into every adjacent safe area by
        // default. For the inline player that made its black background climb
        // behind the transparent navigation bar; only full-screen playback
        // should paint outside the surface's own bounds.
        isFullScreen ? .all : []
#else
        .all
#endif
    }

    // Just the Liquid Glass control bar — no dark gradient behind it.
    private var controlsBar: some View {
        SGPlayerControls(
            session: session,
            isPlaying: $isPlaying,
            volume: $volume,
            isFullScreen: isFullScreen,
            fullScreenSystemImage: fullScreenSystemImage,
            fullScreenAccessibilityLabel: fullScreenAccessibilityLabel,
            fullScreenAction: fullScreenAction,
            onInteraction: keepControlsAlive
        )
    }

    private var controlsVisible: Bool {
#if os(tvOS)
        showsControls
#else
        showsControls && controlsShown
#endif
    }

    // Show the controls (if hidden) and restart the inactivity timer. Called on
    // tap and on any control interaction so the bar stays up while in use.
    // No-op on tvOS, where full-screen control visibility is managed externally.
    private func keepControlsAlive() {
#if !os(tvOS)
        controlsShown = true
        autoHideToken = UUID()
#endif
    }

#if !os(tvOS)
    private func toggleControls() {
        if controlsShown {
            controlsShown = false
        } else {
            keepControlsAlive()
        }
    }

    private func autoHideControls() async {
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        // Keep the controls up while paused so the user can resume.
        guard session.isPlaying else { return }
        controlsShown = false
    }
#endif
}

private struct SGPlayerControls: View {

    let session: SGPlayerCompatibilitySession
    @Binding var isPlaying: Bool
    @Binding var volume: Double
    let isFullScreen: Bool
    let fullScreenSystemImage: String
    let fullScreenAccessibilityLabel: LocalizedStringKey
    let fullScreenAction: (() -> Void)?
    var onInteraction: () -> Void = {}

    var body: some View {
        HStack(spacing: controlSpacing) {
            Button {
                onInteraction()
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(isPlaying ? Text("Pause") : Text("Play"))

            Spacer(minLength: 8)

            Button {
                onInteraction()
                toggleMute()
            } label: {
                Image(systemName: volume <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .accessibilityLabel(volume <= 0 ? Text("Unmute") : Text("Mute"))

            volumeControl

            if let fullScreenAction {
                Button {
                    onInteraction()
                    fullScreenAction()
                } label: {
                    Image(systemName: fullScreenSystemImage)
                }
                .accessibilityLabel(Text(fullScreenAccessibilityLabel))
            }
        }
        .font(controlFont)
        .controlSize(controlSize)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
    }

    private func togglePlayback() {
        if isPlaying {
            session.pause()
            isPlaying = false
        } else {
            session.play()
            isPlaying = true
        }
    }

    private func toggleMute() {
        let nextVolume = volume <= 0 ? 1.0 : 0.0
        volume = nextVolume
        session.volume = nextVolume
    }

    @ViewBuilder
    private var volumeControl: some View {
#if os(tvOS)
        HStack(spacing: 8) {
            Button {
                adjustVolume(by: -0.1)
            } label: {
                Image(systemName: "speaker.minus.fill")
            }
            .accessibilityLabel(Text("Volume Down"))

            ProgressView(value: volume)
                .progressViewStyle(.linear)
                .tint(.white)
                .frame(width: volumeSliderWidth)
                .accessibilityIdentifier("sgplayer-volume")

            Button {
                adjustVolume(by: 0.1)
            } label: {
                Image(systemName: "speaker.plus.fill")
            }
            .accessibilityLabel(Text("Volume Up"))
        }
#else
        Slider(
            value: Binding(
                get: { volume },
                set: { newValue in
                    setVolume(newValue)
                }
            ),
            in: 0...1
        ) {
            Text("Volume")
        }
        .frame(width: volumeSliderWidth)
        .accessibilityIdentifier("sgplayer-volume")
#endif
    }

    private func adjustVolume(by delta: Double) {
        setVolume(volume + delta)
    }

    private func setVolume(_ newValue: Double) {
        onInteraction()
        let clamped = min(max(newValue, 0), 1)
        volume = clamped
        session.volume = clamped
    }

    private var volumeSliderWidth: CGFloat {
#if os(tvOS)
        isFullScreen ? 320 : 220
#elseif os(macOS)
        isFullScreen ? 220 : 150
#else
        isFullScreen ? 220 : 120
#endif
    }

    private var controlSpacing: CGFloat {
#if os(tvOS)
        18
#else
        12
#endif
    }

    private var horizontalPadding: CGFloat {
#if os(tvOS)
        isFullScreen ? 64 : 18
#else
        isFullScreen ? 28 : 12
#endif
    }

    private var verticalPadding: CGFloat {
#if os(tvOS)
        14
#else
        10
#endif
    }

    private var bottomPadding: CGFloat {
#if os(tvOS)
        isFullScreen ? 56 : 14
#else
        isFullScreen ? 28 : 10
#endif
    }

    private var controlFont: Font {
#if os(tvOS)
        .headline
#else
        .body
#endif
    }

    private var controlSize: ControlSize {
#if os(tvOS)
        .large
#else
        .regular
#endif
    }
}

#if os(macOS)
/// Presents the SGPlayer video in a dedicated full-screen window. The video is
/// what fills the screen (not the app window with its sidebar and channel
/// list); the shared SGPlayer session's renderer moves here via attach priority
/// and is handed back to the inline surface when this window closes.
@MainActor
final class MacSGPlayerFullScreenController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var onClose: (() -> Void)?
    private var isClosing = false

    func present(
        session: SGPlayerCompatibilitySession,
        urlString: String,
        volume: Double,
        onPlaybackError: @escaping (String?) -> Void,
        onClose: @escaping () -> Void
    ) {
        guard window == nil else { return }
        self.onClose = onClose

        let content = MacSGPlayerFullScreenContent(
            session: session,
            urlString: urlString,
            initialVolume: volume,
            onPlaybackError: onPlaybackError,
            onExit: { [weak self] in self?.dismiss() }
        )
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = ""
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self
        window.setContentSize(NSSize(width: 1280, height: 720))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        window.toggleFullScreen(nil)
    }

    func dismiss() {
        guard let window, !isClosing else { return }
        if window.styleMask.contains(.fullScreen) {
            // Leave full-screen first; the window is closed once the exit
            // transition finishes (windowDidExitFullScreen).
            window.toggleFullScreen(nil)
        } else {
            window.close()
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        isClosing = true
        window?.delegate = nil
        window = nil
        let onClose = onClose
        self.onClose = nil
        isClosing = false
        onClose?()
    }
}

private struct MacSGPlayerFullScreenContent: View {

    let session: SGPlayerCompatibilitySession
    let urlString: String
    let initialVolume: Double
    let onPlaybackError: (String?) -> Void
    let onExit: () -> Void
    @State private var isPlaying = true
    @State private var volume = 1.0
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SGPlayerSurface(
                urlString: urlString,
                widthMultiplier: 1,
                session: session,
                attachPriority: 2,
                onPlaybackError: { message in
                    errorMessage = message
                    onPlaybackError(message)
                },
                isPlaying: $isPlaying,
                volume: $volume,
                isFullScreen: true,
                showsControls: true,
                fullScreenSystemImage: "xmark",
                fullScreenAccessibilityLabel: "Exit Full Screen",
                fullScreenAction: onExit
            )
            .ignoresSafeArea()

            if let errorMessage {
                ContentUnavailableView {
                    Label("Unable to Play Channel", systemImage: "lock.slash")
                } description: {
                    Text(errorMessage)
                }
                .frame(maxWidth: 480)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            volume = initialVolume
            isPlaying = session.isPlaying
        }
    }
}

private struct MacOsPlayerView: NSViewRepresentable {

    let urlString: String
    let onPlaybackError: (String?) -> Void
    let onExitFullScreen: () -> Void

    func makeNSView(context: Context) -> AVPlayerView {
        // AVPlayerView gives native on-screen transport controls plus a
        // working full-screen toggle button, which a bare AVPlayerLayer
        // lacks.
        let view = AVPlayerView()
        view.player = context.coordinator.controller.player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // No forced play(): the controller autoplays and recovers on its own,
        // and AVPlayerView's own controls own pause/resume.
        if nsView.player !== context.coordinator.controller.player {
            nsView.player = context.coordinator.controller.player
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            controller: StreamPlayerController(
                urlString: urlString,
                onPlaybackError: onPlaybackError
            ),
            onExitFullScreen: onExitFullScreen
        )
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        nsView.player?.pause()
        nsView.player = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Self.NSViewType, context: Self.Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return .init(width: width, height: width * (9.0 / 16.0))
    }

    final class Coordinator: NSObject, AVPlayerViewDelegate {

        let controller: StreamPlayerController
        let onExitFullScreen: () -> Void

        init(controller: StreamPlayerController, onExitFullScreen: @escaping () -> Void) {
            self.controller = controller
            self.onExitFullScreen = onExitFullScreen
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
    let showsPlaybackControls: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        // `showsPlaybackControls` is intentionally fixed for the lifetime of
        // each controller. AVKit warns against creating/destroying its tvOS
        // controls while the controller is already onscreen.
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        // Playback intent belongs to StreamView. The same AVPlayer moves
        // between compact and full-screen controllers, so dismantling one
        // presentation must not pause the shared stream.
        uiViewController.player = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: Self.UIViewControllerType, context: Self.Context) -> CGSize? {
        let multiplier: CGFloat = homeTvOSStreamLayout ? 1 : 2.8 / 3.0
        guard compact, let width = proposal.width.map({ $0 * multiplier }) else { return nil }
        return .init(width: width, height: width * (9.0 / 16.0))
    }
}

private final class TvOSPlayer {

    private let controller: StreamPlayerController

    init(urlString: String, autoplays: Bool = true) {
        controller = StreamPlayerController(urlString: urlString, autoplays: autoplays)
    }

    func compactView(onPlaybackError: @escaping (String?) -> Void) -> some View {
        // Playback is started/stopped by StreamView's activate/pause engine
        // hooks; calling play() here would re-run on every body evaluation
        // (at least once a minute via the TimelineView) and silently undo a
        // user-initiated pause.
        controller.setPlaybackErrorHandler(onPlaybackError)
        return TvOSPlayerView(player: controller.player, compact: true, showsPlaybackControls: false)
    }

    func fullScreenView(onPlaybackError: @escaping (String?) -> Void) -> some View {
        controller.setPlaybackErrorHandler(onPlaybackError)
        return TvOSPlayerView(
            player: controller.player,
            compact: false,
            showsPlaybackControls: true
        )
            .ignoresSafeArea()
    }

    func retry() {
        controller.retry()
    }

    func pause() {
        controller.pause()
    }

    func stop() {
        controller.stop()
    }

    func play() {
        controller.play()
    }

    func togglePlayback() {
        if controller.player.timeControlStatus == .paused {
            controller.play()
        } else {
            controller.pause()
        }
    }
}
#else
private struct iOSPlayerView: UIViewControllerRepresentable {

    let controller: StreamPlayerController
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
        controller.player = self.controller.player
        // iOS playback is intentionally scoped to the visible stream page.
        // Disabling PiP keeps the player from becoming a background playback
        // owner after the user leaves the app.
        controller.allowsPictureInPicturePlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.delegate = context.coordinator
        return controller
    }

    func makeCoordinator() -> Coordinator {
        controller.setPlaybackErrorHandler(onPlaybackError)
        return Coordinator()
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        controller.setPlaybackErrorHandler(onPlaybackError)
        if uiViewController.player !== controller.player {
            uiViewController.player = controller.player
        }
        // Playback intent is owned by StreamView's page/scene lifecycle. Do
        // not call play here: updates can happen while the app is backgrounded.
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            // Match the SGPlayer path: let the phone rotate to landscape for
            // AVPlayer's native fullscreen even though the app UI is portrait.
            IOSVideoOrientationCoordinator.enterFullScreen()
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            IOSVideoOrientationCoordinator.exitFullScreen()
        }
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Self.Coordinator) {
        // StreamView owns and stops the shared controller. The representable
        // only detaches its presentation surface.
        uiViewController.player = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: Self.UIViewControllerType, context: Self.Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return .init(width: width, height: width * (9.0 / 16.0))
    }
}
#endif

#if os(iOS)
/// Presents the SGPlayer video full-screen in a landscape-locked view
/// controller. A real presented controller (declaring `.landscape`) rotates
/// cleanly and keeps SwiftUI hit-testing aligned with the rotation, so the
/// player controls remain tappable — unlike a `.fullScreenCover` forced to
/// rotate via a geometry update, where taps landed in the stale portrait frame.
@MainActor
final class IOSSGPlayerFullScreenController {

    private weak var presented: LandscapeHostingController<AnyView>?

    func present(
        session: SGPlayerCompatibilitySession,
        urlString: String,
        volume: Double,
        onPlaybackError: @escaping (String?) -> Void,
        onClose: @escaping () -> Void
    ) {
        guard presented == nil, let top = Self.topViewController() else { return }

        IOSVideoOrientationCoordinator.enterFullScreen()

        let content = IOSSGPlayerFullScreenView(
            session: session,
            urlString: urlString,
            initialVolume: volume,
            onPlaybackError: onPlaybackError,
            onExit: { [weak self] in self?.dismiss() }
        )
        let controller = LandscapeHostingController(rootView: AnyView(content))
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        controller.onDismiss = onClose
        presented = controller
        top.present(controller, animated: true)
    }

    func dismiss(notifyOnClose: Bool = true) {
        guard let presented else { return }
        self.presented = nil
        if !notifyOnClose {
            // Page teardown owns stopping the session. Suppress the hosting
            // controller's delayed close callback so it cannot revive that
            // session after the navigation transition has already completed.
            presented.onDismiss = nil
        }
        presented.dismiss(animated: true) {
            IOSVideoOrientationCoordinator.exitFullScreen()
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }
            ?? scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let next = top?.presentedViewController {
            top = next
        }
        return top
    }
}

final class LandscapeHostingController<Content: View>: UIHostingController<Content> {

    var onDismiss: (() -> Void)?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var shouldAutorotate: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let onDismiss = onDismiss
        self.onDismiss = nil
        onDismiss?()
    }
}

private struct IOSSGPlayerFullScreenView: View {

    let session: SGPlayerCompatibilitySession
    let urlString: String
    let initialVolume: Double
    let onPlaybackError: (String?) -> Void
    let onExit: () -> Void
    @State private var isPlaying = true
    @State private var volume = 1.0
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SGPlayerSurface(
                urlString: urlString,
                widthMultiplier: 1,
                session: session,
                attachPriority: 2,
                onPlaybackError: { message in
                    errorMessage = message
                    onPlaybackError(message)
                },
                isPlaying: $isPlaying,
                volume: $volume,
                isFullScreen: true,
                showsControls: true,
                fullScreenSystemImage: "xmark",
                fullScreenAccessibilityLabel: "Exit Full Screen",
                fullScreenAction: onExit
            )
            .ignoresSafeArea()

            if let errorMessage {
                ContentUnavailableView {
                    Label("Unable to Play Channel", systemImage: "lock.slash")
                } description: {
                    Text(errorMessage)
                }
                .frame(maxWidth: 480)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            volume = initialVolume
            isPlaying = session.isPlaying
        }
    }
}

@MainActor
private enum IOSVideoOrientationCoordinator {

    static func enterFullScreen() {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            HiPlayerAppDelegate.orientationLock = nil
            refreshSupportedInterfaceOrientations()
            return
        }

        HiPlayerAppDelegate.orientationLock = .landscape
        requestGeometryUpdate(.landscapeRight)
    }

    static func exitFullScreen() {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            HiPlayerAppDelegate.orientationLock = nil
            refreshSupportedInterfaceOrientations()
            return
        }

        // Restore the default (unlocked) state rather than cementing a
        // portrait lock; the delegate already defaults the phone to portrait.
        HiPlayerAppDelegate.orientationLock = nil
        requestGeometryUpdate(.portrait)
    }

    private static func requestGeometryUpdate(_ orientationMask: UIInterfaceOrientationMask) {
        refreshSupportedInterfaceOrientations()
        guard let windowScene = foregroundWindowScene else { return }

        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationMask)) { error in
            Container.shared.logger().error(error)
        }
    }

    private static func refreshSupportedInterfaceOrientations() {
        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in windowScene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    private static var foregroundWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
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
        GeometryReader { geometry in
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(width: geometry.size.width / 4)

                StreamView(
                    content: content,
                    stream: stream,
                    reselectStream: .constant(false),
                    focusedStream: .constant(nil),
                    reloadCurrentProgram: .constant(.init())
                )
                .background(Color(uiColor: .darkGray))
            }
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
