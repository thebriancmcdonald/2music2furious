//
//  RadioSearchView.swift
//  2 Music 2 Furious - MILESTONE 12
//
//  Radio search with filters - Uses SharedComponents for consistency
//  UPDATED: Passes Station Artwork to AudioPlayer for Background Blur
//  UPDATED: Added Drag-to-Reorder for Favorites
//

import SwiftUI

// MARK: - Navigation Destination Enum

enum RadioNavDestination: Hashable {
    case favorites
}

struct RadioSearchView: View {
    @ObservedObject var radioAPI: RadioBrowserAPI
    @ObservedObject var musicPlayer: AudioPlayer
    let dismiss: () -> Void
    
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var selectedGenre: String? = nil
    @State private var selectedCountry: String? = nil
    @State private var selectedBitrate: Int? = nil
    
    // Preset Filters
    let genres = ["Pop", "Rock", "Jazz", "Classical", "Hip Hop", "Electronic", "News", "Talk", "Country", "Indie"]
    let countries = ["USA", "UK", "Germany", "France", "Canada", "Japan", "Brazil", "Spain", "Italy"]
    
    let qualityOptions = [
        (96, "Standard (96k+)"),
        (128, "High (128k+)"),
        (192, "Very High (192k+)"),
        (320, "Audiophile (320k)")
    ]
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                GlassBackgroundView()
                
                List {
                    // SECTION 1: FAVORITES
                    if !radioAPI.favoriteStations.isEmpty {
                        FavoritesCarousel(
                            title: "Favorites",
                            items: Array(radioAPI.favoriteStations.prefix(8)),
                            onSeeAll: { navigationPath.append(RadioNavDestination.favorites) }
                        ) { station in
                            CarouselItemView(
                                title: station.displayName,
                                artworkURL: URL(string: station.favicon),
                                size: 70,
                                fallbackIcon: "antenna.radiowaves.left.and.right",
                                fallbackColor: .orange
                            ) {
                                playStation(station)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 10, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    
                    // SECTION 2: SEARCH & FILTER
                    VStack(alignment: .leading, spacing: 12) {
                        // Search Bar
                        GlassSearchBar(
                            text: $searchText,
                            placeholder: "Search stations...",
                            onCommit: performSearch,
                            onClear: performSearch
                        )
                        
                        // Horizontal Filter Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                // Genre Pill
                                Menu {
                                    Button("All Genres", action: {
                                        selectedGenre = nil
                                        performSearch()
                                    })
                                    ForEach(genres, id: \.self) { genre in
                                        Button(genre, action: {
                                            selectedGenre = genre
                                            performSearch()
                                        })
                                    }
                                } label: {
                                    FilterPill(
                                        icon: "music.note",
                                        title: selectedGenre ?? "Genre",
                                        isActive: selectedGenre != nil
                                    )
                                }
                                
                                // Country Pill
                                Menu {
                                    Button("All Countries", action: {
                                        selectedCountry = nil
                                        performSearch()
                                    })
                                    ForEach(countries, id: \.self) { country in
                                        Button(country, action: {
                                            selectedCountry = country
                                            performSearch()
                                        })
                                    }
                                } label: {
                                    FilterPill(
                                        icon: "globe",
                                        title: selectedCountry ?? "Country",
                                        isActive: selectedCountry != nil
                                    )
                                }
                                
                                // Quality Pill
                                Menu {
                                    Button("Any Quality", action: {
                                        selectedBitrate = nil
                                        performSearch()
                                    })
                                    ForEach(qualityOptions, id: \.0) { option in
                                        Button(option.1, action: {
                                            selectedBitrate = option.0
                                            performSearch()
                                        })
                                    }
                                } label: {
                                    FilterPill(
                                        icon: "waveform",
                                        title: selectedBitrate != nil ? "\(selectedBitrate!)k+" : "Quality",
                                        isActive: selectedBitrate != nil
                                    )
                                }
                                
                                // Reset Button
                                if selectedGenre != nil || selectedCountry != nil || selectedBitrate != nil || !searchText.isEmpty {
                                    Button(action: resetFilters) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                            .padding(6)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    
                    // SECTION 3: RESULTS
                    if radioAPI.isSearching {
                        HStack {
                            Spacer()
                            ProgressView("Searching...")
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 40)
                    } else if radioAPI.searchResults.isEmpty {
                        HStack {
                            Spacer()
                            if searchText.isEmpty && selectedGenre == nil && selectedCountry == nil && selectedBitrate == nil {
                                Text("Loading Top 100...")
                                    .foregroundColor(.secondary)
                                    .onAppear { performSearch() }
                            } else {
                                Text("No stations found")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 40)
                    } else {
                        ForEach(radioAPI.searchResults) { station in
                            GlassStationRow(station: station, radioAPI: radioAPI)
                                .onTapGesture { playStation(station) }
                                .glassListRowWide()
                                .onAppear {
                                    if station.id == radioAPI.searchResults.last?.id {
                                        radioAPI.loadNextPage()
                                    }
                                }
                        }
                        
                        // Bottom Loading Spinner
                        if radioAPI.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .padding(.vertical)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Radio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassCloseButton(action: dismiss)
                }
            }
            .navigationDestination(for: RadioNavDestination.self) { destination in
                switch destination {
                case .favorites:
                    RadioFavoritesDestination(
                        radioAPI: radioAPI,
                        musicPlayer: musicPlayer,
                        dismiss: dismiss
                    )
                }
            }
        }
        .accentColor(.royalPurple)
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        var apiCountry = selectedCountry
        if selectedCountry == "USA" { apiCountry = "United States" }
        if selectedCountry == "UK" { apiCountry = "United Kingdom" }
        
        radioAPI.search(
            name: searchText,
            tag: selectedGenre,
            country: apiCountry,
            minBitrate: selectedBitrate
        )
    }
    
    private func resetFilters() {
        searchText = ""
        selectedGenre = nil
        selectedCountry = nil
        selectedBitrate = nil
        performSearch()
    }
    
    private func playStation(_ station: RadioStation) {
        // UPDATED: Now passes favicon for artwork background
        musicPlayer.addRadioStream(name: station.displayName, streamURL: station.url, artworkURL: station.favicon)
        dismiss()
    }
}

// MARK: - Filter Pill View

struct FilterPill: View {
    let icon: String
    let title: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .opacity(0.6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(backgroundView)
        .foregroundColor(isActive ? .white : .primary)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isActive ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    @ViewBuilder
    var backgroundView: some View {
        if isActive {
            Color.royalPurple
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Glass Station Row

struct GlassStationRow: View {
    let station: RadioStation
    @ObservedObject var radioAPI: RadioBrowserAPI
    
    var body: some View {
        HStack(spacing: 16) {
            MediaArtworkView(
                url: URL(string: station.favicon),
                size: 50,
                cornerRadius: 12,
                fallbackIcon: "antenna.radiowaves.left.and.right",
                fallbackColor: .orange
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(station.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(station.displayCountry)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Stacked Badges
            VStack(alignment: .trailing, spacing: 4) {
                if let count = Int(station.formattedClicks.replacingOccurrences(of: "k", with: "")), count > 0 || station.formattedClicks.contains("k") {
                    HStack(spacing: 4) {
                        Text(station.formattedClicks)
                            .font(.caption.weight(.bold))
                        Image(systemName: "person.fill")
                            .font(.caption2)
                    }
                    .foregroundColor(.primary)
                }
                
                if station.bitrate > 0 {
                    HStack(spacing: 4) {
                        Text("\(station.bitrate)k")
                            .font(.caption2)
                        Image(systemName: "waveform")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.trailing, 4)
            
            // Favorite Button
            Button(action: { radioAPI.toggleFavorite(station) }) {
                Image(systemName: radioAPI.isFavorite(station) ? "star.fill" : "star")
                    .font(.system(size: 18))
                    .foregroundColor(radioAPI.isFavorite(station) ? .orange : .secondary.opacity(0.3))
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }
}

// MARK: - Radio Favorites Destination (Push Navigation)

struct RadioFavoritesDestination: View {
    @ObservedObject var radioAPI: RadioBrowserAPI
    @ObservedObject var musicPlayer: AudioPlayer
    let dismiss: () -> Void
    
    var body: some View {
        ZStack {
            GlassBackgroundView()
            
            if radioAPI.favoriteStations.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "star")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No favorites yet")
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(radioAPI.favoriteStations) { station in
                        GlassStationRow(station: station, radioAPI: radioAPI)
                            .onTapGesture {
                                // UPDATED: Now passes favicon for artwork background
                                musicPlayer.addRadioStream(name: station.displayName, streamURL: station.url, artworkURL: station.favicon)
                                dismiss()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .onMove(perform: moveFavorites) // Drag to reorder
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton() // Enables Drag/Drop mode
        }
    }
    
    private func moveFavorites(from source: IndexSet, to destination: Int) {
        radioAPI.favoriteStations.move(fromOffsets: source, toOffset: destination)
    }
}
