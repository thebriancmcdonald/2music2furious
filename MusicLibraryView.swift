//
//  MusicLibraryView.swift
//  2 Music 2 Furious - MILESTONE 7.3
//
//  Features:
//  - Filter tabs: Playlists, Artists, Albums, Songs, Uploads
//  - Drill-down navigation for Albums/Artists/Playlists (New!)
//  - Uploads Tab restored
//  - Style: Apple Glass
//

import SwiftUI
import MediaPlayer
import UniformTypeIdentifiers

// MARK: - Music Library View

struct MusicLibraryView: View {
    @ObservedObject var library: MusicLibraryManager
    @ObservedObject var musicPlayer: AudioPlayer
    let dismiss: () -> Void
    
    @State private var searchText = ""
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var selectedTab: LibraryTab = .songs
    @State private var showingFilePicker = false
    
    enum LibraryTab: String, CaseIterable {
        case playlists = "Playlists"
        case artists = "Artists"
        case albums = "Albums"
        case songs = "Songs"
        case uploads = "Uploads"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // 1. Background Gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if library.authorizationStatus != .authorized && selectedTab != .uploads {
                        unauthorizedView
                    } else if library.isLoading && selectedTab != .uploads {
                        loadingView
                    } else {
                        mainContent
                    }
                }
                
                toastOverlay
            }
            .navigationTitle("Music Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleFileUpload(result: result)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var unauthorizedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Music Library access not authorized")
                .foregroundColor(.secondary)
            Text("You can still use the Uploads tab")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var loadingView: some View {
        ProgressView("Loading library...")
            .frame(maxHeight: .infinity)
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            tabsView
            
            if selectedTab != .uploads {
                searchBarView
            }
            
            contentSwitcher
        }
    }
    
    private var tabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(tabBackground(for: tab))
                            .foregroundColor(selectedTab == tab ? .white : .primary)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }
    
    @ViewBuilder
    private func tabBackground(for tab: LibraryTab) -> some View {
        if selectedTab == tab {
            Color.blue
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
    
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search music...", text: $searchText)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var contentSwitcher: some View {
        Group {
            switch selectedTab {
            case .songs:
                SongsListView(
                    songs: filteredSongs,
                    library: library,
                    musicPlayer: musicPlayer,
                    onPlay: playSongNow,
                    onQueue: addSongToQueue,
                    dismiss: dismiss
                )
            case .albums:
                AlbumsListView(
                    albums: filteredAlbums,
                    library: library,
                    musicPlayer: musicPlayer,
                    onPlayAlbum: playAlbumNow,
                    onQueueAlbum: addAlbumToQueue,
                    dismiss: dismiss
                )
            case .artists:
                ArtistsListView(
                    artists: filteredArtists,
                    library: library,
                    musicPlayer: musicPlayer,
                    onPlayArtist: playArtistNow,
                    onQueueArtist: addArtistToQueue,
                    dismiss: dismiss
                )
            case .playlists:
                PlaylistsListView(
                    playlists: filteredPlaylists,
                    library: library,
                    musicPlayer: musicPlayer,
                    onPlayPlaylist: playPlaylistNow,
                    onQueuePlaylist: addPlaylistToQueue,
                    dismiss: dismiss
                )
            case .uploads:
                UploadsListView(
                    uploads: library.uploadedTracks,
                    onPlay: playUploadedTrack,
                    onQueue: addUploadedToQueue,
                    onDelete: deleteUploadedTrack,
                    onUpload: { showingFilePicker = true }
                )
            }
        }
    }
    
    private var toastOverlay: some View {
        Group {
            if showingToast {
                VStack {
                    Spacer()
                    ToastView(message: toastMessage)
                        .padding(.bottom, 50)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: showingToast)
                .zIndex(100)
            }
        }
    }
    
    // MARK: - File Upload Handler
    
    private func handleFileUpload(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            var addedCount = 0
            
            for url in urls {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let destinationURL = documentsPath.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    let filename = url.lastPathComponent
                    let title = filename.replacingOccurrences(of: "_", with: " ").components(separatedBy: ".").dropLast().joined(separator: ".")
                    let track = Track(title: title, artist: "Uploaded", filename: filename)
                    library.addUploadedTrack(track)
                    addedCount += 1
                }
            }
            if addedCount > 0 {
                showToast("Added \(addedCount) file\(addedCount == 1 ? "" : "s") to library")
            }
        } catch {
            print("Upload error: \(error)")
            showToast("Upload failed")
        }
    }
    
    // MARK: - Filtered Data
    
    var filteredSongs: [MPMediaItem] {
        if searchText.isEmpty { return library.songs }
        return library.songs.filter { item in
            let search = searchText.lowercased()
            return (item.title?.lowercased().contains(search) ?? false) ||
                   (item.artist?.lowercased().contains(search) ?? false)
        }
    }
    
    var filteredAlbums: [MPMediaItemCollection] {
        if searchText.isEmpty { return library.albums }
        return library.albums.filter { collection in
            let search = searchText.lowercased()
            return (collection.representativeItem?.albumTitle?.lowercased().contains(search) ?? false) ||
                   (collection.representativeItem?.artist?.lowercased().contains(search) ?? false)
        }
    }
    
    var filteredArtists: [MPMediaItemCollection] {
        if searchText.isEmpty { return library.artists }
        return library.artists.filter { collection in
            let search = searchText.lowercased()
            return (collection.representativeItem?.artist?.lowercased().contains(search) ?? false)
        }
    }
    
    var filteredPlaylists: [MPMediaPlaylist] {
        if searchText.isEmpty { return library.playlists }
        return library.playlists.filter { playlist in
            let search = searchText.lowercased()
            return (playlist.name?.lowercased().contains(search) ?? false)
        }
    }
    
    // MARK: - Playback Actions
    
    private func playSongNow(_ item: MPMediaItem) {
        if let track = library.createTrack(from: item) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            musicPlayer.playNow(track)
            dismiss()
        }
    }
    
    private func addSongToQueue(_ item: MPMediaItem) {
        if let track = library.createTrack(from: item) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            musicPlayer.addTrackToQueue(track)
            showToast("Added: \(track.title)")
        }
    }
    
    private func playAlbumNow(_ album: MPMediaItemCollection) {
        let tracks = tracksFromCollection(album)
        guard let firstTrack = tracks.first else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        musicPlayer.playNow(firstTrack)
        for track in tracks.dropFirst() { musicPlayer.addTrackToQueue(track) }
        dismiss()
    }
    
    private func addAlbumToQueue(_ album: MPMediaItemCollection) {
        let tracks = tracksFromCollection(album)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        for track in tracks { musicPlayer.addTrackToQueue(track) }
        showToast("Added \(tracks.count) songs")
    }
    
    private func playArtistNow(_ artist: MPMediaItemCollection) {
        let tracks = tracksFromCollection(artist)
        guard let firstTrack = tracks.first else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        musicPlayer.playNow(firstTrack)
        for track in tracks.dropFirst() { musicPlayer.addTrackToQueue(track) }
        dismiss()
    }
    
    private func addArtistToQueue(_ artist: MPMediaItemCollection) {
        let tracks = tracksFromCollection(artist)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        for track in tracks { musicPlayer.addTrackToQueue(track) }
        showToast("Added \(tracks.count) songs")
    }
    
    private func playPlaylistNow(_ playlist: MPMediaPlaylist) {
        let tracks = tracksFromPlaylist(playlist)
        guard let firstTrack = tracks.first else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        musicPlayer.playNow(firstTrack)
        for track in tracks.dropFirst() { musicPlayer.addTrackToQueue(track) }
        dismiss()
    }
    
    private func addPlaylistToQueue(_ playlist: MPMediaPlaylist) {
        let tracks = tracksFromPlaylist(playlist)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        for track in tracks { musicPlayer.addTrackToQueue(track) }
        showToast("Added \(tracks.count) songs")
    }
    
    private func playUploadedTrack(_ track: Track) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        musicPlayer.playNow(track)
        dismiss()
    }
    
    private func addUploadedToQueue(_ track: Track) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        musicPlayer.addTrackToQueue(track)
        showToast("Added: \(track.title)")
    }
    
    private func deleteUploadedTrack(_ track: Track) {
        library.removeUploadedTrack(track)
        showToast("Deleted: \(track.title)")
    }
    
    // MARK: - Helpers
    
    private func tracksFromCollection(_ collection: MPMediaItemCollection) -> [Track] {
        return collection.items.compactMap { library.createTrack(from: $0) }
    }
    
    private func tracksFromPlaylist(_ playlist: MPMediaPlaylist) -> [Track] {
        return playlist.items.compactMap { library.createTrack(from: $0) }
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { showingToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showingToast = false }
        }
    }
}

// MARK: - GENERIC COLLECTION DETAIL VIEW (NEW)

struct MusicCollectionDetailView: View {
    let title: String
    let subtitle: String
    let artwork: MPMediaItemArtwork?
    let items: [MPMediaItem]
    let library: MusicLibraryManager
    let musicPlayer: AudioPlayer
    let onPlayAll: () -> Void
    let dismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        if let artwork = artwork?.image(at: CGSize(width: 150, height: 150)) {
                            Image(uiImage: artwork)
                                .resizable()
                                .frame(width: 150, height: 150)
                                .cornerRadius(16)
                                .shadow(radius: 8)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 150, height: 150)
                                .overlay(
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 50))
                                        .foregroundColor(.secondary)
                                )
                        }
                        
                        VStack(spacing: 4) {
                            Text(title)
                                .font(.title3.weight(.bold))
                                .multilineTextAlignment(.center)
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // Play All Button
                        Button(action: {
                            onPlayAll()
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play All")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 40)
                            .background(Color.blue)
                            .cornerRadius(25)
                            .shadow(color: Color.blue.opacity(0.3), radius: 5, x: 0, y: 5)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 20)
                    
                    // Song List
                    LazyVStack(spacing: 8) {
                        ForEach(items, id: \.persistentID) { item in
                            Button(action: {
                                if let track = library.createTrack(from: item) {
                                    musicPlayer.playNow(track)
                                    dismiss()
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Text("\(items.firstIndex(of: item)! + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 25)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title ?? "Unknown")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(item.artist ?? "Unknown Artist")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue.opacity(0.6))
                                }
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - List Views

struct SongsListView: View {
    let songs: [MPMediaItem]
    let library: MusicLibraryManager
    let musicPlayer: AudioPlayer
    let onPlay: (MPMediaItem) -> Void
    let onQueue: (MPMediaItem) -> Void
    let dismiss: () -> Void
    
    var body: some View {
        if songs.isEmpty {
            Spacer()
            Text("No songs found").foregroundColor(.secondary)
            Spacer()
        } else {
            List(songs, id: \.persistentID) { item in
                GlassSongRow(item: item, onPlay: { onPlay(item) }, onAddToQueue: { onQueue(item) })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

struct AlbumsListView: View {
    let albums: [MPMediaItemCollection]
    let library: MusicLibraryManager
    let musicPlayer: AudioPlayer
    let onPlayAlbum: (MPMediaItemCollection) -> Void
    let onQueueAlbum: (MPMediaItemCollection) -> Void
    let dismiss: () -> Void
    
    var body: some View {
        if albums.isEmpty {
            Spacer()
            Text("No albums found").foregroundColor(.secondary)
            Spacer()
        } else {
            List(albums, id: \.persistentID) { album in
                // NAVIGATION WRAPPER
                ZStack {
                    NavigationLink(destination: MusicCollectionDetailView(
                        title: album.representativeItem?.albumTitle ?? "Unknown Album",
                        subtitle: album.representativeItem?.albumArtist ?? "Unknown Artist",
                        artwork: album.representativeItem?.artwork,
                        items: album.items,
                        library: library,
                        musicPlayer: musicPlayer,
                        onPlayAll: { onPlayAlbum(album) },
                        dismiss: dismiss
                    )) {
                        EmptyView()
                    }
                    .opacity(0)
                    
                    GlassAlbumRow(
                        album: album,
                        onPlay: { onPlayAlbum(album) },
                        onQueue: { onQueueAlbum(album) }
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

struct ArtistsListView: View {
    let artists: [MPMediaItemCollection]
    let library: MusicLibraryManager
    let musicPlayer: AudioPlayer
    let onPlayArtist: (MPMediaItemCollection) -> Void
    let onQueueArtist: (MPMediaItemCollection) -> Void
    let dismiss: () -> Void
    
    var body: some View {
        if artists.isEmpty {
            Spacer()
            Text("No artists found").foregroundColor(.secondary)
            Spacer()
        } else {
            List(artists, id: \.persistentID) { artist in
                ZStack {
                    NavigationLink(destination: MusicCollectionDetailView(
                        title: artist.representativeItem?.artist ?? "Unknown Artist",
                        subtitle: "\(artist.count) Songs",
                        artwork: artist.representativeItem?.artwork,
                        items: artist.items,
                        library: library,
                        musicPlayer: musicPlayer,
                        onPlayAll: { onPlayArtist(artist) },
                        dismiss: dismiss
                    )) {
                        EmptyView()
                    }
                    .opacity(0)
                    
                    GlassArtistRow(
                        artist: artist,
                        onPlay: { onPlayArtist(artist) },
                        onQueue: { onQueueArtist(artist) }
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

struct PlaylistsListView: View {
    let playlists: [MPMediaPlaylist]
    let library: MusicLibraryManager
    let musicPlayer: AudioPlayer
    let onPlayPlaylist: (MPMediaPlaylist) -> Void
    let onQueuePlaylist: (MPMediaPlaylist) -> Void
    let dismiss: () -> Void
    
    var body: some View {
        if playlists.isEmpty {
            Spacer()
            Text("No playlists found").foregroundColor(.secondary)
            Spacer()
        } else {
            List(playlists, id: \.persistentID) { playlist in
                ZStack {
                    NavigationLink(destination: MusicCollectionDetailView(
                        title: playlist.name ?? "Unknown Playlist",
                        subtitle: "\(playlist.count) Songs",
                        artwork: playlist.representativeItem?.artwork,
                        items: playlist.items,
                        library: library,
                        musicPlayer: musicPlayer,
                        onPlayAll: { onPlayPlaylist(playlist) },
                        dismiss: dismiss
                    )) {
                        EmptyView()
                    }
                    .opacity(0)
                    
                    GlassPlaylistRow(
                        playlist: playlist,
                        onPlay: { onPlayPlaylist(playlist) },
                        onQueue: { onQueuePlaylist(playlist) }
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Uploads List View (RESTORED)

struct UploadsListView: View {
    let uploads: [Track]
    let onPlay: (Track) -> Void
    let onQueue: (Track) -> Void
    let onDelete: (Track) -> Void
    let onUpload: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onUpload) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                    Text("Upload Music Files")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.blue)
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            
            if uploads.isEmpty {
                Spacer()
                Text("No uploaded music").foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(uploads) { track in
                        GlassUploadedTrackRow(
                            track: track,
                            onPlay: { onPlay(track) },
                            onQueue: { onQueue(track) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                onDelete(track)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - Row Views

struct GlassSongRow: View {
    let item: MPMediaItem
    let onPlay: () -> Void
    let onAddToQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let artwork = item.artwork?.image(at: CGSize(width: 44, height: 44)) {
                Image(uiImage: artwork).resizable().frame(width: 44, height: 44).cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(width: 44, height: 44)
                    .overlay(Image(systemName: "music.note").foregroundColor(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "Unknown").font(.system(size: 15, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                Text(item.artist ?? "Unknown").font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: onAddToQueue) {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.secondary).padding(8).background(.ultraThinMaterial).clipShape(Circle())
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture { onPlay() }
    }
}

struct GlassAlbumRow: View {
    let album: MPMediaItemCollection
    let onPlay: () -> Void
    let onQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let artwork = album.representativeItem?.artwork?.image(at: CGSize(width: 50, height: 50)) {
                Image(uiImage: artwork).resizable().frame(width: 50, height: 50).cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(width: 50, height: 50)
                    .overlay(Image(systemName: "square.stack").foregroundColor(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(album.representativeItem?.albumTitle ?? "Unknown").font(.system(size: 16, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                Text(album.representativeItem?.albumArtist ?? "Unknown").font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: onQueue) {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.secondary).padding(8).background(.ultraThinMaterial).clipShape(Circle())
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct GlassArtistRow: View {
    let artist: MPMediaItemCollection
    let onPlay: () -> Void
    let onQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let artwork = artist.representativeItem?.artwork?.image(at: CGSize(width: 50, height: 50)) {
                Image(uiImage: artwork).resizable().frame(width: 50, height: 50).clipShape(Circle())
            } else {
                Circle().fill(Color.gray.opacity(0.2)).frame(width: 50, height: 50)
                    .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.representativeItem?.artist ?? "Unknown").font(.system(size: 16, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                Text("\(artist.count) songs").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onQueue) {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.secondary).padding(8).background(.ultraThinMaterial).clipShape(Circle())
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct GlassPlaylistRow: View {
    let playlist: MPMediaPlaylist
    let onPlay: () -> Void
    let onQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let artwork = playlist.representativeItem?.artwork?.image(at: CGSize(width: 50, height: 50)) {
                Image(uiImage: artwork).resizable().frame(width: 50, height: 50).cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(width: 50, height: 50)
                    .overlay(Image(systemName: "music.note.list").foregroundColor(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name ?? "Unknown").font(.system(size: 16, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                Text("\(playlist.count) songs").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onQueue) {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.secondary).padding(8).background(.ultraThinMaterial).clipShape(Circle())
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct GlassUploadedTrackRow: View {
    let track: Track
    let onPlay: () -> Void
    let onQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.1)).frame(width: 44, height: 44)
                .overlay(Image(systemName: "music.note").foregroundColor(.blue))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 15, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                Text("Uploaded").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onQueue) {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.secondary).padding(8).background(.ultraThinMaterial).clipShape(Circle())
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .onTapGesture { onPlay() }
    }
}

struct ToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text(message).font(.subheadline.weight(.medium)).foregroundColor(.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(.thinMaterial).clipShape(Capsule()).shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}
