//
//  DownloadManager.swift
//  2 Music 2 Furious - MILESTONE 5
//
//  Manages podcast episode downloads
//

import Foundation
import Combine

class DownloadManager: ObservableObject {
    
    static let shared = DownloadManager()
    
    @Published var downloads: [String: Double] = [:] // episodeId -> progress (0-1)
    @Published var downloadedEpisodes: [String] = [] // Array of filenames
    
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    
    init() {
        loadDownloadedEpisodes()
    }
    
    // MARK: - Download Episode
    
    func downloadEpisode(_ episode: Episode, podcastTitle: String) {
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
    
    // MARK: - Check Download Status
    
    func isDownloaded(filename: String) -> Bool {
        return downloadedEpisodes.contains(filename)
    }
    
    func isDownloading(episodeId: String) -> Bool {
        return downloads[episodeId] != nil
    }
    
    // MARK: - Delete Episode
    
    func deleteEpisode(filename: String) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            downloadedEpisodes.removeAll { $0 == filename }
            saveDownloadedEpisodes()
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
    
    // MARK: - Helpers
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}
