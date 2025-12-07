//
//  MusicLibraryManager.swift
//  2 Music 2 Furious - MILESTONE 7.3
//
//  Manages access to iPhone Music Library
//  Includes: Songs, Albums, Artists, Playlists, Uploads
//

import Foundation
import MediaPlayer
import Combine

class MusicLibraryManager: ObservableObject {
    
    @Published var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @Published var songs: [MPMediaItem] = []
    @Published var albums: [MPMediaItemCollection] = []
    @Published var artists: [MPMediaItemCollection] = []
    @Published var playlists: [MPMediaPlaylist] = []
    @Published var uploadedTracks: [Track] = []
    @Published var isLoading = false
    
    private let uploadedTracksKey = "uploadedMusicTracks"
    
    init() {
        loadUploadedTracks()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                if status == .authorized {
                    self?.loadLibrary()
                }
            }
        }
    }
    
    func checkAuthorization() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
        if authorizationStatus == .authorized {
            loadLibrary()
        }
    }
    
    // MARK: - Load All Library Data
    
    private func loadLibrary() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Load songs
            let songsQuery = MPMediaQuery.songs()
            let allSongs = songsQuery.items ?? []
            let playableSongs = allSongs.filter { $0.assetURL != nil }
            
            // Load albums
            let albumsQuery = MPMediaQuery.albums()
            let allAlbums = albumsQuery.collections ?? []
            let playableAlbums = allAlbums.filter { collection in
                collection.items.contains { $0.assetURL != nil }
            }
            
            // Load artists - check both artist and albumArtist fields
            let artistsQuery = MPMediaQuery.artists()
            let allArtists = artistsQuery.collections ?? []
            let playableArtists = allArtists.filter { collection in
                collection.items.contains { $0.assetURL != nil }
            }
            
            // Load playlists
            let playlistsQuery = MPMediaQuery.playlists()
            let allPlaylists = (playlistsQuery.collections as? [MPMediaPlaylist]) ?? []
            let playablePlaylists = allPlaylists.filter { playlist in
                playlist.items.contains { $0.assetURL != nil }
            }
            
            DispatchQueue.main.async {
                self?.songs = playableSongs
                self?.albums = playableAlbums
                self?.artists = playableArtists
                self?.playlists = playablePlaylists
                self?.isLoading = false
                
                print("🎵 Library loaded:")
                print("   - \(playableSongs.count) songs")
                print("   - \(playableAlbums.count) albums")
                print("   - \(playableArtists.count) artists")
                print("   - \(playablePlaylists.count) playlists")
            }
        }
    }
    
    // MARK: - Create Track from MediaItem
    
    func createTrack(from item: MPMediaItem) -> Track? {
        guard let assetURL = item.assetURL else {
            print("❌ No asset URL for: \(item.title ?? "Unknown")")
            return nil
        }
        
        let title = item.title ?? "Unknown"
        let artist = item.artist ?? item.albumArtist ?? "Unknown Artist"
        
        return Track(
            title: title,
            artist: artist,
            filename: assetURL.absoluteString
        )
    }
    
    // MARK: - Uploaded Tracks Management
    
    func addUploadedTrack(_ track: Track) {
        uploadedTracks.append(track)
        saveUploadedTracks()
    }
    
    func removeUploadedTrack(_ track: Track) {
        // Remove file from Documents
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(track.filename)
        try? FileManager.default.removeItem(at: fileURL)
        
        // Remove from list
        uploadedTracks.removeAll { $0.id == track.id }
        saveUploadedTracks()
    }
    
    private func saveUploadedTracks() {
        if let encoded = try? JSONEncoder().encode(uploadedTracks) {
            UserDefaults.standard.set(encoded, forKey: uploadedTracksKey)
        }
    }
    
    private func loadUploadedTracks() {
        if let data = UserDefaults.standard.data(forKey: uploadedTracksKey),
           let decoded = try? JSONDecoder().decode([Track].self, from: data) {
            uploadedTracks = decoded
        }
    }
    
    // MARK: - Helper Methods
    
    func displayName(for item: MPMediaItem) -> String {
        let title = item.title ?? "Unknown"
        let artist = item.artist ?? item.albumArtist ?? "Unknown Artist"
        return "\(artist) - \(title)"
    }
}
