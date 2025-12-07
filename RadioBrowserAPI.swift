//
//  RadioBrowserAPI.swift
//  2 Music 2 Furious
//
//  Fixed: Added '&reverse=true' to all search queries to show
//  most popular stations first (Descending Order).
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
    
    // Formats 12500 -> "12.5k" for display
    var formattedClicks: String {
        if clickcount >= 1000 {
            return String(format: "%.1fk", Double(clickcount) / 1000)
        }
        return "\(clickcount)"
    }
}

class RadioBrowserAPI: ObservableObject {
    @Published var searchResults: [RadioStation] = []
    @Published var isSearching = false
    @Published var favoriteStations: [RadioStation] = []
    
    private let baseURL = "https://de1.api.radio-browser.info/json"
    
    init() {
        loadFavorites()
    }
    
    // MARK: - API Calls
    
    func fetchTopStations() {
        isSearching = true
        // Added reverse=true to get highest clicks first
        let urlString = "\(baseURL)/stations/search?limit=100&order=clickcount&reverse=true&hidebroken=true"
        guard let url = URL(string: urlString) else {
            isSearching = false
            return
        }
        fetchStations(from: url)
    }
    
    func searchByName(query: String) {
        guard !query.isEmpty else { return }
        isSearching = true
        // Added reverse=true
        let urlString = "\(baseURL)/stations/search?limit=50&order=clickcount&reverse=true&hidebroken=true&name=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        guard let url = URL(string: urlString) else {
            isSearching = false
            return
        }
        fetchStations(from: url)
    }
    
    func searchByTag(tag: String) {
        isSearching = true
        let sanitizedTag = tag.lowercased().trimmingCharacters(in: .whitespaces)
        // Added reverse=true
        let urlString = "\(baseURL)/stations/search?limit=50&order=clickcount&reverse=true&hidebroken=true&tag=\(sanitizedTag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        guard let url = URL(string: urlString) else {
            isSearching = false
            return
        }
        fetchStations(from: url)
    }
    
    // Kept for backward compatibility if needed, but not used in new UI
    func searchByCountry(country: String) {
        isSearching = true
        let urlString = "\(baseURL)/stations/bycountry/\(country.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        guard let url = URL(string: urlString) else {
            isSearching = false
            return
        }
        fetchStations(from: url)
    }
    
    private func fetchStations(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSearching = false
                guard let data = data else { return }
                do {
                    let stations = try JSONDecoder().decode([RadioStation].self, from: data)
                    self?.searchResults = stations.filter { !$0.url.isEmpty }
                } catch {
                    print("Decode error: \(error)")
                }
            }
        }.resume()
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
