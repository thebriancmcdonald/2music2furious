//
//  DownloadManager.swift
//  2 Music 2 Furious - MILESTONE 15
//
//  Manages podcast episode downloads
//  PERFORMANCE UPDATE: Lazy loading for downloaded episodes list
//  NEW: Stores episode metadata (description, duration, etc.) alongside downloads
//

import Foundation
import Combine

// MARK: - Episode Metadata for Storage

struct DownloadedEpisodeMetadata: Codable {
    let filename: String
    let episodeTitle: String
    let episodeDescription: String
    let episodeDuration: TimeInterval
    let episodePubDate: Date
    let episodeAudioUrl: String
    let podcastTitle: String
    let podcastAuthor: String
    let podcastArtworkUrl: String
}

class DownloadManager: ObservableObject {
    
    static let shared = DownloadManager()
    
    @Published var downloads: [String: Double] = [:] // episodeId -> progress (0-1)
    @Published var downloadedEpisodes: [String] = [] // Array of filenames
    @Published var isLoaded = false
    
    // NEW: Metadata storage
    private var episodeMetadata: [String: DownloadedEpisodeMetadata] = [:] // filename -> metadata
    
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    
    // MARK: - LAZY LOADING: Empty init
    
    init() {
        // Downloaded episodes loaded lazily via loadIfNeeded()
    }
    
    /// Call this before accessing downloadedEpisodes - loads from disk if not already loaded
    func loadIfNeeded() {
        guard !isLoaded else { return }
        loadDownloadedEpisodes()
        loadMetadata()
        isLoaded = true
    }
    
    // MARK: - Download Episode
    
    func downloadEpisode(_ episode: Episode, podcastTitle: String, podcastAuthor: String = "", podcastArtworkUrl: String = "") {
        loadIfNeeded()
        
        let episodeId = episode.id.uuidString
        
        guard let url = URL(string: episode.audioUrl) else {
            print("Invalid URL: \(episode.audioUrl)")
            return
        }
        
        // Create filename
        let filename = sanitizeFilename("\(podcastTitle)_\(episode.title).mp3")
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent(filename)
        
        // Check if already downloaded
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            print("Episode already downloaded")
            return
        }
        
        // Store metadata BEFORE download completes (so it's ready when needed)
        let metadata = DownloadedEpisodeMetadata(
            filename: filename,
            episodeTitle: episode.title,
            episodeDescription: episode.description,
            episodeDuration: episode.duration,
            episodePubDate: episode.pubDate,
            episodeAudioUrl: episode.audioUrl,
            podcastTitle: podcastTitle,
            podcastAuthor: podcastAuthor,
            podcastArtworkUrl: podcastArtworkUrl
        )
        
        // Start download
        downloads[episodeId] = 0.0
        
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                self?.downloads.removeValue(forKey: episodeId)
                self?.activeTasks.removeValue(forKey: episodeId)
                
                if let error = error {
                    print("Download error: \(error)")
                    return
                }
                
                guard let tempURL = tempURL else {
                    print("No temp URL")
                    return
                }
                
                do {
                    // Move to documents
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    
                    // Track downloaded episode
                    self?.downloadedEpisodes.append(filename)
                    self?.saveDownloadedEpisodes()
                    
                    // Save metadata
                    self?.episodeMetadata[filename] = metadata
                    self?.saveMetadata()
                    
                    print("Downloaded: \(filename)")
                } catch {
                    print("Failed to save file: \(error)")
                }
            }
        }
        
        activeTasks[episodeId] = task
        task.resume()
        
        print("Started download: \(filename)")
    }
    
    // MARK: - Get Metadata
    
    func getMetadata(for filename: String) -> DownloadedEpisodeMetadata? {
        loadIfNeeded()
        return episodeMetadata[filename]
    }
    
    // MARK: - Check Download Status
    
    func isDownloaded(filename: String) -> Bool {
        loadIfNeeded()
        return downloadedEpisodes.contains(filename)
    }
    
    func isDownloading(episodeId: String) -> Bool {
        return downloads[episodeId] != nil
    }
    
    // MARK: - Delete Episode
    
    func deleteEpisode(filename: String) {
        loadIfNeeded()
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            downloadedEpisodes.removeAll { $0 == filename }
            saveDownloadedEpisodes()
            
            // Remove metadata
            episodeMetadata.removeValue(forKey: filename)
            saveMetadata()
            
            print("Deleted: \(filename)")
        } catch {
            print("Failed to delete: \(error)")
        }
    }
    
    // MARK: - Persistence
    
    private func saveDownloadedEpisodes() {
        UserDefaults.standard.set(downloadedEpisodes, forKey: "downloadedEpisodes")
    }
    
    private func loadDownloadedEpisodes() {
        downloadedEpisodes = UserDefaults.standard.stringArray(forKey: "downloadedEpisodes") ?? []
    }
    
    private func saveMetadata() {
        if let encoded = try? JSONEncoder().encode(episodeMetadata) {
            UserDefaults.standard.set(encoded, forKey: "downloadedEpisodeMetadata")
        }
    }
    
    private func loadMetadata() {
        if let data = UserDefaults.standard.data(forKey: "downloadedEpisodeMetadata"),
           let decoded = try? JSONDecoder().decode([String: DownloadedEpisodeMetadata].self, from: data) {
            episodeMetadata = decoded
        }
    }
    
    // MARK: - Helpers
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}
