import FactoryKit
import NukeUI
import SwiftUI

struct PlaylistView: View {

    @InjectedObservable(\.logger) var logger
    @Environment(\.scenePhase) private var scenePhase
    @Binding private var selectedStream: PlaylistParser.Stream?
    @State private var viewModel: PlaylistViewModel
    @Binding private var reloadCurrentProgram: UUID
    private var restoreStreamHmac: () -> String? = { nil }
#if os(tvOS)
    @Binding private var focusedStream: PlaylistParser.Stream?
    @Binding private var reselectStream: Bool
    @FocusState private var isStreamFocused: PlaylistParser.Stream?

    init(
        content: PlaylistItem.Content,
        selectedStream: Binding<PlaylistParser.Stream?>,
        focusedStream: Binding<PlaylistParser.Stream?>,
        reselectStream: Binding<Bool>,
        reloadCurrentProgram: Binding<UUID>,
        restoreStreamHmac: @escaping () -> String? = { nil }
    ) {
        _selectedStream = selectedStream
        _focusedStream = focusedStream
        _reselectStream = reselectStream
        _reloadCurrentProgram = reloadCurrentProgram
        _viewModel = State(wrappedValue: PlaylistViewModel(content: content))
        self.restoreStreamHmac = restoreStreamHmac
    }
#else
    @State private var showPlaylistSettings: PlaylistItem.Identity?
    @State private var onUpdate = UUID()
    @State private var identityChange: PlaylistItem.Identity?
    private var onIdentityChange: (PlaylistItem.Identity) -> Void = { _ in }
#endif
#if !os(tvOS)
    init(
        content: PlaylistItem.Content,
        selectedStream: Binding<PlaylistParser.Stream?>,
        reloadCurrentProgram: Binding<UUID>,
        onIdentityChange: @escaping (PlaylistItem.Identity) -> Void = { _ in },
        restoreStreamHmac: @escaping () -> String? = { nil }
    ) {
        _selectedStream = selectedStream
        _reloadCurrentProgram = reloadCurrentProgram
        _viewModel = State(wrappedValue: PlaylistViewModel(content: content))
        self.onIdentityChange = onIdentityChange
        self.restoreStreamHmac = restoreStreamHmac
    }
#endif

    var body: some View {
        listView()
            .overlay {
                overlayView()
            }
            .onChange(of: selectedStream) {
                if let selectedStream {
                    viewModel.selectedStream(selectedStream)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    reloadCurrentProgram = .init()
                default:
                    break
                }
            }
    }

    private func listView() -> some View {
#if os(tvOS)
        List {
            let showHeader = viewModel.streams.count > 1
            ForEach(Array(viewModel.filteredStreams.enumerated()), id: \.offset) { index, streams in
                Section {
                    ForEach(streams) { stream in
                        Button {
                            reselectStream = selectedStream == stream
                            selectedStream = stream
                        } label: {
                            row(for: stream)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 88)
                        }
                        .focused($isStreamFocused, equals: stream)
                    }
                } header: {
                    if showHeader, let title = streams.first?.groupTitle {
                        HStack {
                            Spacer()
                            Text(title)
                            Spacer()
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        // No .searchable here: on tvOS it permanently shows a keyboard row at
        // the top of the half-width pane and steals initial focus from the
        // channel list, which breaks the remote-first select-a-channel flow.
        .task {
            await viewModel.loadStreams()
            restoreLastWatchedIfNeeded()
        }
        .safeAreaPadding(.trailing, 16)
        .onChange(of: isStreamFocused) {
            for streams in viewModel.streams {
                for stream in streams {
                    if stream == isStreamFocused {
                        focusedStream = stream
                        return
                    }
                }
            }
        }
#else
        List(selection: $selectedStream) {
            let showHeader = viewModel.streams.count > 1
            ForEach(Array(viewModel.filteredStreams.enumerated()), id: \.offset) { index, streams in
                Section {
                    ForEach(streams) { stream in
                        row(for: stream)
                            .tag(stream)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 56)
                    }
                } header: {
                    if showHeader, let title = streams.first?.groupTitle {
                        HStack {
                            Spacer()
                            Text(title)
                            Spacer()
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        .task(id: onUpdate) {
            await viewModel.loadStreams()
            reloadCurrentProgram = .init()
            restoreLastWatchedIfNeeded()
        }
    #if os(iOS)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text("Search channels")
        )
        .refreshable {
            await viewModel.refresh()
            reloadCurrentProgram = .init()
        }
    #else
        .searchable(
            text: $viewModel.searchText,
            placement: .toolbar,
            prompt: Text("Search channels")
        )
    #endif
        .toolbar {
            if !viewModel.streams.isEmpty {
                ToolbarItem {
                    SettingsButtonView {
                        let _ = logger.info("Show Settings button event for", private: viewModel.content.id)
                        showPlaylistSettings = viewModel.content.identity
                    }
                }
            }
    #if os(macOS)
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task {
                        await viewModel.refresh()
                        reloadCurrentProgram = .init()
                    }
                }
                .disabled(viewModel.isLoading || viewModel.isRefreshing)
                .help(Text("Reload playlist and program guide"))
            }
    #endif
        }
        .sheet(item: $showPlaylistSettings, onDismiss: {
            logger.info("Dismiss Settings", private: viewModel.content.id)
            if let identityChange {
                self.identityChange = nil
                onIdentityChange(identityChange)
            }
        }) { playlist in
    #if os(iOS)
            NavigationStack {
                PlaylistSettingsView(
                    identity: viewModel.content.identity,
                    onUpdate: $onUpdate,
                    identityChange: $identityChange
                )
            }
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled(true)
    #else
            PlaylistSettingsView(
                identity: viewModel.content.identity,
                onUpdate: $onUpdate,
                identityChange: $identityChange
            )
            .interactiveDismissDisabled(true)
    #endif
        }
    #if os(iOS)
        .navigationTitle(viewModel.content.identity.name)
        .navigationBarTitleDisplayMode(.inline)
    #endif
#endif
    }

    private func restoreLastWatchedIfNeeded() {
        guard selectedStream == nil,
              let hmac = restoreStreamHmac(),
              let stream = viewModel.stream(matchingLastWatched: hmac) else {
            return
        }
        logger.info("Restore last watched stream", private: viewModel.content.id)
        selectedStream = stream
    }

    private func row(for stream: PlaylistParser.Stream) -> some View {
        StreamRowView(
            logo: { await viewModel.iconURL(for: stream) },
            title: { viewModel.title(for: stream) },
            currentProgram: { await viewModel.currentProgram(for: stream) },
            reloadCurrentProgram: $reloadCurrentProgram
        )
    }

    @ViewBuilder
    private func overlayView() -> some View {
        if viewModel.isLoading && !viewModel.isRefreshing {
            if let progress = viewModel.progress {
                ProgressView(progress)
            } else {
                VStack {
                    ProgressView()
                        .controlSize(.large)
                    Spacer()
                }
                .padding()
            }
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Unable to Load Channels", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
#if !os(tvOS)
                Button("Retry") {
                    onUpdate = .init()
                }
#endif
            }
        } else if !viewModel.searchText.isEmpty, viewModel.filteredStreams.isEmpty, !viewModel.streams.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else if viewModel.streams.isEmpty {
            ContentUnavailableView(
                "No streams found",
                systemImage: "tv.slash",
                description: Text("This playlist does not contain any channels.")
            )
        }
    }
}

private struct StreamRowView: View {

    let logo: @MainActor () async -> String?
    let title: @MainActor () -> String
    let currentProgram: @MainActor () async -> PlaylistViewModel.CurrentProgram?
    @Binding var reloadCurrentProgram: UUID
    @State private var icon: String?
    @State private var program: PlaylistViewModel.CurrentProgram?
    @InjectedObservable(\.logger) var logger

    var body: some View {
        HStack(spacing: 16) {
            if let icon, let url = URL(string: icon) {
                LazyImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                    } else if let error = phase.error {
                        let _ = logger.error(error)
                        EmptyView()
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title())
#if os(tvOS)
                    .font(.system(size: 38, weight: .regular))
#else
                    .font(.headline)
#endif
                    .task {
                        program = await currentProgram()
                        icon = await logo()
                    }
                    .id(reloadCurrentProgram)
                if let program {
                    Text(program.title)
#if os(tvOS)
                        .font(.system(size: 24, weight: .regular))
#else
                        .font(.subheadline)
#endif
                        .foregroundStyle(.secondary)
                    ProgressView(value: program.progress)
                        .progressViewStyle(.linear)
                        .tint(.secondary)
#if os(tvOS)
                        .frame(maxWidth: 320)
#else
                        .frame(maxWidth: 180)
#endif
                }
            }
            .truncationMode(.tail)
            .lineLimit(1)
        }
    }
}

#if DEBUG

struct PlaylistViewPreviews: PreviewProvider {
    
    static var previews: some View {
        let _ = Container.preview { container in
            container.playlistService.register {
                PlaylistServicePreviewMock()
            }
            container.databaseService.register {
                DatabaseService(isStoredInMemoryOnly: true)
            }
        }
        PreviewView()
    }
}

private struct PreviewView: View {

    @State private var selectedStream: PlaylistParser.Stream?

    var body: some View {
        let content = PlaylistItem.Content(
            identity: .init(
                name: "Playlist Name",
                date: Date(timeIntervalSince1970: 100)
            ),
            url: Data("https://example.com/playlist.m3u".utf8),
            data: Data("#EXTM3U".utf8),
            isStoredInMemoryOnly: false
        )
#if os(macOS)
        PlaylistView(
            content: content,
            selectedStream: $selectedStream,
            reloadCurrentProgram: .constant(.init())
        )
        .frame(width: 310, height: 360)
#elseif os(iOS)
        NavigationStack {
            PlaylistView(
                content: content,
                selectedStream: $selectedStream,
                reloadCurrentProgram: .constant(.init())
            )
        }
#else
        PlaylistView(
            content: content,
            selectedStream: $selectedStream,
            focusedStream: .constant(nil),
            reselectStream: .constant(false),
            reloadCurrentProgram: .constant(.init())
        )
        .background(Color.init(uiColor: UIColor.darkGray))
#endif
    }
}

private final class PlaylistServicePreviewMock: PlaylistServiceInterface {
    
    private lazy var pastDate = Date().addingTimeInterval(-100)
    private lazy var futureDate = Date().addingTimeInterval(100)
    private lazy var guides: [String: ProgramGuide] = [
        "Paramount": .init(channel: .init(id: "2", displayName: "-", iconURL: nil),
          programs: [.init(title: "Hot in cleveland", start: pastDate, stop: futureDate)]
        ),
        "Live Music": .init(channel: .init(id: "3", displayName: "-", iconURL: nil),
          programs: [.init(title: "And The Beat Goes On: The Sonny And Cher Story. Continue.",
                           start: pastDate, stop: futureDate)]
        ),
        "Action TV": .init(channel: .init(id: "4", displayName: "-", iconURL: nil),
          programs: [.init(title: "Gladiator",
                           start: pastDate, stop: futureDate)]
        ),
        "Comedy": .init(channel: .init(id: "5", displayName: "-", iconURL: nil),
          programs: [.init(title: "The Truman Show",
                           start: pastDate, stop: futureDate)]
        ),
        "Westerns": .init(channel: .init(id: "5", displayName: "-", iconURL: nil),
          programs: [.init(title: "South of Heaven, West of Hell",
                           start: pastDate, stop: futureDate)]
        )
    ]

    func playlists(
        for content: PlaylistItem.Content,
        reloadProgramGuide: Bool,
        progress: @escaping ProgressHandler
    ) async throws -> [PlaylistParser.Playlist] {
        [
            .init(
                tvgURL: nil,
                imageURL: nil,
                xTvgURL: nil,
                tvgLogo: nil,
                streams: [
                    .init(
                        title: "Channel One",
                        url: "https://example.com/one.m3u8",
                        tvgLogo: "https://raw.githubusercontent.com/mikehouse/Apple-TV-Player/refs/heads/master/logo.png",
                        tvgID: nil,
                        tvgName: "Channel One HD",
                        groupTitle: nil
                    ),
                    .init(
                        title: "Paramount",
                        url: "https://example.com/paramount.m3u8",
                        tvgLogo: nil, tvgID: nil, tvgName: nil, groupTitle: nil
                    ),
                    .init(
                        title: "Live Music",
                        url: "https://example.com/live-music.m3u8",
                        tvgLogo: nil, tvgID: nil, tvgName: nil, groupTitle: nil
                    ),
                    .init(
                        title: "Action TV",
                        url: "https://example.com/action.m3u8",
                        tvgLogo: nil, tvgID: nil, tvgName: nil, groupTitle: nil
                    ),
                    .init(
                        title: "Comedy",
                        url: "https://example.com/comedy.m3u8",
                        tvgLogo: nil, tvgID: nil, tvgName: nil, groupTitle: nil
                    ),
                    .init(
                        title: "Westerns",
                        url: "https://example.com/comedy.m3u8",
                        tvgLogo: nil, tvgID: nil, tvgName: nil, groupTitle: nil
                    )
                ]
            )
        ]
    }

    func playlists(
        for content: PlaylistItem.Content,
        reloadPlaylist: Bool,
        progress: @escaping ProgressHandler = { _, _ in }
    ) async throws -> [PlaylistParser.Playlist] {
        try await playlists(for: content, reloadProgramGuide: reloadPlaylist, progress: progress)
    }

    func programGuide(
        for content: PlaylistItem.Content,
        stream: PlaylistParser.Stream
    ) async -> ProgramGuide? {
        guides[stream.title]
    }

    func clearCache(for content: PlaylistItem.Content) async {
    }

    func programGuides(for content: PlaylistItem.Content, since: Date) async -> [ProgramGuide] {
        []
    }
}

#endif
