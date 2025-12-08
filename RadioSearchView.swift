//
//  RadioSearchView.swift
//  2 Music 2 Furious - MILESTONE 7.8
//
//  Layout: [X] ... [Favorites] [Search] [Filter Pills] [Results]
//  Style: Apple Glass "Invisible UI" + Infinite Scroll
//  Updates: Swapped Headphones icon for Person icon
//

import SwiftUI

struct RadioSearchView: View {
    @ObservedObject var radioAPI: RadioBrowserAPI
    @ObservedObject var musicPlayer: AudioPlayer
    let dismiss: () -> Void
    
    @State private var searchText = ""
    @State private var selectedGenre: String? = nil
    @State private var selectedCountry: String? = nil
    @State private var selectedBitrate: Int? = nil
    @State private var showingFavoritesFull = false
    
    // Preset Filters
    let genres = ["Pop", "Rock", "Jazz", "Classical", "Hip Hop", "Electronic", "News", "Talk", "Country", "Indie"]
    let countries = ["USA", "UK", "Germany", "France", "Canada", "Japan", "Brazil", "Spain", "Italy"]
    
    // Quality Options (kbps)
    let qualityOptions = [
        (96, "Standard (96k+)"),
        (128, "High (128k+)"),
        (192, "Very High (192k+)"),
        (320, "Audiophile (320k)")
    ]
    
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
                
                // 2. Main Scrolling Content
                List {
                    // SECTION 1: FAVORITES
                    if !radioAPI.favoriteStations.isEmpty {
                        favoritesSection
                    }
                    
                    // SECTION 2: SEARCH & FILTER
                    VStack(alignment: .leading, spacing: 12) {
                        // Search Bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            
                            TextField("Search stations...", text: $searchText, onCommit: performSearch)
                                .submitLabel(.search)
                            
                            if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                    performSearch()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        
                        // Horizontal Filter Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                // 1. Genre Pill
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
                                
                                // 2. Country Pill
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
                                
                                // 3. Quality Pill
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
                                
                                // 4. Reset Button
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
                        // Show empty state / Default Load
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
                        // THE LIST LOOP
                        ForEach(radioAPI.searchResults) { station in
                            GlassStationRow(station: station, radioAPI: radioAPI)
                                .onTapGesture { playStation(station) }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .onAppear {
                                    // INFINITE SCROLL TRIGGER
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
                
                if showingFavoritesFull {
                    RadioFavoritesFullView(
                        radioAPI: radioAPI,
                        musicPlayer: musicPlayer,
                        dismiss: { showingFavoritesFull = false }
                    )
                    .transition(.move(edge: .trailing))
                    .zIndex(100)
                }
            }
            .navigationTitle("Radio")
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
        }
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
        musicPlayer.addRadioStream(name: station.displayName, streamURL: station.url)
        dismiss()
    }
    
    // MARK: - Subviews
    
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Favorites")
                    .font(.title2.weight(.bold))
                Spacer()
                Button(action: { showingFavoritesFull = true }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(radioAPI.favoriteStations.prefix(8)) { station in
                        Button(action: { playStation(station) }) {
                            VStack(spacing: 8) {
                                stationIcon(station, size: 70)
                                    .shadow(radius: 4)
                                Text(station.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 70)
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 10)
            }
        }
        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 10, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    
    @ViewBuilder
    private func stationIcon(_ station: RadioStation, size: CGFloat) -> some View {
        if !station.favicon.isEmpty, let url = URL(string: station.favicon) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                radioPlaceholder(size: size)
            }
            .frame(width: size, height: size)
            .cornerRadius(16)
        } else {
            radioPlaceholder(size: size)
        }
    }
    
    private func radioPlaceholder(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(LinearGradient(colors: [.orange.opacity(0.2), .red.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: size * 0.4)).foregroundColor(.orange))
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
            Color.blue
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
            // Icon
            if !station.favicon.isEmpty, let url = URL(string: station.favicon) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { defaultIcon }
                    .frame(width: 50, height: 50).cornerRadius(12).shadow(radius: 2)
            } else {
                defaultIcon
            }
            
            // Info
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
            
            // STACKED BADGES
            VStack(alignment: .trailing, spacing: 4) {
                // 1. Listeners (Person Icon)
                if let count = Int(station.formattedClicks.replacingOccurrences(of: "k", with: "")), count > 0 || station.formattedClicks.contains("k") {
                    HStack(spacing: 4) {
                        Text(station.formattedClicks)
                            .font(.caption.weight(.bold))
                        Image(systemName: "person.fill") // UPDATED ICON
                            .font(.caption2)
                    }
                    .foregroundColor(.primary)
                }
                
                // 2. Bitrate (Waveform Icon)
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
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var defaultIcon: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(colors: [.orange.opacity(0.2), .red.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 50, height: 50)
            .overlay(Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 20)).foregroundColor(.orange))
    }
}

// MARK: - Full Favorites View

struct RadioFavoritesFullView: View {
    @ObservedObject var radioAPI: RadioBrowserAPI
    @ObservedObject var musicPlayer: AudioPlayer
    let dismiss: () -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(radioAPI.favoriteStations) { station in
                            GlassStationRow(station: station, radioAPI: radioAPI)
                                .onTapGesture {
                                    musicPlayer.addRadioStream(name: station.displayName, streamURL: station.url)
                                    dismiss()
                                }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { dismiss() }
                }
            }
        }
    }
}
