
import SwiftUI
import SwiftData
import FactoryKit
#if os(iOS)
import UIKit
#endif

struct ContentView: View {

    @Binding var playlistListUpdate: UUID
    @State private var viewModel = ContentViewModel()
    @InjectedObservable(\.logger) var logger
#if os(tvOS)
    @State private var reselectStream: Bool = false
    @State var focusedStream: PlaylistParser.Stream?
#endif
    @State private var reloadCurrentProgram: UUID = .init()
    @State private var showAcknowledgements = false
    var body: some View {
        contentView()
            .task {
#if os(iOS)
                // A fresh iOS launch always starts at the playlist home. The
                // last-watched data is still recorded for recents/statistics,
                // but it must not drive navigation back into a player page.
                viewModel.prepareForLaunch(restoringLastWatched: false)
#else
                viewModel.prepareForLaunch(restoringLastWatched: true)
#endif
            }
#if os(tvOS)
            .fullScreenCover(isPresented: $viewModel.isShowingPlaylistAdd, onDismiss: {
                viewModel.updatePlaylists()
            }) {
                addPlaylistView()
            }
#else
            .sheet(isPresented: $viewModel.isShowingPlaylistAdd) {
                addPlaylistView()
                    .onDisappear {
                        viewModel.updatePlaylists()
                    }
            }
#endif
            .onChange(of: viewModel.selectedPlaylist) {
                viewModel.onPlaylistSelectionChanged()
            }
            .alert("Unable to Open Playlist", isPresented: $viewModel.isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: playlistListUpdate) {
                viewModel.updatePlaylists()
            }
            .sheet(isPresented: $showAcknowledgements) {
#if os(iOS)
                NavigationStack {
                    AcknowledgementsView()
                }
#else
                AcknowledgementsView()
#endif
            }
            .sheet(item: $viewModel.isShowingPlaylistDecryptPin, onDismiss: {
                viewModel.onDecrypt()
            }) { identity in
#if os(iOS)
                NavigationStack {
                    pinCodeSheet(identity)
                }
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled(true)
#else
                pinCodeSheet(identity)
                    .interactiveDismissDisabled(true)
#endif
            }
    }

    private func pinCodeSheet(_ identity: PlaylistItem.Identity) -> some View {
        PlaylistsEnterPinDecryptView(
            identity: identity,
            selectedPlaylistContent: $viewModel.selectedPlaylistContent
        )
    }
    
    private func addPlaylistView() -> some View {
#if os(iOS)
        NavigationStack {
            PlaylistAddView()
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .presentationDetents([.large])
#elseif os(tvOS)
        ZStack {
            Color.black
                .ignoresSafeArea()
            PlaylistAddView()
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
#else
        PlaylistAddView()
#endif
    }
#if os(tvOS)
    private func contentView() -> some View {
        GeometryReader { geometry in
            NavigationStack(path: $viewModel.path) {
                VStack {
                    PlaylistsView(
                        selectedPlaylist: $viewModel.selectedPlaylist
                    )
                    .frame(width: geometry.size.width / 2)

                    HStack {
                        AddButtonView(isToolbar: false) {
                            viewModel.onAddPlaylist()
                        }
                        Button("", systemImage: "info.circle") {
                            showAcknowledgements = true
                        }
                        .accessibilityIdentifier("acknowledgements")
                    }
                }
                .id(viewModel.playlistListUpdate)
                .navigationDestination(for: PlaylistItem.Content.self) { content in
                    HStack(spacing: 0) {
                        PlaylistView(
                            content: content,
                            selectedStream: $viewModel.selectedPlaylistStream,
                            focusedStream: $focusedStream,
                            reselectStream: $reselectStream,
                            reloadCurrentProgram: $reloadCurrentProgram,
                            restoreStreamHmac: { viewModel.consumeRestoreStreamHmac() }
                        )
                        .frame(width: geometry.size.width / 2.8)
                        .padding(32)
                        .ignoresSafeArea()
                        .onAppear {
                            PlaybackIdlePrevention.acquire(PlaybackIdlePrevention.streamDetail)
                        }
                        .onDisappear {
                            PlaybackIdlePrevention.release(PlaybackIdlePrevention.streamDetail)
                        }

                        if let stream = viewModel.selectedPlaylistStream {
                            StreamView(
                                content: content,
                                stream: stream,
                                reselectStream: $reselectStream,
                                focusedStream: $focusedStream,
                                reloadCurrentProgram: $reloadCurrentProgram
                            )
                            .id(stream)
                            .padding([.top], 32)
                            .ignoresSafeArea()
                        } else {
                            ContentUnavailableView(
                                "Select a channel",
                                systemImage: "play.tv",
                                description: Text("Choose a channel from the list to start watching.")
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .id(content.id)
                    .ignoresSafeArea()
                    .onDisappear {
                        viewModel.selectedPlaylist = nil
                    }
                }
            }
        }
    }
#else
    @ViewBuilder
    private func contentView() -> some View {
#if os(iOS)
        // Keep the phone on one stable navigation architecture even when the
        // player rotates to landscape and changes size classes for full screen.
        if UIDevice.current.userInterfaceIdiom == .phone {
            compactIOSContentView()
        } else {
            splitContentView()
        }
#else
        splitContentView()
#endif
    }

    private func splitContentView() -> some View {
        NavigationSplitView(sidebar: {
            _sidebarView()
        }, content: {
            _contentView()
    #if os(macOS)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 400)
    #endif
        }, detail: {
            _detailView()
        })
#if os(macOS)
        .navigationTitle(viewModel.selectedPlaylistStream?.title ?? viewModel.selectedPlaylist?.name ?? "")
#endif
    }

#if os(iOS)
    private func compactIOSContentView() -> some View {
        NavigationStack {
            _sidebarView()
                .navigationDestination(item: compactPlaylistDestination) { content in
                    compactPlaylistView(content)
                }
        }
    }

    private var compactPlaylistDestination: Binding<PlaylistItem.Content?> {
        Binding(
            get: { viewModel.selectedPlaylistContent },
            set: { content in
                if let content {
                    viewModel.selectedPlaylistContent = content
                } else {
                    viewModel.leavePlaylist()
                }
            }
        )
    }

    private func compactPlaylistView(_ content: PlaylistItem.Content) -> some View {
        PlaylistView(
            content: content,
            selectedStream: $viewModel.selectedPlaylistStream,
            reloadCurrentProgram: $reloadCurrentProgram,
            onIdentityChange: { identity in
                viewModel.onPlaylistRenamed(identity)
            },
            restoreStreamHmac: { viewModel.consumeRestoreStreamHmac() }
        )
        .id(content.id)
        .accessibilityIdentifier("content")
        .navigationTitle(viewModel.selectedPlaylist?.name ?? "")
        .navigationDestination(item: $viewModel.selectedPlaylistStream) { stream in
            StreamView(
                content: content,
                stream: stream,
                reloadCurrentProgram: $reloadCurrentProgram
            )
            .id(stream)
            .accessibilityIdentifier("details")
            .onAppear {
                PlaybackIdlePrevention.acquire(PlaybackIdlePrevention.streamDetail)
            }
            .onDisappear {
                PlaybackIdlePrevention.release(PlaybackIdlePrevention.streamDetail)
            }
        }
    }
#endif

    @ViewBuilder
    private func _sidebarView() -> some View {
        PlaylistsView(
            selectedPlaylist: $viewModel.selectedPlaylist,
            onAddPlaylist: {
                viewModel.onAddPlaylist()
            }
        )
        .accessibilityIdentifier("sidebar")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 280)
#endif
#if os(iOS)
        .navigationTitle(String(localized: "Playlists"))
#endif
        .toolbar {
#if os(macOS)
            ToolbarItem {
                Button("Acknowledgements", systemImage: "info.circle") {
                    showAcknowledgements = true
                }
                .accessibilityIdentifier("acknowledgements")
            }
            ToolbarItem(placement: .secondaryAction) {
                AddButtonView(isToolbar: true) {
                    viewModel.onAddPlaylist()
                }
            }
#else
            ToolbarItem {
                AddButtonView(isToolbar: true) {
                    viewModel.onAddPlaylist()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Acknowledgements", systemImage: "info.circle") {
                    showAcknowledgements = true
                }
                .accessibilityIdentifier("acknowledgements")
            }
#endif
        }
        .id(viewModel.playlistListUpdate)
    }

    @ViewBuilder
    private func _contentView() -> some View {
        if let content = viewModel.selectedPlaylistContent {
            PlaylistView(
                content: content,
                selectedStream: $viewModel.selectedPlaylistStream,
                reloadCurrentProgram: $reloadCurrentProgram,
                onIdentityChange: { identity in
                    viewModel.onPlaylistRenamed(identity)
                },
                restoreStreamHmac: { viewModel.consumeRestoreStreamHmac() }
            )
            .id(content.id)
            .accessibilityIdentifier("content")
#if os(iOS)
            .navigationTitle(viewModel.selectedPlaylist?.name ?? "")
#endif
        } else {
            ContentUnavailableView {
                Label {
                    // The identifier must stay on a Text, UI tests assert
                    // staticTexts["select-playlist"].
                    Text("Select a playlist")
                        .accessibilityIdentifier("select-playlist")
                } icon: {
                    Image(systemName: "play.tv")
                }
            } description: {
                Text("Choose a playlist from the sidebar to see its channels.")
            }
        }
    }

    @ViewBuilder
    private func _detailView() -> some View {
        if let stream = viewModel.selectedPlaylistStream,
           let content = viewModel.selectedPlaylistContent {
            StreamView(
                content: content,
                stream: stream,
                reloadCurrentProgram: $reloadCurrentProgram,
                onPlaybackPageDisappear: {
#if os(iOS)
                    // The compact NavigationSplitView keeps its selection when
                    // the user taps Back. Clear only the stream that actually
                    // disappeared so tapping the same channel creates one
                    // fresh detail instead of reviving a retained player.
                    exitPlaybackPage(for: stream)
#endif
                }
            )
                .id(stream)
                .accessibilityIdentifier("details")
#if os(iOS)
                .onAppear {
                    PlaybackIdlePrevention.acquire(PlaybackIdlePrevention.streamDetail)
                }
                .onDisappear {
                    PlaybackIdlePrevention.release(PlaybackIdlePrevention.streamDetail)
                }
#endif
        }
    }

#if os(iOS)
    private func exitPlaybackPage(for stream: PlaylistParser.Stream) {
        viewModel.clearSelectedStream(ifMatching: stream)
    }
#endif
#endif
}

#if DEBUG

import SwiftData

struct ContentViewPreviews: PreviewProvider {
    
    static var previews: some View {
        Container.preview { container in
            container.databaseService.register {
                let database = DatabaseService(isStoredInMemoryOnly: true)
                let now = Date()
                let mainContext = database.mainContext
                let items = [
                    PlaylistItem(
                        name: "Netflix", date: now.addingTimeInterval(100),
                        icon: nil, url: Data(), salt: nil, encrypted: false
                    ),
                    PlaylistItem(
                        name: "Amazon TV", date: now.addingTimeInterval(103),
                        icon: nil, url: Data(), salt: nil, encrypted: false
                    ),
                    PlaylistItem(
                        name: "America TV", date: now.addingTimeInterval(200),
                        icon: "https://raw.githubusercontent.com/mikehouse/Apple-TV-Player/refs/heads/master/logo.png",
                        url: Data(), salt: nil, encrypted: false
                    )
                ]
                for item in items {
                    mainContext.insert(item)
                    if let identity = item.identity {
                        mainContext.insert(
                            PlaylistSettingsItem(
                                playlistName: identity.name,
                                playlistDate: identity.date,
                                data: Data(),
                                order: nil
                            )
                        )
                    }
                }
                return database
            }
        }
        ContentView(playlistListUpdate: .constant(.init()))
#if os(tvOS)
            .background(Color.init(uiColor: .darkGray))
#endif
    }
}

#endif
