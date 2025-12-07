//
//  PodcastSearchManager.swift
//  2 Music 2 Furious - MILESTONE 5
//
//  Search podcasts via iTunes API and parse RSS feeds
//

import Foundation
import Combine

struct Podcast: Identifiable, Codable {
    let id: Int
    let title: String
    let author: String
    let artworkUrl: String
    let feedUrl: String
    
    enum CodingKeys: String, CodingKey {
        case id = "collectionId"
        case title = "collectionName"
        case author = "artistName"
        case artworkUrl = "artworkUrl600"
        case feedUrl = "feedUrl"
    }
}

struct Episode: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let audioUrl: String
    let duration: TimeInterval
    let pubDate: Date
    var isDownloaded: Bool = false
    var localFilename: String?
}

class PodcastSearchManager: ObservableObject {
    
    @Published var searchResults: [Podcast] = []
    @Published var isSearching = false
    @Published var episodes: [Episode] = []
    @Published var isLoadingEpisodes = false
    @Published var favoritePodcasts: [Podcast] = []
    
    init() {
        loadFavorites()
    }
    
    // MARK: - Favorites Management
    
    func toggleFavorite(_ podcast: Podcast) {
        if isFavorite(podcast) {
            favoritePodcasts.removeAll { $0.id == podcast.id }
        } else {
            favoritePodcasts.append(podcast)
        }
        saveFavorites()
    }
    
    func isFavorite(_ podcast: Podcast) -> Bool {
        return favoritePodcasts.contains { $0.id == podcast.id }
    }
    
    private func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favoritePodcasts) {
            UserDefaults.standard.set(encoded, forKey: "favoritePodcasts")
        }
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: "favoritePodcasts"),
           let decoded = try? JSONDecoder().decode([Podcast].self, from: data) {
            favoritePodcasts = decoded
        }
    }
    
    // MARK: - Search Podcasts
    
    func searchPodcasts(query: String) {
        guard !query.isEmpty else { return }
        
        isSearching = true
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?media=podcast&term=\(encodedQuery)&limit=20"
        
        guard let url = URL(string: urlString) else {
            isSearching = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSearching = false
                
                if let error = error {
                    print("Search error: \(error)")
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    let result = try JSONDecoder().decode(SearchResponse.self, from: data)
                    self?.searchResults = result.results
                    print("Found \(result.results.count) podcasts")
                } catch {
                    print("Decode error: \(error)")
                }
            }
        }.resume()
    }
    
    // MARK: - Load Episodes from RSS
    
    func loadEpisodes(for podcast: Podcast) {
        isLoadingEpisodes = true
        episodes = []
        
        guard let url = URL(string: podcast.feedUrl) else {
            isLoadingEpisodes = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoadingEpisodes = false
                
                if let error = error {
                    print("RSS fetch error: \(error)")
                    return
                }
                
                guard let data = data else { return }
                
                self?.parseRSS(data: data)
            }
        }.resume()
    }
    
    // MARK: - RSS Parsing
    
    private func parseRSS(data: Data) {
        let parser = XMLParser(data: data)
        let delegate = RSSParserDelegate()
        parser.delegate = delegate
        
        if parser.parse() {
            self.episodes = delegate.episodes
            print("Parsed \(delegate.episodes.count) episodes")
        } else {
            print("RSS parse failed")
        }
    }
}

// MARK: - Supporting Types

struct SearchResponse: Codable {
    let results: [Podcast]
}

// MARK: - RSS Parser Delegate

class RSSParserDelegate: NSObject, XMLParserDelegate {
    
    var episodes: [Episode] = []
    
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentAudioUrl = ""
    private var currentDuration: TimeInterval = 0
    private var currentPubDate = Date()
    
    private var isInItem = false
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "item" {
            isInItem = true
            // Reset current values
            currentTitle = ""
            currentDescription = ""
            currentAudioUrl = ""
            currentDuration = 0
            currentPubDate = Date()
        }
        
        // Handle enclosure tag (audio file)
        if elementName == "enclosure", let url = attributeDict["url"] {
            currentAudioUrl = url
            if let durationStr = attributeDict["length"], let duration = TimeInterval(durationStr) {
                currentDuration = duration / 60 // Convert to minutes
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && isInItem else { return }
        
        switch currentElement {
        case "title":
            currentTitle += trimmed
        case "description", "itunes:summary":
            currentDescription += trimmed
        case "pubDate":
            if let date = parseDate(trimmed) {
                currentPubDate = date
            }
        case "itunes:duration":
            if let duration = parseDuration(trimmed) {
                currentDuration = duration
            }
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" && isInItem {
            // Create episode if we have required data
            if !currentTitle.isEmpty && !currentAudioUrl.isEmpty {
                let episode = Episode(
                    title: currentTitle,
                    description: currentDescription,
                    audioUrl: currentAudioUrl,
                    duration: currentDuration,
                    pubDate: currentPubDate
                )
                episodes.append(episode)
            }
            isInItem = false
        }
    }
    
    // MARK: - Helpers
    
    private func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: string)
    }
    
    private func parseDuration(_ string: String) -> TimeInterval? {
        // Parse formats like "1:23:45" or "12:34" or "3600"
        let components = string.split(separator: ":")
        
        if components.count == 3 {
            // HH:MM:SS
            guard let hours = TimeInterval(components[0]),
                  let minutes = TimeInterval(components[1]),
                  let seconds = TimeInterval(components[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        } else if components.count == 2 {
            // MM:SS
            guard let minutes = TimeInterval(components[0]),
                  let seconds = TimeInterval(components[1]) else { return nil }
            return minutes * 60 + seconds
        } else if let seconds = TimeInterval(string) {
            // Just seconds
            return seconds
        }
        
        return nil
    }
}
