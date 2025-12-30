//
//  RadioBrowserAPI.swift
//  2 Music 2 Furious
//
//  API Manager for Radio Browser
//  PERFORMANCE UPDATE: Lazy loading for favorites
//  FIX: Added server fallback, User-Agent header, and HTML error detection
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
    @Published var isLoaded = false
    @Published var errorMessage: String? = nil // NEW: Surface errors to UI
    
    // Multiple servers for fallback - Radio Browser is distributed
    // de1 is the primary/best server, others are fallbacks
    // Check https://api.radio-browser.info/ for current server list
    private let serverList = [
        "de1.api.radio-browser.info",   // Primary - best data when available
        "de2.api.radio-browser.info",   // Germany backup
        "fi1.api.radio-browser.info",   // Finland - documented as reliable
        "nl2.api.radio-browser.info",   // Netherlands backup
        "at2.api.radio-browser.info"    // Austria backup
    ]
    private var currentServerIndex = 0
    
    private var baseURL: String {
        "https://\(serverList[currentServerIndex])/json"
    }
    
    private var currentOffset = 0
    private let limit = 50 // Batch size (50 is fast)
    
    // Store current queries to use when loading more
    private var lastQueryName: String?
    private var lastQueryTag: String?
    private var lastQueryCountry: String?
    private var lastQueryBitrate: Int?
    
    // Prevent duplicate searches
    private var currentSearchTask: URLSessionDataTask?
    
    // MARK: - LAZY LOADING: Empty init
    
    init() {
        // Favorites loaded lazily via loadIfNeeded()
    }
    
    /// Call this before accessing favorites - loads from disk if not already loaded
    func loadIfNeeded() {
        guard !isLoaded else { return }
        loadFavorites()
        isLoaded = true
    }
    
    // MARK: - Advanced Search (Resets List)
    
    func search(name: String?, tag: String?, country: String?, minBitrate: Int? = nil) {
        // Cancel any in-flight request
        currentSearchTask?.cancel()
        
        // 1. Reset State
        isSearching = true
        hasMorePages = true
        currentOffset = 0
        searchResults = [] // Clear previous results
        errorMessage = nil
        
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
    
    private func fetchBatch(retryCount: Int = 0) {
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
            DispatchQueue.main.async {
                self.isSearching = false
                self.isLoadingMore = false
                self.errorMessage = "Invalid URL"
            }
            return
        }
        
        // Create request with User-Agent header (some servers require this)
        var request = URLRequest(url: url)
        request.setValue("2Music2Furious/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15 // Don't wait forever
        
        print("📡 Fetching from \(serverList[currentServerIndex]): \(url.absoluteString)")
        
        currentSearchTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Handle cancellation silently
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    return
                }
                
                // Handle network errors with server fallback
                if let error = error {
                    print("📡 Network error: \(error.localizedDescription)")
                    self.tryNextServer(retryCount: retryCount, originalError: error.localizedDescription)
                    return
                }
                
                guard let data = data, !data.isEmpty else {
                    print("📡 Empty response")
                    self.tryNextServer(retryCount: retryCount, originalError: "Empty response from server")
                    return
                }
                
                // Check if response is HTML (server error page) instead of JSON
                if let firstChar = String(data: data.prefix(1), encoding: .utf8), firstChar == "<" {
                    print("📡 Server returned HTML error page, trying next server...")
                    self.tryNextServer(retryCount: retryCount, originalError: "Server returned error page")
                    return
                }
                
                // Check HTTP status code
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    print("📡 HTTP error: \(httpResponse.statusCode)")
                    self.tryNextServer(retryCount: retryCount, originalError: "HTTP \(httpResponse.statusCode)")
                    return
                }
                
                do {
                    let newStations = try JSONDecoder().decode([RadioStation].self, from: data)
                    let validStations = newStations.filter { !$0.url.isEmpty }
                    
                    self.isSearching = false
                    self.isLoadingMore = false
                    self.errorMessage = nil
                    
                    if validStations.isEmpty {
                        self.hasMorePages = false // Stop trying to load
                    } else {
                        // Append to existing list
                        self.searchResults.append(contentsOf: validStations)
                        print("📡 Found \(validStations.count) stations (total: \(self.searchResults.count))")
                    }
                    
                } catch {
                    print("📡 Decode error: \(error)")
                    self.tryNextServer(retryCount: retryCount, originalError: "Failed to parse response")
                }
            }
        }
        currentSearchTask?.resume()
    }
    
    // MARK: - Server Fallback
    
    private func tryNextServer(retryCount: Int, originalError: String) {
        // Try next server if we haven't tried them all
        if retryCount < serverList.count - 1 {
            currentServerIndex = (currentServerIndex + 1) % serverList.count
            print("📡 Trying fallback server: \(serverList[currentServerIndex])")
            fetchBatch(retryCount: retryCount + 1)
        } else {
            // All servers failed
            isSearching = false
            isLoadingMore = false
            errorMessage = "Unable to reach radio servers. Please check your internet connection."
            print("📡 All servers failed. Last error: \(originalError)")
        }
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
        loadIfNeeded()
        if isFavorite(station) {
            favoriteStations.removeAll { $0.id == station.id }
        } else {
            favoriteStations.append(station)
        }
        saveFavorites()
    }
    
    func isFavorite(_ station: RadioStation) -> Bool {
        loadIfNeeded()
        return favoriteStations.contains { $0.id == station.id }
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
