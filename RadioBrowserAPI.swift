//
//  RadioBrowserAPI.swift
//  2 Music 2 Furious
//
//  API Manager for Radio Browser
//  Updates: Infinite Scrolling (Pagination)
//

import Foundation
import Combine

struct RadioStation: Identifiable, Codable {
    let stationuuid: String
    let name: String
    let url: String
    let favicon: String
    let country: String
    let tags: String
    let clickcount: Int
    let bitrate: Int
    
    var id: String { stationuuid }
    var displayName: String { name.trimmingCharacters(in: .whitespaces) }
    var displayCountry: String { country.isEmpty ? "Unknown" : country }
    var displayTags: String { tags.isEmpty ? "Music" : tags }
    
    // Formats 12500 -> "12k"
    var formattedClicks: String {
        if clickcount >= 1000 {
            return "\(clickcount / 1000)k"
        }
        return "\(clickcount)"
    }
}

class RadioBrowserAPI: ObservableObject {
    @Published var searchResults: [RadioStation] = []
    @Published var isSearching = false
    @Published var isLoadingMore = false // For bottom spinner
    @Published var favoriteStations: [RadioStation] = []
    @Published var hasMorePages = true // Stop if API returns empty
    
    private let baseURL = "https://de1.api.radio-browser.info/json"
    private var currentOffset = 0
    private let limit = 50 // Batch size (50 is fast)
    
    // Store current queries to use when loading more
    private var lastQueryName: String?
    private var lastQueryTag: String?
    private var lastQueryCountry: String?
    private var lastQueryBitrate: Int?
    
    init() {
        loadFavorites()
    }
    
    // MARK: - Advanced Search (Resets List)
    
    func search(name: String?, tag: String?, country: String?, minBitrate: Int? = nil) {
        // 1. Reset State
        isSearching = true
        hasMorePages = true
        currentOffset = 0
        searchResults = [] // Clear previous results
        
        // 2. Save Query for Pagination
        lastQueryName = name
        lastQueryTag = tag
        lastQueryCountry = country
        lastQueryBitrate = minBitrate
        
        // 3. Fetch First Batch
        fetchBatch()
    }
    
    // MARK: - Load More (Pagination)
    
    func loadNextPage() {
        guard !isLoadingMore && !isSearching && hasMorePages else { return }
        
        isLoadingMore = true
        currentOffset += limit
        fetchBatch()
    }
    
    // MARK: - Private Fetcher
    
    private func fetchBatch() {
        var queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(currentOffset)), // Pagination magic
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "hidebroken", value: "true")
        ]
        
        if let name = lastQueryName, !name.isEmpty {
            queryItems.append(URLQueryItem(name: "name", value: name))
        }
        
        if let tag = lastQueryTag, !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tag", value: tag.lowercased()))
        }
        
        if let country = lastQueryCountry, !country.isEmpty {
            queryItems.append(URLQueryItem(name: "country", value: country))
        }
        
        if let minBitrate = lastQueryBitrate {
            queryItems.append(URLQueryItem(name: "bitrateMin", value: String(minBitrate)))
        }
        
        var components = URLComponents(string: "\(baseURL)/stations/search")
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            isSearching = false
            isLoadingMore = false
            return
        }
        
        print("ðŸ“¡ Fetching: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                self.isSearching = false
                self.isLoadingMore = false
                
                guard let data = data else { return }
                
                do {
                    let newStations = try JSONDecoder().decode([RadioStation].self, from: data)
                    let validStations = newStations.filter { !$0.url.isEmpty }
                    
                    if validStations.isEmpty {
                        self.hasMorePages = false // Stop trying to load
                    } else {
                        // Append to existing list
                        self.searchResults.append(contentsOf: validStations)
                    }
                    
                } catch {
                    print("Decode error: \(error)")
                }
            }
        }.resume()
    }
    
    // MARK: - Legacy Calls
    
    func fetchTopStations() {
        // Just treat it as an empty search (defaults to top 100 sorted by clicks)
        search(name: nil, tag: nil, country: nil)
    }
    
    func searchByName(query: String) {
        search(name: query, tag: nil, country: nil)
    }
    
    func searchByTag(tag: String) {
        search(name: nil, tag: tag, country: nil)
    }
    
    // MARK: - Favorites
    
    func toggleFavorite(_ station: RadioStation) {
        if isFavorite(station) {
            favoriteStations.removeAll { $0.id == station.id }
        } else {
            favoriteStations.append(station)
        }
        saveFavorites()
    }
    
    func isFavorite(_ station: RadioStation) -> Bool {
        favoriteStations.contains { $0.id == station.id }
    }
    
    private func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favoriteStations) {
            UserDefaults.standard.set(encoded, forKey: "favoriteRadioStations")
        }
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: "favoriteRadioStations"),
           let decoded = try? JSONDecoder().decode([RadioStation].self, from: data) {
            favoriteStations = decoded
        }
    }
}
