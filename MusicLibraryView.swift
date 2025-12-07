//
//  MusicLibraryView.swift
//  2 Music 2 Furious - MILESTONE 7.3
//
//  Features:
//  - Filter tabs: Playlists, Artists, Albums, Songs, Uploads
//  - Tap to play immediately
//  - Grey [+] button to add to queue (secondary action)
//  - Add entire albums/playlists to queue
//  - Upload music files to library
//  - Toast notifications with haptic feedback
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
                VStack(spacing: 0) {
                    if library.authorizationStatus != .authorized && selectedTab != .uploads {
                        VStack(spacing: 16) {
                            Text("Music Library access not authorized")
                                .foregroundColor(.gray)
                            Text("You can still use the Uploads tab")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxHeight: .infinity)
                    } else if library.isLoading && selectedTab != .uploads {
                        ProgressView("Loading library...")
                    } else {
                        // Filter tabs
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(LibraryTab.allCases, id: \.self) { tab in
                                    Button(action: { selectedTab = tab }) {
                                        Text(tab.rawValue)
                                            .font(.system(size: 13, weight: .medium))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(selectedTab == tab ? Color.blue : Color.gray.opacity(0.2))
                                            .foregroundColor(selectedTab == tab ? .white : .primary)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        
                        // Search bar (not for uploads)
                        if selectedTab != .uploads {
                            TextField("Search...", text: $searchText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                        }
                        
                        // Content based on selected tab
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
                                onQueueAlbum: addAlbumToQueue
                            )
                        case .artists:
                            ArtistsListView(
                                artists: filteredArtists,
                                library: library,
                                musicPlayer: musicPlayer,
                                onPlayArtist: playArtistNow,
                                onQueueArtist: addArtistToQueue
                            )
                        case .playlists:
                            PlaylistsListView(
                                playlists: filteredPlaylists,
                                library: library,
                                musicPlayer: musicPlayer,
                                onPlayPlaylist: playPlaylistNow,
                                onQueuePlaylist: addPlaylistToQueue
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
                
                // Toast overlay
                if showingToast {
                    VStack {
                        Spacer()
                        ToastView(message: toastMessage)
                            .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: showingToast)
                }
            }
            .navigationTitle("Music Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
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
                    
                    // Remove existing file if present
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    
                    // Copy file
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    
                    // Create track and add to library
                    let filename = url.lastPathComponent
                    let title = filename
                        .replacingOccurrences(of: "_", with: " ")
                        .components(separatedBy: ".").dropLast().joined(separator: ".")
                    
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
        if searchText.isEmpty {
            return library.songs
        }
        return library.songs.filter { item in
            let title = item.title?.lowercased() ?? ""
            let artist = item.artist?.lowercased() ?? ""
            let albumArtist = item.albumArtist?.lowercased() ?? ""
            let album = item.albumTitle?.lowercased() ?? ""
            let search = searchText.lowercased()
            return title.contains(search) || artist.contains(search) || albumArtist.contains(search) || album.contains(search)
        }
    }
    
    var filteredAlbums: [MPMediaItemCollection] {
        let albums = library.albums
        if searchText.isEmpty {
            return albums
        }
        return albums.filter { collection in
            let albumTitle = collection.representativeItem?.albumTitle?.lowercased() ?? ""
            let artist = collection.representativeItem?.albumArtist?.lowercased() ?? ""
            let artistAlt = collection.representativeItem?.artist?.lowercased() ?? ""
            let search = searchText.lowercased()
            return albumTitle.contains(search) || artist.contains(search) || artistAlt.contains(search)
        }
    }
    
    var filteredArtists: [MPMediaItemCollection] {
        let artists = library.artists
        if searchText.isEmpty {
            return artists
        }
        return artists.filter { collection in
            let artist = collection.representativeItem?.artist?.lowercased() ?? ""
            let albumArtist = collection.representativeItem?.albumArtist?.lowercased() ?? ""
            let search = searchText.lowercased()
            return artist.contains(search) || albumArtist.contains(search)
        }
    }
    
    var filteredPlaylists: [MPMediaPlaylist] {
        let playlists = library.playlists
        if searchText.isEmpty {
            return playlists
        }
        return playlists.filter { playlist in
            let name = playlist.name?.lowercased() ?? ""
            let search = searchText.lowercased()
            return name.contains(search)
        }
    }
    
    // MARK: - Playback Actions
    
    private func playSongNow(_ item: MPMediaItem) {
        if let track = library.createTrack(from: item) {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            musicPlayer.playNow(track)
            dismiss()
        }
    }
    
    private func addSongToQueue(_ item: MPMediaItem) {
        if let track = library.createTrack(from: item) {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            musicPlayer.addTrackToQueue(track)
            showToast("Added: \(track.title)")
        }
    }
    
    private func playAlbumNow(_ album: MPMediaItemCollection) {
        let tracks = tracksFromCollection(album)
        guard let firstTrack = tracks.first else { return }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        musicPlayer.playNow(firstTrack)
        for track in tracks.dropFirst() {
            musicPlayer.addTrackToQueue(track)
        }
        dismiss()
    }
    
    private func addAlbumToQueue(_ album: MPMediaItemCollection) {
        let tracks = tracksFromCollection(album)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        for track in tracks {
            musicPlayer.addTrackToQueue(track)
        }
        let albumName = album.representativeItem?.albumTitle ?? "Album"
        showToast("Added \(tracks.count) songs from \(albumName)")
    }
    
    private func playArtistNow(_ artist: MPMediaItemCollection) {
        let tracks = tracksFromCollection(artist)
        guard let firstTrack = tracks.first else { return }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        musicPlayer.playNow(firstTrack)
        for track in tracks.dropFirst() {
            musicPlayer.addTrackToQueue(track)
        }
        dismiss()
    }
    
    private func addArtistToQueue(_ artist: MPMediaItemCollection) {
        let tracks = tracksFromCollection(artist)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        for track in tracks {
            musicPlayer.addTrackToQueue(track)
        }
        let artistName = artist.representativeItem?.artist ?? "Artist"
        showToast("Added \(tracks.count) songs by \(artistName)")
    }
    
    private func playPlaylistNow(_ playlist: MPMediaPlaylist) {
        let tracks = tracksFromPlaylist(playlist)
        guard let firstTrack = tracks.first else { return }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        musicPlayer.playNow(firstTrack)
        for track in tracks.dropFirst() {
            musicPlayer.addTrackToQueue(track)
        }
        dismiss()
    }
    
    private func addPlaylistToQueue(_ playlist: MPMediaPlaylist) {
        let tracks = tracksFromPlaylist(playlist)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        for track in tracks {
            musicPlayer.addTrackToQueue(track)
        }
        let playlistName = playlist.name ?? "Playlist"
        showToast("Added \(tracks.count) songs from \(playlistName)")
    }
    
    private func playUploadedTrack(_ track: Track) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        musicPlayer.playNow(track)
        dismiss()
    }
    
    private func addUploadedToQueue(_ track: Track) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
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
        withAnimation {
            showingToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showingToast = false
            }
        }
    }
}

// MARK: - Uploads List View

struct UploadsListView: View {
    let uploads: [Track]
    let onPlay: (Track) -> Void
    let onQueue: (Track) -> Void
    let onDelete: (Track) -> Void
    let onUpload: () -> Void
    
    var body: some View {
        VStack {
            // Upload button header
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
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            if uploads.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No uploaded music")
                        .foregroundColor(.gray)
                    Text("Tap above to add files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(uploads) { track in
                        UploadedTrackRow(
                            track: track,
                            onPlay: { onPlay(track) },
                            onQueue: { onQueue(track) }
                        )
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
            }
        }
    }
}

struct UploadedTrackRow: View {
    let track: Track
    let onPlay: () -> Void
    let onQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundColor(.blue)
                )
            
            // Track info (tappable)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("Uploaded")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onPlay()
            }
            
            // Add to queue button
            Button(action: onQueue) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Songs List View

struct SongsListView: View {
    let songs: [MPMediaItem]
    let library: MusicLibraryManager
    let musicPlayer: AudioPlayer
    let onPlay: (MPMediaItem) -> Void
    let onQueue: (MPMediaItem) -> Void
    let dismiss: () -> Void
    
    var body: some View {
        if songs.isEmpty {
            Text("No songs found")
                .foregroundColor(.gray)
                .frame(maxHeight: .infinity)
        } else {
            List(songs, id: \.persistentID) { item in
                SongRow(
                    item: item,
                    onPlay: { onPlay(item) },
                    onAddToQueue: { onQueue(item) }
                )
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Song Row

struct SongRow: View {
    let item: MPMediaItem
    let onPlay: () -> Void
    let onAddToQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Album artwork
            if let artwork = item.artwork?.image(at: CGSize(width: 44, height: 44)) {
                Image(uiImage: artwork)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    )
            }
            
            // Song info (tappable)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "Unknown")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(item.artist ?? item.albumArtist ?? "Unknown Artist")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onPlay()
            }
            
            // Add to queue button (subtle grey)
            Button(action: onAddToQueue) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Albums List View

struct AlbumsListView: View {
    let albums: [MPMediaItemCollection]
    let library: MusicLibraryManager
    let musicPlayer: AudioPlayer
    let onPlayAlbum: (MPMediaItemCollection) -> Void
    let onQueueAlbum: (MPMediaItemCollection) -> Void
    
    var body: some View {
        if albums.isEmpty {
            Text("No albums found")
                .foregroundColor(.gray)
                .frame(maxHeight: .infinity)
        } else {
            List(albums, id: \.persistentID) { album in
                AlbumRow(
                    album: album,
                    onPlay: { onPlayAlbum(album) },
                    onQueue: { onQueueAlbum(album) }
                )
            }
            .listStyle(.plain)
        }
    }
}

struct AlbumRow: View {
    let album: MPMediaItemCollection
    let onPlay: () -> Void
    let onQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Album artwork
            if let artwork = album.representativeItem?.artwork?.image(at: CGSize(width: 50, height: 50)) {
                Image(uiImage: artwork)
                    .resizable()
                    .frame(width: 50, height: 50)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "square.stack")
                            .foregroundColor(.gray)
                    )
            }
            
            // Album info (tappable)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.representativeItem?.albumTitle ?? "Unknown Album")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(album.representativeItem?.albumArtist ?? album.representativeItem?.artist ?? "Unknown Artist")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("\(album.count) songs")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onPlay()
            }
            
            // Add to queue
            Button(action: onQueue) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Artists List View

struct ArtistsListView: View {
    let artists: [MPMediaItemCollection]
    let library: MusicLibraryManager
    let musicPlayer: AudioPlayer
    let onPlayArtist: (MPMediaItemCollection) -> Void
    let onQueueArtist: (MPMediaItemCollection) -> Void
    
    var body: some View {
        if artists.isEmpty {
            Text("No artists found")
                .foregroundColor(.gray)
                .frame(maxHeight: .infinity)
        } else {
            List(artists, id: \.persistentID) { artist in
                ArtistRow(
                    artist: artist,
                    onPlay: { onPlayArtist(artist) },
                    onQueue: { onQueueArtist(artist) }
                )
            }
            .listStyle(.plain)
        }
    }
}

struct ArtistRow: View {
    let artist: MPMediaItemCollection
    let onPlay: () -> Void
    let onQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Artist image
            if let artwork = artist.representativeItem?.artwork?.image(at: CGSize(width: 50, height: 50)) {
                Image(uiImage: artwork)
                    .resizable()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
            }
            
            // Artist info (tappable)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.representativeItem?.artist ?? artist.representativeItem?.albumArtist ?? "Unknown Artist")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(artist.count) songs")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onPlay()
            }
            
            // Add to queue
            Button(action: onQueue) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Playlists List View

struct PlaylistsListView: View {
    let playlists: [MPMediaPlaylist]
    let library: MusicLibraryManager
    let musicPlayer: AudioPlayer
    let onPlayPlaylist: (MPMediaPlaylist) -> Void
    let onQueuePlaylist: (MPMediaPlaylist) -> Void
    
    var body: some View {
        if playlists.isEmpty {
            Text("No playlists found")
                .foregroundColor(.gray)
                .frame(maxHeight: .infinity)
        } else {
            List(playlists, id: \.persistentID) { playlist in
                PlaylistRow(
                    playlist: playlist,
                    onPlay: { onPlayPlaylist(playlist) },
                    onQueue: { onQueuePlaylist(playlist) }
                )
            }
            .listStyle(.plain)
        }
    }
}

struct PlaylistRow: View {
    let playlist: MPMediaPlaylist
    let onPlay: () -> Void
    let onQueue: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Playlist artwork
            if let artwork = playlist.representativeItem?.artwork?.image(at: CGSize(width: 50, height: 50)) {
                Image(uiImage: artwork)
                    .resizable()
                    .frame(width: 50, height: 50)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "music.note.list")
                            .foregroundColor(.gray)
                    )
            }
            
            // Playlist info (tappable)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name ?? "Unknown Playlist")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(playlist.count) songs")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                onPlay()
            }
            
            // Add to queue
            Button(action: onQueue) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
    }
}
